## The sound effects: every recipe renders a sound that is audible, in range and the right length; variation, the
## voice limit, delays, ducking and the buses (port of the sfx.js half of test/mix.test.js)
extends "res://tests/test_case.gd"

const Sfx = preload("res://src/audio/sfx.gd")
const Synth = preload("res://src/audio/synth.gd")
const Mix = preload("res://src/audio/mix.gd")
const Shout = preload("res://src/audio/shout.gd")

# How long each non-voice recipe should last, in seconds: [min, max]. The JS recipes' last note plus its release.
const LENGTHS := {
	"hit": [0.15, 0.3], "crit": [0.3, 0.5], "miss": [0.2, 0.35], "hurt": [0.2, 0.35], "kill": [0.5, 0.8], "down": [0.7, 1.0],
	"death": [2.0, 2.4], "save": [0.25, 0.4], "fire": [0.5, 0.7], "fireball": [1.4, 1.7], "missile": [0.3, 0.5],
	"holy": [0.9, 1.2], "sleep": [1.0, 1.3], "hold": [0.8, 1.0], "heal": [0.8, 1.0], "revive": [1.5, 1.9],
	"buff": [0.8, 1.0], "dice": [0.12, 0.3], "diceLand": [0.1, 0.2], "good": [0.5, 0.7], "bad": [0.6, 0.8],
	"fear": [0.7, 0.9], "sad": [0.8, 1.0], "odd": [0.4, 0.6], "join": [1.3, 1.6], "gold": [0.3, 0.5],
	"levelup": [1.1, 1.4], "achieve": [1.1, 1.4], "slash": [0.5, 0.7], "encounter": [0.5, 0.7], "boss": [2.1, 2.4],
	"flee": [0.4, 0.55], "bump": [0.1, 0.25], "heartbeat": [0.3, 0.5], "stairs": [0.5, 0.7], "tick": [0.05, 0.15],
	"land": [1.1, 1.4], "great": [2.8, 3.2],
}


## The loudest int16 in a rendered stream, as a share of full scale
func _stored_peak(wav: AudioStreamWAV) -> float:
	var peak := 0
	for i in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	return peak / 32767.0


func test_every_recipe_has_a_name_and_the_list_is_complete():
	var names := Sfx.names()
	eq(names.size(), 51)
	for n in LENGTHS:
		ok(names.has(n), "%s has no recipe" % n)
	for k in Shout.KINDS:
		ok(names.has("voice_" + k), "voice_%s has no recipe" % k)
	for n in Sfx.PREWARM:
		ok(names.has(n), "%s is pre-rendered but has no recipe" % n)
	for n in Sfx.VARY:
		ok(names.has(n), "%s varies but has no recipe" % n)
	for n in Sfx.POLY:
		ok(n == "default" or names.has(n), "%s is limited but has no recipe" % n)


func test_every_sound_renders_audible_unclipped_and_a_plausible_length():
	for name in Sfx.names():
		var wets: Array = [false, true] if name.begins_with("voice_") else [false]
		for wet in wets:
			var o := {}
			if name.begins_with("voice_"):
				o = {"f0": 120.0, "size": 1.0, "rasp": 0.3, "wet": wet, "vol": 1.0, "syll": 3}
			var r := Sfx.render(name, o)
			var label := "%s%s" % [name, " (wet)" if wet else ""]
			ok(r.dry != null, "%s is silent" % label)
			if r.dry == null:
				continue
			ok(r.peak > 0.02, "%s is almost silent: peak %s" % [label, r.peak])
			# after the effects fader (0.55) and the bus make-up the loudest voice stays under full scale
			ok(r.peak * 0.55 * db_to_linear(Mix.SFX_MAKEUP_DB) < 1.0, "%s would clip: peak %s" % [label, r.peak])
			ok(_stored_peak(r.dry) < 0.95, "%s clips in its 16-bit render" % label)
			ok(r.seconds > 0.04 and r.seconds < 3.5, "%s lasts %s s" % [label, r.seconds])
			if LENGTHS.has(name):
				ok(r.seconds >= LENGTHS[name][0] and r.seconds <= LENGTHS[name][1], "%s lasts %s s, expected %s" % [label, r.seconds, LENGTHS[name]])
			ok(r.send == null or r.send_peak <= r.peak + 1e-6, "%s sends more to the room than it plays" % label)
			ok(r.send_peak > 0.0, "%s has no room send" % label)


