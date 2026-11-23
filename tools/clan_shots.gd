## Pictures of the clans' askers, to look at: one standing on a floor, what it asks, a line typed to it, a request paid, the
## teleporter offered at the stairs, the teleport as it happens, the clan's hall with its own either side and its lord at the
## end, and the lord saying its piece. It needs a real window:
##   godot --path . -s res://tools/clan_shots.gd -- out=/some/dir [nofocus]
## Nothing reaches the player's saves (`nosave` is always on).
extends SceneTree

const Ally = preload("res://src/game/ally.gd")
const Envoys = preload("res://src/rules/envoys.gd")
const Flags = preload("res://src/utils/flags.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

var _out := ""
var _game


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave", "nosound", "notips", "nojev", "seed=7"]))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://clan_shots"))
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
	var f = s.floor_map
	# an asker on the floor, from two cells off, and what it asks
	var asker: Dictionary = f.envoys[0]
	s.banner = null
	_look_at(s, f, asker.cell)
	await _wait(0.6)
	await _shot("1_asker_ahead")
	var coil := Envoys.figure("coil", asker.cell)
	await flow.go("envoy", {"who": coil})
	await _wait(0.4)
	await _shot("2_what_it_asks")
	# something typed to it: too short, then long enough
	await flow.press("2")
	await _wait(0.4)
	await _shot("3_typing_to_it")
	await flow.submit_text("hiss")
	await _wait(0.4)
	await _shot("4_too_short")
	await flow.go("envoy", {"who": coil})
	await flow.press("2")
	await flow.submit_text("hissssssssssss")
	await _wait(0.5)
	await _shot("5_request_done")
	# a friend handed over: the second request done opens the teleporter
	s.banner = null
	await flow.go("envoy", {"who": coil})
	await flow.press("1")
	s.allies = [Ally.make("bandit", "JINKS", 60.0)]
	await flow.go("envoy", {"who": coil})
	await _wait(0.4)
	await _shot("6_a_friend_to_hand_over")
	await flow.press("1")
	await _wait(0.5)
	await _shot("7_teleporter_open")
	# the stairs offer it; through it, the picture tears; then the hall and its lord
	s.banner = null
	await flow.go("end")
	await _wait(0.6)
	await _shot("8_stairs_offer_it")
	var row: int = s.menu.find_custom(func(r): return str(r.label).contains("TELEPORTER"))
	await flow.press(str(row + 1))
	await _wait(0.12)
	await _shot("9_teleporting")
	await _wait(1.2)
	s.banner = null
	await _wait(0.3)
	await _shot("10_the_hall")
	var hall = s.floor_map
	var lord: Dictionary = hall.envoys[0]
	s.cell = lord.cell + Vector2i(0, 2)
	s.facing = FloorMap.DIRS.find(Vector2i(0, -1))
	s.visited[s.cell] = true
	s.look()
	await _wait(0.6)
	await _shot("11_the_lord_ahead")
	await flow.go("envoy", {"who": lord})
	await _wait(0.4)
	await _shot("12_the_lord_speaks")
	for i in Envoys.entry(str(lord.clan)).lord_says.size() - 1:
		await flow.press("1")
		await _wait(0.3)
	await _wait(0.3)
	await _shot("13_heard_out")
	print("clan_shots: written to %s" % _out)
	quit()


## Stands the party two cells from `cell` (or one), facing it.
func _look_at(s, f, cell: Vector2i) -> void:
	for steps in [2, 1]:
		for i in 4:
			var ok := true
			for n in range(1, steps + 1):
				ok = ok and f.is_open(cell - FloorMap.DIRS[i] * n)
			if ok:
				s.cell = cell - FloorMap.DIRS[i] * steps
				s.facing = i
				s.visited[s.cell] = true
				s.look()
				return


## A moment of the story is a drawing over everything, and the game holds still under it (view/story_cg.gd): send it away, as a
## key would, so the walk goes on and the picture taken is of the asker, the hall or its lord.
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


func _shot(name: String) -> void:
	await _past_story()
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("clan_shots: %s" % name)
