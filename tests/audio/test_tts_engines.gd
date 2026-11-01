## The pluggable voices (tts_engines.gd, tts_config.gd) and the Narrator stepping through them, against fake services
extends "res://tests/test_case.gd"

const Tts = preload("res://src/audio/tts.gd")
const Engines = preload("res://src/audio/tts_engines.gd")
const TtsConfig = preload("res://src/audio/tts_config.gd")
const StoreScript = preload("res://src/core/store.gd")


## An engine that records what it said and may refuse lines
class FakeEngine:
	extends RefCounted
	var said: Array = []
	var cancels := 0
	var says_all := true

	func get_voices() -> Array:
		return []

	func can_say(_u) -> bool:
		return says_all

	func speak(u) -> void:
		said.append(u.text)

	func cancel() -> void:
		cancels += 1


## Answers requests from a script: [[method, url-suffix, status, body (String or PackedByteArray)], ...] in order
class FakeFetch:
	extends RefCounted
	var replies: Array = []
	var asked: Array = []  # [method, url, headers, body]

	func call_it(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
		asked.append([method, url, headers, body])
		await (Engine.get_main_loop() as SceneTree).process_frame
		if replies.is_empty():
			return {"error": "nothing scripted for " + url}
		var r: Array = replies.pop_front()
		if r[0] == "error":
			return {"error": r[1]}
		var b = r[3]
		return {"status": r[2], "body": b if b is PackedByteArray else str(b).to_utf8_buffer()}


func _u(text: String, species = "slime", log := []) -> Tts.Utterance:
	var u := Tts.Utterance.new()
	u.text = text
	u.species = species
	u.onstart = func(): log.append("start " + text)
	u.onend = func(): log.append("end " + text)
	u.onerror = func(): log.append("error " + text)
	return u


## A short WAV file (16-bit mono silence) as the services send them
func _wav(samples := 2400, rate := 24000) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(44 + samples * 2)
	b.encode_u32(0, 0x46464952)  # RIFF
	b.encode_u32(4, 36 + samples * 2)
	b.encode_u32(8, 0x45564157)  # WAVE
	b.encode_u32(12, 0x20746d66)  # fmt
	b.encode_u32(16, 16)
	b.encode_u16(20, 1)
	b.encode_u16(22, 1)
	b.encode_u32(24, rate)
	b.encode_u32(28, rate * 2)
	b.encode_u16(32, 2)
	b.encode_u16(34, 16)
	b.encode_u32(36, 0x61746164)  # data
	b.encode_u32(40, samples * 2)
	return b


func _wait(cond: Callable, frames := 200) -> void:
	for i in frames:
		if cond.call():
			return
		await (Engine.get_main_loop() as SceneTree).process_frame


func test_a_rendered_line_is_filed_under_the_words_said():
	eq(Tts.line_key("*blank stare* ...Blorp.  *lunges at {target}*"), "blorp.")
	eq(Tts.line_key("No hurt Glop. please."), "no hurt glop. please.")
	eq(Tts.line_key("*oozes away*"), "")


func test_the_chain_gives_each_line_to_the_first_engine_that_has_it():
	var bank := FakeEngine.new()
	var system := FakeEngine.new()
	var chain := Engines.Chain.new([bank, system])
	chain.speak(_u("Hi."))
	bank.says_all = false
	chain.speak(_u("Hello, Hortense."))
	eq(bank.said, ["Hi."])
	eq(system.said, ["Hello, Hortense."])
	chain.cancel()
	eq([bank.cancels, system.cancels], [1, 1])
	system.says_all = false
	var log := []
	chain.speak(_u("Nobody.", "slime", log))
	eq(log, ["error Nobody."], "no engine: the line ends at once, so nothing waits on it")


func test_the_player_keeps_lines_in_order_even_when_the_second_is_ready_first():
	var p := Engines.Player.new()
	var log := []
	var a := p.enqueue(_u("One.", "slime", log))
	var b := p.enqueue(_u("Two.", "slime", log))
	var c := p.enqueue(_u("Three.", "slime", log))
	p.fill(b, AudioStreamWAV.new())
	eq(log, [], "Two waits for One")
	p.fill(a, AudioStreamWAV.new())
	eq(log, ["start One."])
	p.fail(c)
	p._ended()
	eq(log, ["start One.", "end One.", "start Two."])
	p._ended()
	eq(log, ["start One.", "end One.", "start Two.", "end Two.", "error Three."])
	var d := p.enqueue(_u("Four.", "slime", log))
	p.fill(d, AudioStreamWAV.new())
	p.enqueue(_u("Five.", "slime", log))
	p.cancel()
	eq(log.slice(-3), ["start Four.", "error Four.", "error Five."], "cancel ends the line playing and everything waiting")
	p.free()


func test_a_bank_says_its_own_lines_and_lets_the_rest_through():
	var dir := "user://test-bank"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"id": "testbank", "label": "TEST", "lines": {"slime": {"blorp.": "res://assets/audio/fanfare.ogg", "hi.": "missing.ogg"}}}))
	f.close()
	var p := Engines.Player.new()
	var bank := Engines.Bank.open(dir, p)
	eq(bank.id, "testbank")
	eq(bank.size(), 2)
	ok(bank.can_say(_u("...Blorp. *lunges*")))
	ok(not bank.can_say(_u("Blorp.", "goblin")), "another monster's line")
	ok(not bank.can_say(_u("Hello, Hortense.")))
	var log := []
	bank.speak(_u("Blorp.", "slime", log))
	eq(log, ["start Blorp."])
	ok(p._current.stream is AudioStream)
	eq(Engines.Bank.open("user://no-such-bank", p), null)
	p.free()


