## Checks what you hear, with no window and no speakers: every sound the game asks for has a recipe and renders at
## 44.1 kHz, the right events call for the right sounds (a recording fake stands in for the effects and the music), the
## menu cursor ticks, the buses are built with a limiter on Master, the music paces itself and never races its own
## fades, and a monster's line finds its recording. Prints one line per check and exits with 1 if any failed.
## It builds the audio buses, so run it without `nosound`:
##   godot --headless --path . -s res://tools/audio_test.gd -- nosave
extends "res://tools/test_base.gd"

const Audio = preload("res://src/audio/audio.gd")
const Content = preload("res://src/rules/content.gd")
const Events = preload("res://src/game/events.gd")
const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const Minds = preload("res://src/mind/minds.gd")
const Mix = preload("res://src/audio/mix.gd")
const Music = preload("res://src/audio/music.gd")
const Rng = preload("res://src/utils/rng.gd")
const Sfx = preload("res://src/audio/sfx.gd")
const Shout = preload("res://src/audio/shout.gd")
const Synth = preload("res://src/audio/synth.gd")
const Voices = preload("res://src/audio/voices.gd")

## The effects BEFORE the rewrite could play from the 3D scene, under the names the game uses now.
const REACHABLE := [
	"strike", "hit", "crit", "miss", "hurt", "slain", "spared", "bump", "tick", "slash", "holy", "shield", "stairs",
	"encounter", "boss", "dead", "flee", "good", "bad", "odd", "ally_left", "recruited",
]
const VOICE_KINDS := ["roar", "bark", "grunt", "growl", "hiss", "squelch", "laugh", "squeal", "whimper", "sigh", "rumble", "zap", "babble"]
const NOW_ONLY := ["step", "beat", "mercy_refused", "shout", "move", "pick"]
## The kinds of line the bank was rendered for, which must keep finding their recordings.
const RENDERED_KINDS := [
	"attack", "special", "defend", "flee", "converse", "not_ready", "demand_tribute", "accept_tribute", "refuse_tribute",
	"join_party", "leave_peacefully", "attack_monster",
]
## The kinds written since, which the synthesised voice says until tools/voices renders them; then they move to the list above.
const AWAITING_RENDER := ["pleased", "stung", "hurt", "scared", "puzzled", "kin_spared", "kin_slain", "side_spared", "side_slain"]


## Stands in for the effects: remembers what it was asked to play.
class FakeSfx:
	extends RefCounted
	var enabled := true
	var played: Array = []
	var shouts: Array = []

	func play(sound: String, _opt := {}) -> bool:
		played.append(sound)
		return true

	func shout(line, species, opts := {}):
		shouts.append({"line": line, "species": species, "boss": opts.get("boss", false)})
		return null

	func clear() -> void:
		played = []
		shouts = []


## Stands in for the music: remembers what it was asked to do.
class FakeMusic:
	extends RefCounted
	var calls: Array = []

	func set_mode(mode: String) -> void:
		calls.append("mode:" + mode)

	func sting(name: String) -> void:
		calls.append("sting:" + name)

	func duck(on: bool) -> void:
		calls.append("duck:" + str(on))

	func clear() -> void:
		calls = []


func _name() -> String:
	return "audio_test"


func _run() -> void:
	Flags.set_args(PackedStringArray(["nosave", "seed=7"]))
	Mix.build_buses()
	_every_name_has_a_recipe()
	_recipes_render()
	_voices_render()
	await _prewarm_and_limits()
	await _events_call_for_sounds()
	await _menu_keys_tick()
	_master_has_its_limiter()
	_flags_exist()
	_shout_plans()
	_voice_keys()
	await _music_pacing()
	await _music_fades()
	await _motifs()
	_finish()


# ---------------------------------------------------------------- the names

## Every sound name a game file hands to the sound event, or maps to one.
func _emitted_names() -> Dictionary:
	var names := {}
	var named := RegEx.create_from_string("\"name\":\\s*\"(\\w+)\"")
	var pair := RegEx.create_from_string("\"\\w+\":\\s*\"(\\w+)\"") # the hazards' table: "stomp": "hit"
	for path in _gd_files("res://src"):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if path.begins_with("res://src/audio/") or not line.to_lower().contains("sound"):
				continue
			for m in (pair if line.contains("\"type\": \"sound\"") else named).search_all(line):
				if m.get_string(1) != "sound":
					names[m.get_string(1)] = path
	for sound in Audio.SOUNDS.values():
		names[sound] = "audio.gd SOUNDS"
	return names


