## The game's sound effects: a name for each thing that happens, a recipe for each name, built from a few primitives
## (src/audio/synth.gd): pitched tones with envelopes, filtered noise bursts, and a formant "vocal". Nothing is a file.
## A recipe is rendered once into a dry stream and a room send, kept, and played through one polyphonic player; the
## send goes to the room's reverb bus (mix.gd). They are rendered over the frames after the start, a few
## milliseconds each, so the first hit of a fight does not stall the game. A sound is a little different every time
## (VARY), and the same one cannot pile up (POLY).
extends Node

const Mix = preload("res://src/audio/mix.gd")
const Shout = preload("res://src/audio/shout.gd")
const Synth = preload("res://src/audio/synth.gd")

## Sounds you hear over and over get a little different each time: a random detune up to +/- `cents` and a volume up to
## +/- `gain`, so ten sword hits in a row sound like ten hits, not one sample on repeat.
const VARY := {
	"hit": {"cents": 110, "gain": 0.12},
	"crit": {"cents": 50, "gain": 0.08},
	"miss": {"cents": 180, "gain": 0.15},
	"hurt": {"cents": 90, "gain": 0.12},
	"kill": {"cents": 70, "gain": 0.08},
	"bump": {"cents": 140, "gain": 0.15},
	"slash": {"cents": 100, "gain": 0.1},
	"tick": {"cents": 40, "gain": 0.1},
	"stairs": {"cents": 50, "gain": 0.08},
	"step": {"cents": 120, "gain": 0.12},
	"creep": {"cents": 160, "gain": 0.15},
}
## Voice limit: at most this many copies of one sound may start within POLY_WINDOW seconds of each other (a dodge round
## can land several hazards at once). The rest are dropped, and the ones that play are each a little quieter, so a
## pile-up sounds bigger without clipping.
const POLY := {"default": 4, "hit": 3, "crit": 2, "miss": 2, "hurt": 2, "kill": 2, "tick": 1, "bump": 1}
const POLY_WINDOW := 0.06
## Recipes with a dice roll in them are rendered this many times, and a variant is picked per play.
const VARIANTS := {"voice_squelch": 3, "voice_babble": 4, "voice_zap": 3}
## Only these voices change with the number of syllables in the line.
const SYLLABLE_VOICES := ["voice_bark", "voice_squelch", "voice_babble"]
## What the game calls a sound -> the recipe that makes it, where they differ.
const ALIASES := {
	"strike": "hit", "slain": "kill", "spared": "good", "recruited": "join", "ally_left": "sad", "dead": "death",
	"shield": "buff",
}
## Rendered ahead of time, in this order, a few milliseconds per frame (voices depend on the monster and render when first needed).
const PREWARM := [
	"hit", "miss", "crit", "hurt", "kill", "bump", "tick", "slash", "stairs", "good", "bad", "death", "holy", "buff", "sad", "odd",
	"join", "chime", "encounter", "boss", "flee", "step", "alert", "creep", "beat", "move", "pick", "mercy_refused", "shout",
]
const PREWARM_MS := 4.0 # per frame for background rendering...
const URGENT_MS := 10.0 # ...and per frame while a sound is waiting for its render
## The room the sounds sit in, as a share of each voice sent to the reverb.
const ROOM_WET := 0.22
const POLYPHONY := 64

## False with the `nosfx` flag: nothing plays.
var enabled := true
## () -> seconds, the clock the limits run on (tests drive it).
var clock: Callable = func(): return Time.get_ticks_usec() / 1000000.0
## () -> float in [0, 1)
var random: Callable = func(): return randf()
## Render a missing sound on the spot instead of over the next frames (tests, dumps).
var blocking := false
## The latest sound played: {name, key, at, rate, gain}.
var last_play := {}
var stats := {"played": 0, "dropped": 0}

var _player: AudioStreamPlayer
var _playback: AudioStreamPlaybackPolyphonic
var _cache := {} # slot -> a render result (see `render`)
var _recent := {} # recipe -> start times, for the voice limit
var _last_shout := {} # monster -> when it last shouted
var _jobs: Array = [] # renders in progress: {slot, name, recorder, render, waiting: [{rate, gain}]}
var _prewarm: Array = []


static var _recipes := {}


