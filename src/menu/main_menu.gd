## The first scene: the title and the main menu. Starting or loading a run hands a request to session.gd and changes to the
## gameplay scene. Flags `meet=<species>` and `personality-slice` skip the menu and start a fight at once (testing hooks).
extends Control

const Flags = preload("res://src/utils/flags.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Menus = preload("res://src/menu/menus.gd")
const MenuPanel = preload("res://src/menu/menu_panel.gd")
const Palette = preload("res://src/view/palette.gd")
const PersonalitySlice = preload("res://src/game/personality_slice.gd")
const Saves = preload("res://src/menu/saves.gd")
const Session = preload("res://src/menu/session.gd")
const Settings = preload("res://src/menu/settings.gd")

const GAMEPLAY := "res://src/gameplay/gameplay.tscn"

var panel: MenuPanel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Settings.apply()
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	if Flags.value("meet") != "" or PersonalitySlice.pending():
		print("menu: straight to a fight (flag)")
		_start(Session.start_new)
		return
	panel = MenuPanel.new()
	add_child(panel)
	var version := Label.new()
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	version.add_theme_font_override("font", Fonts.title())
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Palette.DIM)
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.position = Vector2(16, -28)
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)
	panel.closed.connect(_reopen)
	_reopen()
	print("menu: ready (%d saves)" % Saves.list().filter(func(i): return not i.empty).size())


## The first page is the main menu; Esc on it just shows it again.
func _reopen() -> void:
	var ctx := {"new_game": _new_game, "load_slot": _load_slot}
	if not OS.has_feature("web"):
		ctx["quit"] = func(): get_tree().quit()
	panel.open(func(): return Menus.main(panel, ctx))


func _new_game() -> void:
	print("menu: new game")
	_start(Session.start_new)


func _load_slot(slot: String) -> void:
	var state := Saves.read(slot)
	if state.is_empty():
		push_warning("menu: slot '%s' can't be read" % slot)
		panel.refresh()
		return
	print("menu: load slot %s" % slot)
	_start(Session.start_load.bind(state))


func _start(hand_over: Callable) -> void:
	hand_over.call()
	get_tree().change_scene_to_file.call_deferred(GAMEPLAY)