func _gd_files(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


func _every_name_has_a_recipe() -> void:
	var names := _emitted_names()
	var missing := []
	for n in names:
		if not Sfx.has_recipe(n):
			missing.append("%s (%s)" % [n, names[n]])
	_check(names.size() >= 12, "the scan of src finds the sound names the game emits (%d)" % names.size())
	_check(missing.is_empty(), "every sound name in src has a recipe (missing: %s)" % [missing])
	for n in ["good", "bad", "odd", "flee", "crit", "move", "pick"]:
		_check(Sfx.has_recipe(n), "'%s' has a recipe" % n)
	var lacking := []
	for n in REACHABLE + NOW_ONLY:
		if not Sfx.has_recipe(n):
			lacking.append(n)
	_check(lacking.is_empty(), "every effect BEFORE could play, and every one added since, has a recipe (lacking: %s)" % [lacking])


func _recipes_render() -> void:
	_check(Synth.RATE == 44100, "effects are rendered at 44.1 kHz")
	var bad := []
	for n in REACHABLE + NOW_ONLY:
		var r := Sfx.render(Sfx.recipe_of(n))
		var peak: float = r.get("peak", 0.0)
		if r.get("dry") == null or peak <= 0.0001 or float(r.seconds) > 3.0 or r.dry.mix_rate != Synth.RATE:
			bad.append("%s (peak %.4f, %.2f s)" % [n, peak, float(r.get("seconds", 0.0))])
	_check(bad.is_empty(), "every effect renders: audible, under 3 s, 44.1 kHz (bad: %s)" % [bad])
	var boss := Sfx.render("boss")
	var tick := Sfx.render("tick")
	_check(float(boss.seconds) > 2.0 and float(tick.seconds) < 0.1, "BEFORE's lengths: the boss drone is %.2f s, the tick %.3f s" % [boss.seconds, tick.seconds])
	_check(boss.send != null and tick.send != null, "a recipe with a room send keeps it for the reverb bus")


func _voices_render() -> void:
	var bad := []
	for k in VOICE_KINDS:
		_check(Sfx.has_recipe("voice_" + k), "voice_%s has a recipe" % k)
		var r := Sfx.render("voice_" + k, {"f0": 130.0, "size": 1.0, "rasp": 0.3, "wet": false, "syll": 3})
		if r.dry == null or float(r.peak) <= 0.0001:
			bad.append(k)
	_check(bad.is_empty(), "all 13 voice kinds render (bad: %s)" % [bad])


# ---------------------------------------------------------------- the effects node

func _prewarm_and_limits() -> void:
	var sfx := Sfx.new()
	var t := [100.0]
	sfx.clock = func(): return t[0]
	root.add_child(sfx)
	await process_frame
	_check(sfx.rendering() > 0, "the effects are rendered over the frames after the start, not all in the first (%d waiting)" % sfx.rendering())
	var frames := 0
	while sfx.rendering() > 0 and frames < 2000:
		await process_frame
		frames += 1
	_check(sfx.rendering() == 0, "the prewarm finishes by itself (%d frames)" % frames)
	sfx.blocking = true
	var played := 0
	for i in 6:
		if sfx.play("hit"):
			played += 1
	_check(played == Sfx.POLY["hit"], "six hits at once: only %d start (POLY), %d did" % [Sfx.POLY["hit"], played])
	t[0] += 1.0
	_check(sfx.play("hit"), "a second later a hit starts again")
	var rates := {}
	for i in 12:
		t[0] += 1.0
		sfx.play("miss")
		rates[snappedf(sfx.last_play.rate, 0.0001)] = true
	_check(rates.size() > 6, "VARY: the same sound is a little different each time (%d distinct pitches in 12)" % rates.size())
	var other := Sfx.new()
	other.enabled = false
	root.add_child(other)
	_check(not other.play("hit"), "with the effects off (nosfx) nothing plays")
	var plan = sfx.shout("RAAH! *swings a club*", "dragon", {"key": "d1", "boss": true})
	_check(plan != null and plan.kind == "roar", "a monster's shout plays its voice")
	_check(sfx.shout("RAAH again!", "dragon", {"key": "d1"}) == null, "the same monster is held to one shout per 0.8 s")
	t[0] += 1.0
	_check(sfx.shout("RAAH again!", "dragon", {"key": "d1"}) != null, "...and may shout again after that")
	_check(sfx.shout("*stares at you*", "dragon", {"key": "d2"}) == null, "a stage direction with no sound stays silent")
	sfx.queue_free()
	other.queue_free()


# ---------------------------------------------------------------- events -> sounds

func _fresh_audio() -> Node:
	var audio = Audio.new()
	root.add_child(audio)
	return audio


func _fake(audio) -> Array:
	audio._sfx.queue_free()
	audio._music.queue_free()
	var sfx := FakeSfx.new()
	var music := FakeMusic.new()
	audio._sfx = sfx
	audio._music = music
	return [sfx, music]


func _data_for(name: String, boss: bool, crit: bool) -> Dictionary:
	var out := {}
	for f in Events.FIELDS[name]:
		out[f] = {"boss": boss, "crit": crit, "damage": 3, "text": "RAAH!", "species": "slime", "from": "menu", "to": "explore", "name": "hit"}.get(f, "x")
	return out


func _events_call_for_sounds() -> void:
	var audio = _fresh_audio()
	await process_frame
	var f := _fake(audio)
	var sfx: FakeSfx = f[0]
	var music: FakeMusic = f[1]
	# every event, with every flag, only ever asks for a sound that exists
	var asked := {}
	for name in Events.FIELDS:
		for boss in [false, true]:
			for crit in [false, true]:
				sfx.clear()
				audio._on_event(name, _data_for(name, boss, crit))
				for s in sfx.played:
					asked[s] = name
	var missing := []
	for s in asked:
		if not Sfx.has_recipe(s):
			missing.append("%s (from %s)" % [s, asked[s]])
	_check(missing.is_empty(), "no event asks for a sound without a recipe (%s)" % [missing])
	var silent := []
	for name in _emitted_names():
		sfx.clear()
		audio._on_event("sound", {"name": name})
		if sfx.played != [name]:
			silent.append(name)
	_check(silent.is_empty(), "the sound event plays every name the game sends it (silent: %s)" % [silent])
	# the swing
	sfx.clear()
	audio._on_event("strike", {"damage": 4, "crit": true})
	_check(sfx.played == ["crit"], "a critical strike plays crit, not strike (%s)" % [sfx.played])
	sfx.clear()
	audio._on_event("strike", {"damage": 4, "crit": false})
	_check(sfx.played == ["strike"], "an ordinary strike plays strike (%s)" % [sfx.played])
	# victory on every spared and slain, fanfare at the stairs and only there
	for name in ["spared", "slain"]:
		for boss in [false, true]:
			music.clear()
			audio._on_event(name, {"boss": boss})
			_check(music.calls == ["sting:victory"], "%s%s: the victory sting (%s)" % [name, " (champion)" if boss else "", music.calls])
	music.clear()
	sfx.clear()
	audio._on_event("stairs", {})
	_check(music.calls == ["sting:fanfare"] and sfx.played == ["stairs"], "the stairs: the fanfare and the stairs effect (%s %s)" % [music.calls, sfx.played])
	sfx.clear()
	audio._on_event("menu_move", {})
	audio._on_event("menu_pick", {})
	_check(sfx.played == ["move", "pick"], "the menu cursor plays move and a confirm plays pick (%s)" % [sfx.played])
	# a line with a recording is played and the music ducks; one without goes to the synth voice, once
	var known := _first_recorded_line()
	music.clear()
	audio._on_event("shout", {"text": known.text, "species": known.species, "boss": false})
	_check(audio._voice.stream != null and music.calls == ["duck:true"], "a recorded line is played and the music ducks under it (%s)" % [music.calls])
	_check(sfx.shouts.is_empty(), "...and the synth voice stays out of it")
	audio._voice.stop()
	audio._on_voice_done()
	_check(music.calls.back() == "duck:false", "when the line ends the music comes back")
	audio._voice.stream = null
	audio._on_event("shout", {"text": "RAAH! *swings a club*", "species": "bandit", "boss": true})
	_check(sfx.shouts.size() == 1 and sfx.shouts[0].boss and audio._voice.stream == null, "a line with no recording is handed to the synth voice, with the champion flag")
	# nosfx and nomusic
	audio.queue_free()
	Flags.set_args(PackedStringArray(["nosave", "nomusic"]))
	var no_music = _fresh_audio()
	await process_frame
	_check(not no_music._music.enabled and no_music._sfx.enabled, "nomusic: the music is off and the effects are on")
	no_music._music.set_mode("explore")
	_check(no_music._music.loop_player("explore") == null, "nomusic: no loop is started")
	no_music.queue_free()
	Flags.set_args(PackedStringArray(["nosave", "nosfx"]))
	var no_sfx = _fresh_audio()
	await process_frame
	_check(no_sfx._music.enabled and not no_sfx._sfx.enabled, "nosfx: the effects are off and the music is on")
	no_sfx.queue_free()
	Flags.set_args(PackedStringArray(["nosave", "seed=7"]))
	await process_frame


func _first_recorded_line() -> Dictionary:
	for species in ["bandit", "dragon", "slime", "snake", "rock"]:
		for kind in Content.species(species).lines:
			for line in Content.species(species).lines[kind]:
				var text: String = Content.fill(line, {"name": "Rook", "target": "you"})
				if Voices.find(species, text) != null:
					return {"species": species, "text": text}
	return {"species": "bandit", "text": "no such line"}


## The real menu: up/down emit menu_move, a confirm and a digit emit menu_pick, and the Audio hears them.
func _menu_keys_tick() -> void:
	var rng := Rng.new(7)
	var flow = Flow.new(rng, Minds.create(rng, "", true))
	await flow.new_run()
	var heard := []
	flow.happened.connect(func(name, _d): heard.append(name))
	var audio = _fresh_audio()
	var f := _fake(audio)
	flow.happened.connect(audio._on_event)
	await flow.go("intro", {"foe": flow.state.floor_map.monsters[0]})
	var clock := 0.0
	for i in 100:
		if flow.state.stage == "menu":
			break
		clock += 100.0
		await flow.tick(clock)
	_check(flow.state.stage == "menu", "a fight reaches its menu")
	heard.clear()
	f[0].clear()
	await flow.press("down")
	await flow.press("up")
	_check(heard == ["menu_move", "menu_move"], "up and down in the fight menu announce a cursor move (%s)" % [heard])
	_check(f[0].played == ["move", "move"], "...and the audio plays move for each (%s)" % [f[0].played])
	heard.clear()
	await flow.press("2")
	_check(heard.has("menu_pick"), "a digit announces a pick (%s)" % [heard])
	await flow.press("cancel") # back to the fight menu
	for i in 5:
		if flow.state.stage == "menu":
			break
		await flow.press("cancel")
		await flow.tick(clock)
	heard.clear()
	if flow.state.stage == "menu":
		await flow.press("confirm")
		_check(heard.has("menu_pick"), "confirm announces a pick (%s)" % [heard])
	_check(f[0].played.has("pick"), "...and pick for the confirm (%s)" % [f[0].played])
	flow.happened.disconnect(audio._on_event)
	audio.queue_free()


# ---------------------------------------------------------------- the desk

func _master_has_its_limiter() -> void:
	Mix.build_buses()
	Mix.build_buses() # twice: still one of each
	var kinds := []
	for i in AudioServer.get_bus_effect_count(0):
		kinds.append(AudioServer.get_bus_effect(0, i).get_class())
	_check(kinds == ["AudioEffectCompressor", "AudioEffectHardLimiter"], "Master has a compressor and then a hard limiter (%s)" % [kinds])
	var comp := AudioServer.get_bus_effect(0, 0) as AudioEffectCompressor
	_check(comp != null and comp.ratio == 12.0 and comp.threshold == -6.0, "the compressor is -6 dB at 12:1")
	var lim := AudioServer.get_bus_effect(0, 1) as AudioEffectHardLimiter
	_check(lim != null and lim.ceiling_db == -0.5, "the limiter's ceiling is -0.5 dB")
	var routes := {}
	for b in [Mix.MUSIC_IN, Mix.MUSIC, Mix.SFX, Mix.ROOM]:
		var idx := AudioServer.get_bus_index(b)
		routes[b] = String(AudioServer.get_bus_send(idx)) if idx >= 0 else "(no bus)"
	_check(routes == {"MusicIn": "Music", "Music": "Master", "SFX": "Master", "SFXRoom": "SFX"}, "the buses: MusicIn into Music, SFXRoom into SFX (%s)" % [routes])
	var room := AudioServer.get_bus_index(Mix.ROOM)
	_check(room >= 0 and AudioServer.get_bus_effect(room, 0) is AudioEffectReverb, "the room bus is a reverb")
	var count := AudioServer.bus_count
	Mix.build_buses()
	_check(AudioServer.bus_count == count, "building the buses again adds none")


func _flags_exist() -> void:
	for n in ["nomusic", "nosfx", "nosound"]:
		_check(Flags.KNOWN.has(n), "the flag '%s' is declared" % n)


# ---------------------------------------------------------------- voices

func _shout_plans() -> void:
	var plain = Shout.shout_plan("RAAH! *swings*", "dragon")
	var boss = Shout.shout_plan("RAAH! *swings*", "dragon", {"boss": true})
	_check(plain != null and boss != null and is_equal_approx(boss.f0, plain.f0 * 0.85) and is_equal_approx(boss.vol, plain.vol * 1.1), "a champion's voice is 15% lower and 10% louder")
	_check(Shout.shout_plan("*stares at you*", "bandit") == null, "a stage direction with no sound has no voice")
	_check(Shout.shout_plan("...bloop?", "slime").kind == "squelch", "a slime's bloop is a squelch")
	_check(Shout.shout_plan("*hisses softly*", "snake").kind == "hiss", "a snake's hiss is a hiss")
	var kinds := {}
	for line in ["RAAH!", "Grrr.", "ugh.", "sssso", "*blorp*", "hahaha", "*screeches*", "*whimpers*", "*sighs*", "*the ground rumbles*", "*lightning crackles*", "come here, little one", "WHAT?!"]:
		kinds[Shout.shout_plan(line, "bandit").kind] = true
	_check(kinds.size() >= 9, "the classifier tells many kinds apart (%d of 13 in 13 lines)" % kinds.size())
	_check(Shout.KINDS == VOICE_KINDS, "the classifier has the 13 kinds the synth can voice")


func _voice_keys() -> void:
	_check(Voices._key("*hisses* ...Hello {target}!") == Voices._key("Hello you!".replace("you", "{target}")), "stage directions, dots and braces are not part of the key")
	_check(Voices._key("  Hi,   THERE. ") == "hi, there.", "the key is lower case with single spaces")
	_check(Voices._key("You lied to Tringus. ...fine.") == "you lied to tringus., fine.", "'...' becomes ', ' as the bank was filed (%s)" % Voices._key("You lied to Tringus. ...fine."))
	# the roster as the game fills it in: every name, "you" as the target. A line that is only a stage direction has no
	# words to record; the synthesised voice takes it.
	var spoken := 0
	var found := 0
	var stage_only := 0
	var waiting := 0
	var unknown_kinds := {}
	var unrecorded := []
	for species in ["bandit", "dragon", "slime", "snake", "rock"]:
		var sp := Content.species(species)
		for kind in sp.lines:
			if kind in AWAITING_RENDER:
				waiting += sp.lines[kind].size() * sp.names.size()
				continue
			if not kind in RENDERED_KINDS:
				unknown_kinds[kind] = true
			for line in sp.lines[kind]:
				for who in sp.names:
					var text := Content.fill(line, {"name": who.left(1) + who.substr(1).to_lower(), "target": "you"})
					if Voices.speakable(text) == "":
						stage_only += 1
						continue
					spoken += 1
					if Voices.find(species, text) != null:
						found += 1
					elif unrecorded.size() < 6:
						unrecorded.append("%s: %s" % [species, text])
	print("audio_test: %d of %d spoken roster lines have a recording, %d are stage directions only, %d wait for a render (%s); first misses: %s" % [found, spoken, stage_only, waiting, AWAITING_RENDER, unrecorded])
	_check(unknown_kinds.is_empty(), "a new kind of line is rendered or named in AWAITING_RENDER (%s)" % [unknown_kinds.keys()])
	_check(spoken > 150 and float(found) / spoken >= 0.9, "nearly every line with words finds its recording: %d of %d" % [found, spoken])


# ---------------------------------------------------------------- the music

func _music() -> Node:
	var m = Music.new()
	var seq := [0.0]
	m.random = func():
		seq[0] = fposmod(seq[0] + 0.381966, 1.0)
		return seq[0]
	root.add_child(m)
	return m


func _music_pacing() -> void:
	var m = _music()
	await process_frame
	# a fight never gets the tune of the one before
	var last := ""
	var repeats := 0
	var seen := {}
	for i in 200:
		m.set_mode("battle")
		var pick: String = m.battle_name()
		seen[pick] = true
		if pick == last:
			repeats += 1
		last = pick
		m.set_mode("explore")
	_check(repeats == 0 and seen.size() == Music.BATTLES.size(), "the battle theme is never the last fight's, and all four come up (%d repeats in 200 fights, %d themes)" % [repeats, seen.size()])
	m.free()
	m = _music()
	await process_frame
	m.set_mode("explore")
	_check(m.loop_player("explore") != null and m.loop_player("explore").playing, "exploring starts the loop")
	var p: float = m.pending_in()
	_check(p >= 80.0 and p <= 110.0, "the loop plays for 80-110 s before it rests (%.0f)" % p)
	m.advance(p + 0.1)
	_check(m.is_resting(), "...then it rests")
	p = m.pending_in()
	_check(p >= 60.0 and p <= 120.0, "...for 60-120 s (%.0f)" % p)
	m.advance(p + 0.1)
	_check(not m.is_resting() and m.pending_in() >= 80.0, "...then plays again")
	# a fight takes the music; its end rests two seconds, then the loop returns
	m.set_mode("battle")
	_check(m.pending_in() < 0.0 and m.loop_player("battle") != null, "a fight starts its own loop and cancels the explore pacing")
	m.set_mode("explore")
	_check(absf(m.pending_in() - 2.0) < 0.01, "after a fight the explore loop waits 2 s (%.2f)" % m.pending_in())
	# the sting holds the explore loop back for its length plus 4 s
	m.set_mode("battle")
	m.sting("victory")
	var len: float = m.sting_length()
	_check(len > 1.0, "the victory sting is loaded (%.1f s)" % len)
	m.set_mode("explore")
	_check(absf(m.pending_in() - (len + 4.0)) < 0.5, "after a sting the explore loop returns in sting length + 4 s (%.1f vs %.1f)" % [m.pending_in(), len + 4.0])
	m.advance(len + 4.5)
	_check(not m.is_resting() and m.mode() == "explore", "...and it does")
	m.free()


## Five seconds of silence, as a motif's stand-in: the real ones are local files that aren't in the repository.
func _fake_motif(seconds := 5.0) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(int(seconds * w.mix_rate) * 2)
	w.data = data
	return w


## Abdulla's motifs, on trial (#49): only from local files, taking turns with the exploring music, never in what ships.
func _motifs() -> void:
	var m = _music()
	await process_frame
	m.set_mode("explore")
	_check(m.playing_motif() == 0 and m.loop_player("explore").playing, "no motifs: the exploring music as ever")
	m.free()
	m = _music()
	m.motifs = [_fake_motif(), _fake_motif(), _fake_motif()]
	await process_frame
	m.set_mode("explore")
	_check(m.playing_motif() == 1, "with motifs, the first stretch is the first of them")
	_check(not m.loop_player("explore").playing, "and the exploring music waits")
	var p: float = m.pending_in()
	_check(absf(p - 5.0) < 0.01, "it plays once, to its end (%.1f)" % p)
	m.advance(p + 0.1)
	_check(m.playing_motif() == 0 and m.is_resting(), "then a rest")
	_check(m.pending_in() <= Music.TRIAL.rest[1], "a short one, so the team can compare (%.1f)" % m.pending_in())
	m.advance(m.pending_in() + 0.1)
	_check(m.playing_motif() == 0 and m.loop_player("explore").playing and not m.is_resting(), "then the exploring music, next to it")
	_check(m.pending_in() <= Music.TRIAL.play[1], "for a short stretch (%.1f)" % m.pending_in())
	m.advance(m.pending_in() + 0.1)
	m.advance(m.pending_in() + 0.1)
	_check(m.playing_motif() == 2, "then the next motif")
	m.set_mode("battle")
	_check(m.playing_motif() == 0, "a fight takes it off")
	_check(m.pending_in() < 0.0, "with nothing waiting")
	m.set_mode("explore")
	m.advance(m.pending_in() + 0.1)
	_check(m.playing_motif() == 0 and m.loop_player("explore").playing, "back from a fight, it is the exploring music's turn")
	m.advance(m.pending_in() + 0.1)
	m.advance(m.pending_in() + 0.1)
	_check(m.playing_motif() == 3, "and then the one after")
	m.sting("victory")
	_check(m.playing_motif() == 0, "a sting takes it off too")
	m.free()
	_check(Music.local_motifs("res://no/such/dir/").is_empty(), "no local files, no motifs")
	var dir := DirAccess.open("res://assets")
	var shipped := []
	for path in _files_under("res://assets"):
		if path.get_file().to_lower().contains("motif"):
			shipped.append(path)
	_check(dir != null and shipped.is_empty(), "no motif is in what ships (%s)" % [shipped])
	_check(not FileAccess.get_file_as_string("res://assets/CREDITS.txt").to_lower().contains("motif"), "nor in the credits: its license isn't known")
	_check(Music.MOTIF_DIR.begins_with("res://build/"), "they load from build/, which git and the exports leave out")
	var one := Music.pick_motifs([1, 2, 3], "2")
	_check(one == [2], "motif=N keeps that one")
	_check(Music.pick_motifs([1, 2, 3], "") == [1, 2, 3], "without it, all of them")
	_check(Music.pick_motifs([1, 2, 3], "9") == [1, 2, 3], "and a number that isn't one is ignored")


func _files_under(path: String) -> Array:
	var out := []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for f in dir.get_files():
		out.append(path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_files_under(path.path_join(d)))
	return out


## An old fade must not stop what a newer one is playing: the loop faded out for a fight and brought back before the fade
## ended is still playing after the old fade's time is up, and a fight right after a fight keeps its music.
func _music_fades() -> void:
	var m = _music()
	await process_frame
	m.set_mode("explore")
	await create_timer(1.7).timeout # faded in
	m.set_mode("battle") # the exploring loop starts a 0.4 s fade-out that ends in a pause...
	m.set_mode("explore")
	m.advance(2.1) # ...and the 2 s wait after the fight is up at once: it fades back in before the pause is due
	await create_timer(2.3).timeout
	var e: AudioStreamPlayer = m.loop_player("explore")
	_check(e != null and e.playing and not e.stream_paused and e.volume_db > -6.0, "an old fade-out does not stop the loop that was brought back (db %.1f)" % (e.volume_db if e else -99.0))
	m.set_mode("battle")
	m.set_mode("explore")
	m.set_mode("battle") # a second fight right on the first one's heels
	await create_timer(1.6).timeout
	var b: AudioStreamPlayer = m.loop_player("battle")
	_check(b != null and b.playing and b.volume_db > -12.0, "a fight right after a fight keeps its music (db %.1f)" % (b.volume_db if b else -99.0))
	m.duck(true)
	await create_timer(0.4).timeout
	var ducked := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Mix.MUSIC_IN))
	m.duck(false)
	await create_timer(1.0).timeout
	var back := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Mix.MUSIC_IN))
	_check(ducked < -8.0 and back > -1.0, "ducking drops MusicIn under a voice and brings it back (%.1f dB, then %.1f dB)" % [ducked, back])
	m.free()
