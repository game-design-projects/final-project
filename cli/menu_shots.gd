## Screenshots of the main menu, its settings and save pages, and the pause menu over a run, to look at. Opens a window
## briefly (not headless), keeps the saves in a throwaway folder and leaves your settings alone:
##   godot --path . -s res://cli/menu_shots.gd [-- out=/some/dir]
extends SceneTree

const Flags = preload("res://src/core/flags.gd")
const Saves = preload("res://src/menu/saves.gd")
const Session = preload("res://src/menu/session.gd")
const Settings = preload("res://src/menu/settings.gd")
const MemoryStore = preload("res://src/core/store.gd").Memory

var out_dir := ProjectSettings.globalize_path("res://build/shots/menu/") # build/ is gitignored
var scene: Control


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.trim_prefix("out=").path_join("")
	Flags.override = "nosound"
	Settings.store_override = MemoryStore.new()
	Settings.apply_enabled = false
	Saves.dir_override = "user://menu_shots_saves"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	seed(5)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("shot %s %s" % [name, img.get_size()])


func _keys(list: Array) -> void:
	for k in list:
		scene.panel.on_key(k)
	await _frames(2)


func _run() -> void:
	Saves.write(1, {"x": 1}, "B1F · HP 14/20 · spared 2 · slain 0 · 1 allies", "Pear's run")
	Saves.write(4, {"x": 1}, "B1F · HP 20/20 · spared 0 · slain 0")
	Saves.write(Saves.AUTO, {"x": 1}, "B1F · HP 9/20 · spared 1 · slain 1")
	scene = load("res://src/menu/main_menu.tscn").instantiate()
	scene.navigate = false
	root.add_child(scene)
	await _frames(3)
	await _shot("1-main")
	await _keys(["4"])
	await _shot("2-save-manager")
	await _keys(["Escape", "5", "Enter"])
	await _shot("3-display")
	await _keys(["Escape", "ArrowDown", "Enter"])
	await _shot("4-effects")
	await _keys(["Escape", "Escape", "ArrowDown", "ArrowDown", "ArrowDown", "ArrowDown", "Enter"])
	await _shot("5-data")
	scene.queue_free()
	await _frames(2)
	scene = load("res://src/genre/genre_halls.tscn").instantiate()
	scene.navigate = false
	Session.start_new()
	root.add_child(scene)
	await _frames(3)
	scene.on_key("Escape")
	await _frames(2)
	await _shot("6-pause")
	Saves.delete_all()
	DirAccess.remove_absolute(Saves.dir())
	quit()
