## The main menu scene and its pages: what is enabled, how the settings and save pages behave, what a pick hands over.
extends "res://tests/test_case.gd"

const Flags = preload("res://src/core/flags.gd")
const Saves = preload("res://src/menu/saves.gd")
const Session = preload("res://src/menu/session.gd")
const Settings = preload("res://src/menu/settings.gd")
const MemoryStore = preload("res://src/core/store.gd").Memory
const SCENE = preload("res://src/menu/main_menu.tscn")

var menu: Control
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
	if menu != null:
		menu.queue_free()
		menu = null
		await (Engine.get_main_loop() as SceneTree).process_frame


func _open() -> Control:
	menu = SCENE.instantiate()
	menu.navigate = false
	(Engine.get_main_loop() as SceneTree).root.add_child(menu)
	return menu


func _labels() -> Array:
	return menu.panel.page.items.map(func(i): return i.label)


func _keys(list: Array) -> void:
	for k in list:
		menu.panel.on_key(k)


func _state() -> Dictionary:
	return {"x": 1, "y": 1, "dir": 0, "hp": 9, "maxHp": 20}


func test_the_main_menu_lists_the_classic_entries() -> void:
	_open()
	eq(menu.panel.page.title, "DONJON")
	eq(_labels(), ["CONTINUE", "NEW GAME", "LOAD GAME", "SAVE MANAGER", "SETTINGS", "CREDITS", "QUIT"])


func test_with_no_saves_continue_and_load_are_greyed_and_new_game_is_selected() -> void:
	_open()
	var items: Array = menu.panel.page.items
	eq(items[0].enabled, false)
	eq(items[2].enabled, false)
	eq(menu.panel.sel, 1, "the highlight skips the greyed Continue")
	_keys(["Enter"])
	eq(menu.last_action, "new")
	eq(Session.pending.kind, "new", "the Genre Halls scene is told to start a run")


func test_continue_loads_the_newest_save() -> void:
	Saves.write(3, _state(), "B1F · HP 9/20")
	_open()
	var items: Array = menu.panel.page.items
	eq(items[0].enabled, true)
	ok(items[0].sub.begins_with("B1F · HP 9/20"), items[0].sub)
	eq(menu.panel.sel, 0)
	_keys(["Enter"])
	eq(menu.last_action, "load:3")
	eq(Session.pending.kind, "load")
	eq(Session.pending.state.hp, 9)


func test_load_game_lists_the_slots_and_loads_the_one_you_pick() -> void:
	Saves.write(2, _state(), "two")
	Saves.write(5, _state(), "five")
	_open()
	_keys(["ArrowDown", "ArrowDown", "Enter"]) # LOAD GAME
	eq(menu.panel.page.title, "LOAD GAME")
	var items: Array = menu.panel.page.items
	eq(items.size(), Saves.SLOTS + 1)
	eq(items.filter(func(i): return i.get("enabled", true)).size(), 2, "only the used slots can be picked")
	_keys(["Enter"])
	eq(menu.last_action, "load:2")
	_keys(["Escape", "Escape"])
	eq(menu.panel.page.title, "DONJON", "Esc on the first page keeps the menu open")


