## Genre Halls with the menu around it: saving and loading a run, the pause menu, and the settings it reads.
extends "res://tests/test_case.gd"

const Flags = preload("res://src/core/flags.gd")
const Saves = preload("res://src/menu/saves.gd")
const Session = preload("res://src/menu/session.gd")
const Settings = preload("res://src/menu/settings.gd")
const MemoryStore = preload("res://src/core/store.gd").Memory
const SCENE = preload("res://src/genre/genre_halls.tscn")
const Rules = preload("res://src/genre/genre_rules.gd")

var scene: Control
var root := ""


func before_each() -> void:
	Flags.override = "nosound"
	Settings.store_override = MemoryStore.new()
	Settings.apply_enabled = false
	Settings.forget()
	root = "user://test_saves_%d" % Time.get_ticks_usec()
	Saves.dir_override = root
	Session.pending = {}


func after_each() -> void:
	Flags.override = null
	Settings.store_override = null
	Settings.apply_enabled = true
	Settings.forget()
	Saves.delete_all()
	if DirAccess.dir_exists_absolute(root):
		for f in DirAccess.get_files_at(root):
			DirAccess.remove_absolute(root + "/" + f)
		DirAccess.remove_absolute(root)
	Saves.dir_override = ""
	Session.pending = {}
	if scene != null:
		scene.queue_free()
		scene = null
		await (Engine.get_main_loop() as SceneTree).process_frame


func _scene(fake_clock := true) -> Control:
	scene = SCENE.instantiate()
	if fake_clock:
		scene.clock_override = 1000.0
	scene.navigate = false
	(Engine.get_main_loop() as SceneTree).root.add_child(scene)
	scene.set_process(false)
	return scene


func test_a_run_survives_export_json_free_roundtrip_through_a_save_slot() -> void:
	_scene()
	scene.new_run()
	scene.G.x = 3
	scene.G.hp = 11
	scene.G.tally.spared = 2
	scene.G.allies.append({"species": "slime", "name": "Drip", "loyalty": 70.0})
	scene.G.map.monsters[0].lastIntent = "kindness"
	scene.G.seen[17] = true
	ok(Saves.write(1, scene.export_state(), scene.summary()), "the whole state can be written")
	var saved := Saves.read(1)
	eq(saved.map.grid, scene.G.map.grid)
	eq(saved.map.monsters.size(), scene.G.map.monsters.size())
	var other := SCENE.instantiate()
	other.clock_override = 1000.0
	other.navigate = false
	(Engine.get_main_loop() as SceneTree).root.add_child(other)
	other.set_process(false)
	ok(other.import_state(saved), "and loaded into a fresh scene")
	eq(other.G.mode, "explore")
	eq(other.G.x, 3)
	eq(other.G.hp, 11)
	eq(other.G.tally.spared, 2)
	eq(other.G.allies[0].name, "Drip")
	ok(other.G.seen.has(17), "integer keys of the seen set survive")
	eq(other.G.map.stairs, scene.G.map.stairs)
	eq(other.G.map.monsters[0].lastIntent, "kindness", "the monster's recent impression survives a save")
	other.queue_free()
	# Saves from before the impression field was added still use the species baseline.
	saved.map.monsters[0].erase("lastIntent")
	ok(scene.import_state(saved))
	ok(Rules.ask_mercy(scene.G.map.monsters[0]).noul > 0.0)


func test_a_state_that_is_not_ours_is_refused() -> void:
	_scene()
	scene.new_run()
	var before: int = scene.G.x
	ok(not scene.import_state({}))
	ok(not scene.import_state({"map": {"grid": []}}))
	var st: Dictionary = scene.export_state()
	st.x = 0 # a wall
	ok(not scene.import_state(st), "standing in a wall is not a position")
	eq(scene.G.x, before, "a refused state changes nothing")


func test_a_session_request_starts_a_run_or_loads_one() -> void:
	Session.start_new()
	_scene()
	eq(scene.G.mode, "explore", "a new-game request skips the title card")
	eq(Session.pending, {}, "the request is used once")
	var st: Dictionary = scene.export_state()
	st.hp = 7
	scene.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
	Session.start_load(st)
	_scene()
	eq(scene.G.mode, "explore")
	eq(scene.G.hp, 7)
	scene.queue_free()
	scene = null
	await (Engine.get_main_loop() as SceneTree).process_frame
	_scene()
	eq(scene.G.mode, "title", "with nothing pending the title card shows")


func test_the_autosave_is_written_when_you_are_back_to_walking() -> void:
	Flags.override = "nosound"
	_scene(false) # the real clock: autosaving is on
	scene.new_run()
	eq(Saves.info(Saves.AUTO).empty, false, "a new floor is autosaved")
	eq(Saves.latest().slot, "auto")
	ok(str(Saves.info(Saves.AUTO).summary).begins_with("B1F · HP 20/20"), Saves.info(Saves.AUTO).summary)


