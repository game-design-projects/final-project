## Monster voices: which sound a spoken line gets (port of test/shout.test.js)
extends "res://tests/test_case.gd"

const Species = preload("res://src/rules/species.gd")
const Shout = preload("res://src/audio/shout.gd")
const Sfx = preload("res://src/audio/sfx.gd")
const Synth = preload("res://src/audio/synth.gd")


## Every string in a species' line banks, with where it came from.
func _all_lines(id: String) -> Array:
	var out := []
	var sp: Dictionary = Species.SPECIES[id]
	for bank in ["lines", "broken", "reactions"]:
		_walk(sp.get(bank), bank, out)
	return out


func _walk(o, path: String, out: Array) -> void:
	if o is Array:
		for l in o:
			if l is String:
				out.append({"path": path, "line": l})
	elif o is Dictionary:
		for k in o:
			_walk(o[k], "%s.%s" % [path, k], out)


func _kind_of(id, line):
	var plan = Shout.shout_plan(line, id)
	return null if plan == null else plan.kind


func test_the_signature_lines_get_the_sound_you_would_expect():
	var cases := [
		["goblin", "RAAH! *swings a knotted club at {target}*", "roar"],
		["goblin", "*grunts and punches {target}*", "grunt"],
		["goblin", "*lifts the club high and SMASHES {target}*", "roar"],
		["goblin", "LIAR! {name} SMASH!", "roar"],
		["goblin", "Hur hur. Talky one, eh?", "laugh"],
		["goblin", "Hmph.", "grunt"],
		["goblin", "Smash the smart creature! *swings at {target}*", "bark"],
		["goblin", "What you want, tiny?", "babble"],
		["dragon", "BURN IN MY STORM! *lightning floods the corridor*", "roar"],
		["dragon", "*snaps its great jaws at {target}*", "growl"],
		["dragon", "*inhales, then unleashes crackling yellow lightning over the whole party*", "zap"],
		["dragon", "*yawns, curls up, and ignores you entirely*", "sigh"],
		["dragon", "Ha! Wit, from a mortal. How rare.", "laugh"],
		["snake", "*raises its hood and hisses a warning*", "hiss"],
		["snake", "Hold ssstill, little one. *bites {target}*", "hiss"],
		["snake", "Clever. Very clever.", "babble"],
		["slime", "...bloop?", "squelch"],
		["slime", "*splorts orange goo all over {target}*", "squelch"],
		["slime", "*jiggles* ...hehe. funny.", "laugh"],
		["slime", "LIAR! *lunges at the party*", "squeal"],
		["slime", "*trembles* ...no like.", "whimper"],
		["rock", "*the ceiling groans... and a rockslide pours down on the party*", "rumble"],
		["rock", "...MOVE. *slams into {target}*", "rumble"],
		["rock", "...hmm.", "rumble"],
		["bandit", "Nothin' personal! *slashes at {target}*", "bark"],
		["bandit", "*darts in with a knife at {target}*", "grunt"],
		["bandit", "Ha! Nice work!", "laugh"],
	]
	for c in cases:
		eq(_kind_of(c[0], c[1]), c[2], "%s: %s" % [c[0], c[1]])


func test_every_attack_special_and_fight_line_in_species_makes_a_sound():
	var re := RegEx.create_from_string("^lines\\.(attack|special|attack_monster)$|^broken\\.attack_party$|^reactions\\.betray$")
	for id in Species.SPECIES:
		for item in _all_lines(id):
			if re.search(item.path) != null:
				ok(_kind_of(id, item.line) != null, "%s %s: %s" % [id, item.path, item.line])


