## Sound effects: hits, crits, spells, kills, dice, monster voices, the Roll of Fate. Nothing is a file.
## Every sound is a recipe (`snd_<name>`, below) built from a few primitives: pitched tones with envelopes,
## filtered noise bursts, and a formant "vocal" (src/audio/synth.gd). A recipe is rendered once into an
## AudioStreamWAV and cached; each play only picks the cached stream and sets its pitch and volume.
## The room (the JS convolver) is a send bus with a reverb: see src/audio/mix.gd.
## Load it with `const Sfx = preload("res://src/audio/sfx.gd")` and use `Sfx.Sfx.new()`.
extends RefCounted

const Self = preload("res://src/audio/sfx.gd")  # Sfx (inner class) reaches the recipes through this
const Synth = preload("res://src/audio/synth.gd")
const Shout = preload("res://src/audio/shout.gd")
const Mix = preload("res://src/audio/mix.gd")

# Sounds you hear over and over get a little different each time: a random detune up to ± `cents` and a
# volume up to ± `gain`, so ten sword hits in a row sound like ten hits, not one sample on repeat.
const VARY := {
	"hit": {"cents": 110, "gain": 0.12},
	"crit": {"cents": 50, "gain": 0.08},
	"miss": {"cents": 180, "gain": 0.15},
	"hurt": {"cents": 90, "gain": 0.12},
	"kill": {"cents": 70, "gain": 0.08},
	"bump": {"cents": 140, "gain": 0.15},
	"slash": {"cents": 100, "gain": 0.1},
	"gold": {"cents": 60, "gain": 0.1},
	"tick": {"cents": 40, "gain": 0.1},
	"stairs": {"cents": 50, "gain": 0.08},
	"heartbeat": {"cents": 30, "gain": 0.05},
}
# Voice limit: at most this many copies of one sound may start within POLY_WINDOW seconds of each other
# (QUICK ATTACK can land six hits at once). The rest are dropped, and the ones that play are each a little
# quieter, so a pile-up sounds bigger without clipping.
const POLY := {"default": 4, "hit": 3, "crit": 2, "miss": 2, "hurt": 2, "kill": 2, "dice": 1, "tick": 1, "bump": 1, "heartbeat": 1}
const POLY_WINDOW := 0.06

# Recipes with a dice roll in them (Math.random in the JS) are rendered this many times and a variant is picked per play
const VARIANTS := {"dice": 4, "voice_squelch": 3, "voice_babble": 4, "voice_zap": 3}
# Only these voices change with the number of syllables in the line
const SYLLABLE_VOICES := ["voice_bark", "voice_squelch", "voice_babble"]
# Rendered ahead of time, in this order, a few milliseconds per frame (voices depend on the monster and render when first needed)
const PREWARM := [
	"hit", "miss", "crit", "hurt", "kill", "bump", "tick", "dice", "diceLand", "slash", "gold", "stairs", "heartbeat",
	"good", "bad", "save", "down", "death", "fire", "fireball", "missile", "holy", "sleep", "hold", "heal", "revive", "buff",
	"fear", "sad", "odd", "join", "levelup", "achieve", "encounter", "boss", "flee", "land", "great",
]
const PREWARM_MS := 4.0  # per frame for background rendering...
const URGENT_MS := 10.0  # ...and per frame while a sound is waiting for its render

# The room the sounds sit in, as a share of each voice sent to the reverb
const ROOM_WET := 0.22


## MIDI note number -> Hz
static func note(n: float) -> float:
	return Synth.note(n)


static var _recipes := {}


## name -> the recipe function (`snd_<name>`), in the order of this file
static func recipes() -> Dictionary:
	if _recipes.is_empty():
		_recipes = {
			"hit": snd_hit, "crit": snd_crit, "miss": snd_miss, "hurt": snd_hurt, "kill": snd_kill, "down": snd_down,
			"death": snd_death, "save": snd_save,
			"fire": snd_fire, "fireball": snd_fireball, "missile": snd_missile, "holy": snd_holy, "sleep": snd_sleep,
			"hold": snd_hold, "heal": snd_heal, "revive": snd_revive, "buff": snd_buff,
			"dice": snd_dice, "diceLand": snd_diceLand,
			"voice_roar": snd_voice_roar, "voice_bark": snd_voice_bark, "voice_grunt": snd_voice_grunt,
			"voice_growl": snd_voice_growl, "voice_hiss": snd_voice_hiss, "voice_squelch": snd_voice_squelch,
			"voice_laugh": snd_voice_laugh, "voice_squeal": snd_voice_squeal, "voice_whimper": snd_voice_whimper,
			"voice_sigh": snd_voice_sigh, "voice_rumble": snd_voice_rumble, "voice_zap": snd_voice_zap,
			"voice_babble": snd_voice_babble,
			"good": snd_good, "bad": snd_bad, "fear": snd_fear, "sad": snd_sad, "odd": snd_odd, "join": snd_join,
			"gold": snd_gold, "levelup": snd_levelup, "achieve": snd_achieve, "slash": snd_slash,
			"encounter": snd_encounter, "boss": snd_boss, "flee": snd_flee, "bump": snd_bump,
			"heartbeat": snd_heartbeat, "stairs": snd_stairs,
			"tick": snd_tick, "land": snd_land, "great": snd_great,
		}
	return _recipes


