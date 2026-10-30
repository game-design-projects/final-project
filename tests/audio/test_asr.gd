## Speech to text on the player's machine (asr.gd): the helper's protocol and the listening session against a fake
## helper and microphone, then the real helper on a recording when native/asr/build.sh has built it and the model
extends "res://tests/test_case.gd"

const Asr = preload("res://src/audio/asr.gd")
const Voice = preload("res://src/audio/voice.gd")
const J = preload("res://src/core/js.gd")


## Stands in for the helper process: keeps what the game sends as frames, prints what the test tells it to
class FakePipe:
	extends RefCounted
	var sent := PackedByteArray()
	var out := ""
	var err := ""
	var alive := true
	var closed := false

	func write(bytes: PackedByteArray) -> bool:
		sent.append_array(bytes)
		return alive

	func read() -> PackedByteArray:
		var b := out.to_utf8_buffer()
		out = ""
		return b

	func read_err() -> PackedByteArray:
		var b := err.to_utf8_buffer()
		err = ""
		return b

	func running() -> bool:
		return alive

	func close() -> void:
		closed = true
		alive = false

	func say(ev: Dictionary) -> void:
		out += JSON.stringify(ev) + "\n"

	## The frames sent so far as [tag, payload size]
	func frames() -> Array:
		var list := []
		var i := 0
		while i + 5 <= sent.size():
			var n := sent.decode_u32(i + 1)
			list.append([String.chr(sent[i]), n])
			i += 5 + n
		return list

	func tags() -> String:
		return "".join(frames().map(func(f): return f[0]))


## Stands in for the microphone: hands out whatever the test queued, one chunk per read
class FakeMic:
	extends RefCounted
	var rate := 48000
	var on := false
	var chunks: Array = []

	func start() -> bool:
		on = true
		return true

	func read() -> PackedFloat32Array:
		return chunks.pop_front() if not chunks.is_empty() else PackedFloat32Array()

	func stop() -> void:
		on = false


## A Runtime with the model "there" and a fake helper (an empty file, so the existence check passes) behind `pipe`
func _ready_runtime(pipe: FakePipe, mic: FakeMic) -> Asr.Runtime:
	var dir := ProjectSettings.globalize_path("user://test-asr")
	DirAccess.make_dir_recursive_absolute(dir)
	FileAccess.open(dir.path_join(Asr.exe_name(Asr.platform())), FileAccess.WRITE).close()
	var rt := Asr.Runtime.new({"helper_dir": dir, "spawn": func(_exe, _args): return pipe, "mic": mic})
	rt.state = "idle"
	return rt


func _chunk(n := 480, v := 0.1) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(v)
	return a


func test_frames_are_a_tag_a_little_endian_length_and_the_payload():
	var f := Asr.frame("F")
	eq(Array(f), [70, 0, 0, 0, 0])
	var s := Asr.start_frame(48000)
	eq(s.size(), 9)
	eq(String.chr(s[0]), "S")
	eq(s.decode_u32(1), 4)
	eq(s.decode_s32(5), 48000)
	var a := Asr.audio_frame(PackedFloat32Array([0.5, -0.25]))
	eq(a.decode_u32(1), 8)
	near(a.decode_float(5), 0.5)
	near(a.decode_float(9), -0.25)


func test_the_helpers_output_is_read_line_by_line_keeping_a_half_line_for_later():
	var p := Asr.parse_events('{"event":"ready"}\n{"event":"text","text":"hel')
	eq(p.events, [{"event": "ready"}])
	eq(p.rest, '{"event":"text","text":"hel')
	p = Asr.parse_events(p.rest + 'lo"}\n')
	eq(p.events, [{"event": "text", "text": "hello"}])
	eq(p.rest, "")


func test_stereo_capture_becomes_one_channel():
	var m := Asr.mono(PackedVector2Array([Vector2(1, 0), Vector2(0.5, 0.5)]))
	eq(Array(m), [0.5, 0.5])


func test_the_helper_gets_the_four_model_files_and_its_threads():
	var args := Asr.helper_args("/m")
	eq(Array(args), ["--tokens=/m/tokens.txt", "--encoder=/m/encoder.int8.onnx", "--decoder=/m/decoder.int8.onnx", "--joiner=/m/joiner.int8.onnx", "--threads=%d" % Asr.THREADS])
	ok(Asr.model_bytes() > 600000000, "the model is the big download the player is told about")
	eq(Asr.mb(Asr.model_bytes()), "662 MB")
	eq(Asr.model_complete(ProjectSettings.globalize_path("res://tests")), false)


