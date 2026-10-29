## Renders every sound effect (and a few monster shouts) to WAV files, to listen to or measure with ffmpeg:
##   godot --headless --path . -s res://cli/sfx_dump.gd -- --out=/tmp/donjon-sfx
## Each file is the dry sound as it leaves the effects fader (the recipe's own level x the 0.55 volume x the bus
## make-up); the room send is written beside it as <name>.room.wav at the level it is added to the mix. Prints a table
## with the length, the peak and the RMS of every one, in dBFS.
extends SceneTree

const Sfx = preload("res://src/audio/sfx.gd")
const Synth = preload("res://src/audio/synth.gd")
const Shout = preload("res://src/audio/shout.gd")
const Mix = preload("res://src/audio/mix.gd")

const SHOUTS := [
	["goblin_roar", "goblin", "RAAH! *swings a knotted club at {target}*", false],
	["goblin_boss_roar", "goblin", "RAAH! *swings a knotted club at {target}*", true],
	["goblin_laugh", "goblin", "Hur hur. Talky one, eh?", false],
	["goblin_bark", "goblin", "Smash the smart creature! *swings at {target}*", false],
	["goblin_babble", "goblin", "What you want, tiny?", false],
	["dragon_roar", "dragon", "BURN IN MY STORM! *lightning floods the corridor*", false],
	["dragon_growl", "dragon", "*snaps its great jaws at {target}*", false],
	["dragon_laugh", "dragon", "Ha! Wit, from a mortal. How rare.", false],
	["snake_hiss", "snake", "*raises its hood and hisses a warning*", false],
	["snake_babble", "snake", "Clever. Very clever.", false],
	["slime_squelch", "slime", "*splorts orange goo all over {target}*", false],
	["slime_squeal", "slime", "LIAR! *lunges at the party*", false],
	["slime_laugh", "slime", "*jiggles* ...hehe. funny.", false],
	["slime_whimper", "slime", "*trembles* ...no like.", false],
	["rock_rumble", "rock", "*the ceiling groans... and a rockslide pours down on the party*", false],
	["bandit_bark", "bandit", "Nothin' personal! *slashes at {target}*", false],
	["bandit_grunt", "bandit", "*darts in with a knife at {target}*", false],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := "/tmp/donjon-sfx"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var level := 0.55 * db_to_linear(Mix.SFX_MAKEUP_DB)
	seed(1)
	print("%-24s %8s %9s %9s %9s %8s" % ["sound", "seconds", "peak dBFS", "rms dBFS", "room dBFS", "render ms"])
	var total_ms := 0.0
	for name in Sfx.names():
		if name.begins_with("voice_"):
			continue  # the shouts below
		total_ms += _dump(out, name, name, {}, level)
	for s in SHOUTS:
		var plan = Shout.shout_plan(s[2], s[1], {"boss": s[3]})
		if plan == null:
			push_error("sfx_dump: %s makes no sound" % s[0])
			continue
		var vol: float = plan.vol
		var opts: Dictionary = plan.duplicate()
		opts.erase("vol")
		total_ms += _dump(out, "shout_" + s[0], "voice_" + plan.kind, opts, level * vol)
	print("rendered everything in %.0f ms; files in %s" % [total_ms, out])
	quit()


func _dump(out: String, file: String, recipe: String, opts: Dictionary, gain: float) -> float:
	var t0 := Time.get_ticks_usec()
	var s := Synth.Render.new()
	Sfx.run_recipe(recipe, s, 0.0, opts)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var dry := s.dry.slice(0, s.used)
	var send := s.send.slice(0, s.used)
	var send_gain: float = gain * Sfx.ROOM_WET * db_to_linear(Mix.ROOM_RETURN_DB)
	Synth.to_wav(dry, s.rate, gain).save_to_wav("%s/%s.wav" % [out, file])
	Synth.to_wav(send, s.rate, send_gain).save_to_wav("%s/%s.room.wav" % [out, file])
	print("%-24s %8.3f %9.1f %9.1f %9.1f %8.1f" % [file, s.seconds(), linear_to_db(Synth.peak_of(dry) * gain), linear_to_db(Synth.rms_of(dry) * gain), linear_to_db(Synth.peak_of(send) * send_gain), ms])
	return ms
