## A small offline DSP library: the WebAudio nodes the sound effects were built from, rendered into sample
## arrays instead of live graphs. Oscillators (sine, square, sawtooth, triangle; the first two band-limited
## like WebAudio's), a noise source, BiquadFilterNode-compatible filters, AudioParam automation (`Param`),
## and `Render`, the equivalent of Sfx's tone/noise/vocal/arp primitives mixing into a dry and a room-send buffer.
## `src/audio/sounds.gd` holds the recipes, `src/audio/sfx.gd` plays what they render.
## Load it with `const Synth = preload("res://src/audio/synth.gd")`.
extends RefCounted

const Synth = preload("res://src/audio/synth.gd")  # inner classes reach this file's static funcs through it

const RATE := 44100

# Vowel formants (F1, F2, F3 in Hz) for a mid-sized throat; `size` scales them.
const VOWELS := {
	"ah": [730.0, 1090.0, 2440.0],
	"aw": [660.0, 1000.0, 2500.0],
	"oh": [570.0, 840.0, 2410.0],
	"uh": [520.0, 1190.0, 2390.0],
	"eh": [530.0, 1840.0, 2480.0],
	"ee": [270.0, 2290.0, 3010.0],
	"oo": [300.0, 870.0, 2240.0],
}
const FORMANT_GAIN := [1.0, 0.6, 0.3]
const VOICE_GAIN := 3.0  # narrow band-pass filters take most of the buzz out; this puts voices on par with the other effects
const NOISE_VOICE := 4.0  # ...and white noise loses even more through them

## A filter's coefficients are recomputed every this many samples while its frequency moves
const FILTER_BLOCK := 16

## 1 s of white noise (-1..1), the same every run, that the noise sources loop through from a random start
static var _noise := PackedFloat32Array()


