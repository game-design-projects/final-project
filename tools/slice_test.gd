## Checks the personality slice (flag `personality-slice`) with no window: the fixed fights, what ends the slice, the
## retry, the autosave rule, the seed and the mind. Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/slice_test.gd
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Minds = preload("res://src/mind/minds.gd")
const Monster = preload("res://src/rules/monster.gd")
const PersonalitySlice = preload("res://src/game/personality_slice.gd")
const Rng = preload("res://src/utils/rng.gd")

var _failed := 0
var _clock := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _random_seed_repeats()
	await _seed_flag()
	await _pending_flag()
	await _mind_is_pinned()
	await _fair_cut_route()
	await _names_do_not_matter()
	await _retry_heals()
	await _flee_ends_it()
	print("slice_test: %s" % ("all checks passed" if _failed == 0 else "%d CHECK(S) FAILED" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("slice_test: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1


## A slice on a fresh run: the flow, and ROOK's intro already over, at his menu.
func _start(seed_value := 7042):
	Flags.set_args(PackedStringArray(["personality-slice", "seed=%d" % seed_value]))
	var rng := Rng.new(PersonalitySlice.seed_value())
	var flow = Flow.new(rng, Minds.create(rng, "", true))
	await flow.new_run()
	await PersonalitySlice.start(flow)
	await _to_menu(flow)
	return flow


func _to_menu(flow) -> void:
	for i in 100:
		if flow.state.stage == "menu":
			return
		_clock += 100.0
		await flow.tick(_clock)


func _press(flow, keys: Array) -> void:
	for k in keys:
		await flow.press(str(k))


## The seed a random run prints must be one `seed=N` accepts again (not negative) and must replay the same numbers.
func _random_seed_repeats() -> void:
	Flags.set_args(PackedStringArray([]))
	var printable := true
	var repeats := true
	for i in 64:
		var first := Rng.new()
		var again := Rng.new(first.seed_value)
		printable = printable and first.seed_value >= 0
		repeats = repeats and again.seed_value == first.seed_value and again.real() == first.real()
	_check(printable, "a random run's seed is never negative, so the flag can take it back")
	_check(repeats, "a random run's printed seed replays the same run")


func _seed_flag() -> void:
	Flags.set_args(PackedStringArray([]))
	_check(PersonalitySlice.seed_value() == PersonalitySlice.DEFAULT_SEED, "no seed flag gives the documented seed")
	Flags.set_args(PackedStringArray(["seed=9"]))
	_check(PersonalitySlice.seed_value() == 9, "seed=9 is used")
	Flags.set_args(PackedStringArray(["seed=-5"]))
	_check(PersonalitySlice.seed_value() == PersonalitySlice.DEFAULT_SEED, "a negative seed falls back to the documented one, not to random")
	Flags.set_args(PackedStringArray(["seed=abc"]))
	_check(PersonalitySlice.seed_value() == PersonalitySlice.DEFAULT_SEED, "a seed that is not a number falls back to the documented one")


func _pending_flag() -> void:
	Flags.set_args(PackedStringArray(["personality-slice"]))
	_check(PersonalitySlice.pending(), "the flag is pending before the slice starts")
	var flow = await _start()
	_check(not PersonalitySlice.pending(), "the flag has been used once the slice started, so the menu comes back after leaving")
	Flags.set_args(PackedStringArray([]))
	_check(not PersonalitySlice.pending(), "no flag, nothing pending")
	_check(flow.state.floor_map.monsters[0].name == "ROOK" and flow.state.floor_map.monsters[1].name == "VEX", "ROOK and VEX are the first two monsters")
	var vex = flow.state.floor_map.monsters[1]
	var taste_vex = Monster.given({"species": "bandit", "genre": "chess", "hp": 24}, Vector2i.ZERO, "VEX", ["jumpy"], vex.meters)
	_check(taste_vex.taste == vex.taste, "a monster given its traits gets the taste those traits shift, no random part")


func _mind_is_pinned() -> void:
	var rng := Rng.new(1)
	Flags.set_args(PackedStringArray([]))
	var mind = Minds.create(rng, "https://example.invalid", true)
	_check(mind.get_script() == LocalMind, "the slice thinks with the local rules even when a Jev address is saved")


func _fair_cut_route() -> void:
	var flow = await _start()
	var s = flow.state
	var vex = s.floor_map.monsters[1]
	_check(s.gold == 12 and s.foe.name == "ROOK", "starts with 12 gold against ROOK")
	await _press(flow, [2, 2])
	_check(s.stage == "result" and s.gold == 6 and s.foe.gone == "spared", "ROOK takes the 6-gold cut and leaves")
	await _press(flow, [1])
	_check(s.stage == "intro" and s.foe == vex, "CONTINUE goes on to VEX")
	await _to_menu(flow)
	var hp: int = s.hp
	await _press(flow, [2, 2])
	_check(s.gold == 6 and vex.gone == "" and s.hp == hp, "VEX refuses the cut: the gold stays, he stays, and he does not attack on that turn")
	await _press(flow, [3])
	_check(s.stage == "result" and vex.gone == "spared" and s.allies.size() == 1, "sparing VEX recruits him")
	await _press(flow, [1])
	_check(s.stage == "explore" and flow.fixed_roll < 0.0 and flow.slice_queue.is_empty(), "the slice is over and the floor is ordinary again")
	_check(flow.slice_floor, "the floor stays marked as the playtest floor, so it is never autosaved")
	await flow.new_run()
	_check(not flow.slice_floor, "a new floor is an ordinary one")


## A monster of the floor that happens to share the next bandit's name must not be taken for him.
func _names_do_not_matter() -> void:
	var flow = await _start()
	var s = flow.state
	var vex = s.floor_map.monsters[1]
	var twin = s.floor_map.monsters[2]
	twin.name = "VEX"
	s.floor_map.monsters[1] = twin
	s.floor_map.monsters[2] = vex
	await _press(flow, [2, 2, 1])
	_check(s.stage == "intro" and s.foe == vex, "the second fight is the slice's VEX even if another monster is called VEX")


func _retry_heals() -> void:
	var flow = await _start()
	var s = flow.state
	s.encounter_start.hp = 3 # the fight began at 3 HP
	s.stage = "dead"
	await flow.encounter.retry_fight()
	_check(s.hp == s.max_hp, "trying a fight again starts at full health, so a low-HP retry cannot loop")
	_check(flow.slice_queue.size() == 1 and flow.fixed_roll >= 0.0, "a retry keeps the slice going")


func _flee_ends_it() -> void:
	var flow = await _start()
	await _press(flow, [4])
	_check(flow.fixed_roll < 0.0 and flow.slice_queue.is_empty(), "fleeing ends the slice")
