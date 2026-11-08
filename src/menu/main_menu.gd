## The first scene: the title and the main menu. Starting or loading a run hands a request to session.gd and changes to the
## gameplay scene. Flags `meet=<species>` and `personality-slice` skip the menu and start a fight at once (testing hooks).
extends Control

const Flags = preload("res://src/utils/flags.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Menus = preload("res://src/menu/menus.gd")
const MenuPanel = preload("res://src/menu/menu_panel.gd")
const MenuWick = preload("res://src/menu/menu_wick.gd")
const Palette = preload("res://src/view/palette.gd")
const PersonalitySlice = preload("res://src/game/personality_slice.gd")
const Saves = preload("res://src/menu/saves.gd")
const Sprites = preload("res://src/view/sprites.gd")
const Session = preload("res://src/menu/session.gd")
const Settings = preload("res://src/menu/settings.gd")
const State = preload("res://src/game/state.gd")

const GAMEPLAY := "res://src/gameplay/gameplay.tscn"
const KEYART_TINT := Color("#d8cfb8") # the first run's wall colour, about: bone, not white
const KEYART_DIM := 0.58 # the picture behind the page, so the page reads first

var panel: MenuPanel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Settings.apply()
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var drawn := Flags.enabled("hand-drawn")
	if drawn:
		add_child(_keyart())
	if Flags.value("meet") != "" or PersonalitySlice.pending():
		print("menu: straight to a fight (flag)")
		_start(Session.start_new)
		return
	panel = MenuPanel.new()
	if drawn:
		panel.backdrop = 0.0 # its own frame is black; round it you see the halls
		if Flags.enabled("wick"):
			add_child(MenuWick.new())
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


## The drawing of the halls, with a very small witch waving down them, filling the window behind the menu.
func _keyart() -> TextureRect:
	var art := TextureRect.new()
	art.texture = Sprites.texture("keyart")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.modulate = KEYART_TINT.darkened(KEYART_DIM)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


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
	if state.is_empty() or not State.is_playable(state):
		push_warning("menu: slot '%s' can't be read or played" % slot)
		panel.push(func(): return Menus.notice(panel, "CAN'T LOAD", "That save can't be read, or isn't one this version can play."))
		return
	print("menu: load slot %s" % slot)
	_start(Session.start_load.bind(state))


func _start(hand_over: Callable) -> void:
	hand_over.call()
	get_tree().change_scene_to_file.call_deferred(GAMEPLAY)
