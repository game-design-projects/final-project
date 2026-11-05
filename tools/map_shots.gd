## Pictures of the floors the generators make, for looking at (tests can't judge looks): each biome's largest floor from above, and
## in first person what its secrets look like: the start, a cracked wall, the chest behind it, a pad, and the automap on a big floor.
##   godot --path . -s res://tools/map_shots.gd -- out=<dir> nosound
extends SceneTree

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


func _initialize() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=7"] + Array(OS.get_cmdline_user_args())))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://map_shots"))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
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
	print("map_shots: written to %s" % _out)
	quit()


func _plan(biome: Dictionary, depth: int) -> Dictionary:
	var plan: Dictionary = Floors.plan(depth)
	plan.biome = Floors.sized(biome, depth)
	plan.secrets = Floors.secrets(plan.biome)
	plan.boss_at_exit = true
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
	var s = flow.state
	s.floor_map = FloorGen.generate(Rng.new(SEEDS[0]), _plan(biome, 5))
	s.palette_id = Floors.palette(biome.id, SEEDS[0])
	s.depth = 5
	var f = s.floor_map
	s.seen = {}
	s.visited = {}
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


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("map_shots: %s" % name)