func test_the_fake_clock_never_touches_the_save_folder() -> void:
	_scene()
	scene.new_run()
	ok(Saves.info(Saves.AUTO).empty)


func test_esc_opens_the_pause_menu_while_walking_and_takes_the_keys() -> void:
	_scene()
	scene.new_run()
	var x: int = scene.G.x
	var y: int = scene.G.y
	scene.on_key("Escape")
	ok(scene.pause_open())
	var items: Array = scene._pause.page.items
	eq(items.map(func(i): return i.label), ["RESUME", "SAVE GAME", "LOAD GAME", "SETTINGS", "MAIN MENU", "QUIT GAME"])
	ok(items[1].get("enabled", true), "saving is on while walking")
	scene._pause.on_key("Enter") # RESUME
	ok(not scene.pause_open())
	eq([scene.G.x, scene.G.y], [x, y], "the pause didn't move anyone")


func test_saving_from_the_pause_menu_writes_the_slot() -> void:
	_scene()
	scene.new_run()
	scene.on_key("Escape")
	scene._pause.on_key("ArrowDown") # SAVE GAME
	scene._pause.on_key("Enter")
	eq(scene._pause.page.title, "SAVE GAME")
	eq(scene._pause.sel, 1, "AUTOSAVE is disabled, so SLOT 1 is highlighted")
	scene._pause.on_key("Enter")
	ok(not Saves.info(1).empty, "slot 1 holds the run")
	eq(Saves.info(1).summary, scene.summary())
	scene._pause.on_key("Enter") # saving into a used slot asks first
	eq(scene._pause.page.title, "OVERWRITE SLOT 1?")
	eq(scene._pause.sel, 0, "NO is highlighted")


func test_the_pause_menu_in_a_fight_cannot_save() -> void:
	_scene()
	scene.new_run()
	scene.meet("slime")
	scene.G.mode = "menu"
	scene.on_key("Escape")
	ok(scene.pause_open(), "Esc on the fight menu pauses")
	eq(scene._pause.page.items[1].enabled, false, "but a fight is not saved")


func test_loading_from_the_pause_menu_replaces_the_run() -> void:
	_scene()
	scene.new_run()
	Saves.write(2, scene.export_state(), "x")
	scene.G.hp = 3
	scene.on_key("Escape")
	scene._pause.on_key("ArrowDown")
	scene._pause.on_key("ArrowDown") # LOAD GAME
	scene._pause.on_key("Enter")
	eq(scene._pause.sel, 2, "the first slot that can be loaded is SLOT 2")
	scene._pause.on_key("Enter")
	eq(scene._pause.page.title, "LOAD THIS SAVE?", "asks first: progress is lost")
	scene._pause.on_key("ArrowDown")
	scene._pause.on_key("Enter") # LOAD
	ok(not scene.pause_open())
	eq(scene.G.hp, 20, "the saved HP is back")


func test_main_menu_item_on_the_pause_menu_asks_then_leaves() -> void:
	_scene()
	scene.new_run()
	scene.on_key("Escape")
	for _i in 4:
		scene._pause.on_key("ArrowDown")
	scene._pause.on_key("Enter")
	eq(scene._pause.page.title, "LEAVE THE RUN?")
	scene._pause.on_key("ArrowDown")
	scene._pause.on_key("Enter")
	eq(scene.left_for, "menu")


func test_screen_shake_follows_the_setting() -> void:
	_scene()
	scene.new_run()
	scene.G.shake = 0.0
	Settings.set_value("shake", false)
	scene._shake(200.0)
	eq(scene.G.shake, 0.0, "shake off: no shake")
	Settings.set_value("shake", true)
	scene._shake(200.0)
	near(scene.G.shake, 1200.0, 1e-6, "shake on: now + 200ms")


func test_the_effects_volume_follows_the_setting() -> void:
	Flags.override = "" # the real Sfx, which has a volume (no `nosound`)
	_scene()
	scene.apply_settings()
	Settings.set_value("sfx_volume", 2)
	scene.apply_settings()
	near(scene.sfx.volume, 0.2, 1e-6)
	Settings.set_value("sfx", false)
	scene.apply_settings()
	near(scene.sfx.volume, 0.0, 1e-6, "sound off is silent")


func test_quit_game_on_the_pause_menu_asks_first() -> void:
	_scene()
	scene.new_run()
	scene.on_key("Escape")
	for _i in 5:
		scene._pause.on_key("ArrowDown")
	scene._pause.on_key("Enter")
	eq(scene._pause.page.title, "QUIT THE GAME?")
	eq(scene._pause.sel, 0, "NO is highlighted")
	scene._pause.on_key("ArrowDown")
	scene._pause.on_key("Enter") # navigate is off: the scene doesn't quit the test runner
