## Checks the menu panel with no window: a hint longer than the panel is wide wraps and grows the frame instead of being
## cut off at the edge. Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/menu_test.gd
extends "res://tools/test_base.gd"

const Flags = preload("res://src/utils/flags.gd")
const Fonts = preload("res://src/view/fonts.gd")

# loaded when the test runs: the menus read the Store autoload, which a `-s` script is compiled before
var MenuPanel = null
var Menus = null


func _name() -> String:
	return "menu_test"


func _run() -> void:
	root.get_node("Store")._persist = false # the settings checks change settings: keep them off the player's disk
	MenuPanel = load("res://src/menu/menu_panel.gd")
	Menus = load("res://src/menu/menus.gd")
	var panel = MenuPanel.new()
	root.add_child(panel)
	await _hints_fit(panel)
	_credits_have_one_title()
	_data_page_and_nosave(panel)
	_slot_page_shows_the_name(panel)
	_slot_rows_leave_room_for_the_date(panel)
	_copy_page_names_the_slots(panel)
	_settings_fall_back_to_the_old_blob()
	await _digits_wheel_and_clicks(panel)
	await _main_menu_refuses_a_bad_save()
	await _intro_film()
	_finish()


func _hints_fit(panel) -> void:
	_check(panel.has_method("hint_height"), "the panel can say how tall its hint is")
	if not panel.has_method("hint_height"):
		return
	var inner: float = MenuPanel.WIDTH - MenuPanel.PAD * 2.0
	var body: Font = Fonts.body()
	var ctx := {"new_game": func(): pass, "load_slot": func(_s): pass, "resume": func(): pass, "to_main_menu": func(): pass}
	var pages := {
		"main": func(): return Menus.main(panel, ctx),
		"pause": func(): return Menus.pause(panel, ctx),
		"settings": func(): return Menus.settings(panel),
		"display": func(): return Menus.display(),
		"effects": func(): return Menus.effects(),
		"sound": func(): return Menus.sound(),
		"data": func(): return Menus.data(panel),
	}
	for name in pages:
		panel.open(pages[name])
		var hint: String = panel._page.get("hint", "").replace(" · ", "   ")
		var one_line: bool = body.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x <= inner
		var lines_h: float = body.get_multiline_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, inner, 18).y
		_check(one_line or panel.hint_height() >= lines_h, "the %s page's hint is not cut off (%s)" % [name, "one line" if one_line else "wrapped"])
	panel.open(pages.settings)
	var frame_h: float = panel._layout().frame.size.y
	var rows := 0.0
	for item in panel._page.items:
		rows += MenuPanel.ROW_SUB if item.get("sub", "") != "" else MenuPanel.ROW
	_check(frame_h >= MenuPanel.PAD * 2.0 + MenuPanel.TITLE_H + 24.0 + rows + panel.hint_height(), "the settings frame is as tall as its rows plus its whole hint")


## The panel's title says CREDITS; the text under its version line must not start with that heading again.
func _credits_have_one_title() -> void:
	var page: Dictionary = Menus.credits()
	var lines: PackedStringArray = page.body.split("\n")
	var first := ""
	for line in lines.slice(1): # the first line is the version
		if line.strip_edges() != "":
			first = line.strip_edges()
			break
	_check(page.title == "CREDITS" and first != "" and not first.to_upper().contains("CREDITS"), "the credits text does not start with the CREDITS heading again (starts: %s)" % first.left(30))


## DATA offers OPEN SAVE FOLDER, except with `nosave`: the saves are then in memory, and the folder is the player's real one.
func _data_page_and_nosave(panel) -> void:
	var labels := func() -> Array: return Menus.data(panel).items.map(func(i): return i.label)
	Flags.set_args(PackedStringArray([]))
	_check(labels.call().has("OPEN SAVE FOLDER"), "the DATA page offers OPEN SAVE FOLDER")
	Flags.set_args(PackedStringArray(["nosave"]))
	_check(not labels.call().has("OPEN SAVE FOLDER"), "with nosave the DATA page does not open the player's real save folder")
	Flags.set_args(PackedStringArray([]))