static func names() -> Array:
	return recipes().keys()


static func has_recipe(name: String) -> bool:
	return recipes().has(name)


## Runs a recipe on `s` (a Synth.Render, or anything with tone / noise / vocal / arp) starting at t seconds
static func run_recipe(name: String, s, t: float, o := {}) -> void:
	recipes()[name].call(s, t, o)


## The monster voice plan with every field present (a plan from Shout.shout_plan, or just the parts a test gives)
static func _plan(o: Dictionary) -> Dictionary:
	return {
		"f0": float(o.get("f0", 130.0)),
		"size": float(o.get("size", 1.0)),
		"rasp": float(o.get("rasp", 0.3)),
		"wet": o.get("wet", false) == true,
		"vol": float(o.get("vol", 1.0)),
		"syll": int(o.get("syll", 3)),
	}


# ---- Combat

static func snd_hit(s, t, _o = {}):
	s.tone(t, {f0 = 150, f1 = 55, dur = 0.16, vol = 0.55, room = 0.2})
	s.noise(t, {dur = 0.09, vol = 0.4, f0 = 1800, f1 = 500, q = 0.8, room = 0.2})


static func snd_crit(s, t, _o = {}):
	s.tone(t, {f0 = 180, f1 = 45, dur = 0.25, vol = 0.7, room = 0.3})
	s.noise(t, {dur = 0.14, vol = 0.55, f0 = 3000, f1 = 400, q = 0.7, room = 0.3})
	s.tone(t + 0.02, {type = "square", f0 = note(88), dur = 0.22, vol = 0.09, lp = [5000, 1500], room = 0.7})
	s.tone(t + 0.06, {type = "square", f0 = note(95), dur = 0.3, vol = 0.07, lp = [5000, 1500], room = 0.8})


static func snd_miss(s, t, _o = {}):
	s.noise(t, {dur = 0.2, vol = 0.18, f0 = 500, f1 = 2600, q = 2.5, attack = 0.05, room = 0.2})


static func snd_hurt(s, t, _o = {}):
	s.tone(t, {f0 = 110, f1 = 40, dur = 0.22, vol = 0.6, room = 0.2})
	s.tone(t, {type = "sawtooth", f0 = 90, f1 = 60, dur = 0.18, vol = 0.12, lp = [900, 200], room = 0.1})
	s.noise(t, {dur = 0.12, vol = 0.3, type = "lowpass", f0 = 900, f1 = 200, room = 0.2})


static func snd_kill(s, t, _o = {}):
	s.tone(t, {type = "square", f0 = 440, f1 = 50, dur = 0.5, vol = 0.12, lp = [3000, 300], room = 0.6})
	s.tone(t, {f0 = 120, f1 = 30, dur = 0.6, vol = 0.6, room = 0.4})
	s.noise(t, {dur = 0.35, vol = 0.4, type = "lowpass", f0 = 2500, f1 = 150, room = 0.5})


static func snd_down(s, t, _o = {}):
	s.arp(t, [62, 58, 53], {step = 0.16, type = "triangle", dur = 0.5, vol = 0.2})
	s.tone(t, {f0 = 90, f1 = 45, dur = 0.5, vol = 0.4})


static func snd_death(s, t, _o = {}):
	s.tone(t, {f0 = note(38), dur = 2.2, vol = 0.35, attack = 0.01, room = 1})
	s.tone(t, {f0 = note(50) * 1.003, dur = 1.8, vol = 0.12, room = 1})
	s.tone(t, {type = "triangle", f0 = note(57), f1 = note(45), dur = 1.4, vol = 0.12, room = 1})


static func snd_save(s, t, _o = {}):
	s.tone(t, {type = "triangle", f0 = note(84), dur = 0.25, vol = 0.12, room = 0.6})


# ---- Spells

static func snd_fire(s, t, _o = {}):
	s.noise(t, {dur = 0.45, vol = 0.45, type = "lowpass", f0 = 400, f1 = 3500, q = 3, attack = 0.04, room = 0.4})
	s.noise(t + 0.15, {dur = 0.4, vol = 0.3, type = "lowpass", f0 = 3000, f1 = 300, q = 2, room = 0.5})
	s.tone(t, {type = "sawtooth", f0 = 70, f1 = 120, dur = 0.4, vol = 0.1, lp = [600, 1500], room = 0.3})


static func snd_fireball(s, t, _o = {}):
	s.noise(t, {dur = 0.3, vol = 0.3, f0 = 600, f1 = 3000, q = 4, attack = 0.2, room = 0.3})
	s.tone(t + 0.3, {f0 = 90, f1 = 28, dur = 1.1, vol = 0.8, room = 0.8})
	s.noise(t + 0.3, {dur = 1.2, vol = 0.6, type = "lowpass", f0 = 4000, f1 = 120, q = 0.5, room = 0.8})


static func snd_missile(s, t, _o = {}):
	for i in 3:
		s.tone(t + i * 0.09, {type = "square", f0 = 2200, f1 = 500, dur = 0.12, vol = 0.08, lp = [6000, 1200], room = 0.6})


