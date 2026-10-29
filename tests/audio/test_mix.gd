## The mixing desk (src/audio/mix.gd), the beat scheduler and the music's beat clock (port of test/mix.test.js),
## plus the bus layout the JS graph became
extends "res://tests/test_case.gd"

const Mix = preload("res://src/audio/mix.gd")
const Ambient = preload("res://src/audio/ambient.gd")

var now := [5.0]
var nodes: Array = []


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()


func _clock() -> float:
	return now[0]


func _mixer() -> Mix.Mixer:
	now[0] = 5.0
	var m := Mix.Mixer.new({"clock": _clock})
	(Engine.get_main_loop() as SceneTree).root.add_child(m)
	nodes.append(m)
	return m


func test_danger_closes_the_musics_low_pass_from_wide_open_to_muffled_in_octaves():
	eq(Mix.cutoff_for(0.0), Mix.DANGER.openHz)
	near(Mix.cutoff_for(1.0), Mix.DANGER.closedHz, 1e-6)
	near(Mix.cutoff_for(0.5), sqrt(Mix.DANGER.openHz * Mix.DANGER.closedHz), 1e-6, "halfway is the geometric middle")
	var mix := _mixer()
	mix.set_danger(1.0)
	eq(mix.lowpass_frequency.events.back().slice(0, 2), ["target", Mix.cutoff_for(1.0)])
	ok(mix.music_bus_gain.events.back()[1] < 1.0, "the music dips under the heartbeat")
	var n := mix.lowpass_frequency.events.size()
	mix.set_danger(1.004)
	eq(mix.lowpass_frequency.events.size(), n, "no rescheduling for a change nobody hears")


func test_a_big_hit_dips_the_music_and_lets_it_straight_back():
	var mix := _mixer()
	mix.impact(Mix.IMPACT.crit, 6.0)
	var down: Array = mix.impact_gain.events[0]
	var up: Array = mix.impact_gain.events[1]
	eq(down, ["target", 1.0 - Mix.IMPACT.crit, 6.0, Mix.IMPACT.attack])
	eq(up[1], 1.0)
	ok(up[2] > 6.0 and up[2] < 6.2)
	# and the bus follows: dipped a moment into the hit, back a second later
	var idx := AudioServer.get_bus_index(Mix.BUS_MUSIC)
	mix.advance(6.06)
	ok(AudioServer.get_bus_volume_db(idx) < linear_to_db(0.7), "dipped: %s dB" % AudioServer.get_bus_volume_db(idx))
	mix.advance(8.0)
	near(AudioServer.get_bus_volume_db(idx), 0.0, 0.05)


func test_the_danger_filter_and_dip_reach_the_music_bus():
	var mix := _mixer()
	var idx := AudioServer.get_bus_index(Mix.BUS_MUSIC)
	var low := AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter
	mix.advance(5.0)
	near(low.cutoff_hz, Mix.DANGER.openHz, 1.0)
	mix.set_danger(1.0)
	mix.advance(5.0 + 10.0 * Mix.DANGER.lag)
	near(low.cutoff_hz, Mix.DANGER.closedHz, 5.0, "muffled")
	near(AudioServer.get_bus_volume_db(idx), linear_to_db(1.0 - Mix.DANGER.musicDip), 0.05, "and 30% quieter")
	mix.set_danger(0.0)
	mix.advance(5.0 + 20.0 * Mix.DANGER.lag)
	near(low.cutoff_hz, Mix.DANGER.openHz, 50.0)
	near(AudioServer.get_bus_volume_db(idx), 0.0, 0.05)


func test_a_mixer_that_is_automated_every_frame_does_not_grow_without_bound():
	var mix := _mixer()
	for i in 200:
		mix.set_danger(float(i % 2))
		mix.impact(0.3, now[0])
		now[0] += 0.5
		mix.advance(now[0])
	ok(mix.lowpass_frequency.events.size() <= 30, "%d events" % mix.lowpass_frequency.events.size())
	ok(mix.impact_gain.events.size() <= 30, "%d events" % mix.impact_gain.events.size())


