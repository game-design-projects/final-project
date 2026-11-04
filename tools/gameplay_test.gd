## Checks the gameplay scene with no window: after NEW FLOOR (or dying and choosing it) the header, status row, dock and
## overlay read the new floor's state, not the one that was replaced. Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/gameplay_test.gd
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")

const WATCHDOG_S := 60

var _failed := 0


func _initialize() -> void:
	# a script error inside the awaiting checks would end `_run` without ever reaching quit(), so the run would hang
	create_timer(WATCHDOG_S).timeout.connect(func():
		print("gameplay_test: FAIL did not finish in %d s (a script error stopped it?)" % WATCHDOG_S)
		quit(1))
	_run.call_deferred()


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
	print("gameplay_test: %s" % ("all checks passed" if _failed == 0 else "%d CHECK(S) FAILED" % _failed))
	quit(1 if _failed > 0 else 0)


func _bound(game) -> bool:
	var s = game.flow.state
	return game._header.state == s and game._status.state == s and game._dock.state == s and game._overlay.state == s


func _check(ok: bool, what: String) -> void:
	print("gameplay_test: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1
