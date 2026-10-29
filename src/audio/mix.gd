## The mixing desk: Godot audio buses for the music and the effects, so a heartbeat lands on the music's beat
## (BeatScheduler) and big hits punch through the music (Mixer.impact).
##
##   music (ambient.gd) ─▶ MusicIn (ducking, P switch) ─▶ Music (impact dip, danger dip, danger low-pass) ─┐
##   effects (sfx.gd)   ─▶ SFX (volume, ducking) ───────────────────────────────────────────────────────┼─▶ Master (limiter)
##   the room           ─▶ SFXRoom (reverb) ─▶ SFX ──────────────────────────────────────────────────────┘
##   heartbeat (an effect, scheduled here on the music's beat)
##
## Danger (juice.gd danger_of) closes the music's low-pass and starts a heartbeat on the music's beat grid:
## on every other beat while the party is hurt, on every beat when someone is about to die.
## Load it with `const Mix = preload("res://src/audio/mix.gd")` and use `Mix.Mixer`, `Mix.BeatScheduler`.
extends RefCounted

const Self = preload("res://src/audio/mix.gd")  # the classes below reach this file's static funcs through it
const Synth = preload("res://src/audio/synth.gd")
const J = preload("res://src/core/js.gd")

const DANGER := {
	"openHz": 20000.0,  # the music's low-pass with the party healthy: wide open
	"closedHz": 650.0,  # ...and with the party about to fall: muffled, as if heard through your own pulse
	"musicDip": 0.3,  # the music also drops by this share at full danger, so the heartbeat sits on top
	"heartFrom": 0.35,  # the heartbeat starts at this danger...
	"heartFast": 0.75,  # ...and doubles its pace from here
	"lag": 0.25,  # seconds for the filter to follow (setTargetAtTime time constant)
}
# A big hit dips the music this far for a moment, then lets it back
const IMPACT := {"crit": 0.45, "kill": 0.4, "bossKill": 0.6, "hurt": 0.3, "attack": 0.012, "release": 0.35}
const RESTING_BPM := 64  # the heartbeat's pace when no loop is playing (the explore loop's tempo)

# Bus names. Music and effects each have one place to plug in: players of ambient.gd use MUSIC_IN, sfx.gd uses SFX and ROOM
const BUS_MUSIC := "Music"
const BUS_MUSIC_IN := "MusicIn"
const BUS_SFX := "SFX"
const BUS_ROOM := "SFXRoom"

# WebAudio's DynamicsCompressor adds make-up gain for the curve it was given. Worked out from Chrome's compressor
# (public/mix.js limiter: threshold -6 dB, knee 4, ratio 12 -> +2.56 dB; sfx.js compressor: threshold -14, ratio 4,
# default 30 dB knee -> +0.6 dB and almost no compression, so the effects bus only keeps the gain).
const LIMITER_MAKEUP_DB := 2.56
const SFX_MAKEUP_DB := 0.6
# The JS room: a convolver with a 1.1 s noise impulse (normalised by the browser) behind a 0.22 gain. A white-noise
# impulse like that returns about -11 dB of what goes in; the reverb below is set so the same send does too.
const ROOM_RETURN_DB := -11.1
# What the reverb effect returns for its input at wet = 1, measured on white noise (tests/audio/test_mix.gd checks it)
const REVERB_NATIVE_DB := 0.0


## The audio clock in seconds: a monotonic clock shared by the music, the effects and the beat scheduler
static func clock() -> float:
	return Time.get_ticks_usec() / 1000000.0


# Exponential, as the ear hears pitch: halfway in danger is halfway in octaves
static func cutoff_for(d: float) -> float:
	return DANGER.openHz * pow(DANGER.closedHz / DANGER.openHz, d)


## How often the heart beats against the music: null (it doesn't), 2 (every other beat) or 1 (every beat)
static func heart_every(danger: float):
	if danger >= DANGER.heartFast:
		return 1
	if danger >= DANGER.heartFrom:
		return 2
	return null


## Builds the buses (and puts the limiter on Master) if they are not there yet. Safe to call again.
static func build_buses() -> void:
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectCompressor.new()
		limiter.threshold = -6.0
		limiter.ratio = 12.0
		limiter.attack_us = 2000.0  # the JS 3 ms, at the effect's upper limit
		limiter.release_ms = 200.0
		limiter.gain = LIMITER_MAKEUP_DB
		AudioServer.add_bus_effect(0, limiter)
		var ceiling := AudioEffectHardLimiter.new()  # the make-up gain must not clip
		ceiling.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, ceiling)
	if AudioServer.get_bus_index(BUS_MUSIC) < 0:
		var low := AudioEffectLowPassFilter.new()
		low.cutoff_hz = DANGER.openHz
		low.resonance = 1.0
		_add_bus(BUS_MUSIC, "Master", low)
	if AudioServer.get_bus_index(BUS_MUSIC_IN) < 0:
		_add_bus(BUS_MUSIC_IN, BUS_MUSIC)
	if AudioServer.get_bus_index(BUS_SFX) < 0:
		_add_bus(BUS_SFX, "Master")
	if AudioServer.get_bus_index(BUS_ROOM) < 0:
		var room := AudioEffectReverb.new()
		room.room_size = 0.6
		room.damping = 0.5
		room.spread = 1.0
		room.hipass = 0.0
		room.predelay_msec = 20.0
		room.predelay_feedback = 0.0
		room.dry = 0.0
		room.wet = 1.0
		_add_bus(BUS_ROOM, BUS_SFX, room)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_ROOM), ROOM_RETURN_DB - REVERB_NATIVE_DB)


