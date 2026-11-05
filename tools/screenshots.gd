## Takes pictures of the game in its typical moments, to look at: the main menu, walking, the pause menu, a monster ahead, each species close up, a
## monster far away, the stairs, the fight menu, the strike bar, each kind of dodge, the champion, the result, the tooltips (the map's legend, the foe's
## mind, a command, an ally) and the touch pad. It needs a real window (it opens one briefly):
##   godot --path . -s res://tools/screenshots.gd -- out=/some/dir seed=7
## Without `out` the pictures go to user://shots. It prints where. Nothing reaches the player's saves (the `nosave` flag is always on, so a save stays in memory).
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
	await _pages(menu)
	menu.free()
	var scene = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(scene)
	_game = scene
	await _wait(0.6)
	await _shot("00b_title_card")
	for i in 20: # the prompt blinks: catch it lit
		if _game._overlay.title_prompt_on() and _game._overlay.clock_ms > 1000.0:
			break
		await _wait(0.1)
	await _shot("00c_title_card_prompt")
	await _game._begin()
	await _wait(0.4)
	await _camp()
	await _walk_and_fight()
	print("screenshots: written to %s" % _out)
	quit()


## The pages of what is kept between runs, with something on them. In memory: the tool runs with nosave.
func _pages(menu) -> void:
	var store = root.get_node("Store")
	store.set_value("embers", 14)
	store.set_value("achievements", ["words", "friend", "chest"])
	var menus = load("res://src/menu/menus.gd")
	var panel = menu.panel
	panel.push(func(): return menus.legacy(panel))
	await _wait(0.3)
	await _shot("00d_legacy")
	panel.pop()
	panel.push(func(): return menus.achievements())
	await _wait(0.3)
	await _shot("00e_achievements")
	panel.pop()
	store.remove("embers")
	store.remove("achievements")


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


## Each species close up and far away, whatever stands where: `m` wears the species for the picture. Close up shows the model's
## detail, two cells out and from afar its readable lines and tag.
func _species() -> void:
	var s = _game.flow.state
	var m = s.floor_map.monsters[0]
	var worn: String = m.species
	var far := -1
	for steps in [8, 7, 6, 5, 4]:
		if _stand_before(m, steps):
			far = steps
			break
	for species in ["slime", "bandit", "snake", "rock", "dragon"]:
		_forget(m)
		m.species = species
		_stand_before(m, 1)
		await _wait(0.5)
		await _shot("02s_%s_close" % species)
		_stand_before(m, 2)
		await _wait(0.5)
		await _shot("02s_%s_two_cells" % species)
		if far > 0:
			_stand_before(m, far)
			await _wait(0.5)
			await _shot("02s_%s_far_%d_cells" % [species, far])
	_forget(m)
	m.species = worn


## The set builds a monster's model once; drop it, so a changed species shows.
func _forget(m) -> void:
	var stage = _game._stage
	if stage._models.has(m):
		stage._models[m].queue_free()
		stage._tags[m].queue_free()
		stage._models.erase(m)
		stage._tags.erase(m)
		stage._tag_light.erase(m)


## The stairs from two cells off and from one, straight on.
func _stairs() -> void:
	var s = _game.flow.state
	var f = s.floor_map
	for steps in [2, 1]:
		for i in 4:
			var c: Vector2i = f.stairs
			var n := 0
			while n < steps and f.is_open(c - FloorMap.DIRS[i]):
				c -= FloorMap.DIRS[i]
				n += 1
			if n == steps:
				s.cell = c
				s.facing = i
				s.look()
				await _wait(0.5)
				await _shot("02t_stairs_%d_cells" % steps)
				break


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
	_game._tips.pinned = "map"
	await _wait(0.3)
	await _shot("02b_map_tooltip")
	_game._tips.pinned = ""
	await _species()
	await _stairs()
	_stand_before(m, 1) # in a fight the monster is right in front of you
	await flow.go("intro", {"foe": m})
	await _wait(0.4)
	await _shot("03_intro")
	await _wait(0.9)
	await _shot("04_menu")
	await _tooltips()
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
	s.bar.heavy = true # how the same bar looks for HEAVY
	await _wait(0.05)
	await _shot("06b_heavy_bar")
	s.bar.heavy = false
	await flow.press("confirm")
	await _wait(0.15)
	await _shot("07_after_strike")
	# each kind of dodge, whatever the monster really fights in
	var real_max: int = s.max_hp
	s.max_hp = 9999 # the camera isn't here to survive, only to look
	s.rotate_mini_games = false # each picture shows the attack it names
	s.hp = 9999
	for genre in ["bullet", "chess", "shadow", "gates", "stars", "dance", "rhythm"]:
		m.genre = genre
		if genre == "rhythm": # the last one shows the charms
			s.allies = [Ally.make("slime", "GLOP", 60.0), Ally.make("snake", "HISS", 60.0)]
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
		await _wait(0.5)
		await _shot("10b_joined")
	# the death screen: put the game in a dodge with no health left and let the stage notice
	s.stage = "dodge"
	s.foe = monsters[1]
	s.hp = 0
	await flow.go("dead")
	await _wait(0.5)
	await _shot("12_dead")
	await flow.go("explore")
	s.max_hp = real_max
	s.hp = real_max
	s.cell = s.floor_map.stairs
	await flow.go("end")
	await _wait(0.3)
	await _shot("11_end")


## Sitting down: hungry, with a friend and something to eat, the question it asks, and a roast to share.
func _camp() -> void:
	var flow = _game.flow
	var s = flow.state
	var kept: Array = s.items.duplicate()
	s.allies = [Ally.make("slime", "GLOP", 60.0), Ally.make("snake", "HISS", 60.0)]
	s.items = ["ration"]
	s.hunger = 70.0
	await _wait(0.2)
	await _shot("01c_hungry")
	await flow.press("confirm")
	await _wait(0.3)
	await _shot("01d_camp")
	await flow.press("2")
	await _wait(0.3)
	await _shot("01e_camp_asks")
	await flow.press("cancel")
	s.items = ["roast", "ration"]
	flow._stages["camp"]._fill(flow)
	await _wait(0.3)
	await _shot("01f_camp_roast")
	await flow.press("cancel")
	s.allies = []
	s.items = kept
	s.hunger = 0.0
	await _wait(0.2)


## The cards over the picture and the touch pad, in the fight menu: the foe's mind (after a kind word, so it has something to say),
## what SPARE does, two allies (one about to leave), and the pad.
func _tooltips() -> void:
	var s = _game.flow.state
	var tips = _game._tips
	await _game.flow.encounter.decide(s.foe, [{"intent": "kindness", "w": 1.0}], "KIND")
	tips.pinned = "foe"
	await _wait(0.3)
	await _shot("04b_foe_tooltip")
	tips.pinned = ""
	tips.hover_command(2, _game._dock.command_screen_rect(2))
	await _wait(0.3)
	await _shot("04c_command_tooltip")
	tips.hover_command(-1)
	s.allies.append(Ally.make("slime", "GLOP", 80.0))
	s.allies.append(Ally.make("rock", "STONE", 20.0))
	await _wait(0.3)
	tips.pinned = "ally1"
	await _wait(0.3)
	await _shot("04d_ally_tooltip")
	tips.pinned = ""
	_game._pad.visible = true
	await _wait(0.3)
	await _shot("04e_touch_pad")
	_game._pad.visible = false
	s.allies = []
	await _wait(0.2)
