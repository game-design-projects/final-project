## Renders the view modules to PNGs so they can be looked at: the title, a corridor on three palettes, the automap,
## every monster (plus a shiny, a champion and a group of three), and the corridor through the post-processing shader at
## 2.5x with danger 0 and 0.8, hurt and flash. Needs a real window (it opens one briefly and quits):
##   $G --path . -s res://cli/view_shots.gd [-- --out=/some/dir]
extends SceneTree

const J = preload("res://src/core/js.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")
const Render = preload("res://src/view/render.gd")
const Art = preload("res://src/view/art.gd")
const Postfx = preload("res://src/view/postfx.gd")

var out_dir := ProjectSettings.globalize_path("res://build/shots/view/") # build/ is gitignored
var view_vp: SubViewport
var painter: Painter


class Painter:
	extends Node2D
	var size := Vector2(448, 288)
	var fn := Callable()

	func _draw() -> void:
		if fn.is_valid():
			fn.call(Canvas2D.new(self, size))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=").path_join("")
	DirAccess.make_dir_recursive_absolute(out_dir)
	# One canvas unit is one screen pixel, so the shots show exactly what the shader makes of each pixel
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1240, 780)
	RenderingServer.set_default_clear_color(Color(0.07, 0.07, 0.07))

	view_vp = SubViewport.new()
	view_vp.size = Vector2i(448, 288)
	view_vp.disable_3d = true
	view_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view_vp)
	painter = Painter.new()
	view_vp.add_child(painter)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261029
	var map := gen_floor(2, rng)
	map["palette"] = Render.PALETTES[0]
	map["seed"] = 424242

	# ---- title
	await shot("title", func(ctx): Render.draw_title(ctx, 0.0))

	# ---- the corridor on three palettes, from the most interesting spot of the floor
	var spot := best_spot(map)
	print("corridor spot: ", spot)
	# the same scene for the JS reference render (crawler/public/render.js) to compare against
	var scene := FileAccess.open(out_dir + "scene.json", FileAccess.WRITE)
	scene.store_string(JSON.stringify({"grid": map["grid"], "stairs": map["stairs"], "seed": map["seed"], "spot": spot, "n": map["n"]}))
	scene.close()
	for pi in [0, 3, 5]:
		map["palette"] = Render.PALETTES[pi]
		var pal: Dictionary = map["palette"]
		await shot("corridor_%d_%s" % [pi, str(pal.name).to_lower().replace(" ", "_")], func(ctx): Render.draw_corridor(ctx, map, spot[0], spot[1], spot[2], 1234.0))
	# the stairs
	var st: Dictionary = map["stairs"]
	for d in 4:
		var front: Array = Render.DIRS[d]
		var back: Array = Render.DIRS[(d + 2) % 4]
		if Render._is_open(map["grid"], st.x + back[0], st.y + back[1]) and Render._is_open(map["grid"], st.x + back[0] * 2, st.y + back[1] * 2):
			map["palette"] = Render.PALETTES[4]
			await shot("corridor_stairs", func(ctx): Render.draw_corridor(ctx, map, st.x + back[0] * 2, st.y + back[1] * 2, d, 500.0))
			break

	# ---- the automap, after walking a bit
	map["palette"] = Render.PALETTES[1]
	var seen := {}
	var visited := {}
	var n: int = map["n"]
	for pos in walk(map, 60, rng):
		visited[pos[1] * n + pos[0]] = true
		for dir in 4:
			for c in Render.visible_cells(map, pos[0], pos[1], dir):
				seen[c[1] * n + c[0]] = true
	map["boss"] = {"x": n / 2, "y": n / 2, "defeated": false}
	seen[(n / 2) * n + n / 2] = true
	seen[st.y * n + st.x] = true
	painter.size = Vector2(105, 105)
	view_vp.size = Vector2i(105, 105)
	await shot("automap", func(ctx): Render.draw_map(ctx, map, seen, visited, spot[0], spot[1], spot[2]), 6)
	painter.size = Vector2(448, 288)
	view_vp.size = Vector2i(448, 288)

	# ---- monsters
	for sp in ["slime", "goblin", "dragon", "snake", "rock", "bandit"]:
		await shot("monster_" + sp, func(ctx): monster_view(ctx, [[sp, {}]]), 1)
	await shot("monster_slime_shiny", func(ctx): monster_view(ctx, [["slime", {"shiny": true}]], 1700.0))
	await shot("monster_goblin_boss", func(ctx): monster_view(ctx, [["goblin", {"color": Art.BOSS_COLOR}]]))
	await shot("monster_dragon_hurt", func(ctx): monster_view(ctx, [["dragon", {}]], 800.0, 1.0))
	await shot("monsters_group3", func(ctx): monster_view(ctx, [["snake", {}], ["rock", {}], ["bandit", {"shiny": true}]], 2100.0))
	await shot("monsters_group2", func(ctx): monster_view(ctx, [["goblin", {}], ["slime", {}]], 900.0))

	# ---- through the shader at 2.5x
	await fx_shots(map, spot)

	print("shots written to ", out_dir)
	quit()


