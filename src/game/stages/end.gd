## You reached the stairs. With real floors they lead on down: the log says how the floor went, and you go down or back to the
## main menu. The last floor's stairs end the run, and so do any stairs without the feature: the log sums up your route, and
## then a new run or the main menu. The very last door only opens for someone with a friend (last-door): alone you can turn back
## and look for one, or take the lonely way out, which ends the run without clearing it.
extends "res://src/game/stages/list_stage.gd"

const Floors = preload("res://src/rules/floors.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const TURN_BACK := 0
const LEAVE_ALONE := 1

var _at_door := false
var _ways: Array = [] # the ways down on offer (Floors.paths)


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.foe = null
	flow.event("stairs")
	s.run_over = not flow.feature("real-floors") or Floors.is_last(s.depth)
	_at_door = false
	_ways = []
	if s.run_over and flow.feature("last-door") and flow.feature("real-floors") and s.allies.is_empty():
		s.run_over = false
		_at_door = true
		s.say([State.sys_line(Texts.DOOR_SHUT), State.sys_line(Texts.DOOR_HINT)])
		s.menu = [{"label": "TURN BACK", "sub": "Find someone who will come with you"}, {"label": "LEAVE ALONE", "sub": "Ends the run, not cleared"}, {"label": "MAIN MENU", "sub": ""}]
		print("end: the Last Door stays shut, no allies")
	elif s.run_over:
		_finish(flow, Texts.ending(s.tally, s.allies))
	else:
		s.say([State.sys_line(Texts.floor_done(s.depth)), State.sys_line(s.summary() + ".")])
		_ways = Floors.paths(s.run_seed, s.depth) if flow.feature("branching") else []
		s.menu = []
		for way in _ways:
			s.menu.append({"label": way.label, "sub": way.sub})
		if _ways.is_empty():
			s.menu.append({"label": "GO DOWN", "sub": ""})
		s.menu.append({"label": "MAIN MENU", "sub": ""})
		print("end: B%dF done" % s.depth)
	s.hint = "ENTER PICK · ESC MAIN MENU"


func _finish(flow, ending: Dictionary) -> void:
	var s = flow.state
	s.run_over = true
	s.say([State.speech(ending.route, ending.text), State.sys_line(ending.tail)])
	s.menu = [{"label": "NEW RUN" if flow.feature("real-floors") else "NEW FLOOR", "sub": ""}, {"label": "MAIN MENU", "sub": ""}]
	print("end: %s" % ending.route)


func pick(flow, index: int) -> void:
	if _at_door:
		match index:
			TURN_BACK:
				await flow.go("explore", {"lines": [State.sys_line(Texts.DOOR_HINT)]})
			LEAVE_ALONE:
				_at_door = false
				flow.state.selected = 0
				_finish(flow, Texts.lonely_ending())
			_:
				flow.event("leave", {"to": "menu"})
		return
	if index == flow.state.menu.size() - 1:
		flow.event("leave", {"to": "menu"})
	elif flow.state.run_over:
		await flow.new_run()
	elif index < _ways.size():
		print("end: taking %s" % _ways[index].label)
		await flow.next_floor(_ways[index])
	else:
		await flow.next_floor()


## Esc is the way out: the main menu, as the route screen's Esc always was.
func cancel(flow) -> void:
	flow.event("leave", {"to": "menu"})
