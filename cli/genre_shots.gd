## Screenshots of the Genre Halls scene, to look at: the maze view with a monster down the corridor, the command box,
## each faction's dodge box (goo rain, chess, lantern/shadow, rhythm stomps), the mind panel, the strike bar, the
## typed line, a route screen. Opens a window briefly (not headless):
##   godot --path . -s res://cli/genre_shots.gd [-- out=/some/dir] [sound]
## Silent unless `sound` is given.
extends SceneTree

const J = preload("res://src/core/js.gd")
const Rules = preload("res://src/genre/genre_rules.gd")
const Render = preload("res://src/view/render.gd")
const Flags = preload("res://src/core/flags.gd")

var out_dir := "/private/tmp/claude-501/-private-tmp-temp/9a270d88-2fcd-474a-8038-3c1a423642ac/scratchpad/genre/"
var scene: Control


func _initialize() -> void:
	var sound := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.trim_prefix("out=").path_join("")
		elif a == "sound":
			sound = true
	Flags.override = "" if sound else "nosound"
	DirAccess.make_dir_recursive_absolute(out_dir)
	# A window behind other windows is throttled by macOS (the shots then take minutes): keep it on top and off vsync
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	seed(5)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("shot %s %s at %d ms" % [name, img.get_size(), Time.get_ticks_msec()])


func _fresh(species := "") -> void:
	if scene != null:
		scene.queue_free()
		await _frames(2)
	scene = load("res://src/genre/genre_halls.tscn").instantiate()
	root.add_child(scene)
	await _frames(2)
	if species != "":
		scene.meet(species)
		await _secs(0.9) # the intro flash, then the command box
	scene.G.maxHp = 999
	scene.G.hp = 999


## Stand the player in a corridor with `m` straight ahead, 2-4 cells away
func _face(m: Dictionary) -> bool:
	for dir in 4:
		var d: Array = Render.DIRS[dir]
		for k in [3, 4, 2, 5]:
			var ok := true
			for j in range(0, k + 1):
				if not scene._open(m.x - d[0] * j, m.y - d[1] * j):
					ok = false
					break
			if ok:
				scene.G.x = m.x - d[0] * k
				scene.G.y = m.y - d[1] * k
				scene.G.dir = dir
				return true
	return false


func _run() -> void:
	# title
	await _fresh()
	await _secs(0.4)
	await _shot("01-title")

	# the maze, with a monster down the corridor
	scene.on_key("Enter")
	await _secs(0.2)
	var placed := false
	for sp in ["slime", "bandit", "snake", "rock", "dragon"]:
		for m in scene.G.map.monsters:
			if m.species == sp and not placed:
				placed = _face(m)
				if placed:
					print("corridor shot with ", sp, " at ", m.x, ",", m.y)
	await _secs(0.4)
	await _shot("02-maze-monster")

	# the command box, then ACT, then an act's answers in the mind panel
	await _fresh("slime")
	await _shot("03-command-box")
	scene.on_key("2")
	await _secs(0.2)
	await _shot("04-act-menu")
	scene.on_key("3") # OFFER COMFORT
	await _secs(0.3)
	await _shot("05-mind-panel")

	# the strike bar
	await _fresh("bandit")
	scene.on_key("1")
	await _secs(0.5)
	await _shot("06-strike-bar")

	# the typed line
	await _fresh("snake")
	scene.on_key("2")
	scene.on_key("5")
	await _secs(0.3)
	scene._talk_in.text = "you have such beautiful scales"
	await _shot("07-say-something")
	scene.submit_talk(scene._talk_in.text)
	await _secs(0.3)
	await _shot("08-say-answered")

	# each faction's dodge box
	for pair in [["slime", "09-dodge-goo-rain"], ["bandit", "10-dodge-chess"], ["snake", "11-dodge-shadow"], ["rock", "12-dodge-rhythm"]]:
		await _fresh(pair[0])
		scene.start_dodge(2.0)
		await _secs(1.0)
		scene.on_key("ArrowLeft")
		await _shot(pair[1] + "-a")
		await _secs(0.55)
		await _shot(pair[1] + "-b")

	# the champion, each turn's genre
	for turn in 4:
		await _fresh("dragon")
		scene.G.foe.turn = turn
		scene.start_dodge(2.0)
		await _secs(1.4)
		await _shot("13-champion-turn%d" % (turn + 1))

	# allies and the route screen
	await _fresh("rock")
	scene.G.allies = [
		{"species": "slime", "name": "GLOP", "loyalty": 72.0},
		{"species": "bandit", "name": "ROOK", "loyalty": 41.0},
		{"species": "dragon", "name": "EMBER", "loyalty": 22.0},
	]
	scene.render_party()
	scene.start_dodge(1.0)
	await _secs(1.2)
	await _shot("14-allies-dodge")
	scene.D = null
	scene.explore()
	scene.G.tally = {"spared": 2, "slain": 1, "fled": 1, "recruited": 3, "left": 1}
	scene.ending()
	await _secs(0.3)
	await _shot("15-route-screen")

	# sparing, and a recruit joining
	for attempt in 12:
		await _fresh("rock")
		var m: Dictionary = scene.G.foe
		m.meters.friendliness = 100.0
		m.meters.anger = 0.0
		m.meters.fear = 0.0
		scene.on_key("3")
		if scene.G.tally.recruited > 0:
			break
	await _secs(0.3)
	await _shot("16-result-spared")

	# dying
	await _fresh("bandit")
	scene.G.hp = 2
	scene.start_dodge(1.0)
	scene.D.next = 1e12
	var here: int = Rules.idx(scene.D.soul.c, scene.D.soul.r)
	var t: float = scene.now()
	scene.D.hazards.append({"cells": {here: true}, "warn": t, "hit": t + 50.0, "end": t + 2000.0, "kind": "chess", "sounded": false})
	await _secs(0.5)
	await _shot("17-dead")
	quit()
