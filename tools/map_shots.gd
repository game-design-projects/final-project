## Pictures of the floors the generators make, for looking at (tests can't judge looks): each biome's largest floor from above, and
## in first person what its secrets look like: the start, a cracked wall, the chest behind it, a pad, and the automap on a big floor.
## Then the whole floor's map (M) half seen and with the rest charted, and the corner map of a charted floor.
## Each biome starts with no pause menu and a running game clock, and a capture identical to the one before it ends the
## run with a non-zero exit and the capture's name: a frozen picture must never be saved twice and pass as evidence.
##   godot --path . -s res://tools/map_shots.gd -- out=<dir> nosound
extends SceneTree

const Chart = preload("res://src/rules/chart.gd")
const Content = preload("res://src/rules/content.gd")
const Flags = preload("res://src/utils/flags.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Floors = preload("res://src/rules/floors.gd")
const Palette = preload("res://src/view/palette.gd")
const Rng = preload("res://src/utils/rng.gd")

const PLAN_CELL := 8
const SEEDS := [21, 22, 23]

var _out := ""
var _game
var _failed := false
var _last_hash := ""
var _last_name := ""
var _hashes := {}


func _initialize() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=7"] + Array(OS.get_cmdline_user_args())))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://map_shots"))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	if Flags.on("nofocus"): # someone is typing on this screen: stay visible, take no keys
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	else:
		DisplayServer.window_move_to_foreground()
	for biome in Content.table("biomes").biomes:
		for seed_value in SEEDS:
			_plan_picture(FloorGen.generate(Rng.new(seed_value), _plan(biome, 5)), "plan_%s_%d" % [biome.id, seed_value])
	_game = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(_game)
	await _wait(0.6)
	await _game._begin()
	await _wait(0.4)
	_game._overlay.visible = true
	for biome in Content.table("biomes").biomes:
		await _walk_through(biome)
		if _failed:
			return
	print("map_shots: %d captures, every one different from the one before it" % _hashes.size())
	for biome in Content.table("biomes").biomes:
		var id := str(biome.id)
		print("map_shots: %s whole map %s | charted %s | corner %s" % [
			id,
			_hashes.get("%s_3_full_map" % id, "MISSING"),
			_hashes.get("%s_4_full_map_charted" % id, "MISSING"),
			_hashes.get("%s_5_corner_charted" % id, "MISSING"),
		])
	print("map_shots: written to %s" % _out)
	quit()


func _plan(biome: Dictionary, depth: int) -> Dictionary:
	var plan: Dictionary = Floors.plan(depth)
	plan.biome = Floors.sized(biome, depth)
	plan.secrets = Floors.secrets(plan.biome)
	plan.boss_at_exit = true
	plan.items = true
	plan.shop = true
	plan.lurkers = true
	plan.request = true
	return plan


## The whole floor from above: floor, cracked walls, chests, pads, the start, the stairs and the monsters.
func _plan_picture(f, name: String) -> void:
	var img := Image.create(f.size * PLAN_CELL, f.size * PLAN_CELL, false, Image.FORMAT_RGB8)
	img.fill(Color("#101014"))
	var cell := func(c: Vector2i, color: Color, inset := 0):
		img.fill_rect(Rect2i(c * PLAN_CELL + Vector2i.ONE * inset, Vector2i.ONE * (PLAN_CELL - inset * 2)), color)
	for y in f.size:
		for x in f.size:
			var c := Vector2i(x, y)
			if f.is_open(c):
				cell.call(c, Color("#8a8a8a"))
			elif f.is_cracked(c):
				cell.call(c, Color("#ff9d2e"))
	for t in f.treasure:
		cell.call(t.cell, Color("#ffd27a"), 1)
	for t in f.teleports:
		cell.call(t.a, Color("#8fd3ff"), 1)
		cell.call(t.b, Color("#8fd3ff"), 1)
	for m in f.monsters:
		cell.call(m.cell, Palette.monster(m), 2)
	cell.call(f.start, Color.WHITE, 1)
	img.save_png("%s/%s.png" % [_out, name])
	print("map_shots: %s %dx%d" % [name, f.size, f.size])