func test_the_feiyu_service_queues_a_job_polls_it_and_plays_the_audio():
	var fetch := FakeFetch.new()
	fetch.replies = [
		["POST", "/v1/speech", 202, JSON.stringify({"id": "j1", "status": "queued"})],
		["GET", "/v1/jobs/j1", 200, JSON.stringify({"id": "j1", "status": "running"})],
		["GET", "/v1/jobs/j1", 200, JSON.stringify({"id": "j1", "status": "success"})],
		["GET", "/v1/jobs/j1/audio", 200, _wav()],
	]
	var p := Engines.Player.new()
	var f := Engines.Feiyu.new({"url": "http://gpu:8000/", "key": "k", "defaults": {"voice": "donjon", "style": "gentle"},
		"voices": {"dragon": {"style": "cute"}}, "fetch": fetch.call_it}, p)
	ok(f.can_say(_u("Hi.")))
	var log := []
	f.speak(_u("Burn.", "dragon", log))
	await _wait(func(): return not log.is_empty())
	eq(log, ["start Burn."])
	eq(fetch.asked[0][1], "http://gpu:8000/v1/speech")
	eq(JSON.parse_string(fetch.asked[0][3]), {"voice": "donjon", "style": "cute", "text": "Burn."})
	ok(Array(fetch.asked[0][2]).has("Authorization: Bearer k"))
	eq(fetch.asked.map(func(a): return a[1].trim_prefix("http://gpu:8000")), ["/v1/speech", "/v1/jobs/j1", "/v1/jobs/j1", "/v1/jobs/j1/audio"])
	ok(p._current.stream is AudioStreamWAV)
	# heard again: from the cache, no request
	p._ended()
	f.speak(_u("Burn.", "dragon", log))
	eq(fetch.asked.size(), 4)
	eq(log.back(), "start Burn.")
	p.free()


func test_a_failing_service_steps_aside_for_a_while():
	var fetch := FakeFetch.new()
	fetch.replies = [["error", "can't connect"]]
	var p := Engines.Player.new()
	var q := Engines.Qwen.new({"url": "http://mac:8001", "defaults": {"language": "en"}, "voices": {"slime": {"speaker": "Aiden"}}, "fetch": fetch.call_it}, p)
	var log := []
	q.speak(_u("Hi.", "slime", log))
	await _wait(func(): return not log.is_empty())
	eq(log, ["error Hi."])
	eq(q.why, "can't connect")
	ok(not q.can_say(_u("Hi.")), "the chain skips it for now")
	q.down_until = 0.0
	fetch.replies = [["POST", "/synthesize", 200, _wav()]]
	q.speak(_u("Hi.", "slime", log))
	await _wait(func(): return log.size() > 1)
	eq(JSON.parse_string(fetch.asked[1][3]), {"language": "en", "speaker": "Aiden", "text": "Hi."})
	eq(fetch.asked[1][1], "http://mac:8001/synthesize")
	eq(log.back(), "start Hi.")
	p.free()


func test_a_line_cancelled_while_it_was_being_synthesised_never_plays():
	var fetch := FakeFetch.new()
	fetch.replies = [["POST", "/synthesize", 200, _wav()]]
	var p := Engines.Player.new()
	var q := Engines.Qwen.new({"url": "http://mac:8001", "fetch": fetch.call_it}, p)
	var log := []
	q.speak(_u("Late.", "slime", log))
	q.cancel()
	await _wait(func(): return fetch.replies.is_empty(), 5)
	await (Engine.get_main_loop() as SceneTree).process_frame
	eq(log, ["error Late."])
	eq(p.playing, false)
	p.free()


