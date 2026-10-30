# The System One client: which URL, headers and body go out for each way in, the trace, retries with backoff, and errors.
extends "res://tests/test_case.gd"

const Jev = preload("res://src/jev/jev.gd")
const MockJev = preload("res://src/jev/mock_jev.gd")
const Local = preload("res://src/jev/local.gd")
const Q = preload("res://src/jev/q.gd")
const J = preload("res://src/core/js.gd")

const STATE := {"who": "a goblin"}


func before_each():
	Jev.configure_jev()
	Jev.backoff_ms = 1
	Jev.raw_dir = ""


func after_each():
	Jev.configure_jev()
	Jev.backoff_ms = 400
	Jev.raw_dir = ""


func questions() -> Dictionary:
	return {"mood": Q.choice("How does it feel?", {"calm": "Calm", "angry": "Angry"}), "joke": Q.noul("Was that a joke?")}


## A transport that plays back canned replies (the last one repeats) and records every request.
class Canned:
	extends RefCounted
	var replies: Array
	var requests: Array = []

	func _init(r: Array) -> void:
		replies = r

	func fetch(url, headers, body) -> Dictionary:
		requests.append({"url": url, "headers": headers.duplicate(), "body": body.duplicate(true)})
		return replies[mini(requests.size() - 1, replies.size() - 1)]


static func ok_reply() -> Dictionary:
	return {"status": 200, "json": {"model": "jev-x", "answers": {"mood": {"type": "choice", "choice": "calm", "probabilities": {"calm": 1, "angry": 0}}}, "usage": {"input_tokens": 5}}}


func test_without_a_model_it_is_an_error_and_nothing_is_traced():
	var trace := []
	var r := await Jev.jev(STATE, questions(), trace)
	eq(r, {"error": "no System One model configured"})
	eq(trace, [])
	ok(not Jev.is_configured())
	Jev.configure_jev({"via": "systemone"})
	ok(not Jev.is_configured(), "a System One server needs an address")
	Jev.configure_jev({"via": "nonsense", "api_base": "http://s1.test"})
	ok(not Jev.is_configured(), "an unknown way in is none")
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test"})
	ok(Jev.is_configured())


func test_systemone_request_shape_and_trace():
	var t := Canned.new([ok_reply()])
	Jev.configure_jev({"via": "systemone", "api_base": "http://gpu-box:8000/", "transport": t})
	var trace := []
	var r := await Jev.jev(STATE, questions(), trace)
	eq(r["model"], "jev-x")
	ok(r["ms"] >= 0)
	var req: Dictionary = t.requests[0]
	eq(req["url"], "http://gpu-box:8000/v1/systemone")
	eq(req["headers"], {"content-type": "application/json"}, "no key goes anywhere")
	eq(req["body"], {"model": "decider", "state": STATE, "questions": questions()})
	eq(req["body"].keys(), ["model", "state", "questions"])
	eq(trace.size(), 1)
	var e: Dictionary = trace[0]
	eq([e["via"], e["model"], e["attempts"], e["status"]], ["systemone", "decider", 1, 200])
	eq(e["state"], STATE)
	eq(e["response"]["usage"], {"input_tokens": 5})


func test_systemone_sends_the_model_it_was_given():
	var t := Canned.new([ok_reply()])
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "model": "clef", "transport": t})
	await Jev.jev(STATE, questions())
	eq(t.requests[0]["body"]["model"], "clef")


func test_local_goes_to_the_local_server():
	var t := Canned.new([ok_reply()])
	Jev.configure_jev({"via": "local", "transport": t})
	var trace := []
	await Jev.jev(STATE, questions(), trace)
	eq(t.requests[0]["url"], Local.DEFAULT_BASE + "/v1/systemone")
	eq([trace[0]["via"], trace[0]["model"]], ["local", "decider"])
	Jev.configure_jev({"via": "local", "api_base": "http://127.0.0.1:9999/", "transport": t})
	await Jev.jev(STATE, questions())
	eq(t.requests[1]["url"], "http://127.0.0.1:9999/v1/systemone")


func test_local_without_a_transport_reads_decider_through_llama_server():
	Jev.configure_jev({"via": "local", "api_base": "http://127.0.0.1:9999", "wait_s": 7.0})
	ok(Jev.transport is Local.Server, "the readout is the transport")
	eq([Jev.transport.base, Jev.transport.wait_s], ["http://127.0.0.1:9999", 7.0])


