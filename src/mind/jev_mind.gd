## A mind that asks Jev, through the proxy (proxy/worker.js holds the key). Every question becomes one or two Jev
## questions about a small description of the monster; the answers are probabilities and the game rolls them as always.
## When the network can't answer (down, slow, a bad reply) the question goes to the fallback mind, so a fight never stalls.
extends "res://src/mind/mind.gd"

const Content = preload("res://src/rules/content.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Network = preload("res://src/network/network.gd")

var _url: String
var _fallback # a Mind

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
	var a = await _noul(_state(m, {}), "Would this monster accept mercy and stop fighting right now?")
	return a if a >= 0.0 else await _fallback.mercy(m)


func join(m) -> float:
	var a = await _noul(_state(m, {}), "Would this monster join the player's party if asked right now?")
	return a if a >= 0.0 else await _fallback.join(m)


func pressure(m) -> float:
	var q := {"type": "score", "instructions": "How hard will this monster press the player with its next attack? 0 gentle, 3 relentless.", "criteria": ["gentle", "firm", "fierce", "relentless"]}
	var r := await Network.post_json(_url, {"state": _state(m, {}), "questions": {"q": q}})
	var answer = _answer(r)
	if answer is Dictionary and answer.has("score"):
		return clampf(float(answer.score), 0.0, 3.0)
	return await _fallback.pressure(m)


func _feelings() -> Dictionary:
	var out := {}
	for id in Feelings.all():
		out[id] = str(Feelings.all()[id].get("label", id))
	return out


func _state(m, extra: Dictionary) -> Dictionary:
	var s := {"monster": {"species": m.species, "name": m.name, "boss": m.boss, "traits": m.traits, "meters": m.meters, "health": snappedf(m.hp_fraction(), 0.01)}}
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


static func _answer(r: Dictionary):
	if not r.ok or not r.json is Dictionary:
		return null
	var answers = r.json.get("answers")
	return answers.get("q") if answers is Dictionary else null
