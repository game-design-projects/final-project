## Run flags. The web game read them from the address (?debug, #floor5-debug, ?nofx, ?nodebug); here the same words
## come from the address on the web build, and from the command line everywhere else:
##   godot --path . -- floor5-debug mock        (any spelling the JS regexes accepted: --debug, #floor5, ...)
## `text()` is the one string the JS tested its regexes against (location.search + location.hash).
extends RefCounted

static var _text = null
## Tests and tools can set this to pretend a different address / command line.
static var override = null


static func text() -> String:
	if override != null:
		return str(override)
	if _text == null:
		var parts: Array[String] = []
		if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
			var loc = JavaScriptBridge.eval("location.search + location.hash", true)
			if loc != null:
				parts.append(str(loc))
		parts.append_array(OS.get_cmdline_user_args())
		_text = " ".join(parts)
		print_verbose("flags: %s" % _text)
	return _text


## True when `pattern` (a regex, case-insensitive like the JS /…/i) matches the flags
static func test(pattern: String) -> bool:
	return RegEx.create_from_string("(?i)" + pattern).search(text()) != null


## The first capture group of `pattern`, or "" (e.g. capture("floor(\\d+)") -> "5")
static func capture(pattern: String) -> String:
	var m := RegEx.create_from_string("(?i)" + pattern).search(text())
	return m.get_string(1) if m and m.get_group_count() >= 1 else ""