func test_every_line_classifies_to_a_known_kind_and_only_a_wordless_stage_direction_is_silent():
	var sounds := 0
	var total := 0
	var words := RegEx.create_from_string("(?i)[a-z]{2,}")
	var stars := RegEx.create_from_string("\\*[^*]*\\*")
	var braces := RegEx.create_from_string("\\{[^}]*\\}")
	for id in Species.SPECIES:
		for item in _all_lines(id):
			var plan = Shout.shout_plan(item.line, id)
			total += 1
			if plan != null:
				sounds += 1
				ok(Shout.KINDS.has(plan.kind), "%s %s: %s" % [id, item.path, plan.kind])
				ok(plan.f0 > 20 and plan.vol > 0 and plan.vol <= 1.2 and plan.syll >= 2 and plan.syll <= 6, "%s: %s" % [id, item.line])
			else:
				var spoken := braces.sub(stars.sub(item.line, " ", true), " ", true)
				ok(words.search(spoken) == null, "silent line has words: %s %s: %s" % [id, item.path, item.line])
	ok(float(sounds) / total > 0.85, "%d/%d lines make a sound" % [sounds, total])


func test_each_species_keeps_its_own_voice_dragons_deep_goblins_mid_slimes_high_and_wet():
	var plan := func(id): return Shout.shout_plan("Hello there, traveller.", id)
	ok(plan.call("dragon").f0 < plan.call("goblin").f0)
	ok(plan.call("goblin").f0 < plan.call("slime").f0)
	ok(plan.call("rock").f0 < plan.call("dragon").f0)
	ok(plan.call("dragon").size < plan.call("slime").size, "dragon formants sit lower (a bigger throat)")
	eq(plan.call("slime").wet, true)
	eq(plan.call("goblin").wet, false)
	# a wordless emote falls back to the species' own noise
	eq(_kind_of("slime", "*lunges at {target}*"), "squelch")
	eq(_kind_of("dragon", "*lunges at {target}*"), "growl")
	eq(_kind_of("snake", "*lunges at {target}*"), "hiss")
	eq(_kind_of("rock", "*lunges at {target}*"), "rumble")
	eq(_kind_of("goblin", "*lunges at {target}*"), "grunt")
	# a boss is deeper than the rest of its kind
	var boss = Shout.shout_plan("RAAH!", "goblin", {"boss": true})
	var plain = Shout.shout_plan("RAAH!", "goblin")
	ok(boss.f0 < plain.f0 and boss.vol > plain.vol)


func test_free_text_from_jev_loose_spellings_junk_and_huge_input_all_land_somewhere_sane():
	var free := [
		["RAAAAAAH!!!", "roar"], ["*ROARS*", "roar"], ["Grrrrr... you dare?", "growl"], ["*growls low in its throat*", "growl"],
		["Muahahaha! Foolish mortals!", "laugh"], ["*cackles madly*", "laugh"], ["Hehehe", "laugh"], ["*snorts*", "grunt"],
		["Hissss...", "hiss"], ["Yessss, my preciousss", "hiss"], ["*SQUELCH*", "squelch"], ["BLORP", "squelch"],
		["Gloop gloop", "squelch"], ["Aaaaaah!", "squeal"], ["*shrieks*", "squeal"], ["*whimpers*", "whimper"],
		["*sighs heavily*", "sigh"], ["*rumbles ominously*", "rumble"], ["Hello, adventurer.", "babble"],
		["Stop right there!", "bark"], ["YOU SHALL NOT PASS!", "roar"],
	]
	for f in free:
		eq(_kind_of("goblin", f[0]), f[1], f[0])
	# junk never errors and never plays
	for junk in [null, 42, {}, [], "", "   ", "...", "*stares blankly*", "{name}", "{target} {name}", "!!!", "*", "**", "🙂"]:
		Shout.shout_plan(junk, "goblin")
	for silent in [null, 42, "", "...", "{name}", "*stares blankly*"]:
		eq(Shout.shout_plan(silent, "goblin"), null, str(silent))
	# an unknown species still gets a default voice; a huge line is cheap and capped
	eq(Shout.shout_plan("RAAH!", "beholder").species, "other")
	ok(Shout.shout_plan("RAAH!", null).f0 > 0)
	var huge := "blah ".repeat(20000)
	var t0 := Time.get_ticks_usec()
	var p = Shout.shout_plan(huge, "dragon")
	ok((Time.get_ticks_usec() - t0) / 1000.0 < 50, "huge line took %d us" % (Time.get_ticks_usec() - t0))
	ok(p.syll <= 6)
	eq(Shout.classify_kind("ROAR ".repeat(5000)), "roar")


