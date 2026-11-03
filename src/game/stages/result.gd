## The fight is over, one way or the other. The log says how; continue goes back to walking (or, in the personality
## slice, on to the second bandit).
extends "res://src/game/stages/list_stage.gd"


func enter(flow, _args: Dictionary) -> void:
	flow.state.menu = [{"label": "CONTINUE", "sub": ""}]
	flow.state.hint = "ENTER CONTINUE"


func pick(flow, _index: int) -> void:
	if not flow.slice_queue.is_empty():
		await flow.go("intro", {"foe": flow.slice_queue.pop_front()})
		return
	flow.end_slice()
	await flow.go("explore")
