## What a wall and a monster one cell away look like, and a corridor further off, for choosing where the camera stands and how wide
## the picture is (tests can't judge looks). Run it once per setting, with the flags to compare:
##   godot --path . -s res://tools/camera_shots.gd -- out=<dir> label=now nosound no-close-camera no-wide-view
##   godot --path . -s res://tools/camera_shots.gd -- out=<dir> label=new nosound
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

const FAR_OFF := 5

var _out := ""
var _label := "shot"
var _game


func _initialize() -> void:
	var words := Array(OS.get_cmdline_user_args())
	for word in words.filter(func(w): return w.begins_with("label=")):
		_label = word.trim_prefix("label=")
		words.erase(word)
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=7", "no-tutorial", "no-story"] + words))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://camera_shots"))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_game = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(_game)
	await _wait(0.6)
	await _game._begin()
	await _wait(0.4)
	var s = _game.flow.state
	s.banner = null
	var m = s.floor_map.monsters[0]
	await _before(m, 1, "monster_next_cell")
	await _before(m, 2, "monster_two_cells")
	await _at_a_wall(s)
	await _longest_view(s)
	print("camera_shots: written to %s" % _out)
	quit()


## Stand `steps` cells from the monster with a clear line, looking at it.
func _before(m, steps: int, name: String) -> void:
	var s = _game.flow.state
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
			break
	await _wait(0.5)
	await _shot(name)


func _at_a_wall(s) -> void:
	var f = s.floor_map
	for y in f.size:
		for x in f.size:
			var c := Vector2i(x, y)
			if not f.is_open(c) or f.monsters.any(func(m): return m.cell.distance_to(c) < 3.0):
				continue
			for i in 4:
				if not f.is_open(c + FloorMap.DIRS[i]) and not f.is_cracked(c + FloorMap.DIRS[i]) and f.is_open(c - FloorMap.DIRS[i]):
					s.cell = c
					s.facing = i
					s.look()
					await _wait(0.5)
					await _shot("wall_end_of_your_cell")
					return


## The longest straight run on the floor, from one end: the corridor must still look right further away.
func _longest_view(s) -> void:
	var f = s.floor_map
	var best := []
	var facing := 0
	for y in f.size:
		for x in f.size:
			var c := Vector2i(x, y)
			if not f.is_open(c):
				continue
			for i in 4:
				var run := 0
				var at: Vector2i = c + FloorMap.DIRS[i]
				while f.is_open(at):
					run += 1
					at += FloorMap.DIRS[i]
				if run > best.size():
					best = range(run)
					s.cell = c
					facing = i
	s.facing = facing
	s.look()
	await _wait(0.5)
	await _shot("corridor")


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [_out, _label, name])
	print("camera_shots: %s" % name)
