## Headless test runner. Finds res://tests/**/test_*.gd, runs every `test_*` method, exits non-zero on failure.
##   godot --headless --path . -s res://tests/run_tests.gd                 # everything
##   godot --headless --path . -s res://tests/run_tests.gd -- --only=dnd   # files whose path contains "dnd"
## A script error raised inside a test (bad index, null access...) fails that test: a Logger counts them.
extends SceneTree


class ErrorCounter:
	extends Logger
	var errors: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale else code, file, line, function])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var counter := ErrorCounter.new()


func _initialize() -> void:
	OS.add_logger(counter)
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var files: Array[String] = []
	_collect("res://tests", files)
	files.sort()
	var passed := 0
	var failed: Array[String] = []
	var t0 := Time.get_ticks_msec()
	for path in files:
		if only and not path.contains(only):
			continue
		var script = load(path)
		if script == null or not script.can_instantiate():
			failed.append("%s: does not load (parse error?)" % path)
			print("✗ %s does not load" % path)
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_") and not methods.has(m.name):
				methods.append(m.name)
		for m in methods:
			var t = script.new()
			if t.has_method("before_each"):
				await t.before_each()
			var errors_before := counter.errors.size()
			await t.call(m)
			if t.has_method("after_each"):
				await t.after_each()
			var problems: Array[String] = t.failures.duplicate()
			for e in counter.errors.slice(errors_before):
				problems.append("script error: " + e)
			var name := "%s › %s" % [path.trim_prefix("res://tests/"), m]
			if problems.is_empty():
				passed += 1
			else:
				failed.append(name)
				print("✗ %s" % name)
				for p in problems:
					print("    " + p)
	print("\n%d passed, %d failed (%d ms)" % [passed, failed.size(), Time.get_ticks_msec() - t0])
	quit(1 if failed.size() > 0 or passed == 0 else 0)


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)