## name -> the recipe function, in the order of this file. A recipe is `(s, t, o)`: draw on `s` starting at `t` seconds;
## `o` is a voice's plan.
static func recipes() -> Dictionary:
	if _recipes.is_empty():
		_recipes = {
			"hit": snd_hit, "crit": snd_crit, "miss": snd_miss, "hurt": snd_hurt, "kill": snd_kill, "death": snd_death,
			"holy": snd_holy, "buff": snd_buff, "slash": snd_slash,
			"good": snd_good, "bad": snd_bad, "sad": snd_sad, "odd": snd_odd, "join": snd_join, "chime": snd_chime,
			"encounter": snd_encounter, "boss": snd_boss, "flee": snd_flee, "bump": snd_bump, "stairs": snd_stairs,
			"tick": snd_tick,
			"voice_roar": snd_voice_roar, "voice_bark": snd_voice_bark, "voice_grunt": snd_voice_grunt,
			"voice_growl": snd_voice_growl, "voice_hiss": snd_voice_hiss, "voice_squelch": snd_voice_squelch,
			"voice_laugh": snd_voice_laugh, "voice_squeal": snd_voice_squeal, "voice_whimper": snd_voice_whimper,
			"voice_sigh": snd_voice_sigh, "voice_rumble": snd_voice_rumble, "voice_zap": snd_voice_zap,
			"voice_babble": snd_voice_babble,
			"step": snd_step, "alert": snd_alert, "creep": snd_creep, "beat": snd_beat, "mercy_refused": snd_mercy_refused, "shout": snd_shout,
			"move": snd_move, "pick": snd_pick,
		}
	return _recipes


## The recipe a game sound name is made by ("strike" is the "hit" recipe).
static func recipe_of(name: String) -> String:
	return ALIASES.get(name, name)


static func has_recipe(name: String) -> bool:
	return recipes().has(recipe_of(name))


## Renders a sound once. `o` is the voice plan; levels (`level`, a voice's `vol`) are applied by the player as gain.
## {seconds, dry, dry_gain, send, send_gain, peak, name} (see Synth.Render.finish)
static func render(name: String, o := {}) -> Dictionary:
	var s := Synth.Render.new()
	var p := o.duplicate()
	p.erase("vol")
	p.erase("level")
	recipes()[recipe_of(name)].call(s, 0.0, p)
	var out := s.finish()
	out["name"] = name
	return out


## What one play of a sound is called in the cache: the recipe plus whatever of its options changes the render.
## A voice's volume is applied at play time (every `vol` in a voice recipe is a plain factor), so it is not part of the key.
static func cache_key(name: String, o: Dictionary) -> String:
	var recipe := recipe_of(name)
	if recipe.begins_with("voice_"):
		var p := _plan(o)
		return "%s|%.1f|%.3f|%.3f|%d|%d" % [recipe, p.f0, p.size, p.rasp, 1 if p.wet else 0, p.syll if recipe in SYLLABLE_VOICES else 0]
	return recipe


func _ready() -> void:
	if not enabled:
		return
	Mix.build_buses()
	Synth.noise_table()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = POLYPHONY
	_player = AudioStreamPlayer.new()
	_player.stream = poly
	_player.bus = Mix.SFX
	add_child(_player)
	for name in PREWARM:
		var variants: int = VARIANTS.get(name, 1)
		for k in variants:
			_prewarm.append({"slot": cache_key(name, {}) if variants == 1 else "%s#%d" % [cache_key(name, {}), k], "name": name, "opt": {}})
	print_verbose("sfx: %d sounds to render ahead" % _prewarm.size())


func _process(_delta: float) -> void:
	tick()


## Per-frame work: a few milliseconds of rendering, starting the sounds that were waiting for it when one is done.
func tick() -> void:
	if _player == null:
		return
	if _jobs.is_empty():
		if _prewarm.is_empty():
			return
		var next: Dictionary = _prewarm.pop_front()
		if _cache.has(next.slot):
			return
		_job_for(next.slot, next.name, next.opt)
	var urgent := false
	for j in _jobs:
		if not j.waiting.is_empty():
			urgent = true
	var deadline := Time.get_ticks_usec() + int((URGENT_MS if urgent else PREWARM_MS) * 1000.0)
	_jobs.sort_custom(func(a, b): return a.waiting.size() > b.waiting.size()) # jobs with a sound waiting go first
	var job: Dictionary = _jobs[0]
	if job.recorder.run(job.render, deadline):
		_jobs.remove_at(0)
		_cache[job.slot] = job.render.finish()
		_cache[job.slot]["name"] = job.name
		print_verbose("sfx: made '%s'" % job.slot)
		for w in job.waiting:
			_start(_cache[job.slot], w.rate, w.gain)


## Renders still to do, counting the pre-rendering (tests wait for zero).
func rendering() -> int:
	return _jobs.size() + _prewarm.size()