func _walk_through(biome: Dictionary) -> void:
	var flow = _game.flow
	await _reset_before_biome(str(biome.id))
	if _failed:
		return
	var s = flow.state
	s.floor_map = FloorGen.generate(Rng.new(SEEDS[0]), _plan(biome, 5))
	s.palette_id = Floors.palette(biome.id, SEEDS[0])
	s.depth = 5
	var f = s.floor_map
	s.seen = {}
	s.visited = {}
	s.charted = {} # a new floor starts uncharted, as Flow._make_floor: the last biome's charted cells are not this one's
	_put(s, f.start, f.start_facing())
	s.banner = null
	await _wait(0.5)
	await _shot("%s_1_start" % biome.id)
	await _roam(s, f, biome)
	var wall := _a_cracked_wall(f)
	if wall != Vector2i(-1, -1):
		for i in 4:
			var from: Vector2i = wall - FloorMap.DIRS[i]
			if f.is_open(from) and not f.treasure.any(func(t): return t.cell == from):
				_put(s, from, i)
				break
		await _wait(0.4)
		await _shot("%s_3_cracked_wall" % biome.id)
		await flow.press("up")
		await _wait(0.5)
		await _shot("%s_4_wall_broken_chest" % biome.id)
		_put(s, wall, s.facing)
		await _wait(0.4)
		await _shot("%s_4b_chest_close" % biome.id)
	if not f.teleports.is_empty():
		var pad: Vector2i = f.teleports[0].a
		for i in 4:
			var from: Vector2i = pad - FloorMap.DIRS[i] * 2
			if f.is_open(from) and f.is_open(pad - FloorMap.DIRS[i]):
				_put(s, from, i)
				break
		await _wait(0.4)
		await _shot("%s_5_pad" % biome.id)
	if not f.pickups.is_empty():
		_look_at(s, f, f.pickups[0].cell)
		await _wait(0.4)
		await _shot("%s_6_item" % biome.id)
	if not f.merchant.is_empty():
		_look_at(s, f, f.merchant.cell)
		await _wait(0.4)
		await _shot("%s_7_trader" % biome.id)
		for i in 4:
			if f.merchant.cell == s.cell + FloorMap.DIRS[i]:
				s.facing = i
		_put(s, f.merchant.cell - FloorMap.DIRS[s.facing], s.facing)
		s.banner = null
		await flow.press("up")
		await _wait(0.4)
		await _shot("%s_8_shelf" % biome.id)
		await flow.press("cancel")
	var stirring: Array = f.monsters.filter(func(m): return m.lurking)
	if not stirring.is_empty():
		_look_at(s, f, stirring[0].cell)
		await _wait(0.4)
		await _shot("%s_a_lurker" % biome.id)
	if not f.quester.is_empty():
		_look_at(s, f, f.quester.cell)
		await _wait(0.4)
		await _shot("%s_b_asking" % biome.id)
		for i in 4:
			if f.quester.cell == s.cell + FloorMap.DIRS[i]:
				s.facing = i
		_put(s, f.quester.cell - FloorMap.DIRS[s.facing], s.facing)
		s.banner = null
		await flow.press("up")
		await _wait(0.4)
		await _shot("%s_c_request" % biome.id)
		await flow.press("cancel")
	s.items = ["salve", "sugar", "smoke"]
	await flow.go("intro", {"foe": _a_foe(f)})
	await _wait_for_stage(flow, "menu", "%s: the fight menu" % biome.id)
	if _failed:
		return
	await _shot("%s_9_fight_menu" % biome.id)
	var item_row := _menu_row(flow, "ITEM")
	if item_row < 0:
		_fail("%s: the fight menu has no ITEM row" % biome.id)
		return
	await flow.press(str(item_row + 1))
	await _wait_for_stage(flow, "items", "%s: the bag" % biome.id)
	if _failed:
		return
	await _shot("%s_9b_bag" % biome.id)
	await flow.press("cancel")
	await _wait_for_stage(flow, "menu", "%s: back from the bag" % biome.id)
	if _failed:
		return
	await flow.press("4") # FLEE ends the fight: the next floor has to start on the walk, not inside a menu
	await _wait_for_stage(flow, "explore", "%s: the end of the fight" % biome.id)
	if _failed:
		return
	await _wait_awake("%s: after the fight" % biome.id)


## Stand a step or two off a cell, looking at it.
func _look_at(s, f, cell: Vector2i) -> void:
	for steps in [2, 1]:
		for i in 4:
			var ok := true
			for n in range(1, steps + 1):
				ok = ok and f.is_open(cell - FloorMap.DIRS[i] * n)
			if ok:
				_put(s, cell - FloorMap.DIRS[i] * steps, i)
				return


