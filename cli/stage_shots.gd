## Renders the 3D view (Stage3D) to PNGs through the post-processing shader, shown at 2x: the title corridor,
## corridors on four palettes, the stairs, the champion seen down a corridor, every monster in a fight (plus a shiny,
## a champion, a hurt one, groups of two and three, and boxed in by walls), and danger. Needs a real window (it opens one briefly and quits):
##   $G --path . -s res://cli/stage_shots.gd [-- --out=/some/dir] [--only=<substring>] [--walk]
## `--walk` also saves the frames of a short walk (three steps, a turn, a step, a goblin) to <out>/walk/, for a GIF:
##   convert -delay 4 -loop 0 <out>/walk/*.png -layers Optimize walk.gif
extends SceneTree

const J = preload("res://src/core/js.gd")
const Render = preload("res://src/view/render.gd")
const Art = preload("res://src/view/art.gd")
const Postfx = preload("res://src/view/postfx.gd")
const Floors = preload("res://src/game/floors.gd")
const Stage3D = preload("res://src/view/stage3d.gd")
const Dungeon3D = preload("res://src/view/dungeon3d.gd")

const K := 2 # shown at 2x: 896x576, as a window about twice the base size shows it

var out_dir := ProjectSettings.globalize_path("res://build/shots/stage/") # build/ is gitignored
var only := ""
var walk := false
var vp: SubViewport
var stage: Stage3D
var rect: TextureRect
var post


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=").path_join("")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a == "--walk":
			walk = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1000, 640)
	RenderingServer.set_default_clear_color(Color(0.07, 0.07, 0.07))
	vp = SubViewport.new()
	vp.size = Vector2i(448, 288)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	stage = Stage3D.new()
	stage.reduced_motion = true # every shot is where it is put, no easing
	vp.add_child(stage)
	rect = TextureRect.new()
	rect.texture = vp.get_texture()
	rect.position = Vector2(20, 20)
	rect.size = Vector2(vp.size) * K
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(rect)
	post = Postfx.PostFx.create()
	if post != null:
		post.attach(rect)

	await shot("title", func(t): stage.title(t), 1200.0)

	seed(20261030)
	var map := Floors.gen_floor(5) # a champion floor
	map["seed"] = 424242
	var spot := best_spot(map)
	print("corridor spot: ", spot)
	for pi in [0, 3, 5, 1]:
		map["palette"] = Render.PALETTES[pi]
		stage.set_palette(map["palette"])
		var pal: Dictionary = map["palette"]
		await shot("corridor_%d_%s" % [pi, str(pal.name).to_lower().replace(" ", "_")], func(t): explore(map, spot, t))
	var st: Dictionary = map["stairs"]
	for d in 4:
		var back: Array = Render.DIRS[(d + 2) % 4]
		if Render._is_open(map["grid"], st.x + back[0], st.y + back[1]):
			map["palette"] = Render.PALETTES[4]
			stage.set_palette(map["palette"])
			await shot("stairs", func(t): explore(map, [st.x + back[0], st.y + back[1], d], t))
			break
	var b: Dictionary = map["boss"]
	map["palette"] = Render.PALETTES[2]
	stage.set_palette(map["palette"])
	await shot("champion_ahead", func(t): explore(map, [b.x, b.y + 2, 0], t))

	map["palette"] = Render.PALETTES[0]
	stage.set_palette(map["palette"])
	for sp in ["slime", "goblin", "dragon", "snake", "rock", "bandit"]:
		await shot("fight_" + sp, func(t): fight(map, spot, [[sp, {}]], t))
	await shot("fight_slime_shiny", func(t): fight(map, spot, [["slime", {"shiny": true}]], t), 1700.0)
	await shot("fight_goblin_champion", func(t): fight(map, spot, [["goblin", {"color": Art.BOSS_COLOR}]], t))
	await shot("fight_dragon_hurt", func(t): fight(map, spot, [["dragon", {}]], t, 0.8), 800.0)
	await shot("fight_group3", func(t): fight(map, spot, [["snake", {}], ["rock", {}], ["bandit", {"shiny": true}]], t), 2100.0)
	await shot("fight_group2", func(t): fight(map, spot, [["goblin", {}], ["slime", {}]], t), 900.0)
	if post != null:
		post.set_danger(0.8)
		post.pulse_level = 1.0
	await shot("fight_danger", func(t): fight(map, spot, [["bandit", {}]], t))
	if post != null:
		post.set_danger(0.0)
		post.pulse_level = 0.0
	# Boxed in: a wall behind you and in front, so the monsters stand near
	var boxed := boxed_spot(map)
	if not boxed.is_empty():
		await shot("fight_boxed_goblin", func(t): fight(map, boxed, [["goblin", {}]], t))
		await shot("fight_boxed_group3", func(t): fight(map, boxed, [["slime", {}], ["dragon", {}], ["rock", {}]], t))
	if walk:
		if post != null:
			post.set_danger(0.0)
			post.pulse_level = 0.0
		map["palette"] = Render.PALETTES[1]
		stage.set_palette(map["palette"])
		await walk_frames(map, spot)
	print("shots written to ", out_dir)
	quit()