static func _add_bus(bus_name: String, send: String, effect: AudioEffect = null) -> void:
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	if effect != null:
		AudioServer.add_bus_effect(idx, effect)


## The Music bus: danger closes its low-pass and dips it, impacts dip it for an instant. Add it to the tree
## (it eases the buses every frame) and call set_danger / impact from the game.
class Mixer:
	extends Node
	var danger := 0.0
	var clock: Callable
	## the low-pass cutoff in Hz, the impact dip and the danger dip, as automation: tests read their `events`
	var lowpass_frequency := Synth.Param.new(Self.DANGER.openHz)
	var impact_gain := Synth.Param.new(1.0)
	var music_bus_gain := Synth.Param.new(1.0)
	var _cutoff_now := -1.0
	var _db_now := 1.0e9

	func _init(opts := {}) -> void:
		clock = opts.get("clock", Self.clock)
		Self.build_buses()
		var now: float = clock.call()
		lowpass_frequency.set_value_at_time(Self.DANGER.openHz, now)

	## 0..1. Cheap to call every frame: only a real change reschedules anything.
	func set_danger(x: float) -> void:
		var d := clampf(x, 0.0, 1.0)
		if absf(d - danger) < 0.01:
			return
		danger = d
		var now: float = clock.call()
		lowpass_frequency.set_target_at_time(Self.cutoff_for(d), now, Self.DANGER.lag)
		music_bus_gain.set_target_at_time(1.0 - Self.DANGER.musicDip * d, now, Self.DANGER.lag)

	## Dip the music under a big moment so it punches through. `depth` 0..1 is the share taken away; `at` is an
	## audio-clock time (default: now), so a hit that lands a moment from now dips the music then.
	func impact(depth: float, at = null) -> void:
		var when: float = clock.call() if at == null else at
		impact_gain.cancel_scheduled_values(when)
		impact_gain.set_target_at_time(1.0 - depth, when, Self.IMPACT.attack)
		impact_gain.set_target_at_time(1.0, when + 0.09, Self.IMPACT.release)

	## The audio-clock time of a moment given in J.now_ms() milliseconds (what `p.at` is in the fx events)
	func audio_at(perf_ms: float) -> float:
		return float(clock.call()) + (perf_ms - J.now_ms()) / 1000.0

	func _process(_delta: float) -> void:
		advance(clock.call())

	## Sets the buses to what the automation says at `now`
	func advance(now: float) -> void:
		for p in [lowpass_frequency, impact_gain, music_bus_gain]:
			if p.events.size() > 24:
				p.rebase(now)
		var cutoff := lowpass_frequency.value_at(now)
		var music := AudioServer.get_bus_index(Self.BUS_MUSIC)
		if music < 0:
			return
		if absf(cutoff - _cutoff_now) > 0.5:
			_cutoff_now = cutoff
			(AudioServer.get_bus_effect(music, 0) as AudioEffectFilter).cutoff_hz = cutoff
		var db := linear_to_db(maxf(impact_gain.value_at(now) * music_bus_gain.value_at(now), 1e-5))
		if absf(db - _db_now) > 0.01:
			_db_now = db
			AudioServer.set_bus_volume_db(music, db)


## Schedules beats a little ahead on the audio clock (the lookahead pattern: a coarse timer, exact times).
## opts: `now` () -> audio time, `clock` () -> {bpm, origin} (origin = an audio time on which a beat falls) or null to
## use the resting pace, `onBeat` (at, k), `lookahead` (0.2). Each beat k fires onBeat(at, k) exactly once.
## Call tick() every frame.
class BeatScheduler:
	extends RefCounted
	var now: Callable
	var clock: Callable
	var on_beat: Callable
	var lookahead := 0.2
	var next = null  # the audio time of the next beat to schedule
	var grid = null
	var rest_origin = null

	func _init(opts := {}) -> void:
		now = opts.get("now", Self.clock)
		clock = opts["clock"]
		on_beat = opts["onBeat"]
		lookahead = opts.get("lookahead", 0.2)

	func tick() -> void:
		var t: float = now.call()
		var g = clock.call()
		if g == null:
			if rest_origin == null:
				rest_origin = t
			g = {"bpm": Self.RESTING_BPM, "origin": rest_origin}
		var beat: float = 60.0 / g.bpm
		# A new grid (a fight's loop started, or ended): resume from its first beat after now
		if grid == null or grid.bpm != g.bpm or absf(grid.origin - g.origin) > 1e-6:
			grid = g
			next = g.origin + ceil((t - g.origin) / beat - 1e-9) * beat
		while next < t + lookahead:
			var k: int = J.round_js((next - g.origin) / beat)
			if next >= t - 0.005:
				on_beat.call(next, k)
			next += beat