## MIDI note number -> Hz
static func note(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


static func noise_table() -> PackedFloat32Array:
	if _noise.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x5EED
		_noise.resize(RATE)
		for i in RATE:
			_noise[i] = rng.randf() * 2.0 - 1.0
	return _noise


## WebAudio AudioParam: a value plus automation events. `events` holds ["set", v, t], ["ramp", v, t] (linear),
## ["exp", v, t] and ["target", v, t, timeConstant], kept in time order, as a test double records them.
## Used both to render envelopes and glides offline (`fill`) and to run fades while the game plays (`value_at`).
class Param:
	extends RefCounted
	const HOLD := 0
	const LIN := 1
	const EXP := 2
	const DECAY := 3

	var default_value := 0.0
	var events: Array = []
	var _segs: Array = []
	var _dirty := true

	func _init(v := 0.0) -> void:
		default_value = v

	func set_value_at_time(v: float, t: float) -> Param:
		return _add(["set", v, t])

	func linear_ramp_to_value_at_time(v: float, t: float) -> Param:
		return _add(["ramp", v, t])

	func exponential_ramp_to_value_at_time(v: float, t: float) -> Param:
		return _add(["exp", v, t])

	func set_target_at_time(target: float, start: float, time_constant: float) -> Param:
		return _add(["target", target, start, time_constant])

	## Drops every event at or after t (the value in force at t is kept by the caller: see `hold_at`)
	func cancel_scheduled_values(t: float) -> Param:
		events = events.filter(func(e): return e[2] < t)
		_dirty = true
		return self

	## `cancelScheduledValues(now); setValueAtTime(g.value, now)`: freeze the value at now, dropping what was ahead
	func hold_at(now: float) -> float:
		var v := value_at(now)
		cancel_scheduled_values(now)
		set_value_at_time(v, now)
		return v

	## Ramp from wherever the param is at `now` to v over `seconds` (the fade idiom of ambient.js and sfx.js)
	func fade_to(v: float, now: float, seconds: float) -> void:
		hold_at(now)
		linear_ramp_to_value_at_time(v, now + seconds)

	## Collapses the history to the value in force at `now` (and a setTarget curve still running), so a param
	## automated every frame does not grow without bound. A no-op while events are still scheduled ahead.
	func rebase(now: float) -> void:
		if events.is_empty() or events.back()[2] > now:
			return
		var last: Array = events.back()
		events = [["set", value_at(now), now]]
		if last[0] == "target":
			events.append(["target", last[1], now, last[3]])
		_dirty = true

	func _add(e: Array) -> Param:
		var i := events.size()
		while i > 0 and events[i - 1][2] > e[2]:
			i -= 1
		events.insert(i, e)
		_dirty = true
		return self

	## [t0, t1, kind, a, b, c] per piece: HOLD a | LIN a->b | EXP a->b | DECAY from a towards b with time constant c
	func _segments() -> Array:
		if not _dirty:
			return _segs
		_segs = []
		var cur_t := 0.0
		var cur_v := default_value
		var to := 0.0  # while decaying towards a setTarget value
		var tc := 0.0
		for e in events:
			var te: float = e[2]
			match e[0]:
				"set":
					_close(cur_t, te, cur_v, to, tc)
					cur_v = e[1]
					tc = 0.0
				"ramp", "exp":
					if te > cur_t:
						_segs.append([cur_t, te, LIN if e[0] == "ramp" else EXP, cur_v, e[1], 0.0])
					cur_v = e[1]
					tc = 0.0
				"target":
					_close(cur_t, te, cur_v, to, tc)
					if tc > 0.0:
						cur_v = to + (cur_v - to) * exp(-(te - cur_t) / tc)
					to = e[1]
					tc = maxf(e[3], 1e-9)
			cur_t = maxf(cur_t, te)
		_close(cur_t, INF, cur_v, to, tc)
		_dirty = false
		return _segs

	func _close(t0: float, t1: float, v: float, to: float, tc: float) -> void:
		if t1 <= t0:
			return
		if tc > 0.0:
			_segs.append([t0, t1, DECAY, v, to, tc])
		else:
			_segs.append([t0, t1, HOLD, v, v, 0.0])

	func value_at(t: float) -> float:
		for s in _segments():
			if t < s[1]:
				return _eval(s, t)
		return default_value

	static func _eval(s: Array, t: float) -> float:
		var x := maxf(t, s[0])
		match s[2]:
			LIN:
				return s[3] + (s[4] - s[3]) * (x - s[0]) / (s[1] - s[0])
			EXP:
				if s[3] > 0.0 and s[4] > 0.0:
					return s[3] * pow(s[4] / s[3], (x - s[0]) / (s[1] - s[0]))
				return s[3]
			DECAY:
				return s[4] + (s[3] - s[4]) * exp(-(x - s[0]) / s[5])
		return s[3]

	## Sample the param at t_origin + i / rate for i in [0, n) into out[0 .. n)
	func fill(out: PackedFloat32Array, t_origin: float, rate: float, n: int) -> void:
		for s in _segments():
			var i0 := 0 if s[0] <= t_origin else int(ceil((s[0] - t_origin) * rate - 1e-9))
			var i1 := n if s[1] == INF else mini(n, int(ceil((s[1] - t_origin) * rate - 1e-9)))
			if i0 >= i1:
				continue
			var ts: float = t_origin + i0 / rate
			match s[2]:
				LIN:
					var v: float = _eval(s, ts)
					var step: float = (s[4] - s[3]) / (rate * (s[1] - s[0]))
					for i in range(i0, i1):
						out[i] = v
						v += step
				EXP:
					if s[3] > 0.0 and s[4] > 0.0:
						var v: float = _eval(s, ts)
						var r: float = pow(s[4] / s[3], 1.0 / (rate * (s[1] - s[0])))
						for i in range(i0, i1):
							out[i] = v
							v *= r
					else:
						for i in range(i0, i1):
							out[i] = s[3]
				DECAY:
					var d: float = (s[3] - s[4]) * exp(-(ts - s[0]) / s[5])
					var r: float = exp(-1.0 / (rate * s[5]))
					var to: float = s[4]
					for i in range(i0, i1):
						out[i] = to + d
						d *= r
				_:
					var v: float = s[3]
					for i in range(i0, i1):
						out[i] = v


## BiquadFilterNode coefficients [b0, b1, b2, a1, a2] (already divided by a0), the formulas of the WebAudio spec.
## type: lowpass | highpass (q in dB, like WebAudio) | bandpass (q is a plain Q) | peaking (q plain, gain_db).
static func biquad_coeffs(type: String, freq: float, q: float, gain_db := 0.0, rate := float(RATE)) -> PackedFloat64Array:
	var nyquist := rate / 2.0
	var out := PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 0.0])
	if freq >= nyquist:
		# lowpass passes everything, highpass and bandpass nothing
		if type == "highpass" or type == "bandpass":
			out[0] = 0.0
		return out
	if freq <= 0.0:
		if type == "lowpass" or type == "bandpass":
			out[0] = 0.0
		return out
	var w0 := TAU * freq / rate
	var cw := cos(w0)
	var sw := sin(w0)
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a0 := 1.0
	var a1 := 0.0
	var a2 := 0.0
	match type:
		"lowpass":
			var alpha := sw / (2.0 * pow(10.0, q / 20.0))
			b0 = (1.0 - cw) / 2.0
			b1 = 1.0 - cw
			b2 = b0
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		"highpass":
			var alpha := sw / (2.0 * pow(10.0, q / 20.0))
			b0 = (1.0 + cw) / 2.0
			b1 = -(1.0 + cw)
			b2 = b0
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		"bandpass":
			var alpha := sw / (2.0 * maxf(q, 1e-6))
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
			a0 = 1.0 + alpha
			a1 = -2.0 * cw
			a2 = 1.0 - alpha
		"peaking":
			var alpha := sw / (2.0 * maxf(q, 1e-6))
			var a := pow(10.0, gain_db / 40.0)
			b0 = 1.0 + alpha * a
			b1 = -2.0 * cw
			b2 = 1.0 - alpha * a
			a0 = 1.0 + alpha / a
			a1 = -2.0 * cw
			a2 = 1.0 - alpha / a
		_:
			push_warning("synth: unknown filter type %s" % type)
	out[0] = b0 / a0
	out[1] = b1 / a0
	out[2] = b2 / a0
	out[3] = a1 / a0
	out[4] = a2 / a0
	return out