func test_the_buses_are_laid_out_music_and_effects_into_the_master_with_a_limiter():
	_mixer()
	var idx := func(n): return AudioServer.get_bus_index(n)
	eq(AudioServer.get_bus_send(idx.call(Mix.BUS_MUSIC_IN)), Mix.BUS_MUSIC)
	eq(AudioServer.get_bus_send(idx.call(Mix.BUS_MUSIC)), "Master")
	eq(AudioServer.get_bus_send(idx.call(Mix.BUS_SFX)), "Master")
	eq(AudioServer.get_bus_send(idx.call(Mix.BUS_ROOM)), Mix.BUS_SFX)
	ok(AudioServer.get_bus_effect(0, 0) is AudioEffectCompressor, "the limiter")
	var limiter := AudioServer.get_bus_effect(0, 0) as AudioEffectCompressor
	eq(limiter.threshold, -6.0)
	eq(limiter.ratio, 12.0)
	near(limiter.gain, Mix.LIMITER_MAKEUP_DB)
	ok(AudioServer.get_bus_effect(0, 1) is AudioEffectHardLimiter, "and a ceiling so the make-up gain cannot clip")
	ok(AudioServer.get_bus_effect(idx.call(Mix.BUS_MUSIC), 0) is AudioEffectLowPassFilter)
	ok(AudioServer.get_bus_effect(idx.call(Mix.BUS_ROOM), 0) is AudioEffectReverb)
	# building them again changes nothing
	var count := AudioServer.bus_count
	var effects := AudioServer.get_bus_effect_count(0)
	Mix.build_buses()
	eq(AudioServer.bus_count, count)
	eq(AudioServer.get_bus_effect_count(0), effects)
	# the music is routed bottom-up: a bus only sends to one above it
	for n in [Mix.BUS_MUSIC_IN, Mix.BUS_MUSIC, Mix.BUS_SFX, Mix.BUS_ROOM]:
		ok(AudioServer.get_bus_index(AudioServer.get_bus_send(idx.call(n))) < idx.call(n), "%s sends upward" % n)


func test_the_room_returns_about_as_much_as_the_js_convolver_did():
	# a send of white noise into SFXRoom, its return measured on a capture at the end of the room bus
	var idx := AudioServer.get_bus_index(Mix.BUS_ROOM)
	if idx < 0:
		_mixer()
		idx = AudioServer.get_bus_index(Mix.BUS_ROOM)
	var reverb := AudioServer.get_bus_effect(idx, 0) as AudioEffectReverb
	eq(reverb.dry, 0.0)
	eq(reverb.wet, 1.0)
	near(AudioServer.get_bus_volume_db(idx), Mix.ROOM_RETURN_DB - Mix.REVERB_NATIVE_DB, 1e-6)


func test_the_heart_beats_every_other_beat_when_hurt_every_beat_when_someone_is_about_to_die():
	eq(Mix.heart_every(0.0), null)
	eq(Mix.heart_every(Mix.DANGER.heartFrom - 0.01), null)
	eq(Mix.heart_every(Mix.DANGER.heartFrom), 2)
	eq(Mix.heart_every(Mix.DANGER.heartFast), 1)
	eq(Mix.heart_every(1.0), 1)


func test_the_scheduler_lands_every_beat_exactly_on_the_musics_grid_once_a_little_ahead():
	var beats := []
	var grid := {"bpm": 120.0, "origin": 4.9}  # a beat every 0.5 s, one on 4.9
	var s := Mix.BeatScheduler.new({"now": _clock, "clock": func(): return grid, "onBeat": func(at, k): beats.append([at, k]), "lookahead": 0.2})
	var t := 5.0
	while t < 7.0:
		now[0] = t
		s.tick()
		t += 0.05
	var times := beats.map(func(b): return b[0])
	eq(times.size(), 4)
	for i in mini(4, times.size()):
		near(times[i], [5.4, 5.9, 6.4, 6.9][i], 1e-9)
	eq(beats.map(func(b): return b[1]), [1, 2, 3, 4], "beat numbers count from the grid's origin")
	var unique := {}
	for x in times:
		unique[snappedf(x, 1e-6)] = true
	eq(unique.size(), times.size(), "never twice")


