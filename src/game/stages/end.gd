## You reached the stairs. The log sums up your route; then a new floor or back to the main menu.
extends "res://src/game/stages/list_stage.gd"

const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const NEW_FLOOR := 0
const MAIN_MENU := 1


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.foe = null
	flow.event("stairs")
	var ending := Texts.ending(s.tally, s.allies)
	s.say([State.speech(ending.route, ending.text), State.sys_line(ending.tail)])
	s.menu = [{"label": "NEW FLOOR", "sub": ""}, {"label": "MAIN MENU", "sub": ""}]
	s.hint = "ENTER PICK"
	print("end: %s" % ending.route)


func pick(flow, index: int) -> void:
	match index:
		NEW_FLOOR:
			await flow.new_run()
		MAIN_MENU:
			flow.event("leave", {"to": "menu"})
