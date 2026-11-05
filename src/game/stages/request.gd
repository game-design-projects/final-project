## A monster with a request: what it wants, and whether you'll do it; when it's done, you are paid and it goes. Nothing here takes a turn.
extends "res://src/game/stages/list_stage.gd"

const Content = preload("res://src/rules/content.gd")
const Requests = preload("res://src/rules/requests.gd")
const State = preload("res://src/game/state.gd")

var _status := ""


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	var q: Dictionary = s.floor_map.quester
	var t := Requests.table()
	var kind: Dictionary = t.kinds[q.kind]
	_status = Requests.status(q, s)
	var words := Requests.speak(q, s)
	flow.event("shout", {"text": words, "species": q.species, "boss": false})
	s.say([State.speech(q.name, words)])
	var what: String = kind.sub % Requests.subject(q, s.floor_map)
	match _status:
		"new":
			s.menu = [{"label": kind.yes, "sub": what}, {"label": t.not_now, "sub": t.not_now_sub}]
		"ready":
			s.menu = [{"label": kind.give, "sub": t.reward_sub % [int(t.gold), int(t.heal)]}, {"label": t.not_now, "sub": t.not_now_sub}]
		_:
			s.menu = [{"label": t.leave, "sub": what if _status == "waiting" else t.not_now_sub}]
	s.hint = "ENTER CHOOSE · ESC LEAVE · I INFO"
	print("request: %s, %s" % [q.name, _status])


func pick(flow, index: int) -> void:
	if index == 0 and _status == "new":
		flow.state.floor_map.quester.taken = true
		print("request: taken")
		await _leave(flow, Requests.table().kinds[flow.state.floor_map.quester.kind].sub % Requests.subject(flow.state.floor_map.quester, flow.state.floor_map))
	elif index == 0 and _status == "ready":
		await _paid(flow)
	else:
		await cancel(flow)


func cancel(flow) -> void:
	if _status == "failed":
		flow.state.floor_map.quester = {}
		print("request: it has nothing more to say")
	await _leave(flow, Requests.table().farewell)


func _leave(flow, line: String) -> void:
	await flow.go("explore", {"lines": [State.sys_line(line)]})


func _paid(flow) -> void:
	var s = flow.state
	var q: Dictionary = s.floor_map.quester
	var t := Requests.table()
	var got := Requests.settle(q, s, flow.feature("clans"))
	flow.announce(t.done_title, t.done_line % [got.gold, got.healed])
	flow.event("sound", {"name": "good"})
	var thanks: String = t.kinds[q.kind].thanks
	flow.event("shout", {"text": thanks, "species": q.species, "boss": false})
	s.floor_map.quester = {}
	await flow.go("explore", {"lines": [State.speech(q.name, thanks)]})
