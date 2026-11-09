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

var _url: String
var _fallback # a Mind
var _known := {} # a question and the monster's state when it was asked -> the answer, so the same question about the same monster is asked once

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
	var a = await _choice({"player_said": text}, "Which kind of thing is `player_said`?", kinds)
	return a if a != null else await _fallback.read_words(text)


func feeling_when_hit(m) -> Dictionary:
	var a = await _choice(_state(m, {"just_happened": "the player hit it"}), "How does the monster feel after being hit?", _feelings())
	return a if a != null else await _fallback.feeling_when_hit(m)


func feeling_when_told(m, intents: Array) -> Dictionary:
	var said := intents.map(func(i): return "%s (%.1f)" % [i.intent, i.w])
	var a = await _choice(_state(m, {"just_happened": "the player showed: %s" % ", ".join(said)}), "How does the monster feel about what the player just did?", _feelings())
	return a if a != null else await _fallback.feeling_when_told(m, intents)


func mercy(m) -> float:
	var key := _key("mercy", m)
	if not _known.has(key):
		var odds := _odds(_answer(await Network.post_json(_url, {"state": _state(m, {}), "questions": {"q": MERCY_Q}}), "q"))
		if odds < 0.0:
			return await _fallback.mercy(m)
		_remember(key, odds)
	return _known[key]


func join(m) -> float:
	var a = await _noul(_state(m, {}), "Would this monster join the player's party if asked right now?")
	return a if a >= 0.0 else await _fallback.join(m)


func pressure(m) -> float:
	var key := _key("pressure", m)
	if not _known.has(key):
		var press := _score(_answer(await Network.post_json(_url, {"state": _state(m, {}), "questions": {"q": PRESSURE_Q}}), "q"))
		if press < 0.0:
			return await _fallback.pressure(m)
		_remember(key, press)
	return _known[key]


## Mercy and pressure after a feeling, in one request (the Worker takes up to 120 questions at once). The feeling stays its own
## request: its answer changes the monster, and these two are about the monster after that. An answer that is missing comes
## from the local rules, and what Jev did answer is kept, so the menu opening on the same monster asks nothing more.
func mercy_and_pressure(m) -> Dictionary:
	var mercy_key := _key("mercy", m)
	var pressure_key := _key("pressure", m)
	if not (_known.has(mercy_key) and _known.has(pressure_key)):
		var r := await Network.post_json(_url, {"state": _state(m, {}), "questions": {"mercy": MERCY_Q, "pressure": PRESSURE_Q}})
		var odds := _odds(_answer(r, "mercy"))
		var press := _score(_answer(r, "pressure"))
		print_verbose("jev: mercy and pressure in one request (%s)" % ("answered" if odds >= 0.0 and press >= 0.0 else "not fully answered"))
		if odds < 0.0 or press < 0.0:
			return {"mercy": odds if odds >= 0.0 else await _fallback.mercy(m), "pressure": press if press >= 0.0 else await _fallback.pressure(m)}
		_remember(mercy_key, odds)
		_remember(pressure_key, press)
	return {"mercy": _known[mercy_key], "pressure": _known[pressure_key]}


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
func _choice(state: Dictionary, question: String, options: Dictionary):
	var q := {"type": "choice", "instructions": question, "criteria": options}
	var answer = _answer(await Network.post_json(_url, {"state": state, "questions": {"q": q}}))
	if not (answer is Dictionary and answer.get("probabilities") is Dictionary):
		return null
	var out := {}
	var total := 0.0
	for k in options:
		var p := float(answer.probabilities.get(k, 0.0))
		out[k] = p
		total += p
	if total <= 0.0:
		return null
	for k in out:
		out[k] /= total
	return out


## A yes/no question: 0..1, or -1 when Jev didn't answer.
func _noul(state: Dictionary, question: String) -> float:
	var answer = _answer(await Network.post_json(_url, {"state": state, "questions": {"q": {"type": "noul", "instructions": question}}}))
	if answer is Dictionary and answer.has("noul"):
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
	return clampf(float(answer.noul), 0.0, 1.0) if answer is Dictionary and answer.has("noul") else -1.0


## A 0..3 score, or -1 when the answer is not one.
static func _score(answer) -> float:
	return clampf(float(answer.score), 0.0, 3.0) if answer is Dictionary and answer.has("score") else -1.0


func _key(kind: String, m) -> String:
	return kind + JSON.stringify(_state(m, {}))


func _remember(key: String, answer: float) -> void:
	if _known.size() >= KNOWN_MAX:
		_known.clear()
	_known[key] = answer