static func snd_holy(s, t, _o = {}):
	var notes := [76, 83, 88]
	for i in notes.size():
		s.tone(t + i * 0.03, {f0 = note(notes[i]), dur = 0.9, vol = 0.12, attack = 0.05, room = 1, vibrato = {rate = 6, depth = 4}})


static func snd_sleep(s, t, _o = {}):
	var notes := [81, 77, 74, 69]
	for i in notes.size():
		s.tone(t + i * 0.15, {f0 = note(notes[i]), dur = 0.6, vol = 0.12, attack = 0.04, room = 1})


static func snd_hold(s, t, _o = {}):
	s.tone(t, {type = "square", f0 = 110, dur = 0.8, vol = 0.08, lp = [700, 300], vibrato = {rate = 12, depth = 20}, room = 0.6})
	s.tone(t, {f0 = note(83), f1 = note(71), dur = 0.8, vol = 0.06, room = 0.8})


static func snd_heal(s, t, _o = {}):
	s.arp(t, [72, 76, 79, 84, 88], {step = 0.06, type = "sine", dur = 0.6, vol = 0.13})


static func snd_revive(s, t, _o = {}):
	s.arp(t, [60, 67, 72, 76, 79, 84, 91], {step = 0.09, type = "triangle", dur = 1, vol = 0.13})
	s.tone(t, {f0 = note(48), dur = 1.6, vol = 0.2, attack = 0.2, room = 1})


static func snd_buff(s, t, _o = {}):
	var notes := [72, 79, 84]
	for i in notes.size():
		s.tone(t + i * 0.05, {type = "triangle", f0 = note(notes[i]), dur = 0.7, vol = 0.1, attack = 0.08, room = 1, vibrato = {rate = 5, depth = 3}})


# ---- Talking and feelings

## A die in the air: five quick clacks in the ~130ms before it lands
static func snd_dice(s, t, _o = {}):
	for i in 5:
		var at: float = t + i * 0.026 + randf() * 0.008
		s.noise(at, {dur = 0.022, vol = 0.4 - i * 0.04, type = "bandpass", f0 = 2200 + randf() * 2600, q = 2.5, attack = 0.001, room = 0.15})
		s.tone(at, {type = "square", f0 = 380 + randf() * 420, f1 = 200, dur = 0.02, vol = 0.1, lp = [2500], attack = 0.001, room = 0.1})


## ...and the slam. tier: "crit" (natural 20) rings gold, "fumble" (natural 1) cracks and sinks.
static func snd_diceLand(s, t, o = {}):
	s.tone(t, {f0 = 170, f1 = 60, dur = 0.09, vol = 0.5, room = 0.2})
	s.noise(t, {dur = 0.05, vol = 0.3, f0 = 2600, f1 = 900, q = 1, room = 0.2})
	if o.get("tier") == "crit":
		s.arp(t + 0.02, [84, 91, 96], {step = 0.05, type = "triangle", dur = 0.55, vol = 0.1, room = 0.7})
		s.noise(t, {dur = 0.3, vol = 0.1, type = "highpass", f0 = 6500, q = 0.5, room = 0.5})
	elif o.get("tier") == "fumble":
		s.tone(t, {type = "sawtooth", f0 = 140, f1 = 45, dur = 0.35, vol = 0.2, lp = [800, 150], room = 0.3})
		s.noise(t + 0.02, {dur = 0.15, vol = 0.3, type = "lowpass", f0 = 1200, f1 = 150, room = 0.3})


# ---- Monster voices (see shout.gd for which one a line gets). p = { f0, size, rasp, wet, vol, syll }.
# Big throats (size < 1) hold their sounds longer.

static func snd_voice_roar(s, t, o = {}):
	var p := _plan(o)
	var dur: float = 0.42 * minf(1.8, 1.0 / sqrt(p.size))
	s.vocal(t, {f0 = p.f0 * 1.2, f1 = p.f0 * 0.75, dur = dur, vol = 0.55 * p.vol, vowel = ["uh", "aw"], size = p.size, rasp = minf(1.0, p.rasp + 0.3), attack = 0.035, vibrato = {rate = 24, depth = p.f0 * 0.05}, tremolo = {rate = 38, depth = 0.45}, room = 0.5})
	s.noise(t, {dur = dur * 0.8, vol = 0.14 * p.vol, f0 = 900 * p.size, f1 = 350 * p.size, q = 0.8, attack = 0.04, room = 0.4})
	s.tone(t, {f0 = maxf(48.0, p.f0 * 0.5), f1 = maxf(40.0, p.f0 * 0.35), dur = dur, vol = 0.18 * p.vol, attack = 0.03, room = 0.4})


static func snd_voice_bark(s, t, o = {}):
	var p := _plan(o)
	var n: int = maxi(1, mini(3, ceili(p.syll / 2.0)))
	var gap: float = 0.17 / sqrt(p.size)
	for i in n:
		s.vocal(t + i * gap, {f0 = p.f0 * (1.25 - 0.1 * i), f1 = p.f0 * 0.9, dur = 0.14 / sqrt(p.size), vol = (0.75 * p.vol) / sqrt(p.size), vowel = ["eh", "ah"], size = p.size, rasp = p.rasp, attack = 0.012, room = 0.35})