func test_the_save_manager_renames_copies_and_deletes() -> void:
	Saves.write(1, _state(), "mine")
	_open()
	_keys(["3", "Enter"]) # 3 = LOAD GAME? no: pick SAVE MANAGER by number 4
	menu.panel.pop_to_root()
	_keys(["4"])
	eq(menu.panel.page.title, "SAVE MANAGER")
	_keys(["Enter"]) # the highlighted (only) used slot
	eq(menu.panel.page.title, "SLOT 1")
	eq(_labels(), ["LOAD", "COPY TO...", "RENAME", "DELETE"])
	_keys(["ArrowDown", "ArrowDown", "Enter"]) # RENAME
	eq(menu.panel.page.title, "NAME THIS SAVE")
	menu.panel._line.text = "  Pear's run  "
	menu.panel._on_line_submitted(menu.panel._line.text)
	eq(Saves.info(1).name, "Pear's run")
	eq(menu.panel.page.title, "SLOT 1", "back on the slot page after naming")
	_keys(["ArrowUp", "Enter"]) # COPY TO...
	eq(menu.panel.page.title, "COPY TO")
	eq(menu.panel.page.items.size(), Saves.SLOTS - 1, "every manual slot but this one")
	_keys(["Enter"]) # the first one: slot 2, empty
	eq(Saves.info(2).name, "Pear's run")
	eq(Saves.read(2), _state())
	eq(menu.panel.page.title, "SAVE MANAGER", "back on the list after copying")
	_keys(["Enter", "ArrowDown", "ArrowDown", "ArrowDown", "Enter"]) # slot 1 > DELETE
	eq(menu.panel.page.title, "DELETE THIS SAVE?")
	eq(menu.panel.sel, 0, "NO is highlighted")
	_keys(["ArrowDown", "Enter"])
	ok(Saves.info(1).empty, "deleted")
	ok(not Saves.info(2).empty, "the copy stays")
	eq(menu.panel.page.title, "SAVE MANAGER")


func test_settings_change_at_once_and_stay() -> void:
	_open()
	_keys(["5"]) # SETTINGS
	eq(_labels(), ["DISPLAY", "EFFECTS", "SOUND", "CONTROLS", "DATA"])
	_keys(["Enter"]) # DISPLAY
	eq(menu.panel.page.items[0].value, "WINDOWED")
	_keys(["ArrowRight"])
	eq(menu.panel.page.items[0].value, "MAXIMIZED", "the page shows the new value")
	eq(Settings.get_value("window_mode"), "maximized")
	_keys(["ArrowLeft", "ArrowLeft"])
	eq(Settings.get_value("window_mode"), "fullscreen", "wraps around")
	_keys(["ArrowDown", "Enter"]) # VSYNC: Enter steps a toggle
	eq(Settings.get_value("vsync"), false)
	_keys(["Escape", "ArrowDown", "Enter", "ArrowRight"]) # EFFECTS > CRT GLOW
	eq(Settings.get_value("crt"), false)
	Settings.forget() # what a new launch reads
	eq(Settings.get_value("crt"), false, "kept in the store")


func test_data_page_resets_settings_after_asking() -> void:
	_open()
	Settings.set_value("shake", false)
	_keys(["5", "ArrowDown", "ArrowDown", "ArrowDown", "ArrowDown", "Enter"]) # SETTINGS > DATA
	eq(menu.panel.page.title, "DATA")
	var labels := _labels()
	ok(labels.has("RESET SETTINGS") and labels.has("DELETE ALL SAVES"))
	_keys(["ArrowDown" if labels[0] != "RESET SETTINGS" else "Enter"])
	if menu.panel.page.title == "DATA":
		_keys(["Enter"])
	eq(menu.panel.page.title, "RESET SETTINGS?")
	_keys(["ArrowDown", "Enter"])
	eq(Settings.get_value("shake"), true, "back to the default")


func test_credits_and_controls_are_scrolling_text_pages() -> void:
	_open()
	_keys(["6"])
	eq(menu.panel.page.title, "CREDITS")
	ok(str(menu.panel.page.body).contains("Donjon"))
	_keys(["ArrowDown", "PageDown", "Escape"])
	eq(menu.panel.page.title, "DONJON")
	_keys(["5", "ArrowDown", "ArrowDown", "ArrowDown", "Enter"])
	eq(menu.panel.page.title, "CONTROLS")
	ok(str(menu.panel.page.body).contains("Esc"))


func test_quit_asks_the_owner_to_quit() -> void:
	_open()
	_keys(["7"])
	eq(menu.last_action, "quit")


func test_a_pick_by_number_or_the_mouse_does_the_same_as_enter() -> void:
	Saves.write(1, _state(), "x")
	_open()
	menu.panel._rows[1].gui_input.emit(_click(MOUSE_BUTTON_LEFT)) # NEW GAME
	eq(menu.last_action, "new")


func _click(button: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	return e
