## Debug: every API request the game makes, newest first, with the raw Jev calls behind it (what went to the
## model and what came back). Lives in the Jev panel's REQUESTS tab. `summarize` and `find_value` are pure;
## `highlight_json` builds BBCode for a RichTextLabel; the panel itself is wired by src/ui.
## A request log entry is {n, path, at, request, status, ms, response, error?, jev?: [{state, questions, response:
## {answers, usage: {input_tokens}}, ms, attempts, error}]}.
extends RefCounted

const J = preload("res://src/core/js.gd")

## BBCode colors per token kind, as the pixel palette has them: keys, strings, numbers, true/false/null.
const COLORS = {"k": "#7fd6ff", "s": "#f2e6c4", "n": "#6bd36b", "b": "#ff9de2"}

static var _token_re := RegEx.create_from_string("(\"(?:\\\\u[a-fA-F0-9]{4}|\\\\[^u]|[^\\\\\"])*\")(\\s*:)?|\\b(true|false|null)\\b|-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?")


## One line per request: what it was, how it went, what it cost.
## Returns {name, state: pending|ok|bad, status, ms, calls, questions, tokens, traced}.
static func summarize(e: Dictionary) -> Dictionary:
	var calls: Array = J.nz(e.get("jev"), [])
	var questions := 0
	var tokens = 0 # JSON numbers are floats, hand-built ones ints
	for c: Dictionary in calls:
		questions += (J.nz(c.get("questions"), {}) as Dictionary).size()
		var response = c.get("response")
		var usage = response.get("usage") if response is Dictionary else null
		tokens += J.nz(usage.get("input_tokens") if usage is Dictionary else null, 0)
	var status = e.get("status")
	var is_ok: bool = (status is int or status is float) and status < 400
	return {
		"name": str(e.path).trim_prefix("/api/").replace("-", " ").to_upper(),
		"state": "pending" if status == null else ("ok" if is_ok else "bad"),
		"status": "…" if status == null else J.num(status),
		"ms": e.get("ms"),
		"calls": calls.size(),
		"questions": questions,
		"tokens": tokens,
		"traced": e.get("jev") != null,
	}


## `JSON.stringify(value, null, 2)` as JS writes it: two-space indent, keys in insertion order, whole numbers without ".0".
static func json_text(value, indent := "") -> String:
	if value is Dictionary:
		if value.is_empty():
			return "{}"
		var inner := indent + "  "
		var parts := []
		for k in value:
			parts.append("%s%s: %s" % [inner, JSON.stringify(str(k)), json_text(value[k], inner)])
		return "{\n%s\n%s}" % [",\n".join(parts), indent]
	if value is Array:
		if value.is_empty():
			return "[]"
		var inner := indent + "  "
		var parts := []
		for v in value:
			parts.append(inner + json_text(v, inner))
		return "[\n%s\n%s]" % [",\n".join(parts), indent]
	if value is String or value is StringName:
		return JSON.stringify(str(value))
	if value is int or value is float:
		return J.num(value)
	if value is bool:
		return "true" if value else "false"
	if value == null:
		return "null"
	return JSON.stringify(str(value)) # anything Godot-only (a Vector2...) reads as its text


## Text in a RichTextLabel with the BBCode brackets escaped.
static func bb_escape(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i]
		out += "[lb]" if c == "[" else ("[rb]" if c == "]" else c)
	return out


## Pretty JSON as BBCode for a RichTextLabel, each token in the pixel palette: keys, strings, numbers, true/false/null
## (`[` and `]` come out as `[lb]` / `[rb]`).
static func highlight_json(value) -> String:
	var text := json_text(value)
	var out := ""
	var last := 0
	for m in _token_re.search_all(text):
		out += bb_escape(text.substr(last, m.get_start() - last))
		var token := m.get_string()
		if m.get_string(1) != "":
			var cls: String = "k" if m.get_string(2) != "" else "s"
			out += "[color=%s]%s[/color]%s" % [COLORS[cls], bb_escape(m.get_string(1)), bb_escape(m.get_string(2))]
		else:
			out += "[color=%s]%s[/color]" % [COLORS["b" if m.get_string(3) != "" else "n"], bb_escape(token)]
		last = m.get_end()
	return out + bb_escape(text.substr(last))


## What a COPY button refers to: "n:request", "n:response", "n:i:state|questions|answers", or "n" (the whole entry).
## Returns the piece, or null when it isn't there.
static func find_value(log: Array, key: String):
	var parts := key.split(":")
	var n := parts[0]
	if not n.is_valid_float():
		return null
	var found = null
	for x: Dictionary in log:
		if x.get("n") == n.to_float():
			found = x
			break
	if found == null:
		return null
	if parts.size() < 2:
		return found
	var a := parts[1]
	if a == "request" or a == "response":
		return found.get(a)
	var jev = found.get("jev")
	var idx := int(a)
	var c = jev[idx] if jev is Array and a.is_valid_int() and idx >= 0 and idx < jev.size() else null
	if c == null:
		return null
	var b := parts[2] if parts.size() > 2 else ""
	if b == "answers":
		var response = c.get("response")
		return response.get("answers") if response is Dictionary else null
	return c.get(b)


## The text a COPY button puts on the clipboard: the piece as pretty JSON ("null" when it isn't there). Sets the
## clipboard too, except when running headless.
static func copy_value(log: Array, key: String) -> String:
	var text := json_text(find_value(log, key))
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(text)
	else:
		print_verbose("inspector: headless, not copying %d chars" % text.length())
	return text