static func snd_voice_grunt(s, t, o = {}):
	var p := _plan(o)
	var dur: float = 0.16 / sqrt(p.size)
	s.vocal(t, {f0 = p.f0, f1 = p.f0 * 0.72, dur = dur, vol = (0.8 * p.vol) / sqrt(p.size), vowel = ["uh", "oh"], size = p.size, rasp = minf(1.0, p.rasp + 0.3), attack = 0.015, room = 0.3})
	s.noise(t, {dur = 0.06, vol = 0.1 * p.vol, type = "lowpass", f0 = 700, f1 = 250, room = 0.2})


static func snd_voice_growl(s, t, o = {}):
	var p := _plan(o)
	var dur: float = 0.7 * minf(1.8, 1.0 / sqrt(p.size))
	s.vocal(t, {f0 = p.f0 * 0.95, f1 = p.f0 * 0.8, dur = dur, vol = 0.5 * p.vol, vowel = ["oh", "uh"], size = p.size, rasp = minf(1.0, p.rasp + 0.3), attack = 0.08, tremolo = {rate = 28, depth = 0.7}, vibrato = {rate = 9, depth = p.f0 * 0.03}, room = 0.4})


static func snd_voice_hiss(s, t, o = {}):
	var p := _plan(o)
	var dur := 0.5
	var top: float = 0.8 + 0.2 * minf(1.0, p.size)  # bigger snakes hiss lower
	s.noise(t, {dur = dur, vol = 0.3 * p.vol, type = "highpass", f0 = 3200 * top, f1 = 2800 * top, attack = 0.06, room = 0.3})
	s.noise(t, {dur = dur, vol = 0.2 * p.vol, f0 = 5500 * top, f1 = 4500 * top, q = 1.5, attack = 0.08, room = 0.3})


static func snd_voice_squelch(s, t, o = {}):
	var p := _plan(o)
	var n := 3 if p.syll > 3 else 2
	for i in n:
		s.tone(t + i * 0.085, {f0 = p.f0 * (0.8 + 0.5 * i) * (0.9 + randf() * 0.2), f1 = p.f0 * (1.6 + 0.4 * i), dur = 0.11, vol = 0.34 * p.vol, lp = [1800, 700], vibrato = {rate = 32, depth = p.f0 * 0.12}, room = 0.3})
	s.tone(t + n * 0.085, {f0 = p.f0 * 1.8, f1 = p.f0 * 0.6, dur = 0.11, vol = 0.3 * p.vol, lp = [1500, 500], room = 0.3})
	s.noise(t, {dur = 0.09, vol = 0.12 * p.vol, type = "lowpass", f0 = 900, f1 = 300, q = 1, room = 0.2})


static func snd_voice_laugh(s, t, o = {}):
	var p := _plan(o)
	var n := 3 if p.f0 < 90 else 4
	var gap: float = 0.115 / sqrt(p.size)
	for i in n:
		var at: float = t + i * gap
		s.noise(at, {dur = 0.05, vol = 0.08 * p.vol, f0 = 2500, q = 0.5, room = 0.2})
		s.vocal(at, {f0 = p.f0 * (1.35 - 0.1 * i) * (1.4 if p.wet else 1.0), f1 = p.f0 * (1.15 - 0.1 * i), dur = 0.09 / sqrt(p.size), vol = 0.45 * p.vol * (1 - i * 0.1), vowel = ["ee"] if p.wet else ["ah"], size = p.size, rasp = p.rasp * 0.6, attack = 0.01, room = 0.4})


static func snd_voice_squeal(s, t, o = {}):
	var p := _plan(o)
	s.vocal(t, {f0 = p.f0 * 1.9, f1 = p.f0 * 2.5, dur = 0.32, vol = 0.7 * p.vol, vowel = ["ee"], size = p.size, rasp = 0.15, attack = 0.02, vibrato = {rate = 14, depth = p.f0 * 0.2}, room = 0.4})
	if p.wet:
		s.tone(t, {f0 = p.f0 * 2, f1 = p.f0 * 3, dur = 0.28, vol = 0.14 * p.vol, lp = [2500], vibrato = {rate = 20, depth = p.f0 * 0.2}, room = 0.4})


static func snd_voice_whimper(s, t, o = {}):
	var p := _plan(o)
	var delays := [0.0, 0.3]
	for i in delays.size():
		s.vocal(t + delays[i], {f0 = p.f0 * 1.5 * (1 - i * 0.1), f1 = p.f0 * 1.05 * (1 - i * 0.1), dur = 0.25, vol = 0.32 * p.vol, vowel = ["oo", "ee"], size = p.size, rasp = 0.1, attack = 0.05, vibrato = {rate = 8, depth = p.f0 * 0.07}, room = 0.5})


static func snd_voice_sigh(s, t, o = {}):
	var p := _plan(o)
	s.noise(t, {dur = 0.6, vol = 0.3 * p.vol, f0 = 1100 * p.size, f1 = 500 * p.size, q = 0.6, attack = 0.15, room = 0.4})
	s.tone(t, {type = "triangle", f0 = p.f0 * 1.6, f1 = p.f0, dur = 0.6, vol = 0.15 * p.vol, attack = 0.1, lp = [700, 300], room = 0.4})


