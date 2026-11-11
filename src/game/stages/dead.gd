## You fell. Try the same fight again, start a new floor, or leave to the main menu.
extends "res://src/game/stages/list_stage.gd"

const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const RETRY := 0
const NEW_FLOOR := 1
const MAIN_MENU := 2


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.dodge = null
	s.bar = null
	flow.event("dead")
	s.say([State.sys_line(Texts.you_fall(s.foe))])
	s.menu = [{"label": "TRY THIS FIGHT AGAIN", "sub": ""}, {"label": "NEW RUN", "sub": ""}, {"label": "MAIN MENU", "sub": ""}]
	s.hint = "ENTER PICK"


func pick(flow, index: int) -> void:
	match index:
		RETRY:
			await flow.encounter.retry_fight()
		NEW_FLOOR:
			flow.close_run(false)
			await flow.new_run()
		MAIN_MENU:
			flow.close_run(false)
			flow.event("leave", {"to": "menu"})
