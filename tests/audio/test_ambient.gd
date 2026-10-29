## Music mood switching (explore <-> battle), with a clock the test moves by hand (port of test/ambient.test.js)
extends "res://tests/test_case.gd"

const Ambient = preload("res://src/audio/ambient.gd")
const Mix = preload("res://src/audio/mix.gd")

var now := [10.0]
var nodes: Array = []


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()


func _clock() -> float:
	return now[0]


## A silent stream of the given length, named so a test can tell which one a source plays
func _stream(name: String, seconds: float = 1.0) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 1000
	var bytes := PackedByteArray()
	bytes.resize(int(seconds * 1000.0) * 2)
	w.data = bytes
	w.resource_name = name
	return w


func _music(random: Callable = func(): return 0.5) -> Ambient.Ambient:
	var m := Ambient.Ambient.new({"clock": _clock, "random": random})
	(Engine.get_main_loop() as SceneTree).root.add_child(m)
	nodes.append(m)
	return m


## A music player that is attached and has every stream loaded, exploring since t = 10
func _started(random: Callable = func(): return 0.5) -> Ambient.Ambient:
	now[0] = 10.0
	var m := _music(random)
	m.attach()
	m.buffers = {"explore": _stream("explore"), "fanfare": _stream("fanfare", 3.6), "victory": _stream("victory", 2.2)}
	for v in Ambient.TRACKS.battle.variants:
		m.buffers["battle:" + v.name] = _stream("battle:" + v.name)
	m.explore_in(4)
	return m


## The level a track was last told to fade to
func _level(m: Ambient.Ambient, track: String) -> float:
	var v = m.voices.get(track)
	return v.gain.events.back()[1] if v != null else -1.0


func _last_ramp(m: Ambient.Ambient, track: String) -> Array:
	var ev: Array = m.voices[track].gain.events.back()
	return [ev[1], ev[2]]


func test_a_fight_fades_the_battle_loop_in_fast_and_the_ambient_out():
	var music := _started()
	music.set_mood("battle")
	var battle = music.voices.battle
	var explore = music.voices.explore
	ok(battle.src.buffer.resource_name.begins_with("battle:"))
	eq(_last_ramp(music, "battle"), [Ambient.TRACKS.battle.volume, 10.0 + Ambient.FADES.battle["in"]])
	eq(_last_ramp(music, "explore"), [0.0, 10.0 + Ambient.FADES.explore.underFight])
	eq(explore.src.stopped_at, null, "the ambient keeps its place under the fight")


func test_after_the_fight_the_battle_loop_stops_a_quiet_beat_then_the_same_ambient_voice_comes_back():
	var music := _started()
	var ambient = music.voices.explore
	music.set_mood("battle")
	var battle = music.voices.battle
	music.set_mood("explore")
	eq(_level(music, "explore"), 0.0, "not straight back")
	now[0] += Ambient.PACE.afterFight
	music.tick()
	ok(music.voices.explore == ambient, "the same voice")
	eq(_last_ramp(music, "explore"), [Ambient.TRACKS.explore.volume, now[0] + Ambient.FADES.explore["in"]])
	ok(battle.src.stopped_at > 10.0, "battle loop stops once faded")
	ok(not music.voices.has("battle"))


func test_a_fight_silences_the_ambient_almost_at_once_so_the_two_never_play_together():
	var music := _started()
	music.set_mood("battle")
	var r := _last_ramp(music, "explore")
	eq(r[0], 0.0)
	ok(r[1] - 10.0 <= 0.5, "ambient still audible %s s into the fight" % (r[1] - 10.0))


func test_between_stretches_of_exploring_the_ambient_still_fades_out_slowly():
	var music := _started()
	now[0] = 10.0 + (Ambient.PACE.play[0] + Ambient.PACE.play[1]) / 2.0
	music.tick()
	var r := _last_ramp(music, "explore")
	eq(r[0], 0.0)
	near(r[1] - now[0], Ambient.FADES.explore["out"])


func test_each_fight_starts_the_battle_loop_from_bar_one():
	var music := _started()
	music.set_mood("battle")
	var first = music.voices.battle.src
	music.set_mood("explore")
	music.set_mood("battle")
	ok(music.voices.battle.src != first)
	eq(music.voices.battle.src.offset, 0.0, "from the start of the (already trimmed) loop file")
	near(music.voices.battle.origin, 10.0 - Ambient.LOOP_START, 1e-9, "whose bar one is where the render's beat 0 was, 0.25 s earlier")


