## The fight is over, one way or the other. The log says how; continue goes back to walking.
extends "res://src/game/stages/list_stage.gd"


func enter(flow, _args: Dictionary) -> void:
	flow.state.menu = [{"label": "CONTINUE", "sub": ""}]
	flow.state.hint = "ENTER CONTINUE"


func pick(flow, _index: int) -> void:
	await flow.go("explore")