## Filters `buf` in place (transposed direct form II). `freq_curve` is the cutoff in Hz for each sample when it
## moves (the coefficients follow it every FILTER_BLOCK samples); empty means a fixed `freq`.
static func biquad(buf: PackedFloat32Array, type: String, freq: float, q: float, freq_curve := PackedFloat32Array(), gain_db := 0.0, rate := float(RATE)) -> PackedFloat32Array:
	var n := buf.size()
	var z1 := 0.0
	var z2 := 0.0
	var moving := not freq_curve.is_empty()
	var c := biquad_coeffs(type, freq_curve[0] if moving else freq, q, gain_db, rate)
	var i := 0
	while i < n:
		if moving and i > 0:
			c = biquad_coeffs(type, freq_curve[i], q, gain_db, rate)
		var b0 := c[0]
		var b1 := c[1]
		var b2 := c[2]
		var a1 := c[3]
		var a2 := c[4]
		var end := mini(n, i + FILTER_BLOCK) if moving else n
		while i < end:
			var x := buf[i]
			var y := b0 * x + z1
			z1 = b1 * x - a1 * y + z2
			z2 = b2 * x - a2 * y
			buf[i] = y
			i += 1
	return buf


## An oscillator following `freq` (Hz per sample, may glide or vibrate): sine | triangle | sawtooth | square.
## Like WebAudio's, the sawtooth and square are band-limited (polyBLEP) and start at zero phase.
static func osc(type: String, freq: PackedFloat32Array, rate := float(RATE)) -> PackedFloat32Array:
	var n := freq.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var inv := 1.0 / rate
	var ph := 0.0
	match type:
		"sine":
			for i in n:
				out[i] = sin(TAU * ph)
				ph += freq[i] * inv
		"triangle":
			for i in n:
				var p := ph - floorf(ph)
				out[i] = 4.0 * p if p < 0.25 else (2.0 - 4.0 * p if p < 0.75 else 4.0 * p - 4.0)
				ph += freq[i] * inv
		"sawtooth":
			# rises from 0, wraps from +1 to -1 half a cycle in
			for i in n:
				var dt := absf(freq[i]) * inv
				var q := ph + 0.5
				q -= floorf(q)
				var v := 2.0 * q - 1.0
				if q < dt:
					var t := q / dt
					v -= t + t - t * t - 1.0
				elif q > 1.0 - dt:
					var t := (q - 1.0) / dt
					v -= t * t + t + t + 1.0
				out[i] = v
				ph += freq[i] * inv
				ph -= floorf(ph)
		"square":
			for i in n:
				var dt := absf(freq[i]) * inv
				var p := ph - floorf(ph)
				var v := 1.0 if p < 0.5 else -1.0
				if p < dt:
					var t := p / dt
					v += t + t - t * t - 1.0
				elif p > 1.0 - dt:
					var t := (p - 1.0) / dt
					v += t * t + t + t + 1.0
				var h := p + 0.5
				h -= floorf(h)
				if h < dt:
					var t := h / dt
					v -= t + t - t * t - 1.0
				elif h > 1.0 - dt:
					var t := (h - 1.0) / dt
					v -= t * t + t + t + 1.0
				out[i] = v
				ph += freq[i] * inv
		_:
			push_warning("synth: unknown oscillator type %s" % type)
	return out