func test_the_first_vocal_word_wins_shouting_beats_a_plain_effect_word_and_placeholders_are_ignored():
	eq(Shout.classify_kind("*blank stare* ...blorp. *lunges*"), "squelch")
	eq(Shout.classify_kind("Ssso. RAAH!"), "hiss")
	eq(Shout.classify_kind("*stomps* Out of my way!"), "bark")
	eq(Shout.classify_kind("BURN! *crackling lightning*"), "big")
	eq(Shout.classify_kind("{target} {name}"), null)
	eq(Shout.classify_kind("Oi! That's OUR gold you're wastin'!"), "big")


class SpySfx:
	extends Sfx.Sfx
	var played: Array = []

	func play(name: String, opt := {}) -> bool:
		played.append([name, opt.get("kind")])
		return true


func test_shout_respects_the_o_toggle_plays_once_per_monster_per_burst_and_survives_silent_lines():
	var now := [0.0]
	var sfx := SpySfx.new(0.55, {"clock": func(): return now[0]})
	sfx.running = true
	eq(sfx.shout("RAAH! *swings*", "goblin", {"key": "e1"}).kind, "roar")
	eq(sfx.shout("RAAH again!", "goblin", {"key": "e1"}), null, "same monster, same instant: one shout only")
	eq(sfx.shout("*hisses*", "snake", {"key": "e2"}).kind, "hiss", "another monster speaks fine")
	now[0] = 1.0
	eq(sfx.shout("Hmph.", "goblin", {"key": "e1"}).kind, "grunt", "a second later it may speak again")
	eq(sfx.shout("...", "goblin", {"key": "e3"}), null)
	sfx.toggle()
	eq(sfx.shout("RAAH!", "goblin", {"key": "e9"}), null, "sound off: no shout")
	eq(sfx.played.map(func(p): return p[1]), ["roar", "hiss", "grunt"])
	eq(sfx.played.map(func(p): return p[0]), ["voice_roar", "voice_hiss", "voice_grunt"])
	var cold := Sfx.Sfx.new()  # audio never started (no key press yet)
	eq(cold.shout("RAAH!", "goblin"), null)
	cold.free()
	sfx.free()


class Recorder:
	extends RefCounted
	var calls: Array = []

	func tone(at, o):
		calls.append(["tone", at, o])

	func noise(at, o):
		calls.append(["noise", at, o])

	func vocal(at, o):
		calls.append(["vocal", at, o])

	func arp(at, notes, o = {}):
		for t in Synth.arp_tones(at, notes, o):
			calls.append(["tone", t[0], t[1]])


func test_every_voice_kind_has_a_synth_that_drives_the_primitives_wet_or_dry():
	for k in Shout.KINDS:
		for wet in [false, true]:
			var rec := Recorder.new()
			Sfx.run_recipe("voice_" + k, rec, 0.0, {"f0": 100.0, "size": 1.0, "rasp": 0.3, "wet": wet, "vol": 1.0, "syll": 3})
			ok(rec.calls.size() > 0, "%s makes no sound" % k)
			for c in rec.calls:
				var vol = c[2].get("vol")
				if vol != null:
					ok(is_finite(vol) and vol > 0, "%s vol" % k)
	for id in Shout.VOICES:
		var v: Dictionary = Shout.VOICES[id]
		ok(v.f0 > 20 and v.size > 0 and Shout.KINDS.has(v.big) and Shout.KINDS.has(v.emote), id)
		for to in v.remap.values():
			ok(Shout.KINDS.has(to), "%s remaps to %s" % [id, to])