func test_mock_answers_every_question_and_is_repeatable():
	Jev.configure_jev({"via": "mock", "seed": 3})
	ok(Jev.is_configured())
	var trace := []
	var a := await Jev.jev(STATE, questions(), trace)
	eq(a["model"], "jev-mock")
	eq(a["answers"].keys(), ["mood", "joke"])
	eq(trace[0]["via"], "mock")
	Jev.configure_jev({"via": "mock", "seed": 3})
	var b := await Jev.jev(STATE, questions())
	eq(a["answers"], b["answers"], "the same seed answers the same")
	Jev.configure_jev({"via": "mock", "seed": 4})
	var c := await Jev.jev(STATE, questions())
	ne(a["answers"], c["answers"])


func test_mock_latency_delays_the_answer():
	await J.sleep(1)  # the first timer of a run fires on the first frame's long delta; get past it
	Jev.configure_jev({"via": "mock", "seed": 1, "latency": 60})
	var t0 := Time.get_ticks_msec()
	var r := await Jev.jev(STATE, questions())
	# timers fire on frame boundaries, so allow a margin under the 60 ms asked for
	ok(Time.get_ticks_msec() - t0 >= 35, "waited about 60 ms (%d)" % (Time.get_ticks_msec() - t0))
	ok(r["ms"] >= 35, "ms %s" % r["ms"])


func test_a_rate_limited_call_is_retried_after_a_backoff():
	var t := Canned.new([{"status": 429, "text": "slow down"}, {"status": 503, "text": "busy"}, {"status": 529, "text": "overloaded"}, ok_reply()])
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": t})
	var trace := []
	var r := await Jev.jev(STATE, questions(), trace)
	ok(not r.has("error"), str(r))
	eq(t.requests.size(), 4)
	eq(trace[0]["attempts"], 4)
	eq(trace[0]["status"], 200)


func test_a_call_that_stays_rate_limited_gives_up_after_four_attempts():
	var t := Canned.new([{"status": 429, "text": "slow down"}])
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": t})
	var trace := []
	var r := await Jev.jev(STATE, questions(), trace)
	eq(t.requests.size(), 4, "the first try and three retries")
	eq(r, {"error": "System One 429: slow down"})
	eq([trace[0]["attempts"], trace[0]["status"], trace[0]["error"]], [4, 429, "slow down"])


func test_the_backoff_doubles_each_time():
	await J.sleep(1)
	Jev.backoff_ms = 20
	var t := Canned.new([{"status": 429, "text": "x"}])
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": t})
	var t0 := Time.get_ticks_msec()
	await Jev.jev(STATE, questions())
	ok(Time.get_ticks_msec() - t0 >= 130, "20 + 40 + 80 ms of waiting")


func test_other_http_errors_are_not_retried_and_are_trimmed():
	var t := Canned.new([{"status": 500, "text": "x".repeat(3000)}])
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": t})
	var trace := []
	var r := await Jev.jev(STATE, questions(), trace)
	eq(t.requests.size(), 1)
	eq(r["error"], "System One 500: " + "x".repeat(200))
	eq(trace[0]["error"].length(), 2000)
	eq(trace[0]["status"], 500)
	ok(trace[0]["ms"] >= 0)


func test_a_json_error_body_is_reported_as_text():
	var t := Canned.new([{"status": 401, "json": {"error": "bad key"}}])
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": t})
	var r := await Jev.jev(STATE, questions())
	eq(r["error"], "System One 401: {\"error\":\"bad key\"}")


func test_a_network_failure_is_an_error_with_the_reason_in_the_trace():
	var t := Canned.new([{"error": "timed out after 10 s"}])
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": t})
	var trace := []
	var r := await Jev.jev(STATE, questions(), trace)
	eq(r["error"], "System One: timed out after 10 s")
	eq(trace[0]["error"], "timed out after 10 s")
	ok(not trace[0].has("status"))


func test_a_reply_that_is_not_json_is_an_error_and_its_text_is_kept_when_asked():
	var dir := "user://jev-raw-test"
	Jev.raw_dir = dir
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": Canned.new([{"status": 200, "text": "<html>not json</html>"}])})
	var trace := []
	var r := await Jev.jev(STATE, questions(), trace)
	ok(r.has("error"))
	eq(trace[0]["error"], "<html>not json</html>")
	var files := DirAccess.get_files_at(dir)
	eq(files.size(), 1, "the raw reply was saved before parsing")
	if files.size() == 1:
		eq(FileAccess.get_file_as_string(dir.path_join(files[0])), "<html>not json</html>")
	for f in files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_a_text_reply_is_parsed():
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": Canned.new([{"status": 200, "text": "{\"model\":\"m\",\"answers\":{},\"usage\":{\"input_tokens\":1}}"}])})
	var r := await Jev.jev(STATE, questions())
	eq([r["model"], r["answers"]], ["m", {}])
	ok(r.has("ms"))


func test_without_a_trace_nothing_is_recorded_and_it_still_works():
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": Canned.new([ok_reply()])})
	ok(not (await Jev.jev(STATE, questions())).has("error"))
