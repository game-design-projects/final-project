## Saying something to a clan's asker (rules/envoys.gd): one typed line, which the mind judges (a hiss long enough, a voice flat
## enough). Enough and the request is done; not enough and the asker says so, and you may try again.
extends "res://src/game/stages/stage.gd"

const Envoy = preload("res://src/game/stages/envoy.gd")
const Envoys = preload("res://src/rules/envoys.gd")
const State = preload("res://src/game/state.gd")

const MAX_CHARS := 140

var _who := {}
var _request := {}


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	_who = args.who
	_request = args.request
	s.menu = []
	s.hint = str(Envoys.table().lines.say_hint)
	s.say([State.speech(str(_who.name), Envoys.speak(s, _request))])


func handle(flow, key: String) -> void:
	if key == "cancel":
		await flow.go("envoy", {"who": _who})


## The line the player sent.
func submit(flow, raw: String) -> void:
	var s = flow.state
	var text := raw.strip_edges().left(MAX_CHARS)
	if text == "":
		await flow.go("envoy", {"who": _who})
		return
	flow.event("said", {"text": text})
	s.listening = true
	var score: float = await flow.mind.sounds_like(text, str(_request.sounds))
	s.listening = false
	var said := State.sys_line(str(Envoys.table().lines.said) % text)
	print("envoy_say: \"%s\" sounds %.2f like %s" % [text, score, _request.sounds])
	if Envoys.passes(score):
		var words := str(_request.done)
		flow.event("shout", {"text": words, "species": str(_who.species), "boss": false})
		await Envoy.finished(flow, _request, [said, State.speech(str(_who.name), words)])
		return
	var no := str(_request.fail)
	flow.event("sound", {"name": "bad"})
	flow.event("shout", {"text": no, "species": str(_who.species), "boss": false})
	await flow.go("explore", {"lines": [said, State.speech(str(_who.name), no)]})