# Total energy (sum of squares / 44100, in dB) of the tonal recipes as the original sfx.js rendered them in Chrome's
# OfflineAudioContext, through the effects fader (0.55) and its compressor, without the room. Measured with
# the original code, once the compressor had settled; they are what the Godot sounds must stay faithful to.
const CHROME_ENERGY_DB := {
	"save": -45.3, "holy": -33.2, "sleep": -33.7, "heal": -32.1, "buff": -37.6, "fear": -42.3, "sad": -40.3, "good": -38.5,
	"gold": -44.6, "join": -34.8, "great": -23.5, "death": -24.8, "revive": -27.7, "hold": -38.6, "missile": -43.6,
	"tick": -58.1, "odd": -40.3, "levelup": -37.6, "achieve": -38.3, "land": -29.0, "boss": -22.4,
}


func test_the_tonal_sounds_are_as_loud_as_the_webaudio_originals():
	var level := 0.55 * db_to_linear(Mix.SFX_MAKEUP_DB)
	for name in CHROME_ENERGY_DB:
		var s := Synth.Render.new()
		Sfx.run_recipe(name, s, 0.0)
		var energy := 0.0
		for i in s.used:
			var x: float = s.dry[i] * level
			energy += x * x
		var db := 10.0 * log(energy / 44100.0) / log(10.0)
		near(db, CHROME_ENERGY_DB[name], 0.5, "%s: %.1f dB, Chrome rendered %.1f dB" % [name, db, CHROME_ENERGY_DB[name]])


func test_nothing_in_a_sound_is_nan_or_infinite():
	for name in ["hit", "fireball", "voice_roar", "voice_hiss", "great", "boss"]:
		var s := Synth.Render.new()
		Sfx.run_recipe(name, s, 0.0, {"f0": 60.0, "size": 0.5, "rasp": 0.9, "wet": false, "vol": 1.0, "syll": 6})
		for i in s.used:
			if not is_finite(s.dry[i]):
				fail("%s has a non-finite sample at %d" % [name, i])
				break


func test_heartbeat_is_a_quiet_double_thump_that_scales_with_danger():
	var rec := Synth.Recorder.new()
	Sfx.run_recipe("heartbeat", rec, 0.0, {"level": 0.5})
	var tones := rec.calls.filter(func(c): return c[0] == "tone")
	eq(tones.size(), 4, "lub, dub, each with its octave for small speakers")
	var full := Synth.Recorder.new()
	Sfx.run_recipe("heartbeat", full, 0.0, {"level": 1.0})
	ok(full.calls[0][2].vol > rec.calls[0][2].vol)
	near(full.calls[0][2].vol, 2.0 * rec.calls[0][2].vol, 1e-9)
	# it sits under the hits: quieter than a critical hit even at full danger
	ok(Sfx.render("heartbeat").peak < Sfx.render("crit").peak)
	ok(Sfx.render("heartbeat").peak < Sfx.render("hit").peak)


func test_a_dice_roll_differs_every_time_but_a_landing_does_not_depend_on_chance():
	seed(1)
	var a := Sfx.render("dice")
	var b := Sfx.render("dice")
	ne(a.peak, b.peak)
	var crit := Sfx.render("diceLand", {"tier": "crit"})
	var fumble := Sfx.render("diceLand", {"tier": "fumble"})
	var plain := Sfx.render("diceLand")
	ok(crit.seconds > plain.seconds and fumble.seconds > plain.seconds, "crit rings and fumble sinks past the slam")
	eq(Sfx.cache_key("diceLand", {"tier": "crit"}), "diceLand:crit")
	eq(Sfx.cache_key("diceLand", {}), "diceLand:")


