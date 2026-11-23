## Pictures of what the walk stops at, to look at: a champion's keepsakes, the gate and its chain, the stairs, the shut door,
## a run's end and the camp. Each is taken twice, a moment apart, so the moving picture can be seen to move. It needs a real
## window:
##   godot --path . -s res://tools/event_shots.gd -- out=/some/dir [nofocus]
## Nothing reaches the player's saves (`nosave` is always on).
extends SceneTree

const Ally = preload("res://src/game/ally.gd")
const Flags = preload("res://src/utils/flags.gd")
const Floors = preload("res://src/rules/floors.gd")

var _out := ""
var _game


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave", "nosound", "notips", "nojev", "seed=7"]))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://event_shots"))
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
	await _past_story()
	var flow = _game.flow
	var s = flow.state
	# a champion out of the way leaves three keepsakes
	var boss = s.floor_map.monsters.filter(func(x): return x.boss).front()
	await flow.go("intro", {"foe": boss})
	await _until("menu")
	await flow.encounter.defeat(boss, "slain")
	await _pair("1_keepsakes")
	await flow.press("right")
	await _wait(0.2)
	await _shot("1c_keepsakes_second_picked")
	await flow.press("confirm")
	await _wait(0.4)
	# the camp: its commands stay in the dock, the fire is over the picture
	s.banner = null
	await flow.go("camp")
	await _pair("2_camp")
	await flow.press("cancel")
	# the gate on the third stairs, with two friends to leave
	s.depth = int(Floors.toll().depth)
	s.allies = [Ally.make("slime", "GLOP", 60.0), Ally.make("snake", "HISS", 60.0)]
	s.banner = null
	await flow.go("end")
	await _pair("3_gate")
	await flow.press("1")
	await _pair("4_stairs")
	# the last door, alone; then the lonely way out, and a run cleared
	s.depth = s.floors_of if s.floors_of > 0 else 5
	s.allies = []
	await flow.go("explore", {"lines": []})
	await flow.go("end")
	await _pair("5_door")
	s.allies = [Ally.make("slime", "GLOP", 60.0)]
	await flow.go("explore", {"lines": []})
	await flow.go("end")
	await _pair("6_ending")
	print("event_shots: written to %s" % _out)
	quit()


func _pair(name: String) -> void:
	await _wait(0.5)
	await _past_story()
	await _shot(name + "_a")
	await _wait(0.9)
	await _shot(name + "_b")


## A moment of the story is a drawing over everything, and the game holds still under it (view/story_cg.gd): send it away, as a
## key would, so the walk goes on and the picture taken is of what the walk stopped at.
func _past_story() -> void:
	var story = _game._story
	var tries := 0
	while story.visible and tries < 8:
		story._age = 99.0 # past the guard that keeps the key that brought it on from sending it away
		story._dismiss()
		await _wait(0.45)
		tries += 1


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _until(stage: String) -> void:
	var waited := 0.0
	while _game.flow.state.stage != stage and waited < 20.0:
		await _past_story()
		if _game.flow.state.hint == "ANY KEY CONTINUE":
			await _game.flow.press("confirm")
		await _wait(0.1)
		waited += 0.1


func _shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("event_shots: %s" % name)