## Play a named effect. `opt.db` adjusts the loudness; a voice also takes its plan from Shout. An unknown name is
## reported, so a typo can't silently be silent. Returns false if nothing started.
func play(sound: String, opt := {}) -> bool:
	if not enabled:
		return false
	if not has_recipe(sound):
		push_error("sfx: no sound called '%s'" % sound)
		return false
	var recipe := recipe_of(sound)
	var now: float = clock.call()
	var at := now + 0.01
	var near: Array = _recent.get(recipe, []).filter(func(t): return absf(t - at) < POLY_WINDOW)
	if near.size() >= POLY.get(recipe, POLY["default"]):
		stats.dropped += 1
		print_verbose("sfx: '%s' dropped (%d already playing)" % [sound, near.size()])
		return false
	near.append(at)
	_recent[recipe] = near
	stats.played += 1
	var v = VARY.get(recipe)
	var rate: float = pow(2.0, ((float(random.call()) * 2.0 - 1.0) * v.cents) / 1200.0) if v != null else 1.0
	var gain: float = (1.0 + (float(random.call()) * 2.0 - 1.0) * v.gain if v != null else 1.0) / sqrt(near.size())
	if recipe.begins_with("voice_"):
		gain *= float(opt.get("vol", 1.0))
	gain *= db_to_linear(float(opt.get("db", 0.0)))
	var key := cache_key(sound, opt)
	last_play = {"name": sound, "key": key, "at": at, "rate": rate, "gain": gain}
	if _player == null:
		return true
	var variants: int = VARIANTS.get(recipe, 1)
	var slot := key if variants == 1 else "%s#%d" % [key, randi() % variants]
	if _cache.has(slot):
		_start(_cache[slot], rate, gain)
	elif blocking:
		_cache[slot] = render(sound, opt)
		_start(_cache[slot], rate, gain)
	else:
		_job_for(slot, sound, opt).waiting.append({"rate": rate, "gain": gain})
	return true


## A monster speaks: pick a voice from the line's wording (RAAH, *hisses*, blorp...) and the species, and play it.
## At most one shout per `key` (the monster) every 0.8 s. Returns the plan played, or null (a line that makes no sound,
## a monster that just shouted, or the effects off).
func shout(line, species, opts := {}):
	if not enabled:
		return null
	var plan = Shout.shout_plan(line, species, {"boss": opts.get("boss", false)})
	if plan == null:
		print_verbose("sfx: '%s' makes no sound" % line)
		return null
	var key = opts.get("key", species)
	var now: float = clock.call()
	if now - _last_shout.get(key, -9.0) < 0.8:
		return null
	_last_shout[key] = now
	print_verbose("sfx: %s says %s" % [species, plan.kind])
	play("voice_" + plan.kind, plan)
	return plan


func _job_for(slot: String, name: String, opt: Dictionary) -> Dictionary:
	for j in _jobs:
		if j.slot == slot:
			return j
	var rec := Synth.Recorder.new()
	var p := opt.duplicate()
	p.erase("vol")
	p.erase("level")
	recipes()[recipe_of(name)].call(rec, 0.0, p)
	var job := {"slot": slot, "name": name, "recorder": rec, "render": Synth.Render.new(), "waiting": []}
	_jobs.append(job)
	return job


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
		_playback.play_stream(entry.dry, 0.0, linear_to_db(entry.dry_gain * gain), rate, AudioServer.PLAYBACK_TYPE_STREAM, Mix.SFX)
	if entry.send != null:
		_playback.play_stream(entry.send, 0.0, linear_to_db(entry.send_gain * gain * ROOM_WET), rate, AudioServer.PLAYBACK_TYPE_STREAM, Mix.ROOM)


## MIDI note number -> Hz
static func note(n: float) -> float:
	return Synth.note(n)


## The monster voice plan with every field present (a plan from Shout.shout_plan, or just the parts a test gives).
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


static func snd_death(s, t, _o = {}):
	s.tone(t, {f0 = note(38), dur = 2.2, vol = 0.35, attack = 0.01, room = 1})
	s.tone(t, {f0 = note(50) * 1.003, dur = 1.8, vol = 0.12, room = 1})
	s.tone(t, {type = "triangle", f0 = note(57), f1 = note(45), dur = 1.4, vol = 0.12, room = 1})


static func snd_holy(s, t, _o = {}):
	var notes := [76, 83, 88]
	for i in notes.size():
		s.tone(t + i * 0.03, {f0 = note(notes[i]), dur = 0.9, vol = 0.12, attack = 0.05, room = 1, vibrato = {rate = 6, depth = 4}})


## The slime's charm taking a hit (the game calls it "shield").
static func snd_buff(s, t, _o = {}):
	var notes := [72, 79, 84]
	for i in notes.size():
		s.tone(t + i * 0.05, {type = "triangle", f0 = note(notes[i]), dur = 0.7, vol = 0.1, attack = 0.08, room = 1, vibrato = {rate = 5, depth = 3}})


static func snd_slash(s, t, _o = {}):
	s.noise(t, {dur = 0.25, vol = 0.4, f0 = 6000, f1 = 500, q = 3, attack = 0.01, room = 0.4})
	s.tone(t + 0.05, {type = "sawtooth", f0 = 160, f1 = 70, dur = 0.5, vol = 0.12, lp = [1200, 300], room = 0.6})