## Stand in the widest place on the floor and look about, and let the automap fill in.
func _roam(s, f, biome: Dictionary) -> void:
	var best: Vector2i = f.start
	var most := -1
	for y in range(2, f.size - 2):
		for x in range(2, f.size - 2):
			var c := Vector2i(x, y)
			if not f.is_open(c) or f.monster_at(c) != null:
				continue
			var open := 0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if f.is_open(c + Vector2i(dx, dy)):
						open += 1
			if open > most:
				most = open
				best = c
	for facing in 4:
		_put(s, best, facing)
		await _wait(0.1)
	_put(s, best, 1)
	await _wait(0.4)
	await _shot("%s_2_wide" % biome.id)
	# the whole floor's map (M): with the near half of the floor seen, then with the rest charted, and the corner map after that
	var cells: Array = s.reach().keys() # nearest the start first
	for i in cells.size() / 2:
		s.seen[cells[i]] = true
		if i % 3 == 0:
			s.visited[cells[i]] = true
	if not s.charted.is_empty(): # the picture says how much is seen: charted cells before the reveal are another floor's
		_fail("%s: %d charted cells before the reveal, so the half-seen map is not half seen" % [biome.id, s.charted.size()])
		return
	_game.show_map(true)
	await _wait(0.3)
	await _shot("%s_3_full_map" % biome.id)
	Chart.reveal(s)
	await _wait(0.3)
	await _shot("%s_4_full_map_charted" % biome.id)
	_game.show_map(false)
	await _wait(0.3)
	await _shot("%s_5_corner_charted" % biome.id)


func _put(s, c: Vector2i, facing: int) -> void:
	s.cell = c
	s.facing = facing
	s.visited[c] = true
	s.look()


func _a_cracked_wall(f) -> Vector2i:
	for y in f.size:
		for x in f.size:
			if f.is_cracked(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Put the last biome's fight and menus away before the next floor is built, and prove the game is running again: `_process`
## returns early while the pause menu is up, which used to leave every later biome on one frozen frame.
func _reset_before_biome(where: String) -> void:
	_game.show_map(false)
	if _game._pause.visible:
		_game._resume()
		print("map_shots: %s: closed the pause menu left open by the floor before" % where)
	_game._social.suspended = false
	_game._tips.unpin()
	if _game.flow.state.stage != "explore":
		_fail("%s: the next floor would start in stage '%s', not on the walk" % [where, _game.flow.state.stage])
		return
	await _wait_awake(where)


## A frame after the pause menu closes is not enough: wait until the game clock moves, which only `_process` does.
func _wait_awake(where: String) -> void:
	var before: float = _game._clock_ms
	var deadline := Time.get_ticks_msec() + 3000
	while _game._pause.visible or _game._clock_ms <= before:
		if Time.get_ticks_msec() > deadline:
			_fail("%s: the game did not resume ticking (pause menu %s, clock %.0f ms)" % [where, "open" if _game._pause.visible else "closed", _game._clock_ms])
			return
		await create_timer(0.05).timeout


## Wait for the flow to reach a stage, continuing the intro's "ANY KEY" card so the wait is about the stage, not a keypress.
## Every pass yields a timer: `flow.press` can finish without awaiting anything, and a loop that never yields would starve
## the game's `_process` (the intro then never finishes its own continue).
func _wait_for_stage(flow, stage: String, where: String) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while flow.state.stage != stage:
		if Time.get_ticks_msec() > deadline:
			_fail("%s: still in stage '%s', not '%s' (clock %.0f, hint '%s')" % [where, flow.state.stage, stage, flow.clock, flow.state.hint])
			return
		if flow.state.stage == "intro" and flow.state.hint == "ANY KEY CONTINUE":
			await flow.press("confirm")
		await create_timer(0.05).timeout


## The row of a menu with this label, or -1: which key opens ITEM depends on the features that add rows above it.
func _menu_row(flow, label: String) -> int:
	for i in flow.state.menu.size():
		if str(flow.state.menu[i].get("label", "")) == label:
			return i
	return -1


## A monster that can be fled from: a champion blocks FLEE, and the next floor is built after this fight.
func _a_foe(f):
	var walkers: Array = f.monsters.filter(func(m): return not m.is_gone() and not m.boss)
	return walkers[0] if not walkers.is_empty() else f.monsters[0]


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Take the picture, and refuse to save it when the game is frozen or the pixels are the ones just saved.
func _shot(name: String) -> void:
	if _failed:
		return
	await _wait_awake(name)
	if _failed:
		return
	if _game._pause.visible:
		_fail("%s: the pause menu is up, the picture would be frozen" % name)
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var digest := img.get_data().hex_encode().md5_text()
	if digest == _last_hash:
		_fail("%s: the same pixels as %s (%s); the capture is frozen" % [name, _last_name, digest])
		return
	_last_hash = digest
	_last_name = name
	_hashes[name] = digest
	img.save_png("%s/%s.png" % [_out, name])
	print("map_shots: %s %s" % [name, digest])


## Stop with a non-zero exit and the name of the floor and capture: a screenshot tool must not save a frozen frame.
func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("map_shots: FAIL: %s" % message)
	print("map_shots: FAIL: %s" % message)
	quit(1)
