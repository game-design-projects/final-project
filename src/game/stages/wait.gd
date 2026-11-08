## The monster winds up. A short pause, then the dodge begins.
extends "res://src/game/stages/stage.gd"

const Combat = preload("res://src/rules/combat.gd")

var _pressure := 1.0
var _waiting := false
var _started_at := 0.0


func enter(flow, args: Dictionary) -> void:
	_pressure = float(args.get("pressure", 1.0))
	_waiting = args.get("prompt", false)
	_started_at = flow.clock
	flow.state.menu = []
	flow.state.hint = "ANY KEY CONTINUE" if _waiting else ""


func handle(flow, _key: String) -> void:
	if _waiting:
		_waiting = false
		await flow.go("dodge", {"pressure": _pressure})


func tick(flow, _t: float) -> void:
	if not _waiting and flow.clock - _started_at >= Combat.WINDUP_MS:
		await flow.go("dodge", {"pressure": _pressure})