static func snd_voice_rumble(s, t, o = {}):
	var p := _plan(o)
	var dur: float = 0.75 * minf(1.8, 1.0 / sqrt(p.size))
	s.tone(t, {f0 = p.f0 * 1.4, f1 = p.f0 * 0.8, dur = dur, vol = 0.5 * p.vol, attack = 0.05, room = 0.6})
	s.tone(t, {type = "sawtooth", f0 = p.f0 * 2, f1 = p.f0 * 1.4, dur = dur, vol = 0.12 * p.vol, lp = [250, 120], vibrato = {rate = 14, depth = 6}, room = 0.5})
	s.noise(t, {dur = dur, vol = 0.3 * p.vol, type = "lowpass", f0 = 220, f1 = 90, q = 1.2, attack = 0.08, room = 0.5})
	for i in 4:
		s.noise(t + 0.08 + i * 0.12, {dur = 0.1, vol = 0.14 * p.vol, type = "lowpass", f0 = 320, f1 = 160, room = 0.4})


static func snd_voice_zap(s, t, o = {}):
	var p := _plan(o)
	for i in 6:
		s.noise(t + i * 0.045 + randf() * 0.02, {dur = 0.03, vol = 0.2 * p.vol, type = "highpass", f0 = 3000 + randf() * 3000, room = 0.3})
	s.tone(t, {type = "sawtooth", f0 = 380, f1 = 90, dur = 0.3, vol = 0.1 * p.vol, lp = [4000, 800], vibrato = {rate = 60, depth = 80}, room = 0.4})


## Plain speech: a few vowel syllables with a falling sentence tune, in the species' voice
static func snd_voice_babble(s, t, o = {}):
	var p := _plan(o)
	var gap: float = (0.085 if p.wet else 0.1) / minf(1.4, sqrt(p.size))
	var vowels := ["ah", "oh", "uh", "eh", "oo", "aw"]
	for i in p.syll:
		var at: float = t + i * gap + randf() * 0.015
		var f: float = p.f0 * (1.15 - (0.25 * i) / p.syll) * (0.92 + randf() * 0.16)
		if p.wet:
			s.tone(at, {f0 = f * 0.9, f1 = f * 1.4, dur = 0.07, vol = 0.24 * p.vol, lp = [1500, 800], vibrato = {rate = 30, depth = f * 0.08}, room = 0.3})
		else:
			s.vocal(at, {f0 = f, f1 = f * 0.93, dur = gap * 0.8, vol = (0.4 * p.vol) / sqrt(p.size), vowel = [vowels[randi() % 6], vowels[randi() % 6]], size = p.size, rasp = p.rasp, attack = 0.01, room = 0.3})


static func snd_good(s, t, _o = {}):
	s.tone(t, {type = "triangle", f0 = note(76), dur = 0.25, vol = 0.16, room = 0.6})
	s.tone(t + 0.1, {type = "triangle", f0 = note(83), dur = 0.45, vol = 0.16, room = 0.7})


static func snd_bad(s, t, _o = {}):
	s.tone(t, {type = "sawtooth", f0 = 75, f1 = 62, dur = 0.6, vol = 0.18, lp = [400, 900], vibrato = {rate = 9, depth = 6}, room = 0.4})
	s.tone(t, {type = "sawtooth", f0 = 106, f1 = 88, dur = 0.6, vol = 0.1, lp = [500, 1000], room = 0.4})


static func snd_fear(s, t, _o = {}):
	s.tone(t, {type = "triangle", f0 = note(79), f1 = note(67), dur = 0.7, vol = 0.1, vibrato = {rate = 14, depth = 25}, room = 0.8})


static func snd_sad(s, t, _o = {}):
	s.tone(t, {type = "triangle", f0 = note(70), f1 = note(65), dur = 0.8, vol = 0.12, attack = 0.05, room = 0.9})


static func snd_odd(s, t, _o = {}):
	s.tone(t, {f0 = 300, f1 = 900, dur = 0.12, vol = 0.15, room = 0.3})
	s.tone(t + 0.12, {f0 = 900, f1 = 220, dur = 0.3, vol = 0.13, room = 0.5, vibrato = {rate = 18, depth = 40}})


static func snd_join(s, t, _o = {}):
	s.arp(t, [67, 71, 74, 79, 83, 86], {step = 0.08, type = "square", dur = 0.3, vol = 0.06})
	s.arp(t + 0.48, [79, 83, 86, 91], {step = 0, type = "triangle", dur = 0.9, vol = 0.08})


static func snd_gold(s, t, _o = {}):
	for i in 3:
		s.tone(t + i * 0.07, {f0 = 2100 + i * 150, dur = 0.18, vol = 0.06, room = 0.5})
		s.tone(t + i * 0.07, {f0 = 3150 + i * 200, dur = 0.12, vol = 0.04, room = 0.5})


static func snd_levelup(s, t, _o = {}):
	s.arp(t, [60, 64, 67, 72, 76, 79, 84], {step = 0.055, type = "square", dur = 0.25, vol = 0.05})
	s.tone(t + 0.4, {type = "triangle", f0 = note(84), dur = 0.8, vol = 0.12, room = 0.9})


