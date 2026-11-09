## The opening film: after NEW GAME and before the first run, 15 seconds of the way in (assets/video/intro.ogv, made by
## tools/intro_video.sh; the prompt it came from is docs/intro/seedance-prompt.md). A chest, the halls reshuffling, and a very small
## witch waving at the end of the corridor, who is the one the run begins with. Any key, click or tap skips it. It goes on to the
## gameplay scene by itself, handing session.gd whether it was watched to the end, so the run need not bring Wick in again.
extends Control

const Fonts = preload("res://src/view/fonts.gd")
const Flags = preload("res://src/utils/flags.gd")
const Mix = preload("res://src/audio/mix.gd")
const Palette = preload("res://src/view/palette.gd")
const Session = preload("res://src/menu/session.gd")
const Settings = preload("res://src/menu/settings.gd")

const VIDEO := "res://assets/video/intro.ogv"
const GAMEPLAY := "res://src/gameplay/gameplay.tscn"
const ASPECT := 854.0 / 480.0 # the film's shape; it is shown whole, with black either side if the window is another shape
const SKIP_GUARD_S := 0.5 # the key that chose NEW GAME can't be the one that skips it
const HINT_AFTER_S := 1.2
const HINT_FADE_S := 0.6
const FADE_OUT_S := 0.35
const START_WATCHDOG_S := 3.0 # no picture by then (a decoder that can't read it): go on without it

var _player: VideoStreamPlayer
var _veil: ColorRect
var _hint: Label
var _age := 0.0
var _leaving := false


## Whether NEW GAME should play the film: the feature is on, the file is there, and there is a screen to show it on.
static func wanted() -> bool:
	return Flags.enabled("intro-cg") and DisplayServer.get_name() != "headless" and ResourceLoader.exists(VIDEO)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Settings.apply() # makes the buses and sets the volume the player chose
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var box := AspectRatioContainer.new()
	box.ratio = ASPECT
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_player = VideoStreamPlayer.new()
	_player.stream = load(VIDEO)
	_player.expand = true
	_player.bus = Mix.SFX if AudioServer.get_bus_index(Mix.SFX) >= 0 else "Master"
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_player)
	_hint = Label.new()
	_hint.text = "ANY KEY SKIPS"
	_hint.add_theme_font_override("font", Fonts.title())
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Palette.DIM)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.position = Vector2(-16, -28)
	_hint.modulate.a = 0.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_veil = ColorRect.new() # black over everything, to fade out under
	_veil.color = Color(0, 0, 0, 0)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	if _player.stream == null:
		push_warning("intro_cg: %s can't be loaded, going on to the run" % VIDEO)
		_leave(false)
		return
	_player.finished.connect(func(): _leave(true))
	_player.play()
	print("intro_cg: playing (%.1f s)" % _player.get_stream_length())


func _process(delta: float) -> void:
	_age += delta
	if _leaving:
		return
	_hint.modulate.a = clampf((_age - HINT_AFTER_S) / HINT_FADE_S, 0.0, 1.0)
	if _age > START_WATCHDOG_S and _player.stream_position <= 0.0:
		push_warning("intro_cg: nothing played after %.0f s, going on to the run" % START_WATCHDOG_S)
		_leave(false)


func _input(event: InputEvent) -> void:
	if _leaving or _age < SKIP_GUARD_S:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if pressed:
		get_viewport().set_input_as_handled()
		_leave(false)


func _leave(whole: bool) -> void:
	if _leaving:
		return
	_leaving = true
	var at: float = _player.stream_position if _player != null else 0.0
	print("intro_cg: %s at %.1f s" % ["watched to the end" if whole else "skipped", at])
	Session.cg_played(whole and at > 0.0)
	var fade := create_tween().set_parallel(true)
	fade.tween_property(_veil, "color:a", 1.0, FADE_OUT_S)
	if _player != null:
		fade.tween_property(_player, "volume_db", -40.0, FADE_OUT_S)
	await fade.finished
	get_tree().change_scene_to_file(GAMEPLAY)
