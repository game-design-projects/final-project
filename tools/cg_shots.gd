## Pictures of the opening film and of the run it hands on to, to look at: the film at a few moments, then the first seconds of the
## practice floor (the premise, Wick's welcome, how to walk). With `skip=1` the film is skipped a second in, as a key press would,
## and the run brings Wick in itself. It needs a real window (software rendering is fine), so it goes to n8:
##   godot --path . -s res://tools/cg_shots.gd -- out=/some/dir [skip=1]
## Nothing reaches the player's saves (the `nosave` flag is always on).
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")

const FILM_AT := [0.8, 3.0, 6.5, 9.0, 13.5] # seconds into the film
const RUN_AT := [1.0, 5.0, 9.5, 14.0] # seconds into the run

var _out := ""


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave"]))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://shots"))
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("Store")._persist = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run()


func _run() -> void:
	await create_timer(0.3).timeout
	var Session = load("res://src/menu/session.gd")
	Session.start_new()
	var film = load("res://src/menu/intro_cg.tscn").instantiate()
	root.add_child(film)
	var film_id: int = film.get_instance_id()
	current_scene = film # so that its change_scene_to_file replaces it
	if "skip=1" in OS.get_cmdline_user_args():
		await create_timer(1.0).timeout
		await _shot("film_skipping")
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_ENTER
		film._input(key)
	else:
		for t in FILM_AT:
			var waited := 0.0
			while film._player.stream_position < t and waited < 40.0:
				await create_timer(0.05).timeout
				waited += 0.05
			await _shot("film_%04.1f" % t)
	var waited_scene := 0.0
	while (current_scene == null or current_scene.get_instance_id() == film_id) and waited_scene < 15.0: # the end, a fade, and the run
		await create_timer(0.1).timeout
		waited_scene += 0.1
	var game = current_scene
	print("cg_shots: the run's scene is %s, request %s" % [game.name if game != null else "none", game.request if game != null else {}])
	var t0 := Time.get_ticks_msec()
	for t in RUN_AT:
		while (Time.get_ticks_msec() - t0) / 1000.0 < t:
			await create_timer(0.05).timeout
		await _shot("run_%04.1f" % t)
	if game != null:
		print("cg_shots: practice %s, film_seen %s, banner %s" % [game.flow.state.practice, game.flow.film_seen, game.flow.state.banner])
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("cg_shots: %s" % name)
