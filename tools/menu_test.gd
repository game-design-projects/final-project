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
