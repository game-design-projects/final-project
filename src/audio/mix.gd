## The mixing desk, with the volumes the player chose (menu/settings.gd hands them in with `set_levels`):
##
##   music (music.gd) ─▶ MusicIn (ducking under a voice) ─▶ Music (volume, low-pass) ─┐
##   effects (sfx.gd) ─▶ SFX (volume) ──────────────────────────────────────────────┼─▶ Master (compressor, limiter)
##   the room         ─▶ SFXRoom (reverb) ─▶ SFX ───────────────────────────────────┘
##
## The Music bus has a low-pass filter that closes as the player gets hurt, so music sounds muffled, as if heard through
## your own pulse. The Master limiter keeps the music, the effects and the recorded voices from clipping when they land
## together.
extends RefCounted

const MUSIC := "Music"
const MUSIC_IN := "MusicIn"
const SFX := "SFX"
const ROOM := "SFXRoom"
const OPEN_HZ := 20000.0
const CLOSED_HZ := 650.0

## The compressor's make-up gain for its curve (threshold -6 dB, ratio 12), which the hard limiter below then holds under 0 dB.
const LIMITER_MAKEUP_DB := 2.56
## The room is a reverb that returns about -11 dB of what the effects send it, with about the tail of a stone hall: -22 dB
## half a second after a sound stops, -41 dB at 0.9 s. A reverb at wet = 1 returns REVERB_NATIVE_DB of its input.
const ROOM_RETURN_DB := -11.1
const REVERB_NATIVE_DB := 1.7
## How far the music drops under a monster's recorded voice, how quickly, and how slowly it comes back.
const DUCK_DB := -12.0
const DUCK_DOWN_S := 0.15
const DUCK_UP_S := 0.6


static var _sound_on := true
static var _level := 0.5 # 0..1, for the music and the effects


## Make the buses if they aren't there yet. Safe to call again.
static func build_buses() -> void:
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectCompressor.new()
		limiter.threshold = -6.0
		limiter.ratio = 12.0
		limiter.attack_us = 2000.0
		limiter.release_ms = 200.0
		limiter.gain = LIMITER_MAKEUP_DB
		AudioServer.add_bus_effect(0, limiter)
		var ceiling := AudioEffectHardLimiter.new() # the make-up gain must not clip
		ceiling.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, ceiling)
		print_verbose("mix: Master has a compressor and a limiter")
	if AudioServer.get_bus_index(MUSIC) < 0:
		var low := AudioEffectLowPassFilter.new()
		low.cutoff_hz = OPEN_HZ
		_add_bus(MUSIC, "Master", low)
	if AudioServer.get_bus_index(MUSIC_IN) < 0:
		_add_bus(MUSIC_IN, MUSIC)
	if AudioServer.get_bus_index(SFX) < 0:
		_add_bus(SFX, "Master")
	if AudioServer.get_bus_index(ROOM) < 0:
		var room := AudioEffectReverb.new()
		room.room_size = 0.5
		room.damping = 0.5
		room.spread = 1.0
		room.hipass = 0.0
		room.predelay_msec = 20.0
		room.predelay_feedback = 0.0
		room.dry = 0.0
		room.wet = 1.0
		_add_bus(ROOM, SFX, room)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(ROOM), ROOM_RETURN_DB - REVERB_NATIVE_DB)
	set_levels(_sound_on, _level)


## The player's sound settings: sound on or off, and how loud (0..1).
static func set_levels(sound_on: bool, level: float) -> void:
	_sound_on = sound_on
	_level = level
	for bus in [MUSIC, SFX]:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue # the buses are made when the sound starts, and take these levels then
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(level, 0.0001)))
		AudioServer.set_bus_mute(idx, not sound_on or level <= 0.0)


## 0 = healthy, 1 = about to fall: the music's low-pass follows, exponentially, as the ear hears pitch.
static func set_danger(danger: float) -> void:
	var idx := AudioServer.get_bus_index(MUSIC)
	if idx < 0:
		return
	var low := AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter
	low.cutoff_hz = OPEN_HZ * pow(CLOSED_HZ / OPEN_HZ, clampf(danger, 0.0, 1.0))


static func _add_bus(bus_name: String, send: String, effect: AudioEffect = null) -> void:
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	if effect != null:
		AudioServer.add_bus_effect(idx, effect)
	print_verbose("mix: bus %s -> %s" % [bus_name, send])
