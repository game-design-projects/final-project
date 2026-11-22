## Pictures of the story CGs as the game shows them (view/story_cg.gd): a new run comes up with its premise, a key sends it away
## and the run goes on, then every other moment the game tells is put up over the running game in turn, with `only=` naming some.
## It needs a real window (software rendering is fine), so it goes to n8 or server:
##   godot --path . -s res://tools/story_shots.gd -- out=/some/dir [only=gate,end_quiet] [large] [nofocus]
## Nothing reaches the player's saves (the `nosave` flag is always on).
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")

var _out := ""


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave", "notips"]))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://shots"))
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("Store")._persist = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if Flags.on("nofocus"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run()


func _run() -> void:
	await create_timer(0.3).timeout
	load("res://src/menu/settings.gd").set_value("text_size", "large" if "large" in OS.get_cmdline_user_args() else "normal")
	var Session = load("res://src/menu/session.gd")
	Session.start_new()
	var game = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var story = game._story
	var waited := 0.0
	while not story.visible and waited < 10.0:
		await create_timer(0.1).timeout
		waited += 0.1
	await create_timer(1.6).timeout
	await _shot("premise")
	var held: float = game._clock_ms
	await create_timer(0.5).timeout
	print("story_shots: the clock held still under the picture: %s (%.0f -> %.0f)" % [is_equal_approx(held, game._clock_ms), held, game._clock_ms])
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ENTER
	Input.parse_input_event(key)
	await create_timer(1.2).timeout
	print("story_shots: after a key the picture is %s and the clock runs: %s" % ["up" if story.visible else "gone", game._clock_ms > held])
	await _shot("after_premise")
	var only := Flags.value("only")
	var ids: Array = load("res://src/view/story_cg.gd").table().pictures.keys()
	if only != "":
		ids = Array(only.split(","))
	for id in ids:
		if id == "premise":
			continue
		story.show_story(str(id), str(id).to_upper().replace("_", " "), "The words of this moment of the story go here, under the drawing, as the game would set them.")
		await create_timer(1.4).timeout
		await _shot(str(id))
		story._age = 99.0
		story._dismiss()
		await create_timer(0.5).timeout
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("story_shots: %s" % name)