## A renamed slot's page says its name, as the list does.
func _slot_page_shows_the_name(panel) -> void:
	Flags.set_args(PackedStringArray(["nosave"])) # the slots live in memory, so the player's saves are not touched
	var Saves = load("res://src/menu/saves.gd")
	_check(Saves.in_memory(), "the slot test runs on in-memory slots, so it cannot touch the player's saves")
	if not Saves.in_memory():
		return
	Saves.write("2", {"hp": 1}, "HP 1/20")
	var ctx := {"load_slot": func(_s): pass}
	_check(Menus.slot_actions(panel, ctx, "2").title == "SLOT 2", "an unnamed slot's page is titled with the slot")
	Saves.rename("2", "boss run")
	_check(Menus.slot_actions(panel, ctx, "2").title == "SLOT 2  BOSS RUN", "a renamed slot's page is titled like the list: the slot and its name in capitals")
	Saves.rename("2", "W".repeat(Saves.NAME_MAX)) # the widest name a slot can have
	var wide: String = Menus.slot_actions(panel, ctx, "2").title
	var width: float = Fonts.title().get_string_size(wide, HORIZONTAL_ALIGNMENT_LEFT, -1, MenuPanel.TITLE_SIZE).x
	_check(width <= MenuPanel.WIDTH - MenuPanel.PAD * 2.0, "the longest name still fits the page's title line (%d of %d px)" % [width, MenuPanel.WIDTH - MenuPanel.PAD * 2.0])
	Saves.delete("2")
	Flags.set_args(PackedStringArray([]))


## A long name on a save list row is cut off before the date at the right edge, however the row is picked, and the row's
## label does not change length as the pick moves.
func _slot_rows_leave_room_for_the_date(panel) -> void:
	Flags.set_args(PackedStringArray(["nosave"]))
	var Saves = load("res://src/menu/saves.gd")
	if not Saves.in_memory():
		return
	Saves.write("1", {"hp": 1}, "HP 1/20")
	Saves.rename("1", "W".repeat(Saves.NAME_MAX))
	var ctx := {"load_slot": func(_s): pass, "save_slot": func(_s): pass}
	var title: Font = Fonts.title()
	for mode in ["load", "save", "manage"]:
		panel.open(func(): return Menus.slot_list(panel, ctx, mode))
		var item: Dictionary = panel._page.items[1] # slot 1, after the autosave
		var row_w: float = panel._layout().rows[1].size.x # the row as it is drawn
		var room: float = panel.label_room(item, row_w)
		var shown_w: float = 0.0
		for picked in [false, true]:
			shown_w = maxf(shown_w, title.get_string_size(panel._value_shown(item, picked), HORIZONTAL_ALIGNMENT_LEFT, -1, MenuPanel.VALUE_SIZE).x)
		var label_w: float = title.get_string_size("SLOT 1", HORIZONTAL_ALIGNMENT_LEFT, -1, MenuPanel.LABEL_SIZE).x
		var ends: float = MenuPanel.LABEL_X + room # where the label is cut off
		var value_starts: float = row_w - MenuPanel.VALUE_RIGHT - shown_w
		_check(ends <= value_starts and room > label_w, "%s list: the label is cut off before the date, picked or not (ends at %d, the date starts at %d) and still shows the slot" % [mode, ends, value_starts])
		_check(not str(panel._value_shown(item, true)).contains("‹"), "%s list: a save slot's date has no arrows, since Left / Right do nothing there" % mode)
	var plain := {"label": "A VERY LONG LABEL", "value": ""}
	_check(is_equal_approx(panel.label_room(plain, 500.0), 500.0 - MenuPanel.LABEL_X * 2.0), "a row with nothing to show at the right keeps the whole width for its label")
	var setting := {"label": "VOLUME", "value": "80", "adjust": func(_d): pass}
	_check(panel._value_shown(setting, true) == "‹ 80 ›" and panel._value_shown(setting, false) == "80", "a setting shows arrows only while it is picked")
	Saves.delete("1")
	Flags.set_args(PackedStringArray([]))


## COPY TO and its REPLACE question name a slot the way the list does, with its name.
func _copy_page_names_the_slots(panel) -> void:
	Flags.set_args(PackedStringArray(["nosave"]))
	var Saves = load("res://src/menu/saves.gd")
	if not Saves.in_memory():
		return
	Saves.write("1", {"hp": 1}, "HP 1/20")
	Saves.write("3", {"hp": 2}, "HP 2/20")
	Saves.rename("3", "boss run")
	var page: Dictionary = Menus.copy_target(panel, "1")
	var labels: Array = page.items.map(func(i): return i.label)
	_check(labels.has("SLOT 3  BOSS RUN") and labels.has("SLOT 2"), "COPY TO lists a named slot with its name and an unnamed one without (%s)" % [labels])
	panel.open(func(): return page)
	var replace_page: Dictionary = {}
	for item in page.items:
		if item.label == "SLOT 3  BOSS RUN":
			item.act.call()
			replace_page = panel._page
	_check(replace_page.get("hint", "").contains("BOSS RUN"), "and the question before replacing it names it too (%s)" % replace_page.get("hint", ""))
	Saves.delete("1")
	Saves.delete("3")
	Flags.set_args(PackedStringArray([]))


