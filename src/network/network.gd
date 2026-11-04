## The one place the game talks to the internet. Callers get a plain answer, never a hang: every request has the same
## timeout, a failed one is retried a couple of times with a growing wait, and after several failures in a row the
## network is treated as down for a while, so the game falls back to its local rules at once instead of making the
## player wait for every question. A proxy that says it has no key ("Server not configured", a 503) is not retried and
## counts as down at once: waiting won't change that answer. `waiting_ms` tells the screen how long a question has been out.
##   var r = await Network.post_json("https://…/api/jev", {"state": …})
##   if r.ok: use(r.json) else: fall_back(r.error)
extends RefCounted

const TIMEOUT_S := 8.0
const RETRIES := 2 # after the first try, only for 429 / 5xx / a connection that failed
const BACKOFF_S := 0.4 # doubles each retry
const GIVE_UP_AFTER := 3 # failures in a row before the network is called down...
const DOWN_FOR_S := 30.0 # ...for this long

const NOT_CONFIGURED := "not configured" # what the proxy's 503 says when it has no key

const RESULT_NAMES := {
	1: "chunked body size mismatch", 2: "can't connect", 3: "can't resolve the host", 4: "connection error",
	5: "TLS handshake failed", 6: "no response", 7: "body too large", 8: "can't decompress the body", 9: "request failed",
	12: "too many redirects",
}

## Tests set this to stand in for the internet: (url, payload, headers, timeout_s) -> what `_send` returns, awaited.
static var transport := Callable()

static var _failures := 0
static var _down_until := 0.0 # seconds on the engine clock
static var _flights := {} # id -> the engine's msec when that question went out, for the ones still waiting
static var _next_flight := 0


## True while the network is considered down (callers can skip straight to their fallback).
static func is_down() -> bool:
	return _now() < _down_until


## Forget past failures (a settings change, a new run).
static func reset() -> void:
	_failures = 0
	_down_until = 0.0


## How long the longest-waiting question has been out, in ms; 0 when nothing is waiting (the screen shows "thinking").
static func waiting_ms() -> int:
	if _flights.is_empty():
		return 0
	return Time.get_ticks_msec() - int(_flights.values().min())


## POST `body` as JSON. Returns {"ok": bool, "status": int, "json": Variant, "text": String, "error": String, "ms": int}.
static func post_json(url: String, body: Dictionary, headers := {}, timeout_s := TIMEOUT_S) -> Dictionary:
	if is_down():
		return _fail("network is down, skipping %s" % url, 0, Time.get_ticks_msec())
	_next_flight += 1
	var id := _next_flight
	_flights[id] = Time.get_ticks_msec()
	var result := await _post(url, body, headers, timeout_s)
	_flights.erase(id)
	return result


static func _post(url: String, body: Dictionary, headers: Dictionary, timeout_s: float) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var payload := JSON.stringify(body, "", false, true) # insertion order: the order of the questions is part of what is asked
	var attempt := 0
	while true:
		var res: Dictionary
		if transport.is_valid():
			res = await transport.call(url, payload, headers, timeout_s)
		else:
			res = await _send(url, payload, headers, timeout_s)
		if res.get("status", 0) == 503 and str(res.get("text", "")).to_lower().contains(NOT_CONFIGURED):
			push_warning("network: %s has no key (503 %s), not retrying" % [url, NOT_CONFIGURED])
			_failures = GIVE_UP_AFTER - 1 # the answer will not change in a few seconds: this one takes it over the line
			return _failed_for_good("status 503: %s" % str(res.text).left(200), 503, t0)
		var why: String = res.error if res.has("error") else ("status %d" % res.status if res.status == 429 or res.status >= 500 else "")
		if why != "" and attempt < RETRIES:
			var wait := BACKOFF_S * (1 << attempt)
			print_verbose("network: %s, retrying in %.1f s" % [why, wait])
			await Engine.get_main_loop().create_timer(wait).timeout
			attempt += 1
			continue
		if res.has("error"):
			return _failed_for_good(res.error, 0, t0)
		if res.status < 200 or res.status >= 300:
			return _failed_for_good("status %d: %s" % [res.status, str(res.text).left(200)], res.status, t0)
		var parsed := JSON.new() # not parse_string: that prints an engine error for text that isn't JSON
		if parsed.parse(res.text) != OK:
			return _failed_for_good("the reply was not JSON", res.status, t0)
		_failures = 0
		var ms := Time.get_ticks_msec() - t0
		print_verbose("network: %s -> %d in %d ms" % [url, res.status, ms])
		return {"ok": true, "status": res.status, "json": parsed.data, "text": res.text, "error": "", "ms": ms}
	return {}


static func _send(url: String, payload: String, headers: Dictionary, timeout_s: float) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var req := HTTPRequest.new()
	req.timeout = timeout_s
	tree.root.add_child(req)
	var list := PackedStringArray(["content-type: application/json"])
	for k in headers:
		list.append("%s: %s" % [k, headers[k]])
	var err := req.request(url, list, HTTPClient.METHOD_POST, payload)
	if err != OK:
		req.queue_free()
		return {"error": "request failed to start (%s)" % error_string(err)}
	var done: Array = await req.request_completed # [result, code, headers, body]
	req.queue_free()
	if int(done[0]) == HTTPRequest.RESULT_TIMEOUT:
		return {"error": "timed out after %.0f s" % timeout_s}
	if int(done[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"error": "%s (result %d)" % [RESULT_NAMES.get(int(done[0]), "request failed"), int(done[0])]}
	return {"status": int(done[1]), "text": (done[3] as PackedByteArray).get_string_from_utf8()}


static func _failed_for_good(error: String, status: int, t0: int) -> Dictionary:
	_failures += 1
	if _failures >= GIVE_UP_AFTER:
		_down_until = _now() + DOWN_FOR_S
		push_warning("network: %d failures in a row, offline for %.0f s" % [_failures, DOWN_FOR_S])
	return _fail(error, status, t0)


static func _fail(error: String, status: int, t0: int) -> Dictionary:
	push_warning("network: %s" % error)
	return {"ok": false, "status": status, "json": null, "text": "", "error": error, "ms": Time.get_ticks_msec() - t0}


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