func test_the_lineup_banks_first_then_services_then_the_system():
	var cfg := TtsConfig.resolve({"banks": ["extra", "qwen3", "cosyvoice3"], "flags_text": "", "json_text": "", "dotenv_text": "", "system": true})
	eq(cfg.order, ["cosyvoice3", "qwen3", "extra", "system"])
	eq(cfg.banks.cosyvoice3, "res://assets/voices/cosyvoice3")
	eq(cfg.feiyu, null)
	cfg = TtsConfig.resolve({"banks": ["cosyvoice3"], "flags_text": "", "json_text": "", "exported": false, "system": false,
		"dotenv_text": "FEIYU_TTS_URL=http://gpu:8000\nFEIYU_TTS_KEY=k\nFEIYU_TTS_VOICE=cc-dragon\nQWEN_TTS_URL=http://mac:8001"})
	eq(cfg.order, ["cosyvoice3", "feiyu", "qwen"])
	eq(cfg.feiyu.defaults, {"voice": "cc-dragon", "style": "gentle"})
	eq(cfg.feiyu.key, "k")
	eq(cfg.qwen.voices.dragon, {"speaker": TtsConfig.QWEN_SPEAKERS.dragon})


func test_the_feiyu_service_is_not_used_without_a_voice_of_our_own():
	var cfg := TtsConfig.resolve({"banks": [], "flags_text": "", "json_text": "", "exported": false, "system": true,
		"dotenv_text": "FEIYU_TTS_URL=http://gpu:8000"})
	eq(cfg.feiyu, null)
	eq(cfg.order, ["system"])
	match_re(cfg.warnings[0], "Feiyu voice library")


func test_an_exported_build_reads_no_env_and_the_json_and_flag_choose_the_order():
	var json := JSON.stringify({"engines": ["qwen", "system"], "qwen": {"url": "http://mac:8001", "voices": {"slime": {"speaker": "Vivian"}}}})
	var cfg := TtsConfig.resolve({"banks": ["cosyvoice3"], "flags_text": "", "json_text": json, "exported": true, "system": true, "dotenv_text": "FEIYU_TTS_URL=http://gpu:8000\nFEIYU_TTS_VOICE=x"})
	eq(cfg.order, ["qwen", "system", "cosyvoice3"])
	eq(cfg.feiyu, null, ".env is for runs from source only")
	eq(cfg.qwen.voices.slime, {"speaker": "Vivian"})
	cfg = TtsConfig.resolve({"banks": ["cosyvoice3"], "flags_text": "--tts=system", "json_text": json, "exported": true, "system": true})
	eq(cfg.order[0], "system")
	cfg = TtsConfig.resolve({"banks": [], "flags_text": "tts=nope", "json_text": "", "exported": true, "system": true})
	match_re(cfg.warnings[0], "no engine \"nope\"")


func test_l_steps_through_the_voices_then_off_and_remembers_the_choice():
	var made := {"a": FakeEngine.new(), "b": FakeEngine.new()}
	var lineup := {"order": ["a", "b"], "make": func(id): return made[id]}
	var store := StoreScript.Memory.new({"donjon.tts": "on"})
	var n := Tts.Narrator.new({"engines": lineup, "store": store})
	eq(n.engine, "a")
	n.say("One.", "slime")
	eq(made.a.said, ["One."])
	eq(n.toggle(), true, "L: the next voice")
	eq(n.engine, "b")
	eq(store.data["donjon.ttsEngine"], "b")
	n.say("Two.", "slime")
	eq(made.b.said, ["Two."])
	eq(n.toggle(), false, "after the last voice: off")
	eq(n.engine, "a", "and the first voice next time")
	eq(n.say("Three.", "slime"), null)
	eq(n.toggle(), true)
	eq(n.engine, "a")
	n.free()
	# a new run starts with the voice last chosen
	store.data["donjon.ttsEngine"] = "b"
	var again := Tts.Narrator.new({"engines": lineup, "store": store})
	eq(again.engine, "b")
	again.free()
	var none := Tts.Narrator.new({"engines": {"order": [], "make": func(_id): return null}, "store": store})
	eq(none.supported, false)
	none.free()


func test_the_narrator_tells_the_engine_who_is_speaking():
	var e := FakeEngine.new()
	var n := Tts.Narrator.new({"synth": e, "store": StoreScript.Memory.new({"donjon.tts": "on"})})
	var u = n.say("Hello, tiny.", "goblin")
	eq(u.species, "goblin")
	n.free()


func test_the_default_lineup_offers_what_this_build_has():
	var n := Tts.Narrator.new({"store": StoreScript.Memory.new({"donjon.tts": "on"})})
	var cfg := TtsConfig.resolve()
	eq(n.order, cfg.order)
	eq(n.supported, not cfg.order.is_empty())
	if not cfg.order.is_empty():
		eq(n.engine, cfg.order[0])
	n.free()
