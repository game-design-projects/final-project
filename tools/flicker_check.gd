## Looks for flicker in the monster models, by numbers (#47): each species at a few distances, the camera still and then gliding a step,
## frame by frame at a fixed rate, in the set's own picture with no post-processing. Prints, per case:
##   blink  pixels whose brightness turned round FLIPS times or more in FRAMES frames, each time by SWING or more: on, off, on, off (a line
##          that shimmers, a part that fights another). A line sliding across a pixel is on and off once, so it doesn't count. Worst of a few moments.
##   jump   the biggest change in how many of the model's pixels are lit from one frame to the next while gliding, as a share of them (a part popping)
## Each frame is drawn on demand, so the run neither waits on the window (a hidden one draws nothing) nor shows anything in it.
##   godot --path . -s res://tools/flicker_check.gd -- nosound [only=bandit] [out=<dir>]
## With out=, every case leaves a picture of its last frame with the blinking pixels in white, to see which part it is.
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const Stage = preload("res://src/view/stage.gd")

const SPECIES := ["slime", "bandit", "snake", "rock", "dragon"]
const DISTANCES := [1, 2, 4, 7]
const SIZE := Vector2i(608, 288)
const FRAMES := 40
const FLIPS := 4
const SWING := 48 # of 255: less than this isn't seen as a blink
const LIT := 40 # of 255: brighter than this counts as lit
const MOMENTS := [0.0, 0.7, 0.7, 0.7]
const STILL_DT := 1.0 / 60.0
const GLIDE_DT := 1.0 / 120.0

var _view: SubViewport
var _clock := 0.0
var _out := ""
var _name := ""


func _initialize() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=7", "no-roaming"] + Array(OS.get_cmdline_user_args())))
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_out = Flags.value("out")
	_view = SubViewport.new()
	_view.size = SIZE
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	var flow = Flow.new(Rng.new(7), LocalMind.new())
	await flow.new_run()
	var s = flow.state
	s.floor_map.monsters = s.floor_map.monsters.slice(0, 1)
	var m = s.floor_map.monsters[0]
	m.boss = false
	print("flicker: sprite-look %s" % s.viewing("sprite-look"))
	print("flicker: species distance blink jump")
	var only := Flags.value("only")
	var worst := 0
	for species in SPECIES:
		if only != "" and only != species:
			continue
		m.species = species
		for d in DISTANCES:
			var stage: Node3D = Stage.new()
			_view.add_child(stage)
			if not _stand_before(s, m, d + 1):
				stage.free()
				continue
			stage.update(s, _clock, STILL_DT)
			_stand_before(s, m, d + 1)
			_name = "%s_%d" % [species, d]
			var blink: int = await _blink(stage, s)
			var jump: float = await _jump(stage, s, m, d)
			worst = maxi(worst, blink)
			print("flicker: %s %d %d %.3f" % [species, d, blink, jump])
			stage.queue_free()
			await process_frame
	print("flicker: done, worst blink %d" % worst)
	quit()


func _stand_before(s, m, steps: int) -> bool:
	var f = s.floor_map
	for i in 4:
		var c: Vector2i = m.cell
		var n := 0
		while n < steps and f.is_open(c - FloorMap.DIRS[i]):
			c -= FloorMap.DIRS[i]
			n += 1
		if n == steps:
			s.cell = c
			s.facing = i
			s.look()
			return true
	return false


## How bright each pixel is, as a byte per pixel.
func _brightness(dt: float) -> PackedByteArray:
	await process_frame # moved nodes tell the renderer only here
	RenderingServer.force_draw(false, dt)
	var data: PackedByteArray = _view.get_texture().get_image().get_data() # RGB8 or RGBA8
	var stride: int = data.size() / (SIZE.x * SIZE.y)
	var out := PackedByteArray()
	out.resize(SIZE.x * SIZE.y)
	for i in out.size():
		var k := i * stride
		out[i] = maxi(data[k], maxi(data[k + 1], data[k + 2]))
	return out


## The name tag fades in and out by design, and the torches flicker by design: neither is what is being measured. `alone` also
## takes everything but this model out of the picture (the stage shows what it shows again on each update).
func _update(stage, s, dt: float, alone: Node3D = null) -> void:
	stage.update(s, _clock, dt)
	for tag in stage._tags.values():
		tag.visible = false
	stage._wall_mat.set_shader_parameter("torches", PackedVector4Array())
	if alone != null:
		for child in stage.get_children():
			if child is Node3D and child != alone and child != stage._camera:
				child.visible = false


## A pixel counts a flip each time its brightness turns round by SWING or more. Over one stretch of FRAMES.
func _blink_once(stage, s) -> PackedInt32Array:
	var flips := PackedInt32Array()
	flips.resize(SIZE.x * SIZE.y)
	var way := PackedByteArray() # 0 no way yet, 1 rising, 2 falling
	way.resize(SIZE.x * SIZE.y)
	var peak := PackedByteArray() # the furthest it has gone that way
	for _f in FRAMES:
		_clock += STILL_DT
		_update(stage, s, STILL_DT)
		var now: PackedByteArray = await _brightness(STILL_DT)
		if peak.is_empty():
			peak = now
			continue
		for i in now.size():
			var d := int(now[i]) - int(peak[i])
			if way[i] == 1 and d > 0 or way[i] == 2 and d < 0:
				peak[i] = now[i]
			elif d >= SWING or d <= -SWING:
				way[i] = 1 if d > 0 else 2
				peak[i] = now[i]
				flips[i] += 1
	return flips


## The parts move in slow cycles, so one stretch can catch them near still: the worst of a few, spread round the cycle.
func _blink(stage, s) -> int:
	var worst := 0
	for moment in MOMENTS:
		_clock += moment
		var flips: PackedInt32Array = await _blink_once(stage, s)
		var blinking := 0
		for f in flips:
			if f >= FLIPS:
				blinking += 1
		if blinking >= worst:
			worst = blinking
			if _out != "":
				_save_heat(flips)
	return worst


func _save_heat(flips: PackedInt32Array) -> void:
	var picture: Image = _view.get_texture().get_image()
	picture.convert(Image.FORMAT_RGB8)
	for i in flips.size():
		if flips[i] >= FLIPS:
			picture.set_pixel(i % SIZE.x, i / SIZE.x, Color.WHITE)
	DirAccess.make_dir_recursive_absolute(_out)
	picture.save_png("%s/%s.png" % [_out, _name])


## Only the model in the picture, so the walls and whatever lies on the floor coming into view don't count.
func _jump(stage, s, m, d: int) -> float:
	_stand_before(s, m, d)
	var model: Node3D = stage._models[m]
	var counts := []
	for _f in 18:
		_clock += GLIDE_DT
		_update(stage, s, GLIDE_DT, model)
		var now: PackedByteArray = await _brightness(GLIDE_DT)
		var n := 0
		for p in now:
			if p > LIT:
				n += 1
		counts.append(n)
	var worst := 0.0
	for i in range(1, counts.size()):
		worst = maxf(worst, absf(counts[i] - counts[i - 1]) / maxf(1.0, float(counts[i])))
	return worst