# ---- Talking and feelings

static func snd_good(s, t, _o = {}):
	s.tone(t, {type = "triangle", f0 = note(76), dur = 0.25, vol = 0.16, room = 0.6})
	s.tone(t + 0.1, {type = "triangle", f0 = note(83), dur = 0.45, vol = 0.16, room = 0.7})


static func snd_bad(s, t, _o = {}):
	s.tone(t, {type = "sawtooth", f0 = 75, f1 = 62, dur = 0.6, vol = 0.18, lp = [400, 900], vibrato = {rate = 9, depth = 6}, room = 0.4})
	s.tone(t, {type = "sawtooth", f0 = 106, f1 = 88, dur = 0.6, vol = 0.1, lp = [500, 1000], room = 0.4})


static func snd_sad(s, t, _o = {}):
	s.tone(t, {type = "triangle", f0 = note(70), f1 = note(65), dur = 0.8, vol = 0.12, attack = 0.05, room = 0.9})


static func snd_odd(s, t, _o = {}):
	s.tone(t, {f0 = 300, f1 = 900, dur = 0.12, vol = 0.15, room = 0.3})
	s.tone(t + 0.12, {f0 = 900, f1 = 220, dur = 0.3, vol = 0.13, room = 0.5, vibrato = {rate = 18, depth = 40}})


static func snd_chime(s, t, _o = {}):
	s.tone(t, {type = "sine", f0 = note(84), dur = 0.5, vol = 0.14, room = 0.7})
	s.tone(t + 0.12, {type = "sine", f0 = note(91), dur = 0.7, vol = 0.12, room = 0.8})


static func snd_join(s, t, _o = {}):
	s.arp(t, [67, 71, 74, 79, 83, 86], {step = 0.08, type = "square", dur = 0.3, vol = 0.06})
	s.arp(t + 0.48, [79, 83, 86, 91], {step = 0, type = "triangle", dur = 0.9, vol = 0.08})


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


## A monster has seen you: two quick notes going up.
static func snd_alert(s, t, _o = {}):
	s.tone(t, {type = "square", f0 = 520, dur = 0.07, vol = 0.14, lp = [3000], room = 0.3})
	s.tone(t + 0.08, {type = "square", f0 = 780, dur = 0.12, vol = 0.14, lp = [3000], room = 0.3})


## A monster in sight has taken a step: soft, so one a step doesn't tire.
static func snd_creep(s, t, _o = {}):
	s.noise(t, {dur = 0.05, vol = 0.06, f0 = 500, f1 = 200, q = 1, room = 0.4})


static func snd_stairs(s, t, _o = {}):
	for i in 4:
		s.tone(t + i * 0.13, {f0 = 120 - i * 12, f1 = 70 - i * 6, dur = 0.1, vol = 0.3, room = 0.5})


static func snd_tick(s, t, _o = {}):
	s.tone(t, {type = "square", f0 = 1400, dur = 0.03, vol = 0.05, lp = [4000], room = 0.2})


# ---- Only in the 3D game since the rewrite

static func snd_step(s, t, _o = {}):
	s.noise(t, {dur = 0.06, vol = 0.18, type = "lowpass", f0 = 700, room = 0.1})


## The rhythm round's beat.
static func snd_beat(s, t, _o = {}):
	s.tone(t, {f0 = 90, f1 = 55, dur = 0.09, vol = 0.45, room = 0.05})


static func snd_mercy_refused(s, t, _o = {}):
	s.tone(t, {type = "square", f0 = 180, f1 = 150, dur = 0.15, vol = 0.25, room = 0.2})
	s.tone(t + 0.14, {type = "square", f0 = 150, f1 = 120, dur = 0.2, vol = 0.25, room = 0.2})


## A monster's two-note blip.
static func snd_shout(s, t, _o = {}):
	s.tone(t, {type = "square", f0 = 300, f1 = 340, dur = 0.05, vol = 0.12, room = 0.2})
	s.tone(t + 0.07, {type = "square", f0 = 360, f1 = 300, dur = 0.06, vol = 0.12, room = 0.2})


## The menu cursor moving, and a choice confirmed.
static func snd_move(s, t, _o = {}):
	s.tone(t, {type = "square", f0 = 440, dur = 0.03, vol = 0.12, room = 0.1})


static func snd_pick(s, t, _o = {}):
	s.tone(t, {type = "square", f0 = 660, f1 = 880, dur = 0.07, vol = 0.15, room = 0.1})


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
	var top: float = 0.8 + 0.2 * minf(1.0, p.size) # bigger snakes hiss lower
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


## Plain speech: a few vowel syllables with a falling sentence tune, in the species' voice.
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
