## Pictures of the test room, to look at: its row on the main menu, walking in, the view down an aisle, facing one of them, a
## fight with a deep one, the room put back after it, the whole map, the champions' row and the way out. It needs a real window:
##   godot --path . -s res://tools/room_shots.gd -- out=/some/dir [nofocus]
## Nothing reaches the player's saves (`nosave` is always on).
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

var _out := ""
var _game


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave", "nosound", "notips", "nojev", "seed=7"]))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://room_shots"))
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	if Flags.on("nofocus"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	else:
		DisplayServer.window_move_to_foreground()
	# its row on the main menu
	var menu = load("res://src/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _wait(0.5)
	for _i in 8:
		if menu.panel._page.items[menu.panel._selected].label == "TEST ROOM":
			break
		menu.panel._gui_input(_key(KEY_DOWN))
	await _wait(0.2)
	await _shot("0_main_menu")
	menu.queue_free()
	await _wait(0.2)
	# walking in
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave", "nosound", "notips", "nojev", "seed=7", "test-room"]))
	_game = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(_game)
	await _wait(1.5)
	var flow = _game.flow
	var s = flow.state
	var f = s.floor_map
	await _shot("1_walking_in")
	s.banner = null
	await _wait(0.3)
	await _shot("2_down_the_aisle")
	await flow.press("up")
	await _wait(0.6)
	await flow.press("left")
	await _wait(0.8)
	await _shot("3_facing_one")
	await flow.press("right")
	await _wait(0.8)
	await _shot("4_between_two")
	# a fight with a deep one, and the room after it
	var deep = f.monsters.filter(func(m): return m.kind == "cobra")[0]
	s.cell = deep.cell + FloorMap.DIRS[1]
	s.facing = 3
	s.look()
	await _wait(0.8)
	await _shot("5_before_a_deep_one")
	await flow.press("up")
	await _until("menu")
	await _wait(0.6)
	await _shot("6_its_fight")
	await flow.encounter.defeat(deep, "slain")
	await _wait(1.2)
	await _shot("7_put_back")
	# the whole floor on the map
	_game.show_map(true)
	await _wait(0.4)
	await _shot("8_full_map")
	_game.show_map(false)
	# the far end: the elites and the champions
	s.cell = Vector2i(f.start.x, 3)
	s.facing = 0
	s.look()
	await _wait(0.8)
	await _shot("9_elites_and_champions")
	var champion = f.monsters.filter(func(m): return m.boss)[2]
	s.cell = champion.cell + FloorMap.DIRS[2]
	s.facing = 0
	s.look()
	await flow.press("left")
	await flow.press("right")
	await _wait(0.8)
	await _shot("10_a_champion")
	# the way out
	await flow.tick(flow.clock + 60000.0)
	s.cell = f.stairs + FloorMap.DIRS[1] * 2
	s.facing = 3
	s.look()
	await _wait(0.8)
	await _shot("11_the_way_out_ahead")
	await flow.press("up")
	await flow.press("up")
	await _wait(1.2)
	await _shot("12_the_way_out")
	await flow.press("1")
	await _wait(0.3)
	_game._open_pause()
	await _wait(0.3)
	await _shot("13_pause")
	print("room_shots: written to %s" % _out)
	quit()


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


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
	print("room_shots: %s" % name)
