## Checks the gameplay scene with no window: after NEW FLOOR (or dying and choosing it) and after loading a save, the
## header, status row, dock and overlay read the new state, not the one that was replaced. Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/gameplay_test.gd
extends "res://tools/test_base.gd"

const Flags = preload("res://src/utils/flags.gd")


func _name() -> String:
	return "gameplay_test"


func _run() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=11"]))
	var game = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await game._begin()
	_check(_bound(game), "the views read the first floor's state")
	var first = game.flow.state
	await game.flow.new_run()
	_check(game.flow.state != first, "NEW FLOOR makes a new state")
	_check(_bound(game), "after NEW FLOOR the header, status row, dock and overlay read the new state")
	game.flow.state.hp = 0
	game.flow.state.stage = "dead"
	await game.flow.new_run()
	_check(_bound(game), "the same after a death")
	game.flow.state.gold = 8
	var saved: Dictionary = game.flow.state.to_dict()
	await game.flow.new_run()
	var before = game.flow.state
	before.gold = 99 # so the loaded state is told apart from the one it replaces
	var loaded: bool = await game.flow.load_state(saved)
	_check(loaded and game.flow.state != before and game.flow.state.gold == 8, "loading a save makes a new state with the saved gold (8, not the replaced state's 99)")
	_check(_bound(game), "after loading a save the views read the loaded state (nothing else rebinds them)")
	var kept = game.flow.state
	_check(not await game.flow.load_state({}) and game.flow.state == kept and kept.gold == 8 and _bound(game), "a save that cannot be loaded leaves the state, and the views on it, as they were")
	_finish()


func _bound(game) -> bool:
	var s = game.flow.state
	return game._header.state == s and game._status.state == s and game._dock.state == s and game._overlay.state == s


