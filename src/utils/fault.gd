## What the game does when one of its parts fails: a debug build fails fast, a production build carries on.
##
## The two builds already differ underneath (measured on 4.7.2 with a probe in the editor binary and in the 0.9.3 export):
##   debug    a script error (a key that isn't there, a call on null) ends the function it is in with an empty answer
##            ({} / 0.0 / false) and is logged; under the editor's debugger the game stops on that line.
##   export   there is no script error at all: the missing key reads as null, the function runs on to its end, nothing is
##            logged, and `assert` is not even evaluated. Nothing stops, and nothing says anything went wrong.
## So the debug build needs no help to fail fast, and stopping an export would only turn a wrong number into a dead game.
## What an export lacks is a place where a wrong answer is noticed. That place is the edge of a module: whoever takes an
## answer from a part that can fail checks it and calls `report`; then, if `tolerant()`, uses a spare answer instead.
##   if not ok(answer):
##       Fault.report("mind", "jev answered {} to mercy")   # debug: the debugger stops here
##       if Fault.tolerant(): answer = spare()              # export: the fight goes on, and the log says why
extends RefCounted

## Hears every script error the engine logs, whichever part of the game it is in. Only a debug build has any to hear: an
## export logs none. The tools turn it on (`watch`), so a script error anywhere fails the run instead of scrolling past in a
## log: a suite's checks can all pass while a function three calls down was cut short.
class Watch extends Logger:
	var _lock := Mutex.new() # the engine logs from any thread
	var _count := 0
	var _first := ""

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if error_type != Logger.ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		_count += 1
		if _first == "":
			_first = "%s:%d %s" % [file.get_file(), line, (rationale if rationale != "" else code).left(160)]
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_lock.lock()
		var n := _count
		_lock.unlock()
		return n

	func first() -> String:
		_lock.lock()
		var text := _first
		_lock.unlock()
		return text

static var _watch: Watch
static var forced = null # for tests: true = carry on as an export does, false = fail fast, null = as the build says
static var count := 0 # faults reported since the game started
static var last := "" # the latest one, for whoever shows or checks it


## True in a production build: a fault is logged and worked around. False in a debug build: it is an error to stop on.
static func tolerant() -> bool:
	return forced if forced != null else not OS.is_debug_build()


## A part of the game (`where`) gave something that can't be used (`what`).
static func report(where: String, what: String) -> void:
	count += 1
	last = "%s: %s" % [where, what]
	push_error("fault %d: %s" % [count, last])
	if not tolerant():
		assert(false, "fault: %s (a debug build stops here; an export carries on without it)" % last)


## Start counting script errors (once; calling it again changes nothing).
static func watch() -> void:
	if _watch == null:
		_watch = Watch.new()
		OS.add_logger(_watch)


## How many script errors there have been since `watch`, in any part of the game. 0 when nobody is watching.
static func script_errors() -> int:
	return 0 if _watch == null else _watch.count()


## Where the first of them was ("encounter.gd:122 Invalid access to ..."), or "".
static func first_script_error() -> String:
	return "" if _watch == null else _watch.first()
