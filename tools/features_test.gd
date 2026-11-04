## Checks the features in `Flags.FEATURES` with no window: that each can be switched off, and what each does when it is on.
## Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/features_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Flags = preload("res://src/utils/flags.gd")
const Floors = preload("res://src/rules/floors.gd")
const Flow = preload("res://src/game/flow.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")

const BASE := ["nosave", "nosound"]


func _name() -> String:
	return "features_test"


func _run() -> void:
	_flags()
	await _real_floors()
	_finish()


## A flow on the local rules, with these flags on top of BASE.
func _flow(seed_value: int, words := []) -> Variant:
	_set(words)
	var rng := Rng.new(seed_value)
	return Flow.new(rng, LocalMind.new())


func _set(words := []) -> void:
	var all := PackedStringArray(BASE)
	all.append_array(PackedStringArray(words))
	Flags.set_args(all)


func _flags() -> void:
	_set()
	_check(Flags.FEATURES.keys().all(func(f): return Flags.enabled(f)), "every feature is on by default")
	for f in Flags.FEATURES:
		_set(["no-" + f])
		_check(not Flags.enabled(f), "no-%s turns it off" % f)
		_set([f + "=off"])
		_check(not Flags.enabled(f), "%s=off turns it off" % f)
		_set(["classic"])
		_check(not Flags.enabled(f), "classic turns %s off" % f)
		_set(["classic", f])
		_check(Flags.enabled(f), "classic %s brings it back" % f)
	_set()


## Walk the party onto the stairs, as the last step of a floor does.
func _reach_stairs(flow) -> void:
	var s = flow.state
	var stairs: Vector2i = s.floor_map.stairs
	for i in 4:
		var from: Vector2i = stairs - s.floor_map.DIRS[i]
		if s.floor_map.is_open(from):
			s.cell = from
			s.facing = i
			break
	for m in s.floor_map.monsters:
		if m.cell == stairs:
			m.gone = "slain"
	await flow.press("up")


func _real_floors() -> void:
	var flow = _flow(11)
	await flow.new_run()
	var s = flow.state
	s.hp = 5
	s.gold = 3
	s.tally.spared = 2
	var Ally = load("res://src/game/ally.gd")
	s.allies.append(Ally.make("slime", "GLOB", 70.0))
	await _reach_stairs(flow)
	_check(s.stage == "end" and not s.run_over, "the first stairs don't end the run")
	var first_floor = s.floor_map
	await flow.press("1")
	_check(flow.state == s and s.stage == "explore" and s.depth == 2, "GO DOWN goes to B2F (B%dF, %s)" % [s.depth, s.stage])
	_check(s.floor_map != first_floor and s.cell == s.floor_map.start, "on a new floor, at its start")
	_check(s.gold == 3 and s.tally.spared == 2 and s.allies.size() == 1, "gold, the tally and the party came along")
	_check(s.hp == 5 + Floors.rest_heal(), "and the way down rests you a little (%d)" % s.hp)
	_check(s.lines[0].text.begins_with("B2F"), "the log names the floor (%s)" % s.lines[0].text)
	await _reach_stairs(flow)
	await flow.press("1")
	_check(s.depth == 3, "the second stairs lead to B3F")
	var saved: Dictionary = s.to_dict()
	var loaded = State.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(loaded != null and loaded.depth == 3 and loaded.run_seed == s.run_seed, "a save keeps the depth and the run's seed")

	var again = _flow(11)
	await again.new_run()
	await _reach_stairs(again)
	await again.press("1")
	var other = _flow(11)
	await other.new_run()
	other.rng.real() # the fights drew differently
	await _reach_stairs(other)
	await other.press("1")
	_check(again.state.floor_map.grid == other.state.floor_map.grid, "the same seed makes the same B2F, whatever the fights drew")
	var deeper: int = Floors.plan(3).champion.hp
	_check(deeper > Floors.plan(1).champion.hp and Floors.plan(Floors.run_floors()).champion.name == "VEXALITH", "the champions grow up to Vexalith on the last floor")

	s = again.state
	s.depth = Floors.run_floors()
	await _reach_stairs(again)
	_check(s.stage == "end" and s.run_over, "the last floor's stairs end the run")
	var ended = s
	await again.press("1")
	_check(again.state != ended and again.state.depth == 1, "and NEW RUN starts over on B1F")

	var classic = _flow(11, ["classic"])
	await classic.new_run()
	await _reach_stairs(classic)
	_check(classic.state.stage == "end" and classic.state.run_over, "classic: the stairs end the run")
	var kept = classic.state
	await classic.press("1")
	_check(classic.state != kept and classic.state.depth == 1, "classic: NEW FLOOR starts over")
	_set()