## An achievement: a quick 8-bit run up to a bright held chord, with a sparkle on top
static func snd_achieve(s, t, _o = {}):
	s.arp(t, [72, 76, 79, 84], {step = 0.065, type = "square", dur = 0.16, vol = 0.055, room = 0.35})
	for n in [79, 84, 88]:
		s.tone(t + 0.28, {type = "square", f0 = note(n), dur = 0.75, vol = 0.035, lp = [5000, 1800], room = 0.6})
	s.tone(t + 0.28, {type = "triangle", f0 = note(96), dur = 0.9, vol = 0.07, room = 0.9, vibrato = {rate = 7, depth = 8}})
	s.noise(t + 0.28, {dur = 0.5, vol = 0.05, type = "highpass", f0 = 7000, q = 0.5, room = 0.6})


static func snd_slash(s, t, _o = {}):
	s.noise(t, {dur = 0.25, vol = 0.4, f0 = 6000, f1 = 500, q = 3, attack = 0.01, room = 0.4})
	s.tone(t + 0.05, {type = "sawtooth", f0 = 160, f1 = 70, dur = 0.5, vol = 0.12, lp = [1200, 300], room = 0.6})


# ---- Exploring

static func snd_encounter(s, t, _o = {}):
	s.tone(t, {type = "sawtooth", f0 = note(45), dur = 0.5, vol = 0.12, lp = [2000, 400]})
	s.tone(t, {type = "sawtooth", f0 = note(51), dur = 0.5, vol = 0.1, lp = [2000, 400]})
	s.tone(t, {f0 = 70, f1 = 40, dur = 0.4, vol = 0.4})


static func snd_boss(s, t, _o = {}):
	s.tone(t, {f0 = 55, f1 = 41, dur = 2.2, vol = 0.5, attack = 0.02, room = 1})
	s.noise(t, {dur = 2, vol = 0.25, type = "lowpass", f0 = 600, f1 = 80, room = 1})
	var notes := [33, 39, 45]
	for i in notes.size():
		s.tone(t + 0.3 + i * 0.25, {type = "sawtooth", f0 = note(notes[i] + 12), dur = 1.4, vol = 0.08, lp = [300, 1200], attack = 0.2, room = 1})


static func snd_flee(s, t, _o = {}):
	s.noise(t, {dur = 0.3, vol = 0.2, f0 = 300, f1 = 3000, q = 2, attack = 0.05, room = 0.3})
	s.noise(t + 0.12, {dur = 0.3, vol = 0.15, f0 = 400, f1 = 3500, q = 2, attack = 0.05, room = 0.3})


static func snd_bump(s, t, _o = {}):
	s.tone(t, {f0 = 90, f1 = 60, dur = 0.12, vol = 0.4, room = 0.2})


## Your own pulse when the party is in danger (mix.gd schedules it on the music's beat): lub-dub, felt more than heard.
## o.level 0..1 scales it with the danger.
## A sine body for headphones, plus its octave (triangle) so laptop speakers, which play little under 150 Hz, still carry it.
## It sits under the hits: quieter than a critical hit even at full danger (measured offline, peak and RMS).
static func snd_heartbeat(s, t, o = {}):
	var level: float = clampf(float(o.get("level", 1.0)), 0.0, 1.0)
	for beat in [[t, 62, 38, 0.22], [t + 0.17, 55, 34, 0.15]]:
		var at: float = beat[0]
		s.tone(at, {f0 = beat[1], f1 = beat[2], dur = 0.17, vol = beat[3] * level, attack = 0.006, room = 0.05})
		s.tone(at, {type = "triangle", f0 = beat[1] * 2, f1 = beat[2] * 2, dur = 0.12, vol = beat[3] * 0.45 * level, attack = 0.004, lp = [500, 200], room = 0.05})


static func snd_stairs(s, t, _o = {}):
	for i in 4:
		s.tone(t + i * 0.13, {f0 = 120 - i * 12, f1 = 70 - i * 6, dur = 0.1, vol = 0.3, room = 0.5})


# ---- The Roll of Fate

static func snd_tick(s, t, _o = {}):
	s.tone(t, {type = "square", f0 = 1400, dur = 0.03, vol = 0.05, lp = [4000], room = 0.2})


static func snd_land(s, t, _o = {}):
	s.arp(t, [60, 67, 72, 76], {step = 0, type = "sawtooth", dur = 1.2, vol = 0.05})
	s.arp(t, [72, 76, 79, 84, 88], {step = 0.06, type = "triangle", dur = 0.8, vol = 0.1})
	s.tone(t, {f0 = 65, dur = 0.8, vol = 0.3, room = 0.8})


static func snd_great(s, t, _o = {}):
	s.tone(t, {f0 = 55, f1 = 40, dur = 1.5, vol = 0.5, room = 1})
	var chords := [[57, 64, 69, 72], [53, 60, 65, 69], [55, 62, 67, 71], [57, 64, 69, 73, 76]]
	for i in chords.size():
		for n in chords[i]:
			s.tone(t + i * 0.32, {type = "sawtooth", f0 = note(n), dur = 2 if i == 3 else 0.4, vol = 0.045, lp = [800, 4000 if i == 3 else 1500], attack = 0.02, room = 0.9})
	s.arp(t + 0.96, [81, 85, 88, 93], {step = 0.08, type = "triangle", dur = 1.4, vol = 0.09})


