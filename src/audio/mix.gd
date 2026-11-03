## The mixing desk: two buses under Master, one for music and one for effects, with the volumes the player chose
## (menu/settings.gd hands them in with `set_levels`). The music bus has a low-pass filter that closes as the
## player gets hurt, so music sounds muffled, as if heard through your own pulse.
extends RefCounted

const MUSIC := "Music"
const SFX := "SFX"
const OPEN_HZ := 20000.0
const CLOSED_HZ := 650.0


static var _sound_on := true
static var _level := 0.5 # 0..1, for the music and the effects


## Make the buses if they aren't there yet. Safe to call again.
static func build_buses() -> void:
	if AudioServer.get_bus_index(MUSIC) < 0:
		var low := AudioEffectLowPassFilter.new()
		low.cutoff_hz = OPEN_HZ
		_add_bus(MUSIC, low)
	if AudioServer.get_bus_index(SFX) < 0:
		_add_bus(SFX, null)
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


static func _add_bus(bus_name: String, effect: AudioEffect) -> void:
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	if effect != null:
		AudioServer.add_bus_effect(idx, effect)
