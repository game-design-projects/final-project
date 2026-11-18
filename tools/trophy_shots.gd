## Pictures of the achievements, to look at: the toast for one just earned (walking, in a fight, over a choice's dimmed halls,
## two at once), the header's count, and the panel over the game with none earned, some earned, and scrolled. It needs a real
## window:
##   godot --path . -s res://tools/trophy_shots.gd -- out=/some/dir [nofocus]
## Nothing reaches the player's saves (`nosave` is always on).
extends SceneTree

const Ally = preload("res://src/game/ally.gd")
const Flags = preload("res://src/utils/flags.gd")

var _out := ""
var _game


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave", "nosound", "notips", "nojev", "seed=7"]))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://trophy_shots"))
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
	# nothing earned yet: the panel shows what there is to do
	_game.show_trophies()
	await _wait(0.3)
	await _shot("1_panel_none")
	_game._trophy.close()
	# one earned while walking: the toast, and the header's count lit
	s.banner = null
	flow.event("found", {"what": "chest"})
	await _wait(0.1)
	await _shot("2a_toast_sliding_in")
	await _wait(0.5)
	await _shot("2b_toast_walking")
	# two more in a fight, at once
	var boss = s.floor_map.monsters.filter(func(x): return x.boss).front()
	await flow.go("intro", {"foe": boss})
	await _until("menu")
	flow.event("spared", {"boss": false})
	flow.event("slain", {"boss": true})
	await _wait(0.7)
	await _shot("3_toasts_in_a_fight")
	# over a choice's dimmed halls
	await flow.encounter.defeat(boss, "slain")
	await _wait(0.3)
	flow.event("butchered", {"species": "slime"})
	await _wait(0.7)
	await _shot("4_toast_over_a_choice")
	await flow.press("confirm")
	await _wait(6.0) # the toasts leave
	await _shot("5_header_count_after")
	# the panel with some earned, and its end
	_game.show_trophies()
	await _wait(0.3)
	await _shot("6_panel_some")
	_game._trophy.scroll_by(99999.0)
	await _wait(0.2)
	await _shot("7_panel_scrolled")
	_game._trophy.close()
	# the card that ends the run says what the run earned
	s.depth = s.floors_of if s.floors_of > 0 else 5
	s.allies = [Ally.make("slime", "GLOP", 60.0)]
	s.banner = null
	await flow.go("explore", {"lines": []})
	await flow.go("end")
	await _wait(1.2)
	await _shot("7b_ending_this_run")
	# from the pause menu
	_game._open_pause()
	await _wait(0.3)
	await _shot("8_pause_menu")
	print("trophy_shots: written to %s" % _out)
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
	print("trophy_shots: %s" % name)
