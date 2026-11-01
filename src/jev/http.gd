## One HTTP request over HTTPRequest, for the System One clients (jev.gd, local.gd) and the local model's setup.
## Load it with `const Http = preload("res://src/jev/http.gd")`.
##
##   var r: Dictionary = await Http.request(HTTPClient.METHOD_POST, url, {"content-type": "application/json"}, body, 10.0)
##   r: {"status": int, "text": String}, or {"error": String} when nothing came back (timeout, nothing listening)
extends RefCounted

const J = preload("res://src/core/js.gd")

## HTTPRequest.Result, in words, for the log
const RESULT_NAMES := {
	1: "chunked body size mismatch", 2: "can't connect", 3: "can't resolve the host", 4: "connection error",
	5: "TLS handshake failed", 6: "no response", 7: "body too large", 8: "can't decompress the body", 9: "request failed",
	12: "too many redirects",
}


## `body`: a Dictionary or Array sent as JSON (insertion order, not sorted keys: the order of the questions and of their
## options is part of what the model reads), a String sent as it is, or null for none. `timeout_s` <= 0: no timeout.
static func request(method: int, url: String, headers: Dictionary, body = null, timeout_s := 10.0) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var req := HTTPRequest.new()
	req.timeout = maxf(timeout_s, 0.0)
	tree.root.add_child(req)
	var list := PackedStringArray()
	for k in headers:
		list.append("%s: %s" % [k, headers[k]])
	var data := ""
	if body is String:
		data = body
	elif body != null:
		data = JSON.stringify(body, "", false, true)
	var err := req.request(url, list, method, data)
	if err != OK:
		req.queue_free()
		return {"error": "request failed to start (%s)" % error_string(err)}
	var done: Array = await req.request_completed  # [result, response_code, headers, body]
	req.queue_free()
	if int(done[0]) != HTTPRequest.RESULT_SUCCESS:
		if int(done[0]) == HTTPRequest.RESULT_TIMEOUT:
			return {"error": "timed out after %s s" % J.num(timeout_s)}
		return {"error": "%s (HTTPRequest result %d)" % [RESULT_NAMES.get(int(done[0]), "request failed"), int(done[0])]}
	return {"status": int(done[1]), "text": (done[3] as PackedByteArray).get_string_from_utf8()}


## The text of a reply parsed as JSON, or null (not JSON.parse_string: that prints an engine error for text that isn't JSON,
## and an engine error fails the test that walks it)
static func parse(text: String):
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null