# ---------------------------------------------------------------- helpers

func shot(name: String, fn: Callable, upscale := 1) -> void:
	painter.fn = fn
	painter.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := view_vp.get_texture().get_image()
	if upscale > 1:
		img.resize(img.get_width() * upscale, img.get_height() * upscale, Image.INTERPOLATE_NEAREST)
	var path := out_dir + name + ".png"
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func monster_view(ctx, list: Array, t := 600.0, hurt := 0.0) -> void:
	Render.clear(ctx)
	var slots: Array = Art.SLOTS[clampi(list.size(), 1, 3)]
	for i in list.size():
		Art.draw_monster(ctx, list[i][0], t, hurt, slots[i], 1, list[i][1])


func fx_shots(map: Dictionary, spot: Array) -> void:
	var rect := TextureRect.new()
	rect.texture = view_vp.get_texture()
	rect.position = Vector2(60, 30)
	rect.size = Vector2(448, 288) * 2.5
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(rect)
	var post := Postfx.PostFx.create()
	post.attach(rect)
	map["palette"] = Render.PALETTES[0]
	post.set_accent(map["palette"].accent)
	painter.fn = func(ctx): Render.draw_corridor(ctx, map, spot[0], spot[1], spot[2], 1234.0)
	painter.queue_redraw()
	var cases := {
		"fx_corridor_danger0": {},
		"fx_corridor_danger08": {"danger": 0.8, "pulse": true},
		"fx_corridor_hurt": {"hurt": 1.0},
		"fx_corridor_flash": {"flash": ["#ffe03a", 0.45]},
	}
	for name in cases:
		var c: Dictionary = cases[name]
		post.danger = 0.0
		post.hurt_level = 0.0
		post.split_level = 0.0
		post.flash_level = 0.0
		post.pulse_level = 0.0
		post.last = null
		post.set_danger(c.get("danger", 0.0))
		if c.has("hurt"):
			post.hurt(c["hurt"])
		if c.has("flash"):
			post.flash(c["flash"][0], c["flash"][1])
		if c.has("pulse"):
			post.pulse_level = 1.0
		# render() decays from the previous call, so the first call after `last = null` keeps the levels as set
		await RenderingServer.frame_post_draw
		post.render(0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var full := root.get_texture().get_image()
		print("window image ", full.get_size())
		var crop := full.get_region(Rect2i(Vector2i(rect.position), Vector2i(rect.size)))
		crop.save_png(out_dir + name + ".png")
		print("saved ", out_dir + name + ".png", " ", crop.get_size())
	# the title and a monster fight through the shader as well
	post.danger = 0.0
	post.hurt_level = 0.0
	post.split_level = 0.0
	post.flash_level = 0.0
	post.set_danger(0.0)
	post.set_accent("#ffb347")
	painter.fn = func(ctx): Render.draw_title(ctx, 0.0)
	painter.queue_redraw()
	await RenderingServer.frame_post_draw
	post.render(0.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(Vector2i(rect.position), Vector2i(rect.size))).save_png(out_dir + "fx_title.png")
	painter.fn = func(ctx): monster_view(ctx, [["goblin", {}]], 300.0)
	painter.queue_redraw()
	await RenderingServer.frame_post_draw
	post.render(100.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(Vector2i(rect.position), Vector2i(rect.size))).save_png(out_dir + "fx_goblin.png")


## The spot and facing (x, y, dir) with the richest view: many faces, a torch, a decorated wall
func best_spot(map: Dictionary) -> Array:
	var best := []
	var best_score := -1
	var grid: Array = map["grid"]
	for y in grid.size():
		for x in grid[y].size():
			if grid[y][x] != 1:
				continue
			for dir in 4:
				# a real corridor: walls on both sides of you and of the next two cells ahead
				var shut := true
				for d in 3:
					for k in [-1, 1]:
						shut = shut and not Render._is_open_at(grid, Render._cell_at(x, y, dir, d, k))
				if not shut:
					continue
				var v := Render.corridor_view(map, x, y, dir)
				var decor := 0
				for d in v["decor"]:
					if d != null:
						decor += 3 if d["kind"] == "torch" else 1
				# how far down the view you can see (floor cells in view, ahead), and how much there is on the walls
				var ahead := 0
				var fwd: Array = Render.DIRS[dir]
				for c in v["cells"]:
					ahead = maxi(ahead, (c[0] - x) * fwd[0] + (c[1] - y) * fwd[1])
				var score: int = v["cells"].size() * 2 + decor * 4 + ahead * 30
				if score > best_score:
					best_score = score
					best = [x, y, dir]
	return best


## A random walk over the floor, for the automap
func walk(map: Dictionary, steps: int, rng: RandomNumberGenerator) -> Array:
	var x := 1
	var y := 1
	var path := [[x, y]]
	var grid: Array = map["grid"]
	var dir := 1
	for i in steps * 6:
		var d: Array = Render.DIRS[dir]
		if Render._is_open(grid, x + d[0], y + d[1]) and rng.randf() < 0.85:
			x += d[0]
			y += d[1]
			path.append([x, y])
		else:
			dir = rng.randi() % 4
		if path.size() >= steps:
			break
	return path


## The map the game makes (genFloor in game.js): a depth-first maze on odd cells, some walls knocked through, a few
## small rooms, the stairs at the farthest cell
func gen_floor(floor_n: int, rng: RandomNumberGenerator) -> Dictionary:
	var n := mini(25, 13 + 2 * floor_n)
	var grid := []
	for y in n:
		var row := []
		row.resize(n)
		row.fill(0)
		grid.append(row)
	var stack := [[1, 1]]
	grid[1][1] = 1
	while not stack.is_empty():
		var cur: Array = stack[-1]
		var options := []
		for d in Render.DIRS:
			var nx: int = cur[0] + d[0] * 2
			var ny: int = cur[1] + d[1] * 2
			if nx > 0 and ny > 0 and nx < n - 1 and ny < n - 1 and grid[ny][nx] == 0:
				options.append([nx, ny, cur[0] + d[0], cur[1] + d[1]])
		if options.is_empty():
			stack.pop_back()
			continue
		var o: Array = options[rng.randi() % options.size()]
		grid[o[3]][o[2]] = 1
		grid[o[1]][o[0]] = 1
		stack.append([o[0], o[1]])
	for i in J.round_js(28 * pow(n / 21.0, 2)):
		var x := rng.randi_range(1, n - 2)
		var y := rng.randi_range(1, n - 2)
		if grid[y][x] == 1:
			continue
		if (grid[y][x - 1] == 1 and grid[y][x + 1] == 1) or (grid[y - 1][x] == 1 and grid[y + 1][x] == 1):
			grid[y][x] = 1
	for r in 2 + n / 10:
		var x := rng.randi_range(1, n - 5) | 1
		var y := rng.randi_range(1, n - 5) | 1
		for yy in range(y, y + 3):
			for xx in range(x, x + 3):
				grid[yy][xx] = 1
	# the stairs: the floor cell farthest from the start
	var dist := {Vector2i(1, 1): 0}
	var queue := [Vector2i(1, 1)]
	var far := Vector2i(1, 1)
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for d in Render.DIRS:
			var q := Vector2i(p.x + d[0], p.y + d[1])
			if grid[q.y][q.x] == 1 and not dist.has(q):
				dist[q] = dist[p] + 1
				queue.append(q)
				if dist[q] > dist[far]:
					far = q
	return {"grid": grid, "n": n, "stairs": {"x": far.x, "y": far.y}, "floor": floor_n, "boss": null}
