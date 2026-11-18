## What the tools/*_test.gd scripts share: the watchdog, the check lines, the script errors that fail a run, and the exit code. A test extends this, names itself
## in `_name()`, and does its checks in `_run()`, ending with `_finish()`.
extends SceneTree

const Fault = preload("res://src/utils/fault.gd")
const BaseFlags = preload("res://src/utils/flags.gd")

## How long a test may take before it is stopped as hung.
const WATCHDOG_S := 90

var _failed := 0


## The prefix of every line the test prints.
func _name() -> String:
	return "test"


## How many script errors the test causes on purpose (a test of what happens when something trips). Any other count fails it.
func _script_errors_meant() -> int:
	return 0


func _initialize() -> void:
	Fault.watch()
	# a suite never touches the player's store, whatever its command line says: `nosave` is on before anything else happens,
	# and the store heeds it from here (store.gd) for good. The save slots ask the flags every call, though, and a suite that
	# sets its own flags drops `nosave` again (`Flags.set_args` replaces them), so one that would write a save says it there too.
	BaseFlags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave"]))
	var store = root.get_node_or_null("Store")
	if store != null and store.persists():
		print("%s: FAIL the store still reaches the player's file" % _name())
		quit(1)
		return
	# a script error inside the awaiting checks would end `_run` without ever reaching quit(), so the run would hang
	create_timer(WATCHDOG_S).timeout.connect(func():
		print("%s: FAIL did not finish in %d s (a script error stopped it?)" % [_name(), WATCHDOG_S])
		quit(1))
	_run.call_deferred()


func _run() -> void:
	push_error("%s: _run is not written" % _name())
	quit(1)


func _check(ok: bool, what: String) -> void:
	print("%s: %s %s" % [_name(), "ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1


## Print the verdict and end with 1 if any check failed.
func _finish() -> void:
	# a debug build fails fast: a script error in any part of the game fails the test, whatever its own checks say
	var tripped := Fault.script_errors()
	if tripped != _script_errors_meant():
		print("%s: FAIL %d script error(s) where %d were meant, the first at %s" % [_name(), tripped, _script_errors_meant(), Fault.first_script_error()])
		_failed += 1
	print("%s: %s" % [_name(), "all checks passed" if _failed == 0 else "%d CHECK(S) FAILED" % _failed])
	quit(1 if _failed > 0 else 0)