## Three steps down the corridor, a turn toward an opening (or right), a step, then a goblin: one frame every 40 ms
## of game time, the camera easing as it does in the game
func walk_frames(map: Dictionary, start: Array) -> void:
	var dir_out := out_dir.path_join("walk")
	DirAccess.make_dir_recursive_absolute(dir_out)
	stage.reduced_motion = false
	var grid: Array = map["grid"]
	var at := start.duplicate()
	var plan := ["step", "step", "step", "turn", "step", "fight"]
	var t := 0.0
	var frame := 0
	var fighting := false
	for i in plan.size() + 1:
		if i > 0:
			var act: String = plan[i - 1]
			var f: Array = Render.DIRS[at[2]]
			if act == "step" and Render._is_open(grid, at[0] + f[0], at[1] + f[1]):
				at = [at[0] + f[0], at[1] + f[1], at[2]]
			elif act == "turn":
				var left: Array = Render.DIRS[(at[2] + 3) % 4]
				at = [at[0], at[1], (at[2] + 3) % 4 if Render._is_open(grid, at[0] + left[0], at[1] + left[1]) else (at[2] + 1) % 4]
			elif act == "fight":
				fighting = true
		var until := t + (1600.0 if fighting else 480.0)
		while t < until:
			if fighting:
				fight(map, at, [["goblin", {}]], t)
			else:
				explore(map, at, t)
			if post != null:
				post.set_accent(map["palette"].accent)
			await RenderingServer.frame_post_draw
			if post != null:
				post.render(t)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image().get_region(Rect2i(Vector2i(rect.position), Vector2i(rect.size)))
			img.save_png(dir_out.path_join("%03d.png" % frame))
			frame += 1
			t += 40.0
	print("walk: %d frames in %s" % [frame, dir_out])


func explore(map: Dictionary, at: Array, t: float) -> void:
	stage.use_map(map)
	stage.set_fight_visible(false)
	stage.place(at[0], at[1], at[2], t)
	stage.show_champion(map.get("boss"), t)
	stage.light(t)


func fight(map: Dictionary, at: Array, list: Array, t: float, hurt := 0.0) -> void:
	stage.use_map(map)
	stage.set_fight_visible(true)
	stage.place(at[0], at[1], at[2], t, list.size())
	var slots: Array = Art.SLOTS[clampi(list.size(), 1, 3)]
	var show := []
	for i in list.size():
		show.append({"id": "m%d" % i, "species": list[i][0], "look": list[i][1], "slot": slots[i], "hurt": hurt})
	stage.show_fight(show, t)
	stage.light(t)


func shot(name: String, setup: Callable, t := 600.0) -> void:
	if only != "" and not name.contains(only):
		return
	setup.call(t)
	if post != null:
		post.set_accent(stage._palette.get("accent", "#ffb347"))
	for i in 3:
		await RenderingServer.frame_post_draw
		if post != null:
			post.render(t)
	var full := root.get_texture().get_image()
	var crop := full.get_region(Rect2i(Vector2i(rect.position), Vector2i(rect.size)))
	crop.save_png(out_dir + name + ".png")
	print("saved ", out_dir + name + ".png")


## A floor cell and a facing with walls in front and behind (a corridor running across your view)
func boxed_spot(map: Dictionary) -> Array:
	var grid: Array = map["grid"]
	for y in grid.size():
		for x in grid[y].size():
			if grid[y][x] != 1:
				continue
			for dir in 4:
				var f: Array = Render.DIRS[dir]
				if not Render._is_open(grid, x + f[0], y + f[1]) and not Render._is_open(grid, x - f[0], y - f[1]):
					return [x, y, dir]
	return []


## The spot and facing (x, y, dir) with the most to look at: a long view down a corridor with torches in it
func best_spot(map: Dictionary) -> Array:
	var best := []
	var best_score := -1
	var grid: Array = map["grid"]
	var torches: Array = Dungeon3D.build(map)["torches"]
	for y in grid.size():
		for x in grid[y].size():
			if grid[y][x] != 1:
				continue
			for dir in 4:
				var back: Array = Render.DIRS[(dir + 2) % 4]
				if not Render._is_open(grid, x + back[0], y + back[1]):
					continue
				var ahead := 0
				var f: Array = Render.DIRS[dir]
				while ahead < 6 and Render._is_open(grid, x + f[0] * (ahead + 1), y + f[1] * (ahead + 1)):
					ahead += 1
				var cam: Vector3 = Stage3D.pose_of(x, y, dir).pos
				var fwd := Dungeon3D.dir_vec(dir)
				var lit := 0
				for tor in torches:
					var d: Vector3 = tor.pos - cam
					if d.dot(fwd) > 0.5 and d.length() < 7.0:
						lit += 1
				var score := ahead * 3 + lit * 4
				if score > best_score:
					best_score = score
					best = [x, y, dir]
	return best
