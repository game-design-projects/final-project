## The offline DSP behind the sound effects: AudioParam automation, filters, oscillators, the voice primitives
extends "res://tests/test_case.gd"

const Synth = preload("res://src/audio/synth.gd")

const SR := 44100.0


func _sine(freq: float, seconds: float) -> PackedFloat32Array:
	var n := int(seconds * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = sin(TAU * freq * i / SR)
	return out


func _rms_tail(buf: PackedFloat32Array) -> float:
	# RMS of the second half, after the filter has settled
	var half := buf.size() / 2
	var sum := 0.0
	for i in range(half, buf.size()):
		sum += buf[i] * buf[i]
	return sqrt(sum / (buf.size() - half))


func test_note_is_equal_tempered_from_a440():
	near(Synth.note(69), 440.0)
	near(Synth.note(81), 880.0, 1e-9)
	near(Synth.note(60), 261.6255653, 1e-6)


# ---- AudioParam

func test_param_set_and_hold():
	var p := Synth.Param.new(3.0)
	eq(p.value_at(0.0), 3.0, "the intrinsic value before any event")
	p.set_value_at_time(5.0, 2.0)
	eq(p.value_at(1.9), 3.0)
	eq(p.value_at(2.0), 5.0)
	eq(p.value_at(99.0), 5.0)


func test_param_linear_and_exponential_ramps():
	var p := Synth.Param.new(0.0)
	p.set_value_at_time(0.0, 1.0)
	p.linear_ramp_to_value_at_time(1.0, 3.0)
	near(p.value_at(2.0), 0.5)
	near(p.value_at(3.0), 1.0)
	near(p.value_at(5.0), 1.0)
	var e := Synth.Param.new(0.0)
	e.set_value_at_time(0.0001, 0.0)
	e.exponential_ramp_to_value_at_time(1.0, 2.0)
	e.exponential_ramp_to_value_at_time(0.0001, 4.0)
	near(e.value_at(1.0), 0.01, 1e-9, "halfway up is the geometric mean")
	near(e.value_at(2.0), 1.0, 1e-9)
	near(e.value_at(3.0), 0.01, 1e-9)
	near(e.value_at(9.0), 0.0001, 1e-12)


func test_param_set_target_decays_towards_the_target():
	var p := Synth.Param.new(1.0)
	p.set_value_at_time(1.0, 0.0)
	p.set_target_at_time(0.0, 1.0, 0.5)
	near(p.value_at(1.0), 1.0)
	near(p.value_at(1.5), exp(-1.0), 1e-9)
	near(p.value_at(3.0), exp(-4.0), 1e-9)
	# a second target starts from where the first one is
	p.set_target_at_time(2.0, 1.5, 1.0)
	near(p.value_at(1.5), exp(-1.0), 1e-9)
	near(p.value_at(2.5), 2.0 + (exp(-1.0) - 2.0) * exp(-1.0), 1e-9)


func test_param_cancel_and_fade():
	var p := Synth.Param.new(1.0)
	p.fade_to(0.0, 10.0, 4.0)
	near(p.value_at(12.0), 0.5)
	# interrupt the fade half-way: it freezes there and ramps back
	p.fade_to(1.0, 12.0, 2.0)
	near(p.value_at(12.0), 0.5)
	near(p.value_at(13.0), 0.75)
	near(p.value_at(14.0), 1.0)
	near(p.value_at(20.0), 1.0)


func test_param_rebase_keeps_the_value_and_a_running_target():
	var p := Synth.Param.new(1.0)
	for i in 30:
		p.set_target_at_time(float(i % 2), float(i), 0.3)
	var before_a := p.value_at(29.5)
	var before_b := p.value_at(32.0)
	p.rebase(29.5)
	ok(p.events.size() <= 2)
	near(p.value_at(29.5), before_a, 1e-9)
	near(p.value_at(32.0), before_b, 1e-9)


func test_param_fill_matches_value_at():
	var p := Synth.Param.new(0.0)
	p.set_value_at_time(0.0001, 0.01)
	p.exponential_ramp_to_value_at_time(0.8, 0.02)
	p.linear_ramp_to_value_at_time(0.2, 0.04)
	p.set_target_at_time(0.0, 0.05, 0.01)
	p.exponential_ramp_to_value_at_time(0.1, 0.09)
	var n := 6000
	var out := PackedFloat32Array()
	out.resize(n)
	p.fill(out, 0.0, SR, n)
	var worst := 0.0
	for i in range(0, n, 37):
		worst = maxf(worst, absf(out[i] - p.value_at(i / SR)))
	ok(worst < 2e-3, "fill and value_at disagree by %s" % worst)


# ---- filters

func test_lowpass_passes_below_and_cuts_above_the_cutoff():
	var low := Synth.biquad(_sine(200.0, 0.5), "lowpass", 2000.0, 1.0)
	var high := Synth.biquad(_sine(10000.0, 0.5), "lowpass", 2000.0, 1.0)
	near(_rms_tail(low), sqrt(0.5), 0.05)
	ok(_rms_tail(high) < 0.03, "10 kHz through a 2 kHz low-pass: %s" % _rms_tail(high))


func test_highpass_passes_above_and_cuts_below():
	var low := Synth.biquad(_sine(100.0, 0.5), "highpass", 3000.0, 1.0)
	var high := Synth.biquad(_sine(9000.0, 0.5), "highpass", 3000.0, 1.0)
	ok(_rms_tail(low) < 0.01)
	near(_rms_tail(high), sqrt(0.5), 0.05)


func test_bandpass_peaks_at_its_centre_with_unit_gain():
	var centre := Synth.biquad(_sine(1000.0, 0.5), "bandpass", 1000.0, 8.0)
	var off := Synth.biquad(_sine(2000.0, 0.5), "bandpass", 1000.0, 8.0)
	near(_rms_tail(centre), sqrt(0.5), 0.02)
	ok(_rms_tail(off) < 0.15 * sqrt(0.5))


func test_peaking_boosts_by_its_gain_at_the_centre():
	var boosted := Synth.biquad(_sine(1000.0, 0.5), "peaking", 1000.0, 2.0, PackedFloat32Array(), 12.0)
	near(_rms_tail(boosted) / sqrt(0.5), pow(10.0, 12.0 / 20.0), 0.15)


func test_a_gliding_cutoff_follows_its_curve():
	# a low-pass sweeping from 20 kHz down to 200 Hz: a 3 kHz tone is let through at first and gone at the end
	var n := int(SR)
	var tone := _sine(3000.0, 1.0)
	var curve := PackedFloat32Array()
	curve.resize(n)
	for i in n:
		curve[i] = 20000.0 * pow(0.01, float(i) / n)
	Synth.biquad(tone, "lowpass", 0.0, 1.0, curve)
	var first := 0.0
	var last := 0.0
	for i in 2000:
		first += tone[i] * tone[i]
		last += tone[n - 1 - i] * tone[n - 1 - i]
	ok(sqrt(first / 2000.0) > 0.6)
	ok(sqrt(last / 2000.0) < 0.02)


# ---- oscillators

func _hz(buf: PackedFloat32Array) -> float:
	var crossings := 0
	for i in range(1, buf.size()):
		if buf[i - 1] < 0.0 and buf[i] >= 0.0:
			crossings += 1
	return crossings * SR / buf.size()


func _flat(freq: float, n: int) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(n)
	f.fill(freq)
	return f


func test_oscillators_run_at_their_frequency_and_stay_in_range():
	for type in ["sine", "triangle", "sawtooth", "square"]:
		var w := Synth.osc(type, _flat(441.0, 44100))
		near(_hz(w), 441.0, 3.0, type)
		var peak := Synth.peak_of(w)
		ok(peak > 0.8 and peak < 1.05, "%s peak %s" % [type, peak])
		# the levels WebAudio's built-in oscillators have (measured in Chrome at 441 Hz)
		near(Synth.rms_of(w), {"sine": 0.7071, "triangle": 0.5774, "sawtooth": 0.489, "square": 0.847}[type], 0.01, type)


## The amplitude of one frequency in buf (Goertzel)
func _amp_at(buf: PackedFloat32Array, freq: float) -> float:
	var w := TAU * freq / SR
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for i in buf.size():
		var s0 := buf[i] + c * s1 - s2
		s2 = s1
		s1 = s0
	var re := s1 - s2 * cos(w)
	var im := s2 * sin(w)
	return 2.0 * sqrt(re * re + im * im) / buf.size()


func test_sawtooth_and_square_are_band_limited_no_aliasing_above_nyquist_folds_back():
	# a 9 kHz square wave has odd harmonics at 27 kHz and 45 kHz. Rendered naively they fold back to 17.1 kHz and 0.9 kHz,
	# inharmonic tones as loud as 1/3 and 1/5 of the note itself; band-limited, they are not there
	var w := Synth.osc("square", _flat(9000.0, 44100))
	var fundamental := _amp_at(w, 9000.0)
	ok(fundamental > 0.9, "the note itself: %s" % fundamental)
	ok(_amp_at(w, 17100.0) < 0.1 * fundamental, "alias at 17.1 kHz: %s" % (_amp_at(w, 17100.0) / fundamental))
	ok(_amp_at(w, 900.0) < 0.1 * fundamental, "alias at 0.9 kHz: %s" % (_amp_at(w, 900.0) / fundamental))
	var saw := Synth.osc("sawtooth", _flat(7000.0, 44100))
	# 7 kHz saw: 2nd harmonic 14 kHz is fine, the 4th at 28 kHz would fold to 16.1 kHz
	ok(_amp_at(saw, 16100.0) < 0.15 * _amp_at(saw, 7000.0), "saw alias: %s" % (_amp_at(saw, 16100.0) / _amp_at(saw, 7000.0)))


func test_oscillators_follow_a_gliding_frequency():
	var f := PackedFloat32Array()
	f.resize(44100)
	for i in 44100:
		f[i] = 200.0 * pow(4.0, i / 44100.0)  # an octave-and-a-half... two octaves up over a second
	var w := Synth.osc("sine", f)
	var first := _hz(w.slice(0, 4410))
	var last := _hz(w.slice(39690, 44100))
	ok(first < 300.0 and last > 600.0, "%s -> %s" % [first, last])


# ---- the primitives

func test_tone_follows_its_envelope_and_sends_to_the_room():
	var r := Synth.Render.new()
	r.tone(0.0, {"f0": 440.0, "dur": 0.2, "vol": 0.3, "attack": 0.004, "room": 0.5})
	near(r.seconds(), 0.25, 0.001)
	var peak := Synth.peak_of(r.dry, r.used)
	ok(peak > 0.27 and peak <= 0.3001, "peak %s" % peak)
	near(Synth.peak_of(r.send, r.used), peak * 0.5, 0.005, "room send is room x the signal")
	# the exponential release: quiet by the end
	ok(absf(r.dry[r.used - 1]) < 0.001)


func test_tone_start_time_offsets_the_sound():
	var r := Synth.Render.new()
	r.tone(0.5, {"f0": 440.0, "dur": 0.1, "vol": 0.3})
	eq(Synth.peak_of(r.dry.slice(0, 22000)), 0.0, "silent before it starts")
	ok(Synth.peak_of(r.dry, r.used) > 0.2)
	near(r.seconds(), 0.65, 0.001)


func test_a_lowpass_on_a_tone_darkens_it():
	var bright := Synth.Render.new()
	bright.tone(0.0, {"type": "sawtooth", "f0": 300.0, "dur": 0.3, "vol": 0.3})
	var dark := Synth.Render.new()
	dark.tone(0.0, {"type": "sawtooth", "f0": 300.0, "dur": 0.3, "vol": 0.3, "lp": [500.0, 300.0]})
	# the 3rd harmonic (900 Hz) is well past the 500 Hz cutoff
	ok(_amp_at(dark.dry.slice(0, 8000), 900.0) < 0.6 * _amp_at(bright.dry.slice(0, 8000), 900.0))


func test_noise_is_filtered_and_enveloped():
	var r := Synth.Render.new()
	r.noise(0.0, {"dur": 0.1, "vol": 0.4, "type": "bandpass", "f0": 2000.0, "q": 2.0})
	var peak := Synth.peak_of(r.dry, r.used)
	ok(peak > 0.05 and peak < 0.5, "peak %s" % peak)
	near(r.seconds(), 0.15, 0.001)


func test_vocal_has_energy_around_its_formants():
	var r := Synth.Render.new()
	r.vocal(0.0, {"f0": 120.0, "dur": 0.3, "vol": 0.3, "vowel": ["ah"], "rasp": 0.1})
	ok(Synth.peak_of(r.dry, r.used) > 0.1)
	var gliding := Synth.Render.new()
	gliding.vocal(0.0, {"f0": 120.0, "f1": 90.0, "dur": 0.3, "vol": 0.3, "vowel": ["ee", "oo"], "vibrato": {"rate": 6.0, "depth": 4.0}, "tremolo": {"rate": 20.0, "depth": 0.5}})
	ok(Synth.peak_of(gliding.dry, gliding.used) > 0.05)
	# a bigger throat (size < 1) moves the formants down: the same vowel gets darker
	var small := Synth.Render.new()
	small.vocal(0.0, {"f0": 200.0, "dur": 0.3, "vol": 0.3, "vowel": ["ee"], "size": 1.3, "rasp": 0.0})
	var big := Synth.Render.new()
	big.vocal(0.0, {"f0": 200.0, "dur": 0.3, "vol": 0.3, "vowel": ["ee"], "size": 0.5, "rasp": 0.0})
	var bright := func(buf, n):
		# first difference: a rough measure of the high-frequency share
		var s := 0.0
		for i in range(1, n):
			s += absf(buf[i] - buf[i - 1])
		return s / maxf(Synth.rms_of(buf, n) * n, 1e-9)
	ok(bright.call(small.dry, small.used) > bright.call(big.dry, big.used))


func test_arp_plays_its_notes_one_step_apart():
	var r := Synth.Render.new()
	r.arp(0.0, [60, 72], {"step": 0.2, "dur": 0.1, "vol": 0.2})
	near(r.seconds(), 0.35, 0.001)
	ok(Synth.peak_of(r.dry.slice(int(0.15 * SR), int(0.19 * SR))) < 0.001, "a gap before the second note")


func test_the_rate_and_gain_multipliers_of_a_variation_apply_to_the_primitives():
	var r := Synth.Render.new()
	r.rate_mul = 2.0
	r.gain_mul = 0.5
	r.tone(0.0, {"f0": 220.0, "dur": 0.5, "vol": 0.4})
	near(_hz(r.dry.slice(0, 22050)), 440.0 * (22050.0 / 22050.0), 8.0)
	ok(Synth.peak_of(r.dry, r.used) <= 0.2001)


func test_finish_normalises_to_16_bits_with_the_gain_to_restore_the_level():
	var r := Synth.Render.new()
	r.tone(0.0, {"f0": 440.0, "dur": 0.2, "vol": 0.05, "room": 0.3})
	var out := r.finish()
	var wav: AudioStreamWAV = out.dry
	eq(wav.format, AudioStreamWAV.FORMAT_16_BITS)
	eq(wav.mix_rate, 44100)
	var peak := 0
	for i in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	near(peak / 32767.0, 0.9, 0.01, "the stored sound peaks at 0.9")
	near(out.dry_gain * 0.9, out.peak, 1e-9, "gain x stored peak = the real peak")
	ok(out.send != null and out.send_gain < out.dry_gain)
	var silent := Synth.Render.new()
	eq(silent.finish().dry, null)


func test_the_recorder_replays_what_a_recipe_asked_for_in_slices():
	var rec := Synth.Recorder.new()
	rec.tone(0.0, {"f0": 440.0, "dur": 0.1, "vol": 0.2})
	rec.arp(0.1, [60, 64, 67], {"step": 0.05, "dur": 0.1})
	rec.noise(0.0, {"dur": 0.05})
	eq(rec.calls.size(), 5)
	var r := Synth.Render.new()
	var slices := 0
	while not rec.run(r, 0):  # a deadline already past: one call per run
		slices += 1
	eq(slices, 4)
	ok(rec.done())
	ok(Synth.peak_of(r.dry, r.used) > 0.1)