## What one play of a sound is called in the cache: the recipe plus whatever of its options changes the render.
## A voice's volume is applied at play time (every `vol` in a voice recipe is a plain factor), so it is not part of the key.
static func cache_key(name: String, o: Dictionary) -> String:
	if name == "diceLand":
		return "%s:%s" % [name, o.get("tier", "")]
	if name.begins_with("voice_"):
		var p := _plan(o)
		return "%s|%.1f|%.3f|%.3f|%d|%d" % [name, p.f0, p.size, p.rasp, 1 if p.wet else 0, p.syll if name in SYLLABLE_VOICES else 0]
	return name


## Renders a recipe once. `o` carries the recipe's options (a voice plan, a die tier); levels (`level`, a voice's `vol`)
## are applied by the caller as gain.
static func render(name: String, o := {}) -> Dictionary:
	var s := Synth.Render.new()
	var p := o.duplicate()
	p.erase("vol")
	p.erase("level")
	run_recipe(name, s, 0.0, p)
	var out := s.finish()
	out["name"] = name
	return out


class Sfx:
	extends Node

	var volume: float
	var random: Callable  # () -> float in [0, 1)
	var clock: Callable  # () -> seconds on the audio clock (tests drive it)
	var on := true
	var lag := 0.0  # seconds: sounds played right now wait this long (a die's result lands with the die)
	var running := false  # init() has run: the JS `ctx.state === "running"`
	var blocking := false  # render a missing sound on the spot instead of over the next frames (tests, dumps)
	var last_shout := {}
	var recent := {}  # sound name -> start times, for the voice limit
	var stats := {"played": 0, "dropped": 0}
	var last_play := {}  # the latest sound played: {name, key, at, delay, rate, gain}; tests read it
	var log_plays := false  # keep every play in `plays` as well
	var plays: Array = []
	var cache := {}  # slot -> render result (see Sfx.render)
	var out_gain := Synth.Param.new()  # the effects' master fader: volume, ducked under speech

	var _player: AudioStreamPlayer
	var _playback: AudioStreamPlaybackPolyphonic
	var _pending: Array = []  # sounds waiting for their start time: {due, entry, rate, gain}
	var _jobs: Array = []  # renders in progress: {slot, recorder, render, waiting: [{due, rate, gain}]}
	var _prewarm: Array = []
	var _bus_db := 1.0e9

	func _init(vol := 0.55, opts := {}) -> void:
		volume = vol
		random = opts.get("random", func(): return randf())
		clock = opts.get("clock", Mix.clock)

	## Call from the start of the game (or the first key press on the web: browsers keep audio locked until then).
	## `mixer` (mix.gd) is only needed to share one set of buses with the music; without it the buses are built here.
	func init(_mixer = null) -> void:
		if running:
			return
		Mix.build_buses()
		Self.recipes()
		Synth.noise_table()
		out_gain.set_value_at_time(volume, clock.call())
		var poly := AudioStreamPolyphonic.new()
		poly.polyphony = 64
		_player = AudioStreamPlayer.new()
		_player.stream = poly
		_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		_player.bus = Mix.BUS_SFX
		add_child(_player)
		running = true
		for name in Self.PREWARM:
			var opts: Array = [{}]
			if name == "diceLand":
				opts = [{}, {"tier": "crit"}, {"tier": "fumble"}]
			for o in opts:
				var variants: int = Self.VARIANTS.get(name, 1)
				for k in variants:
					var key := Self.cache_key(name, o)
					_prewarm.append({"slot": key if variants == 1 else "%s#%d" % [key, k], "name": name, "opt": o})
		_apply_gain(clock.call())

	func _process(_delta: float) -> void:
		tick()

	## Per-frame work: sounds whose start time has come, the fader, and a few milliseconds of rendering
	func tick() -> void:
		if not running:
			return
		var now: float = clock.call()
		var i := 0
		while i < _pending.size():
			if _pending[i].due <= now:
				var p: Dictionary = _pending[i]
				_pending.remove_at(i)
				_start(p.entry, p.rate, p.gain)
			else:
				i += 1
		_apply_gain(now)
		_render_some(now)

	func _apply_gain(now: float) -> void:
		var db := linear_to_db(maxf(out_gain.value_at(now), 1e-5))
		if absf(db - _bus_db) > 0.01:
			_bus_db = db
			var idx := AudioServer.get_bus_index(Mix.BUS_SFX)
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, db + Mix.SFX_MAKEUP_DB)

	func play(name: String, opt := {}) -> bool:
		if not on or not running or not Self.has_recipe(name):
			return false
		var now: float = clock.call()
		var delay: float = opt.get("delay", lag)
		var at: float = now + 0.01 + delay
		var near: Array = recent.get(name, []).filter(func(t): return absf(t - at) < Self.POLY_WINDOW)
		if near.size() >= Self.POLY.get(name, Self.POLY["default"]):
			stats.dropped += 1
			return false
		near.append(at)
		recent[name] = near
		stats.played += 1
		var v = Self.VARY.get(name)
		var rate: float = pow(2.0, ((float(random.call()) * 2.0 - 1.0) * v.cents) / 1200.0) if v != null else 1.0
		var gain: float = (1.0 + (float(random.call()) * 2.0 - 1.0) * v.gain if v != null else 1.0) / sqrt(near.size())
		if name == "heartbeat":
			gain *= clampf(float(opt.get("level", 1.0)), 0.0, 1.0)
		elif name.begins_with("voice_"):
			gain *= float(opt.get("vol", 1.0))
		var key := Self.cache_key(name, opt)
		last_play = {"name": name, "key": key, "at": at, "delay": delay, "rate": rate, "gain": gain}
		if log_plays:
			plays.append(last_play)
		if gain <= 0.0 or _player == null:
			return true
		var variants: int = Self.VARIANTS.get(name, 1)
		var slot := key if variants == 1 else "%s#%d" % [key, randi() % variants]
		if cache.has(slot):
			_play_entry(cache[slot], now, delay, rate, gain)
		elif blocking:
			cache[slot] = Self.render(name, opt)
			_play_entry(cache[slot], now, delay, rate, gain)
		else:
			_job_for(slot, name, opt).waiting.append({"due": now + delay, "rate": rate, "gain": gain})
		return true

	func toggle() -> bool:
		on = not on
		return on

	## A monster speaks: pick a voice from the line's wording (RAAH, *hisses*, blorp...) and the species, and play it.
	## At most one shout per `key` (the monster) every 0.8s, and none while sound is off. Returns the plan played, or null.
	func shout(line, species, opts := {}):
		if not on or not running:
			return null
		var plan = Shout.shout_plan(line, species, {"boss": opts.get("boss", false)})
		if plan == null:
			return null
		var key = opts.get("key", species)
		var now: float = clock.call()
		if now - last_shout.get(key, -9.0) < 0.8:
			return null
		last_shout[key] = now
		play("voice_" + plan.kind, plan)
		return plan

	## Duck under a monster's spoken line (see tts.gd): effects drop to half, then come back
	func duck(is_on: bool) -> void:
		if not running:
			return
		out_gain.fade_to(volume * (0.5 if is_on else 1.0), clock.call(), 0.15 if is_on else 0.6)

	## Renders still to do, counting the pre-rendering (tests wait for zero)
	func rendering() -> int:
		return _jobs.size() + _prewarm.size()

	func _job_for(slot: String, name: String, opt: Dictionary) -> Dictionary:
		for j in _jobs:
			if j.slot == slot:
				return j
		var rec := Synth.Recorder.new()
		var p := opt.duplicate()
		p.erase("vol")
		p.erase("level")
		Self.run_recipe(name, rec, 0.0, p)
		var job := {"slot": slot, "name": name, "recorder": rec, "render": Synth.Render.new(), "waiting": []}
		_jobs.append(job)
		return job

	## Renders the oldest waiting job for a few milliseconds, starting the sounds that were waiting for it when it is done
	func _render_some(now: float) -> void:
		if _jobs.is_empty():
			if _prewarm.is_empty():
				return
			var next: Dictionary = _prewarm.pop_front()
			if cache.has(next.slot):
				return
			_job_for(next.slot, next.name, next.opt)
		var urgent := false
		for j in _jobs:
			if not j.waiting.is_empty():
				urgent = true
		var deadline := Time.get_ticks_usec() + int((Self.URGENT_MS if urgent else Self.PREWARM_MS) * 1000.0)
		# jobs with a sound waiting go first
		_jobs.sort_custom(func(a, b): return a.waiting.size() > b.waiting.size())
		var job: Dictionary = _jobs[0]
		if job.recorder.run(job.render, deadline):
			_jobs.remove_at(0)
			cache[job.slot] = job.render.finish()
			cache[job.slot]["name"] = job.name
			for w in job.waiting:
				_play_entry(cache[job.slot], now, maxf(0.0, w.due - now), w.rate, w.gain)

	func _play_entry(entry: Dictionary, now: float, delay: float, rate: float, gain: float) -> void:
		if delay > 0.0:
			_pending.append({"due": now + delay, "entry": entry, "rate": rate, "gain": gain})
		else:
			_start(entry, rate, gain)

	func _start(entry: Dictionary, rate: float, gain: float) -> void:
		if _playback == null:
			if not _player.is_inside_tree():
				return
			if not _player.playing:
				_player.play()
			_playback = _player.get_stream_playback() as AudioStreamPlaybackPolyphonic
			if _playback == null:
				return
		if entry.dry != null:
			_playback.play_stream(entry.dry, 0.0, linear_to_db(entry.dry_gain * gain), rate, AudioServer.PLAYBACK_TYPE_STREAM, Mix.BUS_SFX)
		if entry.send != null:
			_playback.play_stream(entry.send, 0.0, linear_to_db(entry.send_gain * gain * Self.ROOM_WET), rate, AudioServer.PLAYBACK_TYPE_STREAM, Mix.BUS_ROOM)
