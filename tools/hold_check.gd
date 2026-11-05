## Holds each arrow key for a few seconds in the real game scene, as a keyboard does (one press, then repeats), and watches the camera frame by
## frame (#44). Prints, per key: frames, what the game did (steps, turns), how often the camera turned back on itself, the longest time it stood still
## while the key was down, and the slowest frame. Against a wall it says how often the lunge started over.
##   godot --path . --resolution 640x360 -s res://tools/hold_check.gd -- nosound nosave [seed=9]
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

const HOLD_MS := 4000.0
const REPEAT_MS := 33.0 # the usual fastest key repeat
const REPEAT_DELAY_MS := 400.0

var _scene


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_scene = load("res://src/gameplay/gameplay.tscn").instantiate()
	_scene.request = {"kind": "new"}
	root.add_child(_scene)
	while _scene.flow == null:
		await process_frame
	_scene._begin()
	while _scene.flow.state.stage != "explore":
		await process_frame
	for i in 30:
		await process_frame
	var s = _scene.flow.state
	s.floor_map.monsters = []
	s.floor_map.pickups = []
	s.floor_map.treasure = []
	s.floor_map.teleports = []
	s.floor_map.merchant = {}
	s.floor_map.quester = {}
	s.floor_map.stairs = Vector2i(-5, -5) # nothing to walk into but walls
	await _hold(KEY_RIGHT, "right")
	await _hold(KEY_LEFT, "left")
	await _hold(KEY_UP, "up")
	await _hold(KEY_DOWN, "down")
	# the same key against a wall, in front of you
	for i in 4:
		s.facing = i
		if not s.floor_map.is_open(s.cell + FloorMap.DIRS[i]):
			break
	s.look()
	for i in 30:
		await process_frame
	await _hold(KEY_UP, "up into a wall")
	print("hold: done")
	quit()


func _key(code: int, echo: bool, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	e.echo = echo
	return e


func _hold(code: int, label: String) -> void:
	var s = _scene.flow.state
	var stage = _scene._stage
	var t0 := Time.get_ticks_msec()
	var next_repeat := t0 + REPEAT_DELAY_MS
	var turns0: int = s.quarter_turns
	var cell0: Vector2i = s.cell
	var moved_cells := 0
	var last_cell: Vector2i = cell0
	var bumps := [0]
	var count_bump := func(n, _d):
		if n == "bump":
			bumps[0] += 1
	_scene.flow.happened.connect(count_bump)
	var frames := 0
	var backs := 0
	var still_ms := 0.0
	var worst_still := 0.0
	var slowest := 0.0
	var last_t := Time.get_ticks_usec()
	var last_pos: Vector3 = stage._camera.position
	var last_yaw: float = stage._camera.rotation.y
	var last_way := Vector3.ZERO
	var last_spin := 0.0
	_scene._unhandled_input(_key(code, false))
	while Time.get_ticks_msec() - t0 < HOLD_MS:
		await process_frame
		frames += 1
		var now_t := Time.get_ticks_usec()
		var ms := (now_t - last_t) / 1000.0
		last_t = now_t
		if frames > 3:
			slowest = maxf(slowest, ms)
		while Time.get_ticks_msec() >= next_repeat:
			_scene._unhandled_input(_key(code, true))
			next_repeat += REPEAT_MS
		if s.cell != last_cell:
			moved_cells += 1
			last_cell = s.cell
		var pos: Vector3 = stage._camera.position
		var yaw: float = stage._camera.rotation.y
		var way := pos - last_pos
		var spin := angle_difference(last_yaw, yaw)
		if way.length() > 0.0001 and last_way.length() > 0.0001 and way.normalized().dot(last_way.normalized()) < -0.5: # (a turn's camera moves along the sides of a square round the cell: a corner is not a turn back)
			backs += 1
		if absf(spin) > 0.0001 and absf(last_spin) > 0.0001 and signf(spin) != signf(last_spin):
			backs += 1
		if way.length() <= 0.0001 and absf(spin) <= 0.0001:
			still_ms += ms
			worst_still = maxf(worst_still, still_ms)
		else:
			still_ms = 0.0
		if way.length() > 0.0001:
			last_way = way
		if absf(spin) > 0.0001:
			last_spin = spin
		last_pos = pos
		last_yaw = yaw
	_scene._unhandled_input(_key(code, false, false))
	_scene.flow.happened.disconnect(count_bump)
	print("hold: %s: %d frames, %d cells, %d turns, %d bumps, camera turned back %d times, stood still at most %.0f ms, slowest frame %.0f ms" % [label, frames, moved_cells, absi(s.quarter_turns - turns0), bumps[0], backs, worst_still, slowest])
	for i in 40:
		await process_frame