## Settings kept by the game before the rewrite sit in one JSON string under `donjon.settings`; on the first read they move to the
## one-key-each form, a bad value is dropped, a key already set is not overwritten, and the old string is gone after.
func _settings_fall_back_to_the_old_blob() -> void:
	var Settings = load("res://src/menu/settings.gd")
	var store = root.get_node("Store")
	var keys: Array = Settings.DEFAULTS.keys()
	var saved := {}
	for k in keys + [Settings.OLD_KEY]:
		saved[k] = store.get_value(k)
		store.remove(k)
	store.set_value(Settings.OLD_KEY, JSON.stringify({"window_mode": "fullscreen", "fps_cap": 120, "crt": false, "calm": true, "sfx_volume": 99, "bogus": 1, "vsync": "yes"}))
	store.set_value("shake", false) # already set the new way: the old blob does not overwrite it
	Settings.forget_migration()
	_check(Settings.get_value("window_mode") == "fullscreen" and Settings.get_value("fps_cap") == 120, "settings the old game kept (fullscreen, 120 fps) are read on the first read")
	_check(Settings.get_value("crt") == false and Settings.get_value("calm") == true, "and its switches")
	_check(Settings.get_value("sfx_volume") == Settings.DEFAULTS.sfx_volume and Settings.get_value("vsync") == Settings.DEFAULTS.vsync, "a bad value in it is dropped for the default (a volume of 99, 'yes' for a switch)")
	_check(Settings.get_value("shake") == false and store.get_value("shake") == false, "a setting already made the new way stays")
	_check(store.get_value(Settings.OLD_KEY) == null and store.get_value("window_mode") == "fullscreen", "the old string is gone and its values are kept under their own keys")
	Settings.reset()
	Settings.forget_migration()
	_check(Settings.get_value("window_mode") == "windowed", "RESET SETTINGS is not undone by the old values coming back")
	store.set_value(Settings.OLD_KEY, "not json {")
	Settings.forget_migration()
	_check(Settings.get_value("fps_cap") == 0 and store.get_value(Settings.OLD_KEY) == null, "an old string that is not JSON is dropped and the defaults stay")
	for k in saved:
		if saved[k] == null:
			store.remove(k)
		else:
			store.set_value(k, saved[k])
	Settings.forget_migration()


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.pressed = true
	return e


func _click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = at
	e.button_index = button as MouseButton
	e.pressed = true
	return e


## The keys and the mouse of the menu pages, as the game before the rewrite had them: the digits 1-9 (the numpad too) pick that
## row, a right click steps a setting back, Page Up and Page Down scroll a text page, Esc leaves the rename box, and a click or tap
## beside the frame goes back (a touch screen has no Esc).
func _digits_wheel_and_clicks(panel) -> void:
	var log := []
	var page := func(): return {"title": "T", "hint": "", "items": [
		{"label": "ONE", "act": func(): log.append("one")},
		{"label": "TWO", "disabled": true, "act": func(): log.append("two")},
		{"label": "THREE", "act": func(): log.append("three")},
	]}
	panel.open(page)
	panel._gui_input(_key(KEY_3))
	_check(log == ["three"] and panel._selected == 2, "3 picks the third row")
	panel._gui_input(_key(KEY_KP_1))
	_check(log == ["three", "one"], "numpad 1 picks the first")
	panel._gui_input(_key(KEY_2))
	_check(log == ["three", "one"], "a digit on a row that is off does nothing")
	panel._gui_input(_key(KEY_9))
	_check(log == ["three", "one"] and panel._pages.size() == 1, "a digit past the last row does nothing")
	# a right click steps a setting back
	var Settings = load("res://src/menu/settings.gd")
	Settings.set_value("fps_cap", 60)
	panel.open(func(): return Menus.display())
	await process_frame
	var rows: Array = panel._layout().rows
	var fps_row := 2 # WINDOW, VSYNC, FRAME RATE
	panel._gui_input(_click(rows[fps_row].get_center(), MOUSE_BUTTON_RIGHT))
	_check(Settings.get_value("fps_cap") == 30, "a right click on FRAME RATE steps it back (60 to 30)")
	panel._gui_input(_click(rows[fps_row].get_center()))
	_check(Settings.get_value("fps_cap") == 60, "and a left click steps it on")
	Settings.reset()
	# Page Up and Page Down scroll a text page
	panel.open(func(): return {"title": "T", "body": "a line\n".repeat(80), "items": [], "hint": ""})
	await process_frame
	await process_frame
	var bar = panel._body.get_v_scroll_bar()
	_check(bar.max_value > bar.page, "the text page has something to scroll")
	panel._gui_input(_key(KEY_PAGEDOWN))
	var down: float = bar.value
	_check(down > 0.0, "Page Down scrolls it (%d)" % down)
	panel._gui_input(_key(KEY_PAGEUP))
	_check(bar.value < down, "Page Up scrolls back")
	# Esc in the rename box
	Flags.set_args(PackedStringArray(["nosave"]))
	var Saves = load("res://src/menu/saves.gd")
	Saves.write("4", {"hp": 1}, "HP 1/20")
	panel.open(func(): return Menus.slot_actions(panel, {"load_slot": func(_s): pass}, "4"))
	panel.push(func(): return Menus.rename_page(panel, "4", ""))
	_check(panel._pages.size() == 2 and panel._line.visible, "the rename page is open with its box")
	var esc := _key(KEY_ESCAPE)
	panel._line.gui_input.emit(esc)
	_check(panel._pages.size() == 1 and Saves.info("4").name == "", "Esc in the box cancels: back on the slot's page, the name unchanged")
	Saves.delete("4")
	Flags.set_args(PackedStringArray([]))
	# a click beside the frame goes back
	var closed := {"v": false}
	panel.closed.connect(func(): closed.v = true)
	panel.open(func(): return Menus.display())
	panel.push(func(): return Menus.effects())
	var frame: Rect2 = panel._layout().frame
	panel._gui_input(_click(frame.position + Vector2(frame.size.x * 0.5, frame.size.y * 0.5)))
	_check(panel._pages.size() == 2, "a click inside the frame (on no row) goes nowhere")
	panel._gui_input(_click(Vector2(frame.position.x - 30.0, frame.position.y + 30.0)))
	_check(panel._pages.size() == 1, "a click beside the frame goes back a page")
	panel._gui_input(_click(Vector2(frame.position.x - 30.0, frame.position.y + 30.0)))
	_check(closed.v, "and from the first page it closes the menu")


