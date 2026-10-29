# The game against the real audio classes (not started, so silent): every call it makes to sfx, music, the
# narrator and the voice listener has to exist with those arguments. A fight, a recruit and a Roll of Fate.
extends "res://tests/game/helpers.gd"

const Sfx = preload("res://src/audio/sfx.gd")
const Ambient = preload("res://src/audio/ambient.gd")
const Tts = preload("res://src/audio/tts.gd")
const Voice = preload("res://src/audio/voice.gd")

var nodes := []


func after_each():
	for n in nodes:
		n.queue_free()
	nodes.clear()
	super.after_each()


func test_the_real_audio_objects_take_every_call():
	make_game({"tips": false, "seed": 121, "start": false, "handler": taming("join_party")})
	var sfx = Sfx.Sfx.new()
	var music = Ambient.Ambient.new()
	var narrator = Tts.Narrator.new({"synth": null, "store": game.store})
	var voice = Voice.Listener.new({"Recognition": null})
	for n in [sfx, music, narrator, voice]:
		(Engine.get_main_loop() as SceneTree).root.add_child(n)
		nodes.append(n)
	game.sfx = sfx
	game.music = music
	game.narrator = narrator
	game.voice = voice
	ok(not narrator.supported and not voice.supported)
	game.started = true
	game.new_run()
	game.key("o")
	game.key("o")
	saw("^SOUND EFFECTS ON\\.$")
	game.key("l")
	eq(lines()[-1], "SOUND EFFECTS ON.", "L does nothing without voices")
	game.debug_meet(["slime"])
	eq(music.mood, "battle")
	await settle()
	if game.G.prompt == null:
		game.key("t")
		game.close_input("hello")
		await settle()
	ok(game.G.prompt != null, "it asks to join")
	game.key("y")
	await settle()
	eq(game.G.combat, null)
	eq(music.mood, "explore")
	game.debug_roll()
	await until(func(): return game.G.waitKey != null)
	game.key("enter")
	await settle()
	eq(game.G.roll, null)
	eq(sfx.lag, 0.0, "the dice lag is back to 0")
