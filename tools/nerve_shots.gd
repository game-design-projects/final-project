## Pictures of nerve, of what a foe's mood does to its attack and of the friends' marks on the strike bar, to look at: the pips
## beside the dodge box, a square in its last moments, the ring of a close call, a heart to catch, the fight menu with nerve to
## spend, and a strike the friends follow. It needs a real window:
##   godot --path . -s res://tools/nerve_shots.gd -- out=/some/dir [nofocus]
## Nothing reaches the player's saves (`nosave` is always on).
extends SceneTree

const Ally = preload("res://src/game/ally.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const Flags = preload("res://src/utils/flags.gd")

var _out := ""
var _game


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave", "nosound", "notips", "nojev", "seed=7"]))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://nerve_shots"))
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	if Flags.on("nofocus"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	else:
		DisplayServer.window_move_to_foreground()
	_game = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(_game)
	await _wait(0.6)
	await _game._begin()
	await _wait(0.4)
	var flow = _game.flow
	var s = flow.state
	var m = s.floor_map.monsters.filter(func(x): return not x.boss).front()
	m.max_hp = 500
	m.hp = 500
	s.rotate_mini_games = false
	await flow.go("intro", {"foe": m})
	await _until("menu")
	# the menu with nerve to spend
	s.nerve = 3
	s.banner = null
	await flow.go("menu")
	await _wait(0.4)
	await _shot("1_menu_with_nerve")
	await flow.press("1")
	await _wait(0.3)
	await _shot("2_strike_bar_with_nerve")
	# the box: pips, a square in its last moments, then the ring of the close call
	s.nerve = 2
	s.max_hp = 999
	s.hp = 999
	s.bar = null
	s.banner = null
	await flow.go("wait", {"pressure": 1.0})
	await _until("dodge")
	var run = s.dodge
	run.end_t = flow.clock + 60000.0
	run.next_t = flow.clock + 60000.0 # nothing of its own for the pictures
	run.hazards = []
	var here := Dodge.index(run.soul.x, run.soul.y)
	run.add_hazard(flow.clock, Dodge.row_cells(run.soul.y), 500.0 * run.pace, 300.0, "chess", {"glyph": "R", "at": Dodge.index(0, run.soul.y)})
	await _wait(0.33)
	await _shot("3_last_moment")
	await flow.press("up")
	await _wait(0.08)
	await _shot("4_close_call")
	await _wait(0.9)
	# a friendly foe's heart
	run.hazards = []
	run.add_hazard(flow.clock, [here + 9], 600.0 * run.pace, 4000.0, "heart", {"at": here + 9})
	run.add_hazard(flow.clock, [here + 2], 0.0, 4000.0, "heart", {"at": here + 2})
	await _wait(0.35)
	await _shot("5_hearts")
	# the strike bar with friends: your strike has landed, the first friend's too, and the line is on its way to the second mark
	run.hazards = []
	run.end_t = flow.clock
	await _until("menu")
	s.banner = null
	s.allies = [Ally.make("slime", "GLOP", 60.0), Ally.make("snake", "HISS", 60.0), Ally.make("rock", "OLD SHALE", 60.0)]
	await flow.press("1")
	await _wait(0.1)
	s.bar.dur = 600000.0 # hold the line still for the picture
	s.bar.t0 = flow.clock - s.bar.dur * 0.5
	await flow.press("confirm")
	s.bar.marks[0].state = "hit"
	s.bar.t0 = flow.clock - s.bar.dur * 0.75
	await _wait(0.2)
	await _shot("6_follow_through")
	print("nerve_shots: written to %s" % _out)
	quit()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _until(stage: String) -> void:
	var waited := 0.0
	while _game.flow.state.stage != stage and waited < 20.0:
		if _game.flow.state.hint == "ANY KEY CONTINUE":
			await _game.flow.press("confirm")
		await _wait(0.1)
		waited += 0.1


func _shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("nerve_shots: %s" % name)
