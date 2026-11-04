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
	Saves.write("2", {"hp": 1}, "HP 1/20")
	var ctx := {"load_slot": func(_s): pass}
	_check(Menus.slot_actions(panel, ctx, "2").title == "SLOT 2", "an unnamed slot's page is titled with the slot")
	Saves.rename("2", "boss run")
	_check(Menus.slot_actions(panel, ctx, "2").title == "SLOT 2  boss run", "a renamed slot's page is titled with the slot and its name")
	Saves.rename("2", "W".repeat(Saves.NAME_MAX)) # the widest name a slot can have
	var wide: String = Menus.slot_actions(panel, ctx, "2").title
	var width: float = Fonts.title().get_string_size(wide, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_check(width <= MenuPanel.WIDTH - MenuPanel.PAD * 2.0, "the longest name still fits the page's title line (%d of %d px)" % [width, MenuPanel.WIDTH - MenuPanel.PAD * 2.0])
	Saves.delete("2")
	Flags.set_args(PackedStringArray([]))
