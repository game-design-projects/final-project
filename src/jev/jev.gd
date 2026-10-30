## Asks the monsters' System One model. Three ways in, one request and answer shape (the System One API that TypeSafe's
## Jev introduced: a state, typed questions, calibrated probabilities back):
##   local      Decider, an open-weight System One model, in llama.cpp's llama-server on this computer (local.gd reads
##              its answers; local_server.gd starts the server)
##   systemone  any server that answers POST <apiBase>/v1/systemone itself (Decider's own server on a GPU box, ...)
##   mock       answers in-process from mock_jev.gd (no model)
## The module keeps the Jev name of the model the game first ran on. config.gd decides the way in. Load it with
## `const Jev = preload("res://src/jev/jev.gd")`.
##
## A transport is whatever carries one request: null means a real HTTPRequest; local.gd, mock_jev.gd and the tests pass
## an object with
##   fetch(url: String, headers: Dictionary, body: Dictionary) -> {"status": int, "json": Variant | "text": String}
## (a coroutine is fine), or {"error": String} like a fetch that rejects.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Http = preload("res://src/jev/http.gd")
const MockJev = preload("res://src/jev/mock_jev.gd")
const Local = preload("res://src/jev/local.gd")

const PATH := "/v1/systemone"
const LABELS := {"local": "Decider", "systemone": "System One", "mock": "Mock"}

## Seconds before one `systemone` request is given up on (a CPU-only server takes a while per round), and the first wait
## (ms) before retrying a 429/503/529 (doubles each time)
static var timeout_s := 300.0
static var backoff_ms := 400

static var via := "none"
static var provider: Dictionary = {}
static var transport = null
## When set to a directory (e.g. "user://jev-raw"), every raw text response body is written there before it is parsed, so
## a parse failure can be looked at. Opt-in: the live scenario scripts turn it on.
static var raw_dir := ""

static var _raw_seq := 0


## opts: via ("local" | "systemone" | "mock"; anything else, or nothing, leaves the model unconfigured), api_base
## (local: default Local.DEFAULT_BASE; systemone: required), model (systemone: the name sent), wait_s (local: how long
## the first request waits for the server to load), transport (see above; `local` and `mock` make their own unless one
## is given), seed and latency (mock).
static func configure_jev(opts := {}) -> void:
	transport = opts.get("transport")
	var base := str(opts.get("api_base", "")).rstrip("/")
	via = str(opts.get("via", "none"))
	match via:
		"local":
			if base == "":
				base = Local.DEFAULT_BASE
			provider = {"url": base + PATH, "model": "decider"}
			if transport == null:
				transport = Local.Server.new(base, {"wait_s": opts.get("wait_s", 3.0)})
		"systemone":
			provider = {"url": base + PATH, "model": str(opts.get("model", "decider"))}
			if base == "":
				via = "none"
		"mock":
			provider = {"url": MockJev.JEV_URL, "model": "jev-mock"}
			if transport == null:
				transport = MockJev.Server.new(opts.get("seed", 1), opts.get("latency", 0))
		_:
			via = "none"
	if via == "none":
		provider = {}


## True when jev() has somewhere to send its questions
static func is_configured() -> bool:
	return via != "none"


static func _label() -> String:
	return LABELS.get(via, "System One")


## Asks the model `questions` about `state`. `trace`: an Array to record this call into (debug mode); it gets exactly
## what went out and what came back. Returns the reply with "ms" added ({model, answers, usage, ms}), or {"error": String}
## (handle() turns it into a 500).
static func jev(state: Dictionary, questions: Dictionary, trace = null) -> Dictionary:
	if not is_configured():
		return {"error": "no System One model configured"}
	var t0 := J.date_ms()
	var entry = null
	if trace != null:
		entry = {"via": via, "model": provider["model"], "state": state, "questions": questions, "attempts": 0}
		trace.append(entry)
	var headers: Dictionary = {"content-type": "application/json"}
	var body := {"model": provider["model"], "state": state, "questions": questions}
	print_verbose("jev: %s %s, %d questions" % [via, provider["model"], questions.size()])
	var attempt := 0
	while true:
		var res: Dictionary = await _send(provider["url"], headers, body)
		if res.has("error"):
			var msg := "%s: %s" % [_label(), res["error"]]
			if entry != null:
				entry.merge({"ms": int(J.date_ms() - t0), "error": str(res["error"])}, true)
			push_warning(msg)
			return {"error": msg}
		if entry != null:
			entry["attempts"] = attempt + 1
		var status := int(res.get("status", 0))
		# Back off and retry when rate-limited or overloaded
		if (status == 429 or status == 503 or status == 529) and attempt < 3:
			print_verbose("jev: %d, retrying in %d ms" % [status, backoff_ms * (1 << attempt)])
			await J.sleep(backoff_ms * (1 << attempt))
			attempt += 1
			continue
		var parsed = res.get("json")
		var text := ""
		if parsed == null:
			text = str(res.get("text", ""))
			_save_raw(text)
		if status < 200 or status >= 300:
			if parsed != null:
				text = JSON.stringify(parsed)
			text = text.left(2000)
			if entry != null:
				entry.merge({"status": status, "ms": int(J.date_ms() - t0), "error": text}, true)
			var msg := "%s %d: %s" % [_label(), status, text.left(200)]
			push_warning(msg)
			return {"error": msg}
		if parsed == null:
			parsed = Http.parse(text)
		if not parsed is Dictionary:
			var msg := "%s: the reply was not a JSON object" % _label()
			if entry != null:
				entry.merge({"status": status, "ms": int(J.date_ms() - t0), "error": text.left(2000)}, true)
			push_warning(msg)
			return {"error": msg}
		var out: Dictionary = (parsed as Dictionary).duplicate()
		out["ms"] = int(J.date_ms() - t0)
		if entry != null:
			entry.merge({"status": status, "ms": out["ms"], "response": out}, true)
		return out
	return {"error": "unreachable"}


static func _send(url: String, headers: Dictionary, body: Dictionary) -> Dictionary:
	if transport != null:
		return await transport.fetch(url, headers, body)
	return await Http.request(HTTPClient.METHOD_POST, url, headers, body, timeout_s)


static func _save_raw(text: String) -> void:
	if raw_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(raw_dir)
	_raw_seq += 1
	var f := FileAccess.open("%s/%d-%03d.json" % [raw_dir, int(J.date_ms()), _raw_seq], FileAccess.WRITE)
	if f != null:
		f.store_string(text)
