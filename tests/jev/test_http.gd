# The real HTTP path (HTTPRequest) against a throwaway server on 127.0.0.1: what goes on the wire, what comes back,
# and the timeout. Nothing leaves the machine.
extends "res://tests/test_case.gd"

const Jev = preload("res://src/jev/jev.gd")
const Q = preload("res://src/jev/q.gd")
const J = preload("res://src/core/js.gd")


func after_each():
	Jev.configure_jev(null)
	Jev.timeout_s = 10.0
	Jev.backoff_ms = 400


## One-shot HTTP server on a thread: serves `replies` in order (the last repeats), records each request, and with
## hang = true reads the request and then never answers.
class Server:
	extends RefCounted
	var tcp := TCPServer.new()
	var thread := Thread.new()
	var replies: Array
	var hang := false
	var stop := false
	var requests: Array = []  # {request_line, headers (lowercased names), body}
	var mutex := Mutex.new()
	var port := 0

	func _init(r: Array, hang_forever := false) -> void:
		replies = r
		hang = hang_forever
		# a port from the dynamic range; take the next free one
		port = 49200 + randi() % 800
		while tcp.listen(port, "127.0.0.1") != OK:
			port += 1
		thread.start(_serve)

	func finish() -> void:
		stop = true
		thread.wait_to_finish()
		tcp.stop()

	func _serve() -> void:
		var served := 0
		while not stop:
			if not tcp.is_connection_available():
				OS.delay_msec(2)
				continue
			var peer := tcp.take_connection()
			var raw := PackedByteArray()
			var head_end := -1
			var deadline := Time.get_ticks_msec() + 3000
			var content_length := 0
			while Time.get_ticks_msec() < deadline and not stop:
				peer.poll()
				if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
					break
				var avail := peer.get_available_bytes()
				if avail > 0:
					raw.append_array(peer.get_data(avail)[1])
				else:
					OS.delay_msec(2)
				if head_end == -1:
					head_end = raw.get_string_from_utf8().find("\r\n\r\n")
					if head_end != -1:
						for line in raw.get_string_from_utf8().substr(0, head_end).split("\r\n"):
							if line.to_lower().begins_with("content-length:"):
								content_length = int(line.split(":")[1])
				if head_end != -1 and raw.size() >= head_end + 4 + content_length:
					break
			var text := raw.get_string_from_utf8()
			var lines := text.substr(0, maxi(head_end, 0)).split("\r\n")
			var headers := {}
			for i in range(1, lines.size()):
				var kv := lines[i].split(":", true, 1)
				if kv.size() == 2:
					headers[kv[0].strip_edges().to_lower()] = kv[1].strip_edges()
			mutex.lock()
			requests.append({"request_line": lines[0], "headers": headers, "body": text.substr(head_end + 4) if head_end != -1 else ""})
			mutex.unlock()
			if hang:
				while not stop:
					OS.delay_msec(5)
				peer.disconnect_from_host()
				return
			var reply: Dictionary = replies[mini(served, replies.size() - 1)]
			served += 1
			var payload: PackedByteArray = str(reply["body"]).to_utf8_buffer()
			var head := "HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [reply["status"], payload.size()]
			peer.put_data(head.to_utf8_buffer())
			peer.put_data(payload)
			OS.delay_msec(20)
			peer.disconnect_from_host()


func ok_body() -> String:
	return JSON.stringify({"model": "wire", "answers": {"q": {"type": "noul", "noul": 0.25}}, "usage": {"input_tokens": 3}})


func test_a_real_request_carries_the_headers_and_the_body_in_order_and_parses_the_reply():
	var server := Server.new([{"status": 200, "body": ok_body()}])
	# the OpenRouter shape (key, x-title, model) pointed at the local server
	Jev.configure_jev("wire-key", {"via": "openrouter"})
	Jev.provider = Jev.provider.merged({"url": "http://127.0.0.1:%d/v1/decisions" % server.port}, true)
	var questions := {"zeta": Q.noul("last?"), "alpha": Q.choice("first?", {"b": "B", "a": "A"})}
	var trace := []
	var r := await Jev.jev({"who": "né – ≥"}, questions, trace)
	server.finish()
	eq(r["model"], "wire")
	eq(r["answers"]["q"]["noul"], 0.25)
	eq(trace[0]["status"], 200)
	eq(server.requests.size(), 1)
	var req: Dictionary = server.requests[0]
	eq(req["request_line"], "POST /v1/decisions HTTP/1.1")
	eq(req["headers"]["authorization"], "Bearer wire-key")
	eq(req["headers"]["x-title"], "Donjon")
	eq(req["headers"]["content-type"], "application/json")
	var sent = JSON.parse_string(req["body"])
	eq(sent["model"], "~typesafe/jev-latest")
	eq(sent["state"]["who"], "né – ≥", "UTF-8 survives")
	eq(sent["questions"].keys(), ["zeta", "alpha"], "question order is kept, not sorted")
	eq(sent["questions"]["alpha"]["criteria"].keys(), ["b", "a"], "option order is kept, not sorted")


func test_an_http_error_status_comes_back_as_an_error():
	var server := Server.new([{"status": 401, "body": "{\"error\":\"bad key\"}"}])
	Jev.configure_jev("k", {"via": "proxy", "api_base": "http://127.0.0.1:%d" % server.port})
	var r := await Jev.jev({}, {"q": Q.noul("x")})
	server.finish()
	eq(r["error"], "Jev (Proxy) 401: {\"error\":\"bad key\"}")


func test_a_429_over_the_wire_is_retried():
	var server := Server.new([{"status": 429, "body": "slow"}, {"status": 200, "body": ok_body()}])
	Jev.backoff_ms = 5
	Jev.configure_jev("k", {"via": "proxy", "api_base": "http://127.0.0.1:%d" % server.port})
	var trace := []
	var r := await Jev.jev({}, {"q": Q.noul("x")}, trace)
	server.finish()
	ok(not r.has("error"), str(r))
	eq(trace[0]["attempts"], 2)
	eq(server.requests.size(), 2)


func test_a_server_that_never_answers_times_out():
	var server := Server.new([], true)
	Jev.timeout_s = 0.4
	Jev.configure_jev("k", {"via": "proxy", "api_base": "http://127.0.0.1:%d" % server.port})
	var trace := []
	var t0 := Time.get_ticks_msec()
	var r := await Jev.jev({}, {"q": Q.noul("x")}, trace)
	server.finish()
	ok(r.has("error"), str(r))
	ok(r["error"].contains("timed out"), r["error"])
	ok(Time.get_ticks_msec() - t0 < 3000, "gave up in time")
	ok(trace[0]["error"].contains("timed out"))


func test_nothing_listening_is_an_error_not_a_hang():
	# bind and release a port, so nothing listens there
	var probe := TCPServer.new()
	var port := 49000 + randi() % 150
	while probe.listen(port, "127.0.0.1") != OK:
		port += 1
	probe.stop()
	Jev.configure_jev("k", {"via": "proxy", "api_base": "http://127.0.0.1:%d" % port})
	var r := await Jev.jev({}, {"q": Q.noul("x")})
	# macOS reports a refused connection as a connection error, Linux as can't connect
	ok(r.has("error") and (r["error"].contains("connection error") or r["error"].contains("can't connect")), str(r))
