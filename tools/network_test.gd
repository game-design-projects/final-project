## Checks the game's talk with Jev with no network: a proxy that has no key is not asked again and again, a failing one is
## retried, the HUD can tell how long a question has been waiting, and the mercy and pressure questions after a feeling are one
## request (and the same question about the same monster is not asked twice). A stand-in for the transport answers instead of
## the internet. Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/network_test.gd
extends "res://tools/test_base.gd"

const JevMind = preload("res://src/mind/jev_mind.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Mind = preload("res://src/mind/mind.gd")
const Minds = preload("res://src/mind/minds.gd")
const Monster = preload("res://src/rules/monster.gd")
const Network = preload("res://src/network/network.gd")
const Rng = preload("res://src/utils/rng.gd")
const SafeMind = preload("res://src/mind/safe_mind.gd")
const SeededMind = preload("res://src/mind/seeded_mind.gd")

const URL := "https://proxy.invalid/api/jev"

var _requests: Array = [] # the body of every request the stand-in saw
var _replies: Array = [] # what it says next: {"status", "text"} or {"error"}; the last one repeats
var _delay_s := 0.0


## A mind whose every answer is the wrong shape: what a script error inside a question leaves behind, and worse.
class Junk extends "res://src/mind/mind.gd":
	func label() -> String: return "junk"
	func read_words(_text: String) -> Dictionary: return {}
	func feeling_when_hit(_m) -> Dictionary: return {"sad": NAN}
	func feeling_when_told(_m, _intents: Array) -> Dictionary: return {"sad": 0.0, "enraged": 0.0}
	func mercy(_m) -> float: return NAN
	func join(_m) -> float: return 1.5
	func pressure(_m) -> float: return -1.0
	func mercy_and_pressure(_m) -> Dictionary: return {"pressure": 2.0}


## The playtest's fault as an export has it: no script error there, the answer that was lost reads back as null.
class Nulled extends "res://src/mind/mind.gd":
	func label() -> String: return "nulled"
	func mercy_and_pressure(_m) -> Dictionary: return {"mercy": null, "pressure": 2.5}


## A mind that trips for real, the way the playtest's did in a debug build: the read of a key that isn't there ends the function.
class Tripping extends "res://src/mind/mind.gd":
	func label() -> String: return "tripping"
	func mercy_and_pressure(_m) -> Dictionary:
		var kept := {}
		return {"mercy": kept["mercy"], "pressure": kept["pressure"]}


## A mind that never answers.
class Silent extends "res://src/mind/mind.gd":
	signal never
	func label() -> String: return "silent"
	func mercy(_m) -> float:
		await never
		return 0.9
	func feeling_when_hit(_m) -> Dictionary:
		await never
		return {"sad": 1.0}


func _name() -> String:
	return "network_test"


## Two faults a debug build asserts on, and one mind that trips on a missing key (_a_mind_gone_wrong_cannot_stop_a_fight).
func _script_errors_meant() -> int:
	return 3


func _run() -> void:
	Network.transport = _transport
	await _no_key_is_not_retried()
	await _outages_are_retried()
	await _waiting_is_visible()
	await _batched_questions()
	await _batch_at_cache_boundary()
	await _half_an_answer_is_kept()
	await _batch_failure_falls_back()
	await _malformed_numbers_fall_back()
	await _asked_ahead_goes_out_once()
	_local_minds_ask_one_then_the_other()
	await _a_mind_gone_wrong_cannot_stop_a_fight()
	_default_proxy_is_for_the_game_only()
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


## Making room for a two-answer reply happens once, before either answer is stored. At 63 entries, clearing on the second
## insertion used to throw mercy away, so the pair cost a second request as soon as the menu asked for it.
func _batch_at_cache_boundary() -> void:
	var mind := JevMind.new("https://proxy.invalid", LocalMind.new())
	for i in range(JevMind.KNOWN_MAX - 1):
		mind._remember("old-%d" % i, 0.0)
	var m = _monster()
	_begin([{"status": 200, "text": JSON.stringify({"answers": {"mercy": {"noul": 0.7}, "pressure": {"score": 2.5}}})}])
	var both: Dictionary = await mind.mercy_and_pressure(m)
	var again: float = await mind.mercy(m)
	var press: float = await mind.pressure(m)
	_check(is_equal_approx(both.mercy, 0.7) and is_equal_approx(both.pressure, 2.5), "a two-answer reply survives the cache boundary (%s)" % [both])
	_check(_requests.size() == 1 and is_equal_approx(again, 0.7) and is_equal_approx(press, 2.5), "and both boundary answers stay cached")


## A reply that answers one of the two: Jev's half is kept, so asked on its own it costs no request, and the missing half is
## the local rules' answer, not remembered as Jev's.
func _half_an_answer_is_kept() -> void:
	var local := LocalMind.new()
	var mind := JevMind.new("https://proxy.invalid", local)
	var m = _monster(70.0)
	_begin([{"status": 200, "text": JSON.stringify({"answers": {"mercy": {"noul": 0.31}}})}])
	var both: Dictionary = await mind.mercy_and_pressure(m)
	var mercy: float = await mind.mercy(m)
	_check(is_equal_approx(both.mercy, 0.31) and is_equal_approx(both.pressure, local.pressure(m)), "a reply with only mercy answered: Jev's mercy and the local pressure")
	_check(_requests.size() == 1 and is_equal_approx(mercy, 0.31), "and the answered half is kept, so asking it alone costs no request (%d requests)" % _requests.size())


## Asked ahead (a dodge asks the mercy the menu after it will need) and asked again before Jev answers: one request, both get
## the answer, and the screen can say what is being thought about.
func _asked_ahead_goes_out_once() -> void:
	var mind := JevMind.new("https://proxy.invalid", LocalMind.new())
	var m = _monster()
	_begin([{"status": 200, "text": JSON.stringify({"answers": {"q": {"noul": 0.64}}})}])
	_delay_s = 0.3
	var ahead := {"v": -1.0}
	(func(): ahead.v = await mind.mercy(m)).call() # not awaited, as Encounter.think_ahead
	await process_frame
	_check(Network.waiting_what() == "WILL IT ACCEPT MERCY?", "a question out says what it asks (%s)" % Network.waiting_what())
	var later: float = await mind.mercy(m)
	_check(_requests.size() == 1, "asked again while it is out, it goes out once (%d requests)" % _requests.size())
	await process_frame # the one who asked ahead hears it right after (inside the same answer)
	_check(is_equal_approx(later, 0.64) and is_equal_approx(ahead.v, 0.64), "and both askers get its answer")
	_check(Network.waiting_what() == "", "nothing is out once it is answered")
	_delay_s = 0.0


func _batch_failure_falls_back() -> void:
	var local := LocalMind.new()
	var mind := JevMind.new("https://proxy.invalid", local)
	var m = _monster(70.0)
	_begin([{"status": 400, "text": "no"}])
	var both: Dictionary = await mind.mercy_and_pressure(m)
	_check(_requests.size() == 1, "a refused batch is not asked again question by question (%d requests)" % _requests.size())
	_check(is_equal_approx(both.mercy, local.mercy(m)) and is_equal_approx(both.pressure, local.pressure(m)), "the local rules answer both, as they would alone")
	_check(await mind.mercy(m) == local.mercy(m) or _requests.size() > 1, "and a failure is not remembered as an answer")


func _malformed_numbers_fall_back() -> void:
	var local := LocalMind.new()
	var m = _monster()
	_check(not JevMind._valid_number(INF, 0.0, 1.0) and not JevMind._valid_number(NAN, 0.0, 1.0), "non-finite numbers are rejected before reaching game rules")
	for bad in ["0.7", -0.1, null]:
		var mind := JevMind.new("https://proxy.invalid", local)
		_begin([{"status": 200, "text": JSON.stringify({"answers": {"mercy": {"noul": bad}, "pressure": {"score": bad}}})}])
		var both: Dictionary = await mind.mercy_and_pressure(m)
		_check(is_equal_approx(both.mercy, local.mercy(m)) and is_equal_approx(both.pressure, local.pressure(m)), "malformed or out-of-range Jev numbers fall back locally (%s)" % str(bad))
	var over := JevMind.new("https://proxy.invalid", local)
	_begin([{"status": 200, "text": '{"answers":{"mercy":{"noul":1.1},"pressure":{"score":3.1}}}'}])
	var exceeded: Dictionary = await over.mercy_and_pressure(m)
	_check(is_equal_approx(exceeded.mercy, local.mercy(m)) and is_equal_approx(exceeded.pressure, local.pressure(m)), "values above each field's upper bound fall back locally")
	var mind := JevMind.new("https://proxy.invalid", local)
	_begin([{"status": 200, "text": '{"answers":{"q":{"probabilities":{"good":-0.2,"bad":1.2}}}}'}])
	var feelings: Dictionary = await mind.feeling_when_hit(m)
	_check(feelings == local.feeling_when_hit(m), "invalid choice probabilities use the local feeling rules")


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


## Every mind the game uses is inside a SafeMind, the edge where its answers are checked. An answer that isn't one (the wrong
## shape, a number out of range, an export's null where a key was missing, a script error's empty leftovers, or none at all):
## a debug build reports it and hands it on as it is (fail fast), an export has the local rules answer so the fight goes on.
func _a_mind_gone_wrong_cannot_stop_a_fight() -> void:
	var m = _monster()
	var local := LocalMind.new()
	var intents := [{"intent": "joke", "w": 1.0}]
	_check(Minds.create(Rng.new(3)) is SafeMind, "the mind a game gets is a guarded one")
	_check(not Fault.tolerant(), "a debug build (this run) fails fast; only an export carries on")
	for as_export in [false, true]:
		Fault.forced = as_export
		var good := SafeMind.new(SeededMind.new(Rng.new(9)))
		var bare := SeededMind.new(Rng.new(9))
		var same: bool = await good.feeling_when_hit(m) == bare.feeling_when_hit(m) and await good.mercy(m) == bare.mercy(m)
		var pair: Dictionary = await good.mercy_and_pressure(m)
		var bare_pair: Dictionary = await bare.mercy_and_pressure(m)
		_check(same and pair == bare_pair and good.saved == 0, "%s: a good answer passes through untouched, in the same order (a seeded game plays the same)" % ("export" if as_export else "debug"))
	print("network_test: the errors below are the faults these checks cause on purpose")
	# debug: reported, and nothing papered over
	Fault.forced = false
	var before := Fault.count
	var loud := SafeMind.new(Junk.new())
	var given: Dictionary = await loud.mercy_and_pressure(m)
	_check(given == {"pressure": 2.0} and Fault.count == before + 1 and loud.saved == 0, "debug: half a pair is a fault and is handed on as it is, so the run fails where it would without the guard (%s)" % Fault.last)
	_check(is_nan(await loud.mercy(m)) and Fault.count == before + 2, "debug: so is a number that is not one")
	# an export: reported, and the local rules answer
	Fault.forced = true
	before = Fault.count
	var junk := SafeMind.new(Junk.new())
	_check(await junk.read_words("hello there") == local.read_words("hello there"), "export: no odds for the words, the local rules read them")
	_check(await junk.feeling_when_hit(m) == local.feeling_when_hit(m), "export: a feeling that is not a number, the local rules feel it")
	_check(await junk.feeling_when_told(m, intents) == local.feeling_when_told(m, intents), "export: odds that add up to nothing, the local rules feel it")
	_check(await junk.mercy(m) == local.mercy(m) and await junk.join(m) == local.join(m) and await junk.pressure(m) == local.pressure(m), "export: numbers that are not numbers or out of range, the local rules answer")
	var half: Dictionary = await junk.mercy_and_pressure(m)
	_check(half.get("mercy") == local.mercy(m) and half.get("pressure") == local.pressure(m), "export: half a pair is no pair, the local rules answer both (%s)" % [half])
	_check(junk.saved == 7 and Fault.count == before + 7 and Fault.last.begins_with("mind: junk "), "export: each one is counted and logged under the mind's own name (%d)" % junk.saved)
	var lost: Dictionary = await SafeMind.new(Nulled.new()).mercy_and_pressure(m)
	_check(lost.get("mercy") == local.mercy(m) and lost.get("pressure") == local.pressure(m), "export: the playtest's fault as an export has it (mercy read back as null) is answered, not played as 0%% mercy (%s)" % [lost])
	var after = await SafeMind.new(Tripping.new()).mercy_and_pressure(m)
	_check(after is Dictionary and after.get("mercy") == local.mercy(m) and after.get("pressure") == local.pressure(m), "export: and as a debug build has it (a script error ends the question) too (%s)" % [after])
	var worst := SafeMind.new(Junk.new(), Junk.new())
	var last: Dictionary = await worst.mercy_and_pressure(m)
	_check(last == {"mercy": SafeMind.LAST_MERCY, "pressure": SafeMind.LAST_PRESSURE} and await worst.feeling_when_hit(m) == SafeMind.LAST_FEELING and await worst.read_words("x") == SafeMind.LAST_WORDS, "export: with the local rules gone wrong too, there is still an answer the game can roll")
	_check(SafeMind.DEADLINE_S > Network.TIMEOUT_S * (Network.RETRIES + 1) + Network.BACKOFF_S * 3.0, "export: the wait is longer than every try of one request, so a slow network is never cut short (%.0f s)" % SafeMind.DEADLINE_S)
	var silent := SafeMind.new(Silent.new())
	silent.deadline_s = 0.2
	var began := Time.get_ticks_msec()
	var odds: float = await silent.mercy(m)
	var took := Time.get_ticks_msec() - began
	_check(odds == local.mercy(m) and took >= 150 and took < 2000, "export: a mind that never answers is waited for only so long, then the local rules answer (%d ms)" % took)
	_check(await silent.feeling_when_hit(m) == local.feeling_when_hit(m) and silent.saved == 2, "export: and so for a feeling")
	Fault.forced = null


func _default_proxy_is_for_the_game_only() -> void:
	_check(Minds.default_url(false) == Minds.DEFAULT_URL and Minds.DEFAULT_URL.begins_with("https://"), "the game asks Jev through the default proxy over https")
	_check(Minds.default_url(true) == "", "a tool run (headless or -s) has no default proxy, so the suites stay on the local rules")
	var rng := Rng.new()
	_check(Minds.create(rng, "", false, true).label() == Minds.create(rng).label(), "so a tool run's mind is the local one even when the game's create asks for the default")