func test_a_monster_voice_depends_on_its_plan_but_not_on_its_volume():
	var a := Sfx.cache_key("voice_roar", {"f0": 150.0, "size": 0.95, "rasp": 0.55, "wet": false, "vol": 1.0, "syll": 3})
	var loud := Sfx.cache_key("voice_roar", {"f0": 150.0, "size": 0.95, "rasp": 0.55, "wet": false, "vol": 0.7, "syll": 5})
	eq(a, loud, "volume is applied at play time, and syllables only matter to the voices that count them")
	ne(a, Sfx.cache_key("voice_roar", {"f0": 62.0, "size": 0.55, "rasp": 0.35, "wet": false, "vol": 1.0, "syll": 3}))
	ne(Sfx.cache_key("voice_bark", {"syll": 2}), Sfx.cache_key("voice_bark", {"syll": 6}))
	# the deeper the throat, the longer a roar
	var dragon := Sfx.render("voice_roar", {"f0": 62.0, "size": 0.55, "rasp": 0.35, "wet": false, "syll": 3})
	var goblin := Sfx.render("voice_roar", {"f0": 150.0, "size": 0.95, "rasp": 0.55, "wet": false, "syll": 3})
	ok(dragon.seconds > goblin.seconds)


# ---- variation, voice limit, delay: the bookkeeping of play(), with the clock in the test's hands

func _sfx(random: Callable, now: Array) -> Sfx.Sfx:
	var s := Sfx.Sfx.new(0.5, {"random": random, "clock": func(): return now[0]})
	s.running = true  # as if init() had run, without making players
	s.log_plays = true
	return s


func test_repeated_hits_never_sound_the_same_twice_random_detune_and_volume_within_bounds():
	var now := [1.0]
	var i := [0]
	var seq := [0.0, 1.0, 0.25, 0.75, 0.5, 0.1]
	var sfx := _sfx(func():
		i[0] += 1
		return seq[(i[0] - 1) % seq.size()], now)
	for n in 3:
		now[0] = 1.0 + n  # far apart: no voice limit
		sfx.play("hit")
	var rates: Array = sfx.plays.map(func(p): return p.rate)
	eq(rates.map(func(r): return "%.4f" % r).size(), 3)
	ok(rates[0] != rates[1] and rates[1] != rates[2] and rates[0] != rates[2], "three different pitches: %s" % [rates])
	for r in rates:
		ok(absf(1200.0 * log(r) / log(2.0)) <= Sfx.VARY.hit.cents + 1e-9)
	# each play asks for two numbers, the pitch's and then the volume's: 0 and 1, 0.25 and 0.75, 0.5 and 0.1
	near(1200.0 * log(rates[0]) / log(2.0), -Sfx.VARY.hit.cents, 1e-6, "random() = 0 detunes all the way down")
	near(1200.0 * log(rates[1]) / log(2.0), -Sfx.VARY.hit.cents / 2.0, 1e-6, "0.25 is half way down")
	near(1200.0 * log(rates[2]) / log(2.0), 0.0, 1e-6, "0.5 keeps the pitch")
	var gains: Array = sfx.plays.map(func(p): return p.gain)
	for g in gains:
		ok(g >= 1.0 - Sfx.VARY.hit.gain - 1e-9 and g <= 1.0 + Sfx.VARY.hit.gain + 1e-9)
	sfx.free()


func test_sounds_not_on_the_list_keep_their_exact_pitch():
	var sfx := _sfx(func(): return 0.9, [1.0])
	sfx.play("save")  # a fixed musical note
	eq(sfx.last_play.rate, 1.0)
	eq(sfx.last_play.gain, 1.0)
	sfx.free()


func test_voice_limit_six_hits_at_once_play_three_each_a_little_quieter_later_ones_play_again():
	var now := [1.0]
	var sfx := _sfx(func(): return 0.5, now)
	for n in 6:
		sfx.play("hit")
	eq(sfx.stats.played, Sfx.POLY.hit)
	eq(sfx.stats.dropped, 6 - Sfx.POLY.hit)
	var gains: Array = sfx.plays.map(func(p): return p.gain)
	eq(gains.size(), 3)
	ok(gains[1] < gains[0] and gains[2] < gains[1], "stacked copies are quieter: %s" % [gains])
	now[0] += Sfx.POLY_WINDOW * 2
	sfx.play("hit")
	eq(sfx.stats.played, Sfx.POLY.hit + 1)
	sfx.free()


func test_the_limit_is_per_sound_and_the_default_is_four():
	var sfx := _sfx(func(): return 0.5, [1.0])
	for n in 6:
		sfx.play("gold")
	eq(sfx.stats.played, Sfx.POLY["default"])
	for n in 3:
		sfx.play("tick")
	eq(sfx.stats.played, Sfx.POLY["default"] + 1, "tick allows one at a time")
	sfx.free()


