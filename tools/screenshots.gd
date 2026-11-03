## Takes pictures of the game in its typical moments, to look at: the main menu, walking, the pause menu, a monster ahead, the fight menu, the strike
## bar, each kind of dodge, the champion, the result, the stairs. It needs a real window (it opens one briefly):
##   godot --path . -s res://tools/screenshots.gd -- out=/some/dir seed=7
## Without `out` the pictures go to user://shots. It prints where. It never saves (the `nosave` flag is always on).
extends SceneTree

const FloorMap = preload("res://src/rules/floor_map.gd")
const Ally = preload("res://src/game/ally.gd")
const Decor = preload("res://src/view/decor.gd")
const Flags = preload("res://src/utils/flags.gd")

var _out := ""
var _game


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave"]))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://shots"))
	DirAccess.make_dir_recursive_absolute(_out)
	# macOS slows a window that is behind others to a crawl: keep this one on top and off vsync
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	var menu = load("res://src/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _wait(0.5)
	await _shot("00_main_menu")
	menu.free()
	var scene = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(scene)
	_game = scene
	await _wait(0.6)
	await _shot("00b_title_card")
	await _game._begin()
	await _wait(0.4)
	await _walk_and_fight()
	print("screenshots: written to %s" % _out)
	quit()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Wait (up to `max_s` seconds) until the game is in this stage. A slow machine makes frames late, so look, don't guess.
func _until(stage: String, max_s: float) -> void:
	var waited := 0.0
	while _game.flow.state.stage != stage and waited < max_s:
		await _wait(0.1)
		waited += 0.1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("screenshots: %s" % name)


## Stand `steps` cells from the monster, in a straight line with it, looking at it. False if no such line exists.
func _stand_before(m, steps: int) -> bool:
	var s = _game.flow.state
	for i in 4:
		var c: Vector2i = m.cell
		var n := 0
		while n < steps and s.floor_map.is_open(c - FloorMap.DIRS[i]):
			c -= FloorMap.DIRS[i]
			n += 1
		if n == steps:
			s.cell = c
			s.facing = i
			s.look()
			return true
	return false


## Stand close to one wall of each kind of decoration, looking at it.
func _decorations() -> void:
	var s = _game.flow.state
	var seen := {}
	for p in Decor.placements(s.floor_map):
		if seen.has(p.kind):
			continue
		var back: Vector2i = p.cell - FloorMap.DIRS[p.side] # one cell behind, so the wall is two cells ahead
		if not s.floor_map.is_open(back):
			s.cell = p.cell # a dead end: stand next to it
		else:
			s.cell = back
		s.facing = p.side
		s.look()
		seen[p.kind] = true
		await _wait(0.9)
		await _shot("02z_decor_%s" % p.kind)
	_game.flow.state.cell = s.floor_map.start
	s.facing = s.floor_map.start_facing()


func _walk_and_fight() -> void:
	var flow = _game.flow
	var s = flow.state
	await _shot("01_start")
	flow.event("pause_requested")
	await _wait(0.2)
	await _shot("01b_pause")
	_game._resume()
	await _decorations()
	var monsters: Array = s.floor_map.monsters
	var m = monsters[0]
	for steps in [4, 3, 2, 1]:
		if _stand_before(m, steps):
			break
	await _wait(1.0)
	await _shot("02_monster_ahead")
	_stand_before(m, 1) # in a fight the monster is right in front of you
	await flow.go("intro", {"foe": m})
	await _wait(0.4)
	await _shot("03_intro")
	await _wait(0.9)
	await _shot("04_menu")
	await flow.press("2")
	await _wait(0.3)
	await _shot("05_act")
	await flow.press("5") # SAY SOMETHING
	await _wait(0.5)
	await _shot("05b_talk")
	await flow.press("cancel") # back to the act list
	await flow.press("cancel") # and to the four commands
	await flow.press("1")
	await _wait(0.5)
	await _shot("06_strike_bar")
	await flow.press("confirm")
	await _wait(0.15)
	await _shot("07_after_strike")
	# each kind of dodge, whatever the monster really fights in
	var real_max: int = s.max_hp
	s.max_hp = 9999 # the camera isn't here to survive, only to look
	s.hp = 9999
	for genre in ["bullet", "chess", "shadow", "rhythm"]:
		m.genre = genre
		await _until("menu", 40.0)
		if s.stage == "menu":
			await flow.go("wait", {"pressure": 1.5})
			await _until("dodge", 20.0)
			await _wait(1.6)
			await _shot("08_dodge_%s" % genre)
	# the champion
	var boss = monsters[-1]
	_stand_before(boss, 1)
	m = boss
	await _until("menu", 40.0)
	if s.stage == "menu":
		await flow.go("explore")
	if s.stage == "explore":
		await flow.go("intro", {"foe": boss})
		await _wait(1.6)
		await _shot("09_boss")
		await flow.encounter.defeat(boss, "spared")
		await _wait(0.4)
		await _shot("10_result")
		await flow.press("confirm")
	# the death screen: put the game in a dodge with no health left and let the stage notice
	s.stage = "dodge"
	s.foe = monsters[1]
	s.hp = 0
	await flow.go("dead")
	await _wait(0.5)
	await _shot("12_dead")
	await flow.go("explore")
	s.allies.append(Ally.make("slime", "GLOP", 60.0))
	s.max_hp = real_max
	s.hp = real_max
	s.cell = s.floor_map.stairs
	await flow.go("end")
	await _wait(0.3)
	await _shot("11_end")