## CONTINUE or LOAD on a slot that can't be played stays on the menu and says so, instead of starting a different run.
func _main_menu_refuses_a_bad_save() -> void:
	Flags.set_args(PackedStringArray(["nosave"]))
	var Saves = load("res://src/menu/saves.gd")
	var Session = load("res://src/menu/session.gd")
	Session.take()
	Saves.write("5", {"cell": "nowhere", "floor": 5}, "a bad one")
	var menu = load("res://src/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var pages_before: int = menu.panel._pages.size()
	menu._load_slot("5")
	_check(Session.pending.is_empty() and menu.panel._pages.size() == pages_before + 1 and menu.panel._page.title == "CAN'T LOAD", "a slot that can't be played is not started; the menu says so on a page of its own")
	menu.panel._gui_input(_key(KEY_ESCAPE))
	_check(menu.panel._pages.size() == pages_before, "and Esc is back on the menu")
	Saves.delete("5")
	menu.queue_free()
	await process_frame
	Flags.set_args(PackedStringArray([]))


## The opening film (menu/intro_cg.gd): it is in the project and Godot can play it, and the menu hands the run what it needs to know.
func _intro_film() -> void:
	var IntroCg = load("res://src/menu/intro_cg.gd")
	var Session = load("res://src/menu/session.gd")
	_check(ResourceLoader.exists(IntroCg.VIDEO) and load(IntroCg.VIDEO) is VideoStream, "the film is in the project, and Godot can read it")
	Flags.set_args(PackedStringArray(["nosave", "nosound"]))
	_check(not IntroCg.wanted(), "with no screen to show it on (this test), NEW GAME goes straight to the run")
	Session.start_new()
	Session.cg_played(true)
	var watched: Dictionary = Session.take()
	_check(watched.get("kind") == "new" and watched.get("cg") == "whole", "a film watched to the end is told to the run")
	Session.start_new()
	Session.cg_played(false)
	_check(Session.take().get("cg") == "skipped" and Session.take().is_empty(), "a skipped one says so, and the request is taken once")
	var player := VideoStreamPlayer.new()
	player.stream = load(IntroCg.VIDEO)
	root.add_child(player)
	await process_frame
	player.play()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and player.stream_position < 1.0:
		await process_frame
	_check(absf(player.get_stream_length() - 15.07) < 0.2 and player.stream_position >= 1.0, "it is 15 seconds long and plays (%.1f s in)" % player.stream_position)
	_check(IntroCg.FADE_IN_S + IntroCg.FADE_OUT_S < player.get_stream_length() / 4.0, "it fades in and out over a small part of its length, not a cut either end")
	_check(IntroCg.SKIP_FADE_S < IntroCg.FADE_OUT_S, "a skip leaves faster than the film's own end")
	player.queue_free()
