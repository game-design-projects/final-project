## Base for every test file: extend it, write `func test_something():` methods (they may await).
## Each assertion that fails records a message; a script error inside a test fails it too (see run_tests.gd).
extends RefCounted

var failures: Array[String] = []
var assertions := 0


func ok(cond, msg := "expected true") -> bool:
	assertions += 1
	if not cond:
		failures.append(msg)
		return false
	return true


func eq(actual, expected, msg := "") -> bool:
	assertions += 1
	if not _same(actual, expected):
		failures.append("%sexpected %s, got %s" % [(msg + ": ") if msg else "", _show(expected), _show(actual)])
		return false
	return true


func ne(actual, unexpected, msg := "") -> bool:
	assertions += 1
	if _same(actual, unexpected):
		failures.append("%sdid not expect %s" % [(msg + ": ") if msg else "", _show(unexpected)])
		return false
	return true


func near(actual: float, expected: float, eps := 1e-6, msg := "") -> bool:
	assertions += 1
	if absf(actual - expected) > eps:
		failures.append("%sexpected %s ± %s, got %s" % [(msg + ": ") if msg else "", expected, eps, actual])
		return false
	return true


func match_re(text: String, pattern: String, msg := "") -> bool:
	var re := RegEx.create_from_string(pattern)
	assertions += 1
	if re == null or re.search(text) == null:
		failures.append("%s%s does not match /%s/" % [(msg + ": ") if msg else "", _show(text), pattern])
		return false
	return true


func fail(msg: String) -> void:
	assertions += 1
	failures.append(msg)


# Deep equality where 3 == 3.0 (JSON numbers come back as floats), like assert.deepStrictEqual on parsed data
static func _same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	if typeof(a) != typeof(b):
		if (a is String or a is StringName) and (b is String or b is StringName):
			return String(a) == String(b)
		return false
	return a == b


static func _show(v) -> String:
	if v is String:
		return JSON.stringify(v)
	if v is Array or v is Dictionary:
		var s := JSON.stringify(v)
		return s if s.length() <= 300 else s.left(300) + "…"
	return str(v)
