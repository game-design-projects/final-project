## The whole path in the real audio server (the dummy driver of a headless run mixes in real time): effects and music
## through their buses and the limiter, measured at the end of the Master bus
extends "res://tests/test_case.gd"

const Sfx = preload("res://src/audio/sfx.gd")
const Ambient = preload("res://src/audio/ambient.gd")
const Mix = preload("res://src/audio/mix.gd")

var nodes: Array = []


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	# take the capture off the Master bus again
	for i in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
		if AudioServer.get_bus_effect(0, i) is AudioEffectCapture:
			AudioServer.remove_bus_effect(0, i)


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _wait(seconds: float) -> void:
	await _root().get_tree().create_timer(seconds).timeout


## What came out of the Master bus (left channel) since the last read
func _drain(cap: AudioEffectCapture) -> PackedFloat32Array:
	var frames := cap.get_buffer(cap.get_frames_available())
	var out := PackedFloat32Array()
	out.resize(frames.size())
	for i in frames.size():
		out[i] = frames[i].x
	return out


func _db(x: float) -> float:
	return linear_to_db(maxf(x, 1e-9))


func _rms(buf: PackedFloat32Array, from := 0, to := -1) -> float:
	var end := buf.size() if to < 0 else mini(to, buf.size())
	var sum := 0.0
	for i in range(from, end):
		sum += buf[i] * buf[i]
	return sqrt(sum / maxf(end - from, 1.0))


func _peak(buf: PackedFloat32Array, from := 0, to := -1) -> float:
	var end := buf.size() if to < 0 else mini(to, buf.size())
	var peak := 0.0
	for i in range(from, end):
		peak = maxf(peak, absf(buf[i]))
	return peak


func _capture() -> AudioEffectCapture:
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 4.0
	AudioServer.add_bus_effect(0, cap)
	return cap


func test_a_sound_effect_reaches_the_master_bus_at_the_level_the_js_gave_it():
	var cap := _capture()
	var sfx := Sfx.Sfx.new(0.55)
	_root().add_child(sfx)
	nodes.append(sfx)
	sfx.init()
	sfx.blocking = true
	await _wait(0.3)
	_drain(cap)  # silence so far
	sfx.play("hit")
	await _wait(0.6)
	var heard := _drain(cap)
	if heard.size() < 10000:
		push_warning("test_playback: the audio server mixed only %d frames, level not measured" % heard.size())
		return
	var peak := _db(_peak(heard))
	# the recipe peaks at about -8.8 dBFS after the fader; the limiter's make-up gain adds 2.56 dB, the pitch variation
	# and the room a little
	ok(peak > -12.0 and peak < -3.0, "a hit peaks at %.1f dBFS on the master bus" % peak)
	# and it dies away: the last 200 ms are silent
	ok(_peak(heard, heard.size() - 4000) < 0.05, "the hit tail is %.1f dBFS" % _db(_peak(heard, heard.size() - 4000)))


func test_the_music_plays_through_its_buses_and_loops_at_the_mastered_level():
	var cap := _capture()
	var music := Ambient.Ambient.new()
	_root().add_child(music)
	nodes.append(music)
	music.attach()
	await music.start()
	await _wait(3.6)  # 1.5 s fade in, then the loop at its level
	var heard := _drain(cap)
	if heard.size() < 44100 * 2:
		push_warning("test_playback: the audio server mixed only %d frames, level not measured" % heard.size())
		return
	# The ambient opens quietly (variation I: organ, low strings, harpsichord): its 2nd to 4th second measure -22.5 dBFS RMS
	# in the file. Then the volume 0.7 (-3.1 dB) and the limiter's make-up gain (+2.56 dB).
	var rms := _db(_rms(heard, heard.size() - 44100))
	var expect: float = -22.5 + linear_to_db(Ambient.TRACKS.explore.volume) + Mix.LIMITER_MAKEUP_DB
	near(rms, expect, 3.0, "the ambient is %.1f dBFS RMS on the master bus, expected about %.1f" % [rms, expect])
	ok(_peak(heard) < 1.0, "never clips")
	# P switches it off: muted within a moment
	music.stop()
	await _wait(0.6)
	_drain(cap)
	await _wait(0.3)
	var silent := _drain(cap)
	ok(_peak(silent) < 0.002, "music off is silent: %.1f dBFS" % _db(_peak(silent)))


func test_the_danger_filter_muffles_the_music_on_the_master_bus():
	var cap := _capture()
	var music := Ambient.Ambient.new()
	_root().add_child(music)
	nodes.append(music)
	var mixer := Mix.Mixer.new()
	_root().add_child(mixer)
	nodes.append(mixer)
	music.attach()
	await music.start()
	await _wait(3.0)
	_drain(cap)
	await _wait(0.5)
	var open := _drain(cap)
	mixer.set_danger(1.0)
	await _wait(2.5)
	_drain(cap)
	await _wait(0.5)
	var closed := _drain(cap)
	if open.size() < 10000 or closed.size() < 10000:
		push_warning("test_playback: the audio server mixed too little, danger not measured")
		return
	# first difference as a measure of the high frequencies: far less above a 650 Hz low-pass
	var edge := func(buf: PackedFloat32Array) -> float:
		var s := 0.0
		for i in range(1, buf.size()):
			s += (buf[i] - buf[i - 1]) * (buf[i] - buf[i - 1])
		return sqrt(s / buf.size())
	ok(edge.call(closed) < 0.6 * edge.call(open), "high frequencies: open %.4f, closed %.4f" % [edge.call(open), edge.call(closed)])
	ok(_rms(closed) < _rms(open), "and the whole music is quieter under the heartbeat")
