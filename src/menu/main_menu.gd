## The first scene: the title and the main menu (continue, new game, load, save manager, settings, credits, quit).
## Starting or loading a run hands a request to `session.gd` and changes to the Genre Halls scene. Flags: `main`
## opens the original Donjon (as before), `meet=<species>` starts a Genre Halls fight at once (a dev hook).
extends Control

const Flags = preload("res://src/core/flags.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")
const Menus = preload("res://src/menu/menus.gd")
const MenuPanel = preload("res://src/menu/menu_panel.gd")
const Saves = preload("res://src/menu/saves.gd")
const Session = preload("res://src/menu/session.gd")
const Settings = preload("res://src/menu/settings.gd")
const Halls = preload("res://src/genre/genre_halls.gd")

const HALLS_SCENE := "res://src/genre/genre_halls.tscn"
const DONJON_SCENE := "res://src/ui/main.tscn"

var panel: MenuPanel
## Tests turn this off: nothing should change the scene or quit the test runner
var navigate := true
var last_action := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Settings.apply()
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if navigate and Halls.wants_main() and ResourceLoader.exists(DONJON_SCENE):
		print("menu: main game (flag)")
		get_tree().change_scene_to_file.call_deferred(DONJON_SCENE)
		return
	if navigate and Flags.capture("meet=(\\w+)") != "":
		print("menu: straight to a fight (flag)")
		Session.start_new()
		get_tree().change_scene_to_file.call_deferred(HALLS_SCENE)
		return
	panel = MenuPanel.new()
	add_child(panel)
	var version := Label.new()
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	version.add_theme_font_override("font", Canvas2D.pixel_font("press start 2p"))
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", MenuPanel.C_DIM)
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.position = Vector2(16, -28)
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)
	panel.closed.connect(_reopen)
	_reopen()
	print("menu: ready (%d saves)" % Saves.list().filter(func(i): return not i.empty).size())


func context() -> Dictionary:
	var ctx := {
		"new_game": new_game,
		"load_slot": load_slot,
	}
	if not OS.has_feature("web"):
		ctx["quit"] = quit_game
	return ctx


## The first page is the main menu; Esc on it just shows it again
func _reopen() -> void:
	var ctx := context()
	panel.open(func(): return Menus.main(panel, ctx))


func new_game() -> void:
	last_action = "new"
	print("menu: new game")
	Session.start_new()
	_enter_halls()


func load_slot(slot) -> void:
	var state := Saves.read(slot)
	if state.is_empty():
		push_warning("menu: slot %s can't be read" % str(slot))
		panel.refresh()
		return
	last_action = "load:" + str(slot)
	print("menu: load slot %s" % str(slot))
	Session.start_load(state)
	_enter_halls()


func quit_game() -> void:
	last_action = "quit"
	if navigate:
		get_tree().quit()


func _enter_halls() -> void:
	if navigate:
		get_tree().change_scene_to_file.call_deferred(HALLS_SCENE)