func test_a_delay_or_lag_moves_the_start_and_unknown_sounds_and_sound_off_play_nothing():
	var now := [5.0]
	var sfx := _sfx(func(): return 0.5, now)
	sfx.play("hit", {"delay": 0.25})
	near(sfx.last_play.at, 5.0 + 0.01 + 0.25, 1e-9)
	sfx.lag = 0.1
	sfx.play("miss")
	near(sfx.last_play.at, 5.0 + 0.01 + 0.1, 1e-9, "sounds played right now wait for the die")
	sfx.play("miss", {"delay": 0})
	near(sfx.last_play.at, 5.0 + 0.01, 1e-9, "an explicit delay wins over the lag")
	eq(sfx.play("no such sound"), false)
	sfx.toggle()
	eq(sfx.play("hit"), false)
	eq(sfx.on, false)
	eq(sfx.toggle(), true)
	var cold := Sfx.Sfx.new()
	eq(cold.play("hit"), false, "before init() nothing plays")
	cold.free()
	sfx.free()


func test_a_voices_volume_and_a_heartbeats_level_scale_the_play():
	var sfx := _sfx(func(): return 0.5, [1.0])
	sfx.play("heartbeat", {"level": 0.5})
	near(sfx.last_play.gain, 0.5)
	sfx.play("voice_roar", {"vol": 0.7, "f0": 100.0, "size": 1.0, "rasp": 0.2, "wet": false, "syll": 3})
	near(sfx.last_play.gain, 0.7)
	sfx.free()


# ---- the real thing: init() builds the buses and the player, and sounds render over the next frames

func _tree_root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_init_builds_the_buses_and_a_player_and_plays_without_errors():
	var sfx := Sfx.Sfx.new(0.55)
	_tree_root().add_child(sfx)
	sfx.init()
	ok(sfx.running)
	for b in [Mix.BUS_SFX, Mix.BUS_ROOM, Mix.BUS_MUSIC, Mix.BUS_MUSIC_IN]:
		ok(AudioServer.get_bus_index(b) >= 0, "bus %s" % b)
	sfx.play("hit")
	sfx.play("miss", {"delay": 0.05})
	sfx.play("voice_roar", {"f0": 150.0, "size": 0.95, "rasp": 0.55, "wet": false, "vol": 1.0, "syll": 3})
	# nothing is rendered yet: the sounds wait for their render and play when it is done
	ok(sfx.rendering() > 3)
	var guard := 0
	while not sfx._jobs.is_empty() and guard < 400:
		sfx.tick()
		guard += 1
	ok(sfx._jobs.is_empty(), "the queued sounds rendered")
	ok(sfx.cache.has("hit") and sfx.cache.has("miss"))
	ok(sfx.cache["hit"].seconds > 0.1)
	# the pre-rendering carries on behind them, a few milliseconds a frame
	var before := sfx.cache.size()
	sfx.tick()
	ok(sfx.cache.size() >= before)
	sfx.queue_free()


func test_blocking_mode_renders_on_the_spot_and_ducking_moves_the_effects_fader():
	var now := [100.0]
	var sfx := Sfx.Sfx.new(0.8, {"clock": func(): return now[0]})
	_tree_root().add_child(sfx)
	sfx.init()
	sfx.blocking = true
	sfx.play("bump")
	ok(sfx.cache.has("bump"), "rendered on the spot")
	var idx := AudioServer.get_bus_index(Mix.BUS_SFX)
	sfx.tick()
	near(AudioServer.get_bus_volume_db(idx), linear_to_db(0.8) + Mix.SFX_MAKEUP_DB, 0.01)
	sfx.duck(true)
	now[0] += 0.15
	sfx.tick()
	near(AudioServer.get_bus_volume_db(idx), linear_to_db(0.4) + Mix.SFX_MAKEUP_DB, 0.01, "effects drop to half")
	sfx.duck(false)
	now[0] += 0.6
	sfx.tick()
	near(AudioServer.get_bus_volume_db(idx), linear_to_db(0.8) + Mix.SFX_MAKEUP_DB, 0.01, "and come back")
	sfx.queue_free()
