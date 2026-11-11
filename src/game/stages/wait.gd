## The monster winds up. A short pause, then the dodge begins.
extends "res://src/game/stages/stage.gd"

const Combat = preload("res://src/rules/combat.gd")

var _pressure := 1.0
var _waiting := false
var _started_at := 0.0
var _queued := false


func enter(flow, args: Dictionary) -> void:
	_pressure = float(args.get("pressure", 1.0))
	_waiting = args.get("prompt", false)
	_started_at = flow.clock
	_queued = false
	flow.state.menu = []
	flow.state.hint = "ANY KEY CONTINUE" if _waiting else ""


func handle(flow, _key: String) -> void:
	if _waiting:
		if flow.clock - _started_at < flow.DIALOGUE_BUFFER_MS:
			_queued = true
		else:
			await _continue(flow)


func tick(flow, _t: float) -> void:
	if _waiting and _queued and flow.clock - _started_at >= flow.DIALOGUE_BUFFER_MS:
		await _continue(flow)
	elif not _waiting and flow.clock - _started_at >= Combat.WINDUP_MS:
		await flow.go("dodge", {"pressure": _pressure})


func _continue(flow) -> void:
	_waiting = false
	_queued = false
	await flow.go("dodge", {"pressure": _pressure})