func test_the_ambient_comes_and_goes_a_stretch_of_music_then_a_stretch_of_quiet():
	var music := _started()
	eq(_level(music, "explore"), Ambient.TRACKS.explore.volume)
	var play: float = (Ambient.PACE.play[0] + Ambient.PACE.play[1]) / 2.0
	var rest: float = (Ambient.PACE.rest[0] + Ambient.PACE.rest[1]) / 2.0
	now[0] = 10.0 + play - 0.001
	music.tick()
	eq(_level(music, "explore"), Ambient.TRACKS.explore.volume)
	now[0] = 10.0 + play
	music.tick()
	eq(_level(music, "explore"), 0.0, "rests after playing")
	now[0] += rest
	music.tick()
	eq(_level(music, "explore"), Ambient.TRACKS.explore.volume, "and comes back")


func test_a_fight_cancels_the_ambients_comings_and_goings_nothing_else_is_pending():
	var music := _started()
	music.set_mood("battle")
	eq(music.pending(), [])


func test_each_fight_picks_a_battle_loop_at_random_never_the_same_one_twice_in_a_row():
	var r := [0]
	var seq := [0.1, 0.1, 0.9, 0.5, 0.5, 0.3, 0.7, 0.2]
	var music := _started(func():
		r[0] += 1
		return seq[(r[0] - 1) % seq.size()])
	var heard := []
	for i in 8:
		music.set_mood("battle")
		heard.append(music.battle.name)
		music.set_mood("explore")
	for i in range(1, heard.size()):
		ne(heard[i], heard[i - 1], "fight %d repeated %s" % [i, heard[i]])
	var distinct := {}
	for h in heard:
		distinct[h] = true
	ok(distinct.size() >= 3, "only heard %s" % [distinct.keys()])


func test_a_loop_that_is_already_loaded_is_preferred_so_the_fight_starts_at_once():
	var music := _started(func(): return 0.0)
	music.buffers.erase("battle:toccata")
	music.buffers.erase("battle:charge")
	music.buffers.erase("battle:crusade")
	music.set_mood("battle")
	eq(music.battle.name, "gallop")


func test_a_long_fight_keeps_its_one_loop_the_tune_never_changes_mid_fight():
	var music := _started()
	music.set_mood("battle")
	var first = music.battle
	var voice = music.voices.battle
	now[0] += 10.0 * 60.0
	music.tick()
	ok(music.battle == first)
	ok(music.voices.battle == voice)
	eq(voice.src.stopped_at, null, "still playing")
	eq(voice.src.loop, true)
	eq(_level(music, "battle"), Ambient.TRACKS.battle.volume, "never faded out")


func test_the_stairs_fanfare_silences_the_ambient_and_leaves_quiet_after_it():
	var music := _started()
	music.sting("fanfare")
	eq(_level(music, "explore"), 0.0)
	var fanfare = music.sources.back()
	eq(fanfare.buffer.resource_name, "fanfare")
	ok(not fanfare.loop, "a sting plays once")
	var pending := music.pending()
	eq(pending.size(), 1)
	near(pending[0], 3.6 + Ambient.PACE.afterSting, 1e-9)
	now[0] += 3.6 + Ambient.PACE.afterSting
	music.tick()
	eq(_level(music, "explore"), Ambient.TRACKS.explore.volume)


func test_winning_a_fight_the_victory_sting_cuts_the_battle_loop():
	var music := _started()
	music.set_mood("battle")
	var battle = music.voices.battle
	music.sting("victory")
	music.set_mood("explore")
	ok(battle.src.stopped_at <= 10.0 + 0.5, "battle loop gone within half a second")
	eq(music.sources.back().buffer.resource_name, "victory")
	ok(Ambient.STINGS.victory.volume > 0)


func test_a_sting_that_is_not_loaded_is_skipped():
	var music := _started()
	music.buffers.erase("fanfare")
	var before := music.sources.size()
	music.sting("fanfare")
	eq(music.sources.size(), before)
	eq(_level(music, "explore"), Ambient.TRACKS.explore.volume, "the music carries on")


func test_mood_changes_before_the_music_starts_are_remembered_not_played():
	var music := _music()
	music.set_mood("battle")
	eq(music.mood, "battle")
	eq(music.voices, {})


func test_no_battle_loop_runs_faster_than_132_bpm():
	for v in Ambient.TRACKS.battle.variants:
		ok(3840.0 / v.loopSeconds <= 132.0 + 1e-9, "%s is %.1f BPM" % [v.name, 3840.0 / v.loopSeconds])