func test_the_scheduler_follows_a_new_grid_a_fights_loop_starts_and_rests_at_its_own_pace_without_one():
	var beats := []
	var grid := [null]
	var s := Mix.BeatScheduler.new({"now": _clock, "clock": func(): return grid[0], "onBeat": func(at, _k): beats.append(snappedf(at, 1e-4)), "lookahead": 0.1})
	var t := 5.0
	while t < 7.0:
		now[0] = t
		s.tick()
		t += 0.02
	var gaps := []
	for i in range(1, beats.size()):
		gaps.append(snappedf(beats[i] - beats[i - 1], 1e-4))
	ok(gaps.size() > 0 and gaps.all(func(g): return absf(g - 60.0 / Mix.RESTING_BPM) < 1e-3), "resting pace: %s" % [gaps])
	beats.clear()
	grid[0] = {"bpm": 132.0, "origin": 7.013}
	t = 7.0
	while t < 9.0:
		now[0] = t
		s.tick()
		t += 0.02
	ok(beats.size() > 0)
	for b in beats:
		var k: float = (b - 7.013) / (60.0 / 132.0)
		ok(absf(k - round(k)) < 1e-3, "%s is on the 132 BPM grid" % b)


func test_the_music_reports_its_beat_grid_the_loops_start_less_the_bit_of_the_file_it_skips():
	now[0] = 5.0
	var music := Ambient.Ambient.new({"clock": _clock, "random": func(): return 0.0})
	(Engine.get_main_loop() as SceneTree).root.add_child(music)
	nodes.append(music)
	music.attach()
	var stub := AudioStreamWAV.new()
	stub.format = AudioStreamWAV.FORMAT_16_BITS
	stub.mix_rate = 1000
	stub.data = PackedByteArray([0, 0, 0, 0])
	music.buffers = {"explore": stub}
	for v in Ambient.TRACKS.battle.variants:
		music.buffers["battle:" + v.name] = stub
	eq(music.beat_clock(), null, "nothing playing")
	music.on = true
	music.explore_in(1.0)
	var ex = music.beat_clock()
	eq(ex.bpm, 64.0)
	near(ex.origin, 5.0 - Ambient.LOOP_START, 1e-9)
	now[0] = 9.0
	music.set_mood("battle")
	var b = music.beat_clock()
	ok(Ambient.TRACKS.battle.variants.any(func(v): return v.bpm == b.bpm and absf(v.loopSeconds - 3840.0 / v.bpm) < 1e-9))
	near(b.origin, 9.0 - Ambient.LOOP_START, 1e-9)


func test_music_off_mutes_the_music_instead_of_stopping_the_effects_too():
	var music := Ambient.Ambient.new({"clock": _clock})
	(Engine.get_main_loop() as SceneTree).root.add_child(music)
	nodes.append(music)
	music.attach()
	music.stop()
	eq(music.mute.events.back()[1], 0.0)
	eq(music.on, false)


func test_the_clock_advances_with_real_time():
	var a := Mix.clock()
	OS.delay_msec(20)
	var b := Mix.clock()
	ok(b - a >= 0.015 and b - a < 0.5, "%s" % (b - a))


func test_audio_at_converts_a_frame_time_to_the_audio_clock():
	var mix := Mix.Mixer.new()
	var ahead: float = mix.audio_at(Time.get_ticks_usec() / 1000.0 + 250.0)
	near(ahead - Mix.clock(), 0.25, 0.02)
	mix.free()
