extends SceneTree
const Synth = preload("res://src/audio/synth.gd")
const Sfx = preload("res://src/audio/sfx.gd")
const Shout = preload("res://src/audio/shout.gd")

func _initialize():
	call_deferred("_run")

func _run():
	var total := 0.0
	for name in Sfx.names():
		var o := {}
		if name.begins_with("voice_"):
			o = {"f0": 150.0, "size": 0.95, "rasp": 0.55, "wet": false, "vol": 1.0, "syll": 4}
		var t0 := Time.get_ticks_usec()
		var r := Sfx.render(name, o)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		print("%-14s %6.1f ms  %.2f s  peak %.3f" % [name, ms, r.seconds, r.peak])
	print("total %.0f ms" % total)
	print(Shout.shout_plan("RAAH! *swings a knotted club at {target}*", "goblin"))
	print(Shout.classify_kind("*stares blankly*"))
	quit()
