## Monsters reading their lines aloud (port of test/tts.test.js), against a fake speech engine
extends "res://tests/test_case.gd"

const Tts = preload("res://src/audio/tts.gd")
const StoreScript = preload("res://src/core/store.gd")


func test_only_the_words_are_spoken_not_the_stage_directions():
	eq(Tts.speakable("RAAH! *swings a knotted club at {target}*"), "RAAH!")
	eq(Tts.speakable("*stares blankly* ...hi heehee."), "hi heehee.")
	eq(Tts.speakable("You broke your word. Now I break YOU."), "You broke your word. Now I break YOU.")
	eq(Tts.speakable("*oozes away*"), "")
	eq(Tts.speakable(null), "")


func test_off_until_the_player_uses_their_voice_an_explicit_choice_always_wins():
	eq(Tts.tts_on({}), false)
	eq(Tts.tts_on({"usedVoice": true}), true)
	eq(Tts.tts_on({"usedVoice": true, "choice": "off"}), false)
	eq(Tts.tts_on({"usedVoice": false, "choice": "on"}), true)


func test_an_english_voice_is_picked_even_when_the_systems_language_isnt_english_local_first():
	var voices := [
		{"name": "Tingting", "lang": "zh-CN", "localService": true},
		{"name": "Google UK English Female", "lang": "en-GB", "localService": false},
		{"name": "Samantha", "lang": "en-US", "localService": true},
	]
	eq(Tts.pick_voice(voices, "slime").name, "Samantha")
	eq(Tts.pick_voice([{"name": "Tingting", "lang": "zh-CN"}], "slime"), null)
	var deep = Tts.pick_voice(voices + [{"name": "Daniel", "lang": "en-GB", "localService": true}], "dragon")
	eq(deep.name, "Daniel")
	# voices as DisplayServer reports them: `language`, with underscores, and no localService
	eq(Tts.pick_voice([{"name": "Alex", "language": "en_US", "id": "x"}], "goblin").name, "Alex")


## A fake speech engine that records what it was asked to say
class FakeSynth:
	extends RefCounted
	var spoken: Array = []
	var cancels := 0

	func get_voices() -> Array:
		return [{"name": "Samantha", "lang": "en-US", "localService": true}]

	func speak(u) -> void:
		spoken.append(u)

	func cancel() -> void:
		cancels += 1
		spoken.clear()


func _narrator(synth, store, ducks = null) -> Tts.Narrator:
	var opts := {"synth": synth, "store": store}
	if ducks != null:
		opts["onDuck"] = func(on): ducks.append(on)
	return Tts.Narrator.new(opts)


func test_silent_by_default_speaks_once_the_player_has_used_the_microphone():
	var synth := FakeSynth.new()
	var store := StoreScript.Memory.new()
	var n := _narrator(synth, store)
	eq(n.say("Hello, tiny.", "goblin"), null)
	n.heard_player()
	var u = n.say("Hello, tiny. *grins*", "goblin")
	eq(u.text, "Hello, tiny.")
	eq(u.pitch, Tts.VOICES.goblin.pitch)
	eq(u.rate, Tts.VOICES.goblin.rate)
	eq(u.voice.name, "Samantha")
	eq(u.lang, "en-US")
	eq(store.data["donjon.usedVoice"], "1", "remembered for next time")
	n.free()


func test_l_toggles_it_for_good_and_turning_it_off_stops_any_speech_at_once():
	var synth := FakeSynth.new()
	var store := StoreScript.Memory.new({"donjon.usedVoice": "1"})
	var n := _narrator(synth, store)
	eq(n.on, true)
	eq(n.toggle(), false)
	eq(store.data["donjon.tts"], "off")
	ok(synth.cancels >= 1)
	eq(n.say("Hi.", "slime"), null)
	eq(n.toggle(), true)
	ok(n.say("Hi.", "slime") != null)
	n.free()


func test_a_backlog_is_dropped_so_speech_keeps_up_with_the_fight():
	var synth := FakeSynth.new()
	var n := _narrator(synth, StoreScript.Memory.new({"donjon.tts": "on"}))
	n.say("One.", "slime")
	n.say("Two.", "slime")
	n.say("Three.", "slime")
	eq(synth.cancels, 1)
	eq(synth.spoken.map(func(u): return u.text), ["Three."])
	n.free()


func test_without_a_speech_engine_it_is_simply_off():
	var n := Tts.Narrator.new({"synth": null, "store": StoreScript.Memory.new({"donjon.tts": "on"})})
	eq(n.supported, false)
	eq(n.on, false)
	eq(n.say("Hello.", "slime"), null)
	n.free()


func test_while_a_monster_speaks_the_rest_of_the_game_ducks_under_it_and_comes_back_when_its_done():
	var synth := FakeSynth.new()
	var ducks := []
	var n := _narrator(synth, StoreScript.Memory.new({"donjon.tts": "on"}), ducks)
	var a = n.say("One.", "slime")
	var b = n.say("Two.", "slime")
	eq(a.volume, 1.0, "speech at full volume")
	a.onstart.call()
	eq(ducks, [true])
	a.onend.call()
	b.onstart.call()
	eq(ducks, [true], "still ducked between two lines in a row")
	b.onend.call()
	eq(ducks, [true, false])
	n.say("Three.", "slime").onstart.call()
	n.hush()
	eq(ducks, [true, false, true, false], "hushing lifts the duck too")
	n.free()


func test_a_cancelled_line_ending_late_doesnt_lift_the_duck_from_under_the_next_one():
	var ducks := []
	var n := _narrator(FakeSynth.new(), StoreScript.Memory.new({"donjon.tts": "on"}), ducks)
	var old = n.say("Old.", "slime")
	old.onstart.call()
	n.hush()
	var fresh = n.say("New.", "slime")
	fresh.onstart.call()
	old.onerror.call()  # the engine reports the cancelled one late
	eq(ducks, [true, false, true], "still ducked for the new line")
	fresh.onend.call()
	eq(ducks, [true, false, true, false])
	n.free()


func test_the_default_engine_matches_what_the_system_offers():
	var n := Tts.Narrator.new({"store": StoreScript.Memory.new({"donjon.tts": "on"})})
	eq(n.supported, DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH))
	if not n.supported:
		eq(n.say("Hello.", "slime"), null)
	n.free()
