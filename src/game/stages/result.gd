## The fight is over, one way or the other. The log says how; continue goes back to walking (or, in the personality
## slice, on to the second bandit).
extends "res://src/game/stages/list_stage.gd"


func enter(flow, _args: Dictionary) -> void:
	flow.state.menu = [{"label": "CONTINUE", "sub": ""}]
	flow.state.hint = "ENTER CONTINUE"


func pick(flow, _index: int) -> void:
	var s = flow.state
	if flow.slice_next != "" and s.foe.name != flow.slice_next:
		for m in s.floor_map.monsters:
			if m.name == flow.slice_next and not m.is_gone():
				await flow.go("intro", {"foe": m})
				return
	flow.end_slice()
	await flow.go("explore")
