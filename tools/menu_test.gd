## Checks the menu panel with no window: a hint longer than the panel is wide wraps and grows the frame instead of being
## cut off at the edge. Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/menu_test.gd
extends SceneTree

const Fonts = preload("res://src/view/fonts.gd")

# loaded when the test runs: the menus read the Store autoload, which a `-s` script is compiled before
var MenuPanel = null
var Menus = null
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	MenuPanel = load("res://src/menu/menu_panel.gd")
	Menus = load("res://src/menu/menus.gd")
	var panel = MenuPanel.new()
	root.add_child(panel)
	await _hints_fit(panel)
	print("menu_test: %s" % ("all checks passed" if _failed == 0 else "%d CHECK(S) FAILED" % _failed))
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("menu_test: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed += 1


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
