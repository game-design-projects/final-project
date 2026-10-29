## Calls Jev. Four ways in, same model family and same request/answer shapes:
##   typesafe    TypeSafe's own System One endpoint
##   openrouter  OpenRouter's decisions API (which serves TypeSafe's Jev)
##   proxy       a Worker that holds the key (proxy/): POST {model, state, questions} to <apiBase>/api/jev, no key sent
##   mock        answers in-process from mock_jev.gd (no key, no credits)
## The key is whatever the caller configures (config.gd decides). Load it with `const Jev = preload("res://src/jev/jev.gd")`.
##
## A transport is whatever carries one request: null means a real HTTPRequest; tests and `mock` pass an object with
##   fetch(url: String, headers: Dictionary, body: Dictionary) -> {"status": int, "json": Variant | "text": String}
## (a coroutine is fine), or {"error": String} like a fetch that rejects.
extends RefCounted

const J = preload("res://src/core/js.gd")
const MockJev = preload("res://src/jev/mock_jev.gd")

const PROVIDERS := {
	"typesafe": {"url": "https://api.typesafe.ai/v1/systemone", "model": "jev-latest", "headers": {}},
	"openrouter": {"url": "https://openrouter.ai/api/alpha/decisions", "model": "~typesafe/jev-latest", "headers": {"x-title": "Donjon"}},
}

## Seconds before a request is given up on, and the first wait (ms) before retrying a 429/529 (doubles each time)
static var timeout_s := 10.0
static var backoff_ms := 400

static var api_key = null
static var via := "typesafe"
static var provider: Dictionary = PROVIDERS["typesafe"]
static var transport = null
## When set to a directory (e.g. "user://jev-raw"), every raw response body is written there before it is parsed, so a
## parse failure costs nothing to redo. Opt-in: the live scenario scripts turn it on.
static var raw_dir := ""

static var _raw_seq := 0


## configureJev(key, { via }). `opts`: via ("typesafe" | "openrouter" | "proxy" | "mock"), api_base (proxy),
## transport (see above; `mock` makes its own MockJev.Server unless one is given), seed and latency (for `mock`).
## An unknown via is "typesafe", as in the JS.
static func configure_jev(key, opts := {}) -> void:
	api_key = key
	transport = opts.get("transport")
	var v: String = opts.get("via", "typesafe")
	if v == "proxy":
		via = "proxy"
		provider = {"url": str(opts.get("api_base", "")).rstrip("/") + "/api/jev", "model": "jev-latest", "headers": {}}
	elif v == "mock":
		via = "mock"
		provider = {"url": MockJev.JEV_URL, "model": "jev-mock", "headers": {}}
		if transport == null:
			transport = MockJev.Server.new(opts.get("seed", 1), opts.get("latency", 0))
	else:
		via = v if PROVIDERS.has(v) else "typesafe"
		provider = PROVIDERS[via]


## True when jev() has what it needs: a key, or a way in that has none (proxy, mock)
static func is_configured() -> bool:
	return via == "proxy" or via == "mock" or (api_key != null and str(api_key) != "")


static func _label() -> String:
	return {"openrouter": "OpenRouter", "proxy": "Proxy", "mock": "Mock"}.get(via, "TypeSafe")


## Asks Jev `questions` about `state`. `trace`: an Array to record this call into (debug mode); it gets exactly what
## went out and what came back, never the key. Returns Jev's reply with "ms" added ({model, answers, usage, ms}), or
## {"error": String} (the JS throws; handle() turns it into a 500).
static func jev(state: Dictionary, questions: Dictionary, trace = null) -> Dictionary:
	if not is_configured():
		return {"error": "Jev API key not configured"}
	var t0 := J.date_ms()
	var entry = null
	if trace != null:
		entry = {"via": via, "model": provider["model"], "state": state, "questions": questions, "attempts": 0}
		trace.append(entry)
	var headers: Dictionary = {"content-type": "application/json"}
	if via != "proxy" and via != "mock":
		headers["authorization"] = "Bearer %s" % str(api_key)
	headers.merge(provider["headers"], true)
	var body := {"model": provider["model"], "state": state, "questions": questions}
	print_verbose("jev: %s %s, %d questions" % [via, provider["model"], questions.size()])
	var attempt := 0
	while true:
		var res: Dictionary = await _send(provider["url"], headers, body)
		if res.has("error"):
			var msg := "Jev (%s): %s" % [_label(), res["error"]]
			if entry != null:
				entry.merge({"ms": int(J.date_ms() - t0), "error": str(res["error"])}, true)
			push_warning(msg)
			return {"error": msg}
		if entry != null:
			entry["attempts"] = attempt + 1
		var status := int(res.get("status", 0))
		# Back off and retry when rate-limited or overloaded, as the API docs recommend
		if (status == 429 or status == 529) and attempt < 3:
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
			var msg := "Jev (%s) %d: %s" % [_label(), status, text.left(200)]
			push_warning(msg)
			return {"error": msg}
		if parsed == null:
			parsed = JSON.parse_string(text)
		if not parsed is Dictionary:
			var msg := "Jev (%s): the reply was not a JSON object" % _label()
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
	return await _http(url, headers, body)


## One POST over HTTPRequest. Returns {"status", "text"}, or {"error"} when nothing came back (timeout, no network).
static func _http(url: String, headers: Dictionary, body: Dictionary) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var req := HTTPRequest.new()
	req.timeout = timeout_s
	tree.root.add_child(req)
	var list := PackedStringArray()
	for k in headers:
		list.append("%s: %s" % [k, headers[k]])
	# insertion order, not sorted keys: the order of the questions and of their options is part of what Jev reads
	var err := req.request(url, list, HTTPClient.METHOD_POST, JSON.stringify(body, "", false, true))
	if err != OK:
		req.queue_free()
		return {"error": "request failed to start (%s)" % error_string(err)}
	var done: Array = await req.request_completed  # [result, response_code, headers, body]
	req.queue_free()
	if int(done[0]) != HTTPRequest.RESULT_SUCCESS:
		var reason := "timed out after %s s" % J.num(timeout_s) if int(done[0]) == HTTPRequest.RESULT_TIMEOUT else "no response (HTTPRequest result %d)" % int(done[0])
		return {"error": reason}
	return {"status": int(done[1]), "text": (done[3] as PackedByteArray).get_string_from_utf8()}


static func _save_raw(text: String) -> void:
	if raw_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(raw_dir)
	_raw_seq += 1
	var f := FileAccess.open("%s/%d-%03d.json" % [raw_dir, int(J.date_ms()), _raw_seq], FileAccess.WRITE)
	if f != null:
		f.store_string(text)