func test_battle_loop_lengths_match_the_renders_16_bars_of_4_4_at_each_tempo():
	# tools/music/build-battle.py: toccata 132, charge 126, crusade 112, gallop 120 BPM
	var want := {"toccata": 29.091, "charge": 30.476, "crusade": 34.286, "gallop": 32.0}
	var names := Ambient.TRACKS.battle.variants.map(func(v): return v.name)
	names.sort()
	var keys := want.keys()
	keys.sort()
	eq(names, keys)
	for v in Ambient.TRACKS.battle.variants:
		ok(absf(v.loopSeconds - want[v.name]) < 0.001, v.name)


func test_ducking_pulls_the_music_down_under_speech_and_brings_it_back():
	var music := _started()
	music.duck(true)
	eq(music.master.events.back()[1], Ambient.DUCK.level)
	music.duck(false)
	eq(music.master.events.back()[1], 1.0)


func test_ducking_and_the_p_switch_set_the_music_input_bus():
	var music := _started()
	var idx := AudioServer.get_bus_index(Mix.BUS_MUSIC_IN)
	music.set_muted(false)
	now[0] += 0.12
	music.tick()
	near(AudioServer.get_bus_volume_db(idx), 0.0, 0.01)
	music.duck(true)
	now[0] += Ambient.DUCK.down
	music.tick()
	near(AudioServer.get_bus_volume_db(idx), linear_to_db(Ambient.DUCK.level), 0.01)
	music.stop()
	now[0] += 0.12
	music.tick()
	ok(AudioServer.get_bus_volume_db(idx) < -60.0, "muted")
	eq(music.on, false)


func test_the_explore_loop_length_matches_the_render_40_bars_of_3_4_at_64_bpm():
	eq(Ambient.TRACKS.explore.loopSeconds, 112.5)
	near(40.0 * 3.0 * 60.0 / 64.0, 112.5)


func test_explore_sits_a_little_under_the_fights_and_stings_match_the_fights():
	# The renders are mastered to -19 dBFS RMS (explore) and -17 dBFS RMS (fights and stings): tools/music/sampler.py
	var db := func(rms, volume): return rms + 20.0 * log(volume) / log(10.0)
	var explore: float = db.call(-19.0, Ambient.TRACKS.explore.volume)
	var battle: float = db.call(-17.0, Ambient.TRACKS.battle.volume)
	ok(battle - explore >= 1.5 and battle - explore <= 4.0, "explore is %.1f dB under battle" % (battle - explore))
	for s in Ambient.STINGS.values():
		eq(s.volume, Ambient.TRACKS.battle.volume)


# ---- the real files

func test_every_music_file_exists_and_loops_where_it_should():
	var music := _music()
	music.attach()
	for name in ["explore", "battle:toccata", "battle:charge", "battle:crusade", "battle:gallop", "fanfare", "victory"]:
		var s := music.load_stream(name)
		ok(s != null, "%s did not load" % name)
		if s == null:
			continue
		ok(s is AudioStreamOggVorbis, name)
		eq(s.loop, not (name == "fanfare" or name == "victory"), "%s loop flag" % name)
		eq(s.loop_offset, 0.0)
	ok(music.load_stream("nope") == null)


func test_loop_files_are_exactly_one_loop_long():
	var music := _music()
	var tracks := [["explore", Ambient.TRACKS.explore.loopSeconds]]
	for v in Ambient.TRACKS.battle.variants:
		tracks.append(["battle:" + v.name, v.loopSeconds])
	for t in tracks:
		var s := music.load_stream(t[0])
		near(s.get_length(), t[1], 0.01, "%s lasts %s s, its loop is %s s" % [t[0], s.get_length(), t[1]])


func test_the_stings_last_as_long_as_the_readme_says():
	var music := _music()
	near(music.load_stream("fanfare").get_length(), 3.9, 0.1)
	near(music.load_stream("victory").get_length(), 2.3, 0.1)


func test_the_real_music_starts_and_the_first_beat_grid_is_reported():
	# start() loads the ambient and plays it from a fade; the loops and stings load behind it, one a frame
	now[0] = 50.0
	var music := _music()
	music.attach()
	music.on = false
	await music.start()
	ok(music.on)
	ok(music.buffers.has("explore"))
	var clock = music.beat_clock()
	eq(clock.bpm, 64.0)
	near(clock.origin, 50.0 - Ambient.LOOP_START, 1e-9)
	var guard := 0
	while music.buffers.size() < 7 and guard < 60:
		await (Engine.get_main_loop() as SceneTree).process_frame
		guard += 1
	eq(music.buffers.size(), 7, "the rest loaded behind it")
	var player: AudioStreamPlayer = music.voices.explore.src.player
	ok(player.playing)
	eq(player.bus, Mix.BUS_MUSIC_IN)