func test_the_build_script_fetches_the_same_model_the_game_does():
	var sh := FileAccess.get_file_as_string("res://native/asr/build.sh")
	ok(sh.contains(Asr.MODEL.url.trim_suffix("/")), "the same pinned commit")
	for f in Asr.MODEL.files:
		ok(sh.contains("%s  %s" % [f.sha256, f.name]), "the same checksum for " + f.name)


func test_a_session_streams_the_microphone_and_ends_with_the_final_words():
	var pipe := FakePipe.new()
	var mic := FakeMic.new()
	var rt := _ready_runtime(pipe, mic)
	var heard := []
	var ended := [0]
	var rec := Asr.NativeRecognition.new()
	rec.onresult = func(ev): heard.append([ev.results[0].transcript, ev.results[0].isFinal])
	rec.onend = func(): ended[0] += 1
	ok(rt.listen(rec), "listening")
	eq(rt.state, "loading", "the helper is starting")
	ok(mic.on, "the microphone is open")
	eq(pipe.frames()[0], ["S", 4], "the sample rate goes first")
	mic.chunks = [_chunk(), _chunk()]
	rt.poll()
	rt.poll()
	eq(pipe.tags(), "SAA", "audio streams even while the model loads: the helper queues it")
	pipe.say({"event": "ready"})
	pipe.say({"event": "text", "text": "hello little"})
	rt.poll()
	eq(rt.state, "ready")
	eq(heard, [["hello little", false]])
	rt.finish(rec)
	ok(not mic.on, "the microphone closes as soon as you let go")
	eq(pipe.tags().right(1), "F")
	pipe.say({"event": "text", "text": "late partial"})
	pipe.say({"event": "final", "text": "hello little slime"})
	rt.poll()
	eq(heard, [["hello little", false], ["hello little slime", true]], "partials after letting go are not shown")
	eq(ended[0], 1)
	eq(rt.session, null)
	rt.free()


func test_the_listener_drives_it_like_the_browsers_recognizer():
	var pipe := FakePipe.new()
	var mic := FakeMic.new()
	var rt := _ready_runtime(pipe, mic)
	Asr.NativeRecognition.runtime = rt
	var shown := []
	var l := Voice.Listener.new({"Recognition": Asr.NativeRecognition, "onText": func(t): shown.append(t)})
	ok(l.native)
	eq(l.prepare(), "")
	var out := {"value": "pending"}
	var run := func(): out.value = await l.start()
	run.call()
	pipe.say({"event": "ready"})
	pipe.say({"event": "text", "text": " want to join "})
	rt.poll()
	eq(shown, ["want to join"])
	l.stop()
	pipe.say({"event": "final", "text": "want to join us"})
	rt.poll()
	eq(out.value, "want to join us")
	eq(l.listening, false)
	Asr.NativeRecognition.runtime = null
	l.free()
	rt.free()


func test_cancelling_drops_the_words_and_a_late_final_line_is_ignored():
	var pipe := FakePipe.new()
	var mic := FakeMic.new()
	var rt := _ready_runtime(pipe, mic)
	Asr.NativeRecognition.runtime = rt
	var l := Voice.Listener.new({"Recognition": Asr.NativeRecognition})
	var out := {"value": "pending"}
	var run := func(): out.value = await l.start()
	run.call()
	pipe.say({"event": "ready"})
	rt.poll()
	l.stop()
	l.cancel()
	eq(out.value, null, "cancelled")
	eq(pipe.tags(), "SFX")
	pipe.say({"event": "final", "text": "never mind"})
	rt.poll()
	eq(rt.session, null)
	# and the next session works
	var again := {"value": "pending"}
	var run2 := func(): again.value = await l.start()
	run2.call()
	l.stop()
	pipe.say({"event": "final", "text": "attack"})
	rt.poll()
	eq(again.value, "attack")
	Asr.NativeRecognition.runtime = null
	l.free()
	rt.free()


