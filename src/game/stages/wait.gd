## The monster winds up. A short pause, then the dodge begins.
extends "res://src/game/stages/stage.gd"

const Combat = preload("res://src/rules/combat.gd")

var _pressure := 1.0


func enter(flow, args: Dictionary) -> void:
	_pressure = float(args.get("pressure", 1.0))
	flow.state.menu = []
	flow.state.hint = ""


func tick(flow, _t: float) -> void:
	if flow.stage_ms() >= Combat.WINDUP_MS:
		await flow.go("dodge", {"pressure": _pressure})
