## A mind that asks Jev, through the proxy (proxy/worker.js holds the key). Every question becomes one or two Jev
## questions about a small description of the monster; the answers are probabilities and the game rolls them as always.
## When the network can't answer (down, slow, a bad reply) the question goes to the fallback mind, so a fight never stalls.
extends "res://src/mind/mind.gd"

const Content = preload("res://src/rules/content.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Network = preload("res://src/network/network.gd")

const MERCY_Q := {"type": "noul", "instructions": "Would this monster accept mercy and stop fighting right now?"}
const PRESSURE_Q := {"type": "score", "instructions": "How hard will this monster press the player with its next attack? 0 gentle, 3 relentless.", "criteria": ["gentle", "firm", "fierce", "relentless"]}
const KNOWN_MAX := 64
## What each question asks, in the words the screen uses while it waits (and the mind card uses for the answer).
const ASKS := {"words": "WHAT DID YOUR WORDS MEAN?", "feeling": "HOW DOES IT FEEL?", "mercy": "WILL IT ACCEPT MERCY?", "pressure": "HOW HARD WILL IT ATTACK?", "join": "DOES IT WANT TO COME ALONG?", "sounds": "HOW DID THAT SOUND?"}
## What Jev is asked about a typed line, for each thing a request listens for (rules/envoys.gd).
const SOUNDS := {
	"hiss": "Is `player_said` a long, drawn-out snake hiss (like \"hissssssssss\"), rather than a short hiss or ordinary words?",
	"monotone": "Is `player_said` written in a flat, dull, monotone way, the way a rock in a wall would talk, with no excitement or emphasis?",
	"likes_slimes": "Is `player_said` asking, in any wording (plainly, jokingly or rudely), what dragons (or this dragon) think of slimes or whether they like them?",
}


## A question still out: whoever asks the same thing meanwhile waits for this answer instead of asking again.
class Asking extends RefCounted:
	signal answered(value: float)

var _url: String
var _fallback # a Mind
var _known := {} # a question and the monster's state when it was asked -> the answer, so the same question about the same monster is asked once
var _asking := {} # the same key -> an Asking, for a question that is out right now (asked ahead, see Encounter.think_ahead)

## `api_base` is where the proxy lives (https://…); `fallback` answers when Jev can't.
func _init(api_base: String, fallback) -> void:
	_url = api_base.rstrip("/") + "/api/jev"
	_fallback = fallback


func label() -> String:
	return "jev via %s" % _url


func read_words(text: String) -> Dictionary:
	var kinds := {}
	for k in Content.table("words").cues:
		kinds[k] = "The player is doing this: %s" % k.replace("_", " ")
	kinds["other"] = "Said something that is none of the above"
	kinds["gibberish"] = "Typed nonsense, not words"
	var a = await _choice({"player_said": text}, "Which kind of thing is `player_said`?", kinds, ASKS.words)
	return a if a != null else await _fallback.read_words(text)


func sounds_like(text: String, what: String) -> float:
	if not SOUNDS.has(what):
		return await _fallback.sounds_like(text, what)
	var a := await _noul({"player_said": text}, str(SOUNDS[what]), ASKS.sounds)
	return a if a >= 0.0 else await _fallback.sounds_like(text, what)


func feeling_when_hit(m) -> Dictionary:
	var a = await _choice(_state(m, {"just_happened": "the player hit it"}), "How does the monster feel after being hit?", _feelings(), ASKS.feeling)
	return a if a != null else await _fallback.feeling_when_hit(m)


func feeling_when_told(m, intents: Array) -> Dictionary:
	var said := intents.map(func(i): return "%s (%.1f)" % [i.intent, i.w])
	var a = await _choice(_state(m, {"just_happened": "the player showed: %s" % ", ".join(said)}), "How does the monster feel about what the player just did?", _feelings(), ASKS.feeling)
	return a if a != null else await _fallback.feeling_when_told(m, intents)


func mercy(m) -> float:
	var odds := await _once(_key("mercy", m), func(): return _odds(_answer(await _post(_state(m, {}), {"q": MERCY_Q}, ASKS.mercy), "q")))
	return odds if odds >= 0.0 else await _fallback.mercy(m)


func join(m) -> float:
	var state := _state(m, {})
	var a := await _once(_key("join", m), func(): return await _noul(state, "Would this monster join the player's party if asked right now?", ASKS.join))
	return a if a >= 0.0 else await _fallback.join(m)


func pressure(m) -> float:
	var press := await _once(_key("pressure", m), func(): return _score(_answer(await _post(_state(m, {}), {"q": PRESSURE_Q}, ASKS.pressure), "q")))
	return press if press >= 0.0 else await _fallback.pressure(m)


## The answer for `key`: known, or joined while it is out, or asked now with `ask` (-> 0.. or -1 for no answer) and kept.
## A question asked ahead (nobody awaiting it) and asked again before Jev answers goes out once.
func _once(key: String, ask: Callable) -> float:
	if _known.has(key):
		return _known[key]
	if _asking.has(key):
		print_verbose("jev: already asking %s, waiting for that answer" % key.left(40))
		return await _asking[key].answered
	var waiting := Asking.new()
	_asking[key] = waiting
	var answer: float = await ask.call()
	_asking.erase(key)
	if answer >= 0.0:
		_remember(key, answer)
	waiting.answered.emit(answer)
	return answer


func _post(state: Dictionary, questions: Dictionary, what: String) -> Dictionary:
	return await Network.post_json(_url, {"state": state, "questions": questions}, {}, Network.TIMEOUT_S, what)


## Mercy and pressure after a feeling, in one request (the Worker takes up to 120 questions at once). The feeling stays its own
## request: its answer changes the monster, and these two are about the monster after that. An answer that is missing comes
## from the local rules; a half Jev did answer is kept, so asked on its own (the dodge thinking a mercy ahead) it costs no
## request, while the pair together is asked again until both halves are answered.
func mercy_and_pressure(m) -> Dictionary:
	var mercy_key := _key("mercy", m)
	var pressure_key := _key("pressure", m)
	if _known.has(mercy_key) and _known.has(pressure_key):
		return {"mercy": _known[mercy_key], "pressure": _known[pressure_key]}
	var r := await _post(_state(m, {}), {"mercy": MERCY_Q, "pressure": PRESSURE_Q}, ASKS.pressure)
	var odds := _odds(_answer(r, "mercy"))
	var press := _score(_answer(r, "pressure"))
	print_verbose("jev: mercy and pressure in one request (%s)" % ("answered" if odds >= 0.0 and press >= 0.0 else "not fully answered"))
	var answered := {}
	if odds >= 0.0:
		answered[mercy_key] = odds
	if press >= 0.0:
		answered[pressure_key] = press
	if not answered.is_empty():
		_remember_all(answered)
	# The answer is what came back, never what the cache holds: making room for it may clear the cache first.
	return {"mercy": odds if odds >= 0.0 else await _fallback.mercy(m), "pressure": press if press >= 0.0 else await _fallback.pressure(m)}


func _feelings() -> Dictionary:
	var out := {}
	for id in Feelings.all():
		out[id] = str(Feelings.all()[id].get("label", id))
	return out


func _state(m, extra: Dictionary) -> Dictionary:
	var s := {"monster": {"species": m.species, "name": m.name, "boss": m.boss, "traits": m.traits, "meters": m.meters, "health": snappedf(m.hp_fraction(), 0.01)}}
	if not m.heard.is_empty():
		s["history"] = {"clan": m.heard.clan, "standing": m.heard.standing, "heard": m.heard.heard}
	if not m.mood.is_empty():
		s["temporary"] = m.mood
		s["recent"] = {"intent": m.last_intent, "tried": m.tried}
	s.merge(extra)
	return s


## A choice question: label -> probability (adding up to 1), or null when Jev didn't answer.
func _choice(state: Dictionary, question: String, options: Dictionary, what := ""):
	var q := {"type": "choice", "instructions": question, "criteria": options}
	var answer = _answer(await _post(state, {"q": q}, what))
	if not (answer is Dictionary and answer.get("probabilities") is Dictionary):
		print("jev: no usable answer to %s, local rules instead" % question)
		return null
	var out := {}
	var total := 0.0
	for k in options:
		var value = answer.probabilities.get(k)
		if not _valid_number(value, 0.0, 1.0):
			return null
		var p := float(value)
		out[k] = p
		total += p
	if total <= 0.0:
		return null
	for k in out:
		out[k] /= total
	return out


## A yes/no question: 0..1, or -1 when Jev didn't answer.
func _noul(state: Dictionary, question: String, what := "") -> float:
	var answer = _answer(await _post(state, {"q": {"type": "noul", "instructions": question}}, what))
	if answer is Dictionary and _valid_number(answer.get("noul"), 0.0, 1.0):
		return clampf(float(answer.noul), 0.0, 1.0)
	return -1.0


## The answer to the question named `id`, or null.
static func _answer(r: Dictionary, id := "q"):
	if not r.ok or not r.json is Dictionary:
		return null
	var answers = r.json.get("answers")
	return answers.get(id) if answers is Dictionary else null


## Yes/no as 0..1, or -1 when the answer is not one.
static func _odds(answer) -> float:
	return float(answer.noul) if answer is Dictionary and _valid_number(answer.get("noul"), 0.0, 1.0) else -1.0


## A 0..3 score, or -1 when the answer is not one.
static func _score(answer) -> float:
	return float(answer.score) if answer is Dictionary and _valid_number(answer.get("score"), 0.0, 3.0) else -1.0


static func _valid_number(value, low: float, high: float) -> bool:
	if not (value is float or value is int):
		return false
	var number := float(value)
	return is_finite(number) and number >= low and number <= high


func _key(kind: String, m) -> String:
	return kind + JSON.stringify(_state(m, {}))


func _remember(key: String, answer: float) -> void:
	_remember_all({key: answer})


## Keeps one reply's answers together when making room: remembered one at a time, the second could find the cache full and
## clear it, throwing the first away, so the pair would be asked again on the next menu.
func _remember_all(answers: Dictionary) -> void:
	var added := 0
	for key in answers:
		if not _known.has(key):
			added += 1
	if _known.size() + added > KNOWN_MAX:
		_known.clear()
	for key in answers:
		_known[key] = answers[key]