func test_a_helper_that_dies_is_reported_and_the_next_try_starts_it_again():
	var pipe := FakePipe.new()
	var mic := FakeMic.new()
	var rt := _ready_runtime(pipe, mic)
	var told := []
	rt.said.connect(func(t): told.append(t))
	var errors := []
	var ended := [0]
	var rec := Asr.NativeRecognition.new()
	rec.onerror = func(ev): errors.append(ev.error)
	rec.onend = func(): ended[0] += 1
	rt.listen(rec)
	pipe.err = "could not open encoder.int8.onnx"
	pipe.alive = false
	rt.poll()
	eq(rt.state, "failed")
	eq(errors, ["asr-failed"])
	eq(ended[0], 1)
	ok(pipe.closed)
	eq(told.size(), 1)
	match_re(told[0], "COULD NOT OPEN ENCODER")
	match_re(rt.prepare(), "^VOICE INPUT ISN'T WORKING")
	eq(rt.state, "idle", "the next hold starts the helper again")
	rt.free()


func test_a_silent_microphone_is_reported_rather_than_listened_to_forever():
	var pipe := FakePipe.new()
	var mic := FakeMic.new()
	var rt := _ready_runtime(pipe, mic)
	var errors := []
	var rec := Asr.NativeRecognition.new()
	rec.onerror = func(ev): errors.append(ev.error)
	rt.listen(rec)
	rt.poll()
	eq(errors, [])
	rt._listen_ms -= Asr.NO_SOUND_MS + 1.0
	rt.poll()
	eq(errors, ["audio-capture"])
	eq(rt.session, null)
	ok(not mic.on)
	rt.free()


func test_without_the_model_the_first_try_offers_the_download():
	var rt := Asr.Runtime.new({"helper_dir": "/fake", "model_dir": ProjectSettings.globalize_path("res://tests"), "mic": FakeMic.new()})
	eq(rt.state, "no-model")
	match_re(rt.prepare(), "ONE-TIME 662 MB DOWNLOAD. HOLD SPACE AGAIN")
	eq(rt.listen(Asr.NativeRecognition.new()), false, "nothing to listen with yet")
	rt.state = "downloading"
	rt.progress = 0.42
	eq(rt.prepare(), "STILL DOWNLOADING THE SPEECH MODEL: 42%. TYPE FOR NOW.")
	rt.free()


func test_the_recognizer_on_this_machine():
	if OS.has_feature("web"):
		return
	eq(Voice.recognizer() == Asr.NativeRecognition, Asr.Runtime.available(), "the native recognizer exactly when this build has the helper")


## The real helper on a recording, through the real pipe: needs native/asr/build.sh <platform> and build.sh model
func test_the_real_helper_hears_a_recording():
	var p := Asr.platform()
	var model := ProjectSettings.globalize_path(Asr.DEV_MODEL)
	if p == "" or not Asr.Runtime.available() or not Asr.model_complete(model):
		print("    (skipped: build the helper and the model with native/asr/build.sh to run this)")
		return
	var wav := _read_wav(model.path_join("test_wavs/8k.wav"))
	var mic := FakeMic.new()
	mic.rate = wav.rate
	var step := int(wav.rate * 0.05)
	for i in range(0, wav.samples.size(), step):
		mic.chunks.append(wav.samples.slice(i, i + step))
	var rt := Asr.Runtime.new({"model_dir": model, "mic": mic})
	rt.warm()  # as the game does for someone who talks: the model takes seconds to load
	var t0 := J.now_ms()
	while rt.state == "loading" and J.now_ms() - t0 < 60000.0:
		rt.poll()
		await J.sleep(20)
	eq(rt.state, "ready")
	var rec := Asr.NativeRecognition.new()
	var heard := []
	var done := [false]
	rec.onresult = func(ev): heard.append(ev.results[0].transcript)
	rec.onend = func(): done[0] = true
	ok(rt.listen(rec))
	t0 = J.now_ms()
	while not mic.chunks.is_empty() and J.now_ms() - t0 < 60000.0:
		rt.poll()
		await J.sleep(50)  # one 50 ms chunk per poll: at the pace of speech
	rt.finish(rec)
	while not done[0] and J.now_ms() - t0 < 90000.0:
		rt.poll()
		await J.sleep(20)
	ok(done[0], "the session ended")
	ok(heard.size() >= 2, "words while speaking, then the final text")
	match_re(str(heard.back()).to_lower(), "these thoughts affected hester prynne less with hope than apprehension")
	rt.shut()
	rt.free()


func _read_wav(path: String) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path)
	var rate := b.decode_u32(24)
	var at := 12
	while at + 8 <= b.size() and b.slice(at, at + 4).get_string_from_ascii() != "data":
		at += 8 + b.decode_u32(at + 4)
	var n := b.decode_u32(at + 4) / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = b.decode_s16(at + 8 + i * 2) / 32768.0
	return {"rate": rate, "samples": out}
