## Looks for monsters that don't show, or show only in part, by numbers (#45): the camera at the end of the longest straight line on a floor of
## each generator, a monster at every distance down it, drawn on the GPU in the set's own picture. Then monsters across open floor, at
## every cell the camera has a clear line to. Prints, per distance, how many pixels the model lights by itself (`alone`), how many of
## them are seen with the walls in place (`seen`), and whether its name shows. A case with a clear line and nothing seen is reported.
##   godot --path . -s res://tools/far_check.gd -- nosound [out=<dir>]
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const Stage = preload("res://src/view/stage.gd")
const Vision = preload("res://src/rules/vision.gd")

const SPECIES := ["slime", "bandit", "snake", "rock", "dragon"]
const SIZE := Vector2i(608, 288)
const LIT := 24 # of 255
const DEPTHS := [1, 2, 3, 4, 5] # each a biome's floor: halls, warren or caves, by the seed
const SIDE_CASES := 40
const STILL_DT := 1.0 / 60.0

var _view: SubViewport
var _out := ""
var _clock := 0.0
var _missed := 0
var _partly := 0


func _initialize() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "no-roaming"] + Array(OS.get_cmdline_user_args())))
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_out = Flags.value("out")
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	_view = SubViewport.new()
	_view.size = SIZE
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	var flow = Flow.new(Rng.new(11), LocalMind.new())
	await flow.new_run()
	var s = flow.state
	for depth in DEPTHS:
		s.depth = depth
		flow._make_floor()
		s.floor_map.monsters = s.floor_map.monsters.slice(0, 1)
		var m = s.floor_map.monsters[0]
		m.boss = false
		m.lurking = false
		s.floor_map.quester = {}
		s.floor_map.merchant = {}
		print("far: B%dF %s %dx%d" % [depth, s.floor_map.biome, s.floor_map.size, s.floor_map.size])
		await _down_the_line(s, m, depth)
		await _across_the_floor(s, m)
	print("far: done, %d not seen with a clear line, %d seen less than half" % [_missed, _partly])
	quit()


## The longest straight line of open floor.
func _longest_line(f) -> Array:
	var best := [Vector2i.ZERO, 0, 0]
	for y in f.size:
		for x in f.size:
			var c := Vector2i(x, y)
			if not f.is_open(c):
				continue
			for i in 4:
				var n := 0
				while f.is_open(c + FloorMap.DIRS[i] * (n + 1)):
					n += 1
				if n > best[2]:
					best = [c, i, n]
	return best


func _down_the_line(s, m, depth: int) -> void:
	var line := _longest_line(s.floor_map)
	s.cell = line[0]
	s.facing = line[1]
	s.look()
	print("far: line of %d cells; species distance alone seen name" % line[2])
	for species in SPECIES:
		m.species = species
		for d in range(1, line[2] + 1):
			m.cell = line[0] + FloorMap.DIRS[line[1]] * d
			var r: Dictionary = await _measure(s, m, "B%d_%s_%d" % [depth, species, d] if d in [1, 4, 8, 12] else "")
			print("far: %s %d %d %d %s" % [species, d, r.alone, r.seen, r.name])
			_tally(r)


func _across_the_floor(s, m) -> void:
	var f = s.floor_map
	var cases := 0
	var worst := 1.0
	var rng := Rng.new(5)
	var tries := 0
	m.species = "bandit"
	while cases < SIDE_CASES and tries < 4000:
		tries += 1
		var from := Vector2i(rng.int_range(0, f.size - 1), rng.int_range(0, f.size - 1))
		var to := Vector2i(rng.int_range(0, f.size - 1), rng.int_range(0, f.size - 1))
		if not f.is_open(from) or not f.is_open(to) or from == to:
			continue
		s.cell = from
		s.facing = rng.int_range(0, 3)
		s.look()
		if not s.in_sight.has(to):
			continue
		var eye := Vector2(from) + Vector2(0.5, 0.5) - Vector2(FloorMap.DIRS[s.facing]) * Vision.BACK
		if not Vision.sees_body(f, eye, to):
			continue
		m.cell = to
		var r: Dictionary = await _measure(s, m, "")
		cases += 1
		if r.alone == 0:
			continue # off the side of the picture
		_tally(r)
		worst = minf(worst, float(r.seen) / r.alone)
		if r.seen == 0:
			print("far: NOT SEEN from %s facing %d to %s (seed %d)" % [from, s.facing, to, f.seed_value])
	print("far: %d cases across the floor, worst share seen %.2f" % [cases, worst])


func _tally(r: Dictionary) -> void:
	if r.alone > 0 and r.seen == 0:
		_missed += 1
	elif r.alone > 0 and r.seen * 2 < r.alone:
		_partly += 1


## Draw the set with the monster in it: alone, then with the walls, against the same picture without it.
func _measure(s, m, picture: String) -> Dictionary:
	var stage: Node3D = Stage.new()
	_view.add_child(stage)
	_clock += 1.0
	stage.update(s, _clock, STILL_DT)
	_clock += 1.0
	stage.update(s, _clock, STILL_DT) # past any glide
	var model: Node3D = stage._models[m]
	var tag: Label3D = stage._tags[m]
	var name_shows: bool = tag.get_meta("wanted", false)
	for t in stage._tags.values():
		t.visible = false
	stage._wall_mat.set_shader_parameter("torches", PackedVector4Array())
	var whole: PackedByteArray = await _draw()
	if picture != "" and _out != "":
		_view.get_texture().get_image().save_png("%s/%s.png" % [_out, picture])
	model.visible = false
	var without: PackedByteArray = await _draw()
	var hidden := []
	for child in stage.get_children():
		if child is Node3D and child != stage._camera and child.visible:
			child.visible = false
			hidden.append(child)
	model.visible = true
	var alone_px: PackedByteArray = await _draw()
	var alone := 0
	var seen := 0
	for i in alone_px.size():
		if alone_px[i] > LIT:
			alone += 1
			if absi(int(whole[i]) - int(without[i])) > LIT:
				seen += 1
	stage.queue_free()
	await process_frame
	return {"alone": alone, "seen": seen, "name": name_shows}


func _draw() -> PackedByteArray:
	await process_frame # moved nodes tell the renderer only here
	RenderingServer.force_draw(false, STILL_DT)
	var data: PackedByteArray = _view.get_texture().get_image().get_data()
	var stride: int = data.size() / (SIZE.x * SIZE.y)
	var out := PackedByteArray()
	out.resize(SIZE.x * SIZE.y)
	for i in out.size():
		var k := i * stride
		out[i] = maxi(data[k], maxi(data[k + 1], data[k + 2]))
	return out
