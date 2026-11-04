## You reached the stairs. With real floors they lead on down: the log says how the floor went, and you go down or back to the
## main menu. The last floor's stairs end the run, and so do any stairs without the feature: the log sums up your route, and
## then a new run or the main menu.
extends "res://src/game/stages/list_stage.gd"

const Floors = preload("res://src/rules/floors.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.foe = null
	flow.event("stairs")
	s.run_over = not flow.feature("real-floors") or Floors.is_last(s.depth)
	if s.run_over:
		var ending := Texts.ending(s.tally, s.allies)
		s.say([State.speech(ending.route, ending.text), State.sys_line(ending.tail)])
		s.menu = [{"label": "NEW RUN" if flow.feature("real-floors") else "NEW FLOOR", "sub": ""}, {"label": "MAIN MENU", "sub": ""}]
		print("end: %s" % ending.route)
	else:
		s.say([State.sys_line(Texts.floor_done(s.depth)), State.sys_line(s.summary() + ".")])
		s.menu = [{"label": "GO DOWN", "sub": ""}, {"label": "MAIN MENU", "sub": ""}]
		print("end: B%dF done" % s.depth)
	s.hint = "ENTER PICK · ESC MAIN MENU"


func pick(flow, index: int) -> void:
	if index == 1:
		flow.event("leave", {"to": "menu"})
	elif flow.state.run_over:
		await flow.new_run()
	else:
		await flow.next_floor()


## Esc is the way out: the main menu, as the route screen's Esc always was.
func cancel(flow) -> void:
	flow.event("leave", {"to": "menu"})
