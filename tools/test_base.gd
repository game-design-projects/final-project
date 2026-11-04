## What the tools/*_test.gd scripts share: the watchdog, the check lines and the exit code. A test extends this, names itself
## in `_name()`, and does its checks in `_run()`, ending with `_finish()`.
extends SceneTree

## How long a test may take before it is stopped as hung.
const WATCHDOG_S := 90

var _failed := 0


## The prefix of every line the test prints.
func _name() -> String:
	return "test"


func _initialize() -> void:
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
	print("%s: %s" % [_name(), "all checks passed" if _failed == 0 else "%d CHECK(S) FAILED" % _failed])
	quit(1 if _failed > 0 else 0)
