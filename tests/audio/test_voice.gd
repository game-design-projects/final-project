## Hold-to-talk with speech recognition (port of test/voice.test.js), against a fake recognizer
extends "res://tests/test_case.gd"

const Voice = preload("res://src/audio/voice.gd")
const Asr = preload("res://src/audio/asr.gd")


## A stand-in for SpeechRecognition: the test feeds it results and ends it
class FakeRecognition:
	extends RefCounted
	static var last = null
	var lang := ""
	var continuous := false
	var interimResults := false
	var started := false
	var stopping := false
	var aborted := false
	var onresult := Callable()
	var onerror := Callable()
	var onend := Callable()

	func _init() -> void:
		FakeRecognition.last = self

	func start() -> bool:
		started = true
		return true

	func stop() -> void:
		stopping = true

	func abort() -> void:
		aborted = true
		if onend.is_valid():
			onend.call()

	## results: [[text, isFinal], ...] as the engine reports the whole session so far
	func emit(results: Array) -> void:
		onresult.call({"resultIndex": 0, "results": results.map(func(r): return {"transcript": r[0], "isFinal": r[1]})})


## Runs `l.start()` in the background and keeps what it returns
func _begin(l) -> Dictionary:
	var out := {"done": false, "value": "pending"}
	var run := func():
		out.value = await l.start()
		out.done = true
	run.call()
	return out


func test_finds_the_recognizer_prefixed_or_not_and_copes_without_one():
	eq(Voice.recognizer({"SpeechRecognition": FakeRecognition}), FakeRecognition)
	eq(Voice.recognizer({"webkitSpeechRecognition": FakeRecognition}), FakeRecognition)
	eq(Voice.recognizer({}), null)
	# a desktop build hears you with its own helper (asr.gd) when it carries one; without, the game keeps the text box
	if not OS.has_feature("web"):
		eq(Voice.recognizer(), Asr.NativeRecognition if Asr.Runtime.available() else null)
		var l = Voice.Listener.new()
		eq(l.supported, Asr.Runtime.available())
		l.free()


func test_a_hold_is_long_enough_to_tell_apart_from_a_tap():
	ok(Voice.HOLD_MS >= 200 and Voice.HOLD_MS <= 500)


func test_words_show_up_as_you_speak_and_the_final_text_comes_back_when_you_let_go():
	var heard := []
	var l := Voice.Listener.new({"Recognition": FakeRecognition, "lang": "en-US", "onText": func(t): heard.append(t)})
	var run := _begin(l)
	var rec: FakeRecognition = FakeRecognition.last
	ok(rec.started and rec.interimResults and rec.continuous)
	eq(rec.lang, "en-US")
	eq(l.listening, true)
	rec.emit([["hello", false]])
	rec.emit([["hello little", false]])
	rec.emit([["hello little slime", true], [" want to", false]])
	l.stop()
	ok(rec.stopping)
	rec.emit([["hello little slime", true], [" want to join us", true]])
	rec.onend.call()
	eq(run.done, true)
	eq(run.value, "hello little slime want to join us")
	eq(heard.slice(0, 2), ["hello", "hello little"])
	eq(heard.back(), "hello little slime want to join us")
	eq(l.listening, false)
	l.free()


func test_nothing_heard_comes_back_empty_not_as_an_error():
	var l := Voice.Listener.new({"Recognition": FakeRecognition})
	var run := _begin(l)
	FakeRecognition.last.onerror.call({"error": "no-speech"})
	FakeRecognition.last.onend.call()
	eq(run.value, "")
	l.free()


func test_a_blocked_microphone_is_reported_so_the_game_can_say_so():
	var why := [null]
	var l := Voice.Listener.new({"Recognition": FakeRecognition, "onError": func(e): why[0] = e})
	var run := _begin(l)
	FakeRecognition.last.onerror.call({"error": "not-allowed"})
	FakeRecognition.last.onend.call()
	eq(run.value, "")
	eq(why[0], "not-allowed")
	l.free()


func test_cancel_throws_the_words_away():
	var l := Voice.Listener.new({"Recognition": FakeRecognition})
	var run := _begin(l)
	FakeRecognition.last.emit([["never mind", false]])
	l.cancel()
	eq(run.done, true)
	eq(run.value, null)
	ok(FakeRecognition.last.aborted)
	l.free()


func test_starting_again_cancels_the_session_before_it():
	var l := Voice.Listener.new({"Recognition": FakeRecognition})
	var first := _begin(l)
	var rec1: FakeRecognition = FakeRecognition.last
	var second := _begin(l)
	ok(rec1.aborted)
	eq(first.value, null)
	eq(second.done, false, "the new session is still listening")
	FakeRecognition.last.emit([["hi", true]])
	FakeRecognition.last.onend.call()
	eq(second.value, "hi")
	l.free()


func test_without_speech_support_start_resolves_to_null_at_once():
	var l := Voice.Listener.new({"Recognition": null})
	eq(l.supported, false)
	var run := _begin(l)
	eq(run.done, true)
	eq(run.value, null)
	l.free()


func test_holding_space_listen_into_an_empty_talk_box_or_open_the_right_one_first():
	eq(Voice.space_hold({"inputOpen": true, "inputEmpty": true}), "listen")
	eq(Voice.space_hold({"inputOpen": true, "inputEmpty": false}), null, "with words in the box, Space types a space")
	eq(Voice.space_hold({"inputOpen": true, "numeric": true}), null, "not in the gold box")
	eq(Voice.space_hold({"combat": true}), "talk")
	eq(Voice.space_hold({"combat": true, "waiting": true}), null, "not while a menu, question or the monsters' turn waits")
	eq(Voice.space_hold({"allies": 2}), "ally")
	eq(Voice.space_hold({}), null, "exploring alone: nobody to talk to")