## 16-bit mono AudioStreamWAV from float samples, each scaled by `scale` and clipped to [-1, 1]
static func to_wav(samples: PackedFloat32Array, rate := RATE, scale := 1.0, count := -1) -> AudioStreamWAV:
	var n := samples.size() if count < 0 else mini(count, samples.size())
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(samples[i] * scale, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	return w


static func peak_of(samples: PackedFloat32Array, count := -1) -> float:
	var n := samples.size() if count < 0 else mini(count, samples.size())
	var peak := 0.0
	for i in n:
		var a := absf(samples[i])
		if a > peak:
			peak = a
	return peak


static func rms_of(samples: PackedFloat32Array, count := -1) -> float:
	var n := samples.size() if count < 0 else mini(count, samples.size())
	if n == 0:
		return 0.0
	var sum := 0.0
	for i in n:
		sum += samples[i] * samples[i]
	return sqrt(sum / n)


## The tones of a quick run of notes (MIDI numbers): [[at, tone options], ...]
## o: {step = 0.07, type = "triangle", dur = 0.35, vol = 0.18, room = 0.6}
static func arp_tones(at: float, notes: Array, o: Dictionary) -> Array:
	var out := []
	var step: float = o.get("step", 0.07)
	for i in notes.size():
		out.append([at + i * step, {type = o.get("type", "triangle"), f0 = note(notes[i]), dur = o.get("dur", 0.35), vol = o.get("vol", 0.18), room = o.get("room", 0.6)}])
	return out


## Stands in for a Render while a recipe runs and only writes down what it asked for, so that the (slow) rendering
## can be done a few voices at a time: `run(render, deadline)` replays the calls until the deadline passes.
class Recorder:
	extends RefCounted
	var rate_mul := 1.0
	var gain_mul := 1.0
	var calls: Array = []
	var _next := 0

	func tone(at: float, o: Dictionary) -> void:
		calls.append(["tone", at, o])

	func noise(at: float, o: Dictionary) -> void:
		calls.append(["noise", at, o])

	func vocal(at: float, o: Dictionary) -> void:
		calls.append(["vocal", at, o])

	func arp(at: float, notes: Array, o := {}) -> void:
		for t in Synth.arp_tones(at, notes, o):
			calls.append(["tone", t[0], t[1]])

	func done() -> bool:
		return _next >= calls.size()

	## Replays calls onto `render` until Time.get_ticks_usec() reaches `deadline_usec` (at least one call per run).
	## Returns true once all are done.
	func run(render, deadline_usec: int) -> bool:
		while _next < calls.size():
			var c: Array = calls[_next]
			_next += 1
			render.call(c[0], c[1], c[2])
			if Time.get_ticks_usec() >= deadline_usec:
				break
		return done()


## The offline stand-in for an AudioContext plus Sfx's tone / noise / vocal / arp: every call mixes one voice
## into `dry` (straight to the effects bus) and `send` (what goes to the room, `room` times the voice).
## `rate_mul` and `gain_mul` are the detune and volume of the sound being built (sfx.js VARY); cached renders
## keep them at 1 and let the player apply the variation through pitch_scale and volume.
class Render:
	extends RefCounted
	var rate := RATE
	var rate_mul := 1.0
	var gain_mul := 1.0
	var dry := PackedFloat32Array()
	var send := PackedFloat32Array()
	var used := 0  # samples written so far
	var _noise := Synth.noise_table()

	func _init(sample_rate := RATE) -> void:
		rate = sample_rate

	func seconds() -> float:
		return float(used) / rate

	func _span(at: float, dur: float) -> Vector2i:
		var s0 := int(floor(at * rate + 0.5))
		var n := int(ceil(dur * rate))
		var need := s0 + n
		if dry.size() < need:
			dry.resize(need)
			send.resize(need)
		used = maxi(used, need)
		return Vector2i(s0, n)

	func _mix(sig: PackedFloat32Array, s0: int, room: float) -> void:
		var n := sig.size()
		if room > 0.0:
			for i in n:
				var x := sig[i]
				dry[s0 + i] += x
				send[s0 + i] += x * room
		else:
			for i in n:
				dry[s0 + i] += sig[i]

	## exponential attack to `vol`, exponential release to silence over `dur` (the envelope of every voice)
	func _env(n: int, at: float, vol: float, attack: float, dur: float) -> PackedFloat32Array:
		var p := Param.new()
		p.set_value_at_time(0.0001, at)
		p.exponential_ramp_to_value_at_time(vol, at + attack)
		p.exponential_ramp_to_value_at_time(0.0001, at + dur)
		var env := PackedFloat32Array()
		env.resize(n)
		p.fill(env, at, rate, n)
		return env

	## a frequency curve: f0 gliding exponentially to f1 over dur, plus a vibrato (LFO adding +-depth Hz)
	func _freq(n: int, at: float, f0: float, f1: float, dur: float, floor_hz: float, vibrato) -> PackedFloat32Array:
		var p := Param.new()
		p.set_value_at_time(f0, at)
		if f1 != f0:
			p.exponential_ramp_to_value_at_time(maxf(floor_hz, f1), at + dur)
		var curve := PackedFloat32Array()
		curve.resize(n)
		p.fill(curve, at, rate, n)
		if vibrato != null:
			var depth: float = vibrato.get("depth", 0.0)
			var w: float = TAU * float(vibrato.get("rate", 0.0)) / rate
			for i in n:
				curve[i] += depth * sin(w * i)
		return curve

	## A pitched tone gliding from f0 to f1, with a fast attack and exponential release.
	## {type = "sine", f0, f1 = f0, dur = 0.2, vol = 0.3, attack = 0.004, lp, room = 0.4, vibrato}
	func tone(at: float, o: Dictionary) -> void:
		var f0: float = float(o["f0"]) * rate_mul
		var f1: float = float(o.get("f1", o["f0"])) * rate_mul
		var dur: float = o.get("dur", 0.2)
		var vol: float = float(o.get("vol", 0.3)) * gain_mul
		var attack: float = o.get("attack", 0.004)
		var lp = o.get("lp")
		var span := _span(at, dur + 0.05)
		var n := span.y
		var sig := Synth.osc(o.get("type", "sine"), _freq(n, at, f0, f1, dur, 1.0, o.get("vibrato")), rate)
		var env := _env(n, at, vol, attack, dur)
		for i in n:
			sig[i] *= env[i]
		if lp != null:
			_lowpass(sig, at, dur, lp, 1.0)
		_mix(sig, span.x, o.get("room", 0.4))

	func _lowpass(sig: PackedFloat32Array, at: float, dur: float, lp: Array, q: float) -> void:
		var curve := PackedFloat32Array()
		if lp.size() > 1 and lp[1] != null and float(lp[1]) != 0.0:
			var p := Param.new()
			p.set_value_at_time(lp[0], at)
			p.exponential_ramp_to_value_at_time(lp[1], at + dur)
			curve.resize(sig.size())
			p.fill(curve, at, rate, sig.size())
		Synth.biquad(sig, "lowpass", lp[0], q, curve, 0.0, rate)

	## white noise from the shared table, starting at a random point, `n` samples
	func _noise_run(n: int) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(n)
		var size := _noise.size()
		var k := int(randf() * 0.5 * size)
		for i in n:
			out[i] = _noise[k]
			k += 1
			if k >= size:
				k = 0
		return out

	## Filtered noise: hits, whooshes, fire, crackle.
	## {dur = 0.15, vol = 0.3, type = "bandpass", f0 = 1000, f1 = f0, q = 1, attack = 0.002, room = 0.4}
	func noise(at: float, o: Dictionary) -> void:
		var dur: float = o.get("dur", 0.15)
		var f0: float = float(o.get("f0", 1000.0)) * rate_mul
		var f1: float = float(o.get("f1", o.get("f0", 1000.0))) * rate_mul
		var vol: float = float(o.get("vol", 0.3)) * gain_mul
		var span := _span(at, dur + 0.05)
		var n := span.y
		var sig := _noise_run(n)
		var curve := PackedFloat32Array()
		if f1 != f0:
			var p := Param.new()
			p.set_value_at_time(f0, at)
			p.exponential_ramp_to_value_at_time(maxf(20.0, f1), at + dur)
			curve.resize(n)
			p.fill(curve, at, rate, n)
		Synth.biquad(sig, o.get("type", "bandpass"), f0, float(o.get("q", 1.0)), curve, 0.0, rate)
		var env := _env(n, at, vol, o.get("attack", 0.002), dur)
		for i in n:
			sig[i] *= env[i]
		_mix(sig, span.x, o.get("room", 0.4))

	## A voice: a buzzing (and, with `rasp`, breathy) source pushed through three vowel-formant filters.
	## vowel: one name, or [from, to] to glide between two; size: < 1 = bigger throat (formants drop); rasp 0..1 = noise mix.
	## {f0, f1 = f0, dur = 0.3, vol = 0.3, vowel = ["ah"], size = 1, rasp = 0.2, attack = 0.02, vibrato, tremolo, room = 0.3, q = 8}
	func vocal(at: float, o: Dictionary) -> void:
		var f0: float = o["f0"]
		var f1: float = o.get("f1", f0)
		var dur: float = o.get("dur", 0.3)
		var vol: float = o.get("vol", 0.3)
		var size: float = o.get("size", 1.0)
		var rasp: float = o.get("rasp", 0.2)
		var q: float = o.get("q", 8.0)
		var vowel = o.get("vowel", ["ah"])
		var names: Array = vowel if vowel is Array else [vowel]
		var va: Array = Synth.VOWELS.get(names[0], Synth.VOWELS["ah"])
		var vb: Array = va
		if names.size() > 1:
			vb = Synth.VOWELS.get(names[1], Synth.VOWELS["ah"])
		var span := _span(at, dur + 0.05)
		var n := span.y
		var src := PackedFloat32Array()
		src.resize(n)
		if rasp < 1.0:
			var saw := Synth.osc("sawtooth", _freq(n, at, f0, f1, dur, 20.0, o.get("vibrato")), rate)
			var g := 1.0 - rasp * 0.7
			for i in n:
				src[i] = saw[i] * g
		if rasp > 0.0:
			var white := _noise_run(n)
			var g := rasp * Synth.NOISE_VOICE
			for i in n:
				src[i] += white[i] * g
		var sum := PackedFloat32Array()
		sum.resize(n)
		for k in 3:
			var fa: float = va[k] * size
			var fb: float = vb[k] * size
			var band := src.duplicate()
			var curve := PackedFloat32Array()
			if vb[k] != va[k]:
				var p := Param.new()
				p.set_value_at_time(fa, at)
				p.exponential_ramp_to_value_at_time(fb, at + dur)
				curve.resize(n)
				p.fill(curve, at, rate, n)
			Synth.biquad(band, "bandpass", fa, q, curve, 0.0, rate)
			var g: float = Synth.FORMANT_GAIN[k]
			for i in n:
				sum[i] += band[i] * g
		var env := _env(n, at, vol * Synth.VOICE_GAIN, o.get("attack", 0.02), dur)
		for i in n:
			sum[i] *= env[i]
		var tremolo = o.get("tremolo")
		if tremolo != null:
			var depth: float = tremolo.get("depth", 0.0)
			var w: float = TAU * float(tremolo.get("rate", 0.0)) / rate
			for i in n:
				sum[i] *= 1.0 - depth / 2.0 + depth / 2.0 * sin(w * i)
		_mix(sum, span.x, o.get("room", 0.3))

	## A quick run of notes (MIDI numbers), see Synth.arp_tones
	func arp(at: float, notes: Array, o := {}) -> void:
		for t in Synth.arp_tones(at, notes, o):
			tone(t[0], t[1])

	## The finished sound as streams: both are scaled to a 0.9 peak (best use of 16 bits) and come with the gain
	## that restores their level. {dry, dry_gain, send, send_gain (send is null without any room), seconds}
	func finish() -> Dictionary:
		var out := {"seconds": seconds(), "dry": null, "dry_gain": 1.0, "send": null, "send_gain": 1.0, "peak": Synth.peak_of(dry, used)}
		if out.peak > 1e-6:
			out.dry = Synth.to_wav(dry, rate, 0.9 / out.peak, used)
			out.dry_gain = out.peak / 0.9
		var send_peak := Synth.peak_of(send, used)
		out["send_peak"] = send_peak
		if send_peak > 1e-6:
			out.send = Synth.to_wav(send, rate, 0.9 / send_peak, used)
			out.send_gain = send_peak / 0.9
		return out
