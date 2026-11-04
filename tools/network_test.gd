## Checks the game's talk with Jev with no network: a proxy that has no key is not asked again and again, a failing one is
## retried, the HUD can tell how long a question has been waiting, and the mercy and pressure questions after a feeling are one
## request (and the same question about the same monster is not asked twice). A stand-in for the transport answers instead of
## the internet. Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/network_test.gd
extends "res://tools/test_base.gd"

const JevMind = preload("res://src/mind/jev_mind.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Monster = preload("res://src/rules/monster.gd")
const Network = preload("res://src/network/network.gd")
const Rng = preload("res://src/utils/rng.gd")
const SeededMind = preload("res://src/mind/seeded_mind.gd")

const URL := "https://proxy.invalid/api/jev"

var _requests: Array = [] # the body of every request the stand-in saw
var _replies: Array = [] # what it says next: {"status", "text"} or {"error"}; the last one repeats
var _delay_s := 0.0


func _name() -> String:
	return "network_test"


func _run() -> void:
	Network.transport = _transport
	await _no_key_is_not_retried()
	await _outages_are_retried()
	await _waiting_is_visible()
	await _batched_questions()
	await _batch_failure_falls_back()
	_local_minds_ask_one_then_the_other()
	Network.transport = Callable()
	Network.reset()
	_finish()


func _transport(_url: String, payload: String, _headers: Dictionary, _timeout: float) -> Dictionary:
	_requests.append(JSON.parse_string(payload))
	if _delay_s > 0.0:
		await create_timer(_delay_s).timeout
	return _replies[mini(_requests.size() - 1, _replies.size() - 1)] if _replies.size() > 0 else {"error": "no reply set"}


func _begin(replies: Array) -> void:
	_requests = []
	_replies = replies
	_delay_s = 0.0
	Network.reset()


func _no_key_is_not_retried() -> void:
	_begin([{"status": 503, "text": '{"error":"Server not configured"}'}])
	var r: Dictionary = await Network.post_json(URL, {"state": {}, "questions": {"q": {}}})
	_check(not r.ok and r.status == 503 and _requests.size() == 1, "a proxy with no key is asked once, not retried (%d requests)" % _requests.size())
	_check(Network.is_down(), "and is treated as down at once: the answer will not change in a few seconds")
	r = await Network.post_json(URL, {"state": {}, "questions": {"q": {}}})
	_check(not r.ok and _requests.size() == 1, "so the next question does not even go out")
	_check(r.ms < 100 and not r.error.is_empty(), "and fails at once with a reason (%s)" % r.error)


func _outages_are_retried() -> void:
	_begin([{"status": 503, "text": "upstream busy"}, {"status": 429, "text": "slow down"}, {"status": 200, "text": '{"answers": {}}'}])
	var r: Dictionary = await Network.post_json(URL, {"state": {}, "questions": {"q": {}}})
	_check(r.ok and _requests.size() == 3, "a busy 503 and a 429 are retried, and the third try is what counts (%d requests)" % _requests.size())
	_begin([{"error": "can't connect (result 2)"}])
	r = await Network.post_json(URL, {"state": {}, "questions": {"q": {}}})
	_check(not r.ok and _requests.size() == Network.RETRIES + 1 and not Network.is_down(), "a connection that fails is tried %d times, and one failed question is not an outage" % (Network.RETRIES + 1))
	_begin([{"status": 400, "text": "bad"}])
	r = await Network.post_json(URL, {"state": {}, "questions": {"q": {}}})
	_check(not r.ok and _requests.size() == 1, "a 400 is not retried")


func _waiting_is_visible() -> void:
	_begin([{"status": 200, "text": '{"answers": {}}'}])
	_delay_s = 0.3
	_check(Network.waiting_ms() == 0, "nothing is waiting before a question goes out")
	var done := {"v": false}
	var ask := func():
		await Network.post_json(URL, {"state": {}, "questions": {"q": {}}})
		done.v = true
	ask.call()
	await create_timer(0.12).timeout
	var waited := Network.waiting_ms()
	_check(not done.v and waited >= 80 and waited < 400, "while a question is out the HUD can read how long it has waited (%d ms)" % waited)
	await create_timer(0.35).timeout
	_check(done.v and Network.waiting_ms() == 0, "and nothing is waiting once it is answered")


# ---------------------------------------------------------------- mercy and pressure

func _monster(friendliness := 50.0):
	var m = Monster.given({"species": "slime", "genre": "bullet", "hp": 18}, Vector2i.ZERO, "GLOP", ["lonely", "sleepy"], {"friendliness": friendliness, "anger": 5.0, "fear": 10.0})
	return m


## An answer for each question that asks for one: noul 0.7 for yes/no, score 2.5 for the pressure, an even choice for feelings.
func _answers(body: Dictionary) -> Dictionary:
	var out := {}
	for k in body.questions:
		var q: Dictionary = body.questions[k]
		match q.type:
			"noul":
				out[k] = {"noul": 0.7}
			"score":
				out[k] = {"score": 2.5}
			_:
				out[k] = {"probabilities": {"sad": 1.0}}
	return out


func _batched_questions() -> void:
	var mind := JevMind.new("https://proxy.invalid", LocalMind.new())
	var m = _monster()
	_begin([])
	# the stand-in answers whatever is asked
	_replies = []
	var serve := func(body):
		return {"status": 200, "text": JSON.stringify({"answers": _answers(body)})}
	Network.transport = func(_u, payload, _h, _t):
		var body = JSON.parse_string(payload)
		_requests.append(body)
		return serve.call(body)
	var both: Dictionary = await mind.mercy_and_pressure(m)
	_check(_requests.size() == 1 and _requests[0].questions.size() == 2, "mercy and pressure after a feeling are one request with two questions (%d requests)" % _requests.size())
	_check(is_equal_approx(both.mercy, 0.7) and is_equal_approx(both.pressure, 2.5), "and both answers come back (%s)" % [both])
	var again: float = await mind.mercy(m)
	var press: float = await mind.pressure(m)
	_check(_requests.size() == 1 and is_equal_approx(again, 0.7) and is_equal_approx(press, 2.5), "asking the same about the same monster again (the menu opening) costs no request")
	m.meters.friendliness = 90.0
	await mind.mercy(m)
	_check(_requests.size() == 2, "a monster that has changed is asked again")
	await mind.feeling_when_hit(m)
	_check(_requests.size() == 3, "a feeling is its own request: what it says changes the monster the next two questions are about")
	Network.transport = _transport


func _batch_failure_falls_back() -> void:
	var local := LocalMind.new()
	var mind := JevMind.new("https://proxy.invalid", local)
	var m = _monster(70.0)
	_begin([{"status": 400, "text": "no"}])
	var both: Dictionary = await mind.mercy_and_pressure(m)
	_check(_requests.size() == 1, "a refused batch is not asked again question by question (%d requests)" % _requests.size())
	_check(is_equal_approx(both.mercy, local.mercy(m)) and is_equal_approx(both.pressure, local.pressure(m)), "the local rules answer both, as they would alone")
	_check(await mind.mercy(m) == local.mercy(m) or _requests.size() > 1, "and a failure is not remembered as an answer")


## The minds that do not call out answer the pair the way two questions in a row would, in the same order: the seeded one draws
## from one generator, so the order is part of what a seed means.
func _local_minds_ask_one_then_the_other() -> void:
	var m = _monster()
	var local := LocalMind.new()
	var pair: Dictionary = await local.mercy_and_pressure(m)
	_check(pair.mercy == local.mercy(m) and pair.pressure == local.pressure(m), "the local mind answers the pair as it answers each alone")
	var a := SeededMind.new(Rng.new(9))
	var b := SeededMind.new(Rng.new(9))
	var both: Dictionary = await a.mercy_and_pressure(m)
	var mercy: float = b.mercy(m)
	var pressure: float = b.pressure(m)
	_check(both.mercy == mercy and both.pressure == pressure, "the seeded mind draws mercy first, then pressure, as before")
