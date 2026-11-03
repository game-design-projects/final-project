## Makes the game's sound effects out of arithmetic, so there are no sample files for them. A sound is a list of parts
## (a tone that may slide in pitch, or filtered noise), each with a start, a length, a loudness and a fade. `render`
## adds them up into a stream the game can play.
extends RefCounted

const RATE := 22050


## A tone: `wave` is "sine", "square", "saw" or "tri"; it glides from `from` Hz to `to` Hz over `dur` seconds.
static func tone(wave: String, from: float, to: float, dur: float, vol := 0.4, delay := 0.0) -> Dictionary:
	return {"wave": wave, "from": from, "to": to, "dur": dur, "vol": vol, "delay": delay}


## Noise, softened by a one-pole low-pass at `lowpass` Hz (higher = hissier).
static func noise(dur: float, vol := 0.3, lowpass := 4000.0, delay := 0.0) -> Dictionary:
	return {"wave": "noise", "from": lowpass, "to": lowpass, "dur": dur, "vol": vol, "delay": delay}


static func render(parts: Array) -> AudioStreamWAV:
	var total := 0.0
	for p in parts:
		total = maxf(total, p.delay + p.dur)
	var n := int(ceil(total * RATE)) + 1
	var mix := PackedFloat32Array()
	mix.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 # the same noise every time, so a sound is always the same sound
	for p in parts:
		_add(mix, p, rng)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream


static func _add(mix: PackedFloat32Array, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var start := int(p.delay * RATE)
	var count := int(p.dur * RATE)
	var phase := 0.0
	var low := 0.0
	for i in count:
		var k := float(i) / maxf(1.0, count - 1.0)
		var hz: float = lerpf(p.from, p.to, k)
		var s: float
		if p.wave == "noise":
			var a := clampf(TAU * hz / RATE, 0.0, 1.0)
			low += a * (rng.randf_range(-1.0, 1.0) - low)
			s = low
		else:
			phase = fposmod(phase + hz / RATE, 1.0)
			s = _wave(p.wave, phase)
		# a short attack so it doesn't click, then a fade to nothing
		var env := minf(1.0, float(i) / (RATE * 0.004)) * pow(1.0 - k, 1.6)
		if start + i < mix.size():
			mix[start + i] += s * env * p.vol


static func _wave(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if phase < 0.5 else -1.0
		"saw":
			return phase * 2.0 - 1.0
		"tri":
			return absf(phase * 4.0 - 2.0) - 1.0
		_:
			return sin(phase * TAU)
