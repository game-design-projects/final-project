## A story CG: at a moment of the story (the run's premise, the gate, the Last Door, an ending, a clan's hall, the last champion, the
## writing on a wall) a drawing comes up over the whole screen with that moment's words under it, and waits for a key. The game
## holds still under it (gameplay.gd stops its clock while it shows). The game says which moment with the event `story`
## {id, title, text}; the picture is the sheet cg_<id> and its tint is in data/story.json. A moment with no picture is not shown,
## so a missing drawing costs nothing but the drawing. Two moments at once (the door, then its ending) wait their turn.
extends Control

const Content = preload("res://src/rules/content.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")
const Sprites = preload("res://src/view/sprites.gd")

signal closed

const FADE_IN_S := 0.45
const FADE_OUT_S := 0.3
const GUARD_S := 0.6 # the key that brought the moment on (ENTER on the stairs) can't be the one that sends it away
const HINT_AFTER_S := 1.4
const DRIFT := 0.035 # the picture grows this much while it is up, slowly, so a still is not quite still
const DRIFT_S := 14.0
const CAPTION_H := 0.25 # of the screen's height, the words' band at the bottom
const TITLE_PX := 12
const TEXT_PX := 20
const TEXT_PX_LARGE := 24
const MAX_TEXT_W := 820.0

## The TEXT SIZE setting (gameplay.gd keeps it up to date).
var large_text := false

var _queue: Array = [] # moments waiting: {id, title, text}
var _now: Dictionary = {}
var _age := 0.0
var _leaving := false
var _veil: ColorRect
var _art: TextureRect
var _shade: TextureRect
var _title: Label
var _text: Label
var _hint: Label
var _fade: Tween


## Whether there is a picture for moment `id`, and a screen to show it on.
static func has_picture(id: String) -> bool:
	return DisplayServer.get_name() != "headless" and Sprites.has("cg_" + id) and table().pictures.has(id)


static func table() -> Dictionary:
	return Content.table("story")


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_veil = ColorRect.new()
	_veil.color = Color.BLACK
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_shade = TextureRect.new() # black rising behind the words, so a line of the drawing never runs through them
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0, 0, 0, 0))
	ramp.set_color(1, Color(0, 0, 0, 0.92))
	var grad := GradientTexture2D.new()
	grad.gradient = ramp
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 0.55)
	_shade.texture = grad
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_title = _label(Fonts.title(), TITLE_PX, Palette.MERCY)
	_text = _label(Fonts.body(), TEXT_PX, Palette.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(Fonts.title(), 8, Palette.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	resized.connect(_place)


func _label(font: Font, px: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Show moment `id` (or queue it behind the one showing). Returns false, and shows nothing, when it has no picture.
func show_story(id: String, title: String, text: String) -> bool:
	if not has_picture(id):
		print("story cg: no picture for %s" % id)
		return false
	_queue.append({"id": id, "title": title, "text": text})
	if not visible:
		_next()
	return true


func showing() -> String:
	return str(_now.get("id", "")) if visible else ""


func _next() -> void:
	_now = _queue.pop_front()
	var id := str(_now.id)
	var picture: Dictionary = table().pictures[id]
	_art.texture = Sprites.texture("cg_" + id)
	_art.modulate = Color(str(picture.get("tint", "#e8e8e8")))
	_title.text = str(_now.title)
	_text.text = str(_now.text)
	_text.add_theme_font_size_override("font_size", TEXT_PX_LARGE if large_text else TEXT_PX)
	_hint.text = str(table().get("hint", "ANY KEY"))
	_age = 0.0
	_leaving = false
	_hint.modulate.a = 0.0
	_art.scale = Vector2.ONE
	_kill_fade()
	_fade = create_tween()
	if visible: # one picture after another: the screen stays dark and only the drawing comes up
		_art.modulate.a = 0.0
		_fade.tween_property(_art, "modulate:a", 1.0, FADE_IN_S)
	else:
		modulate.a = 0.0
		_fade.tween_property(self, "modulate:a", 1.0, FADE_IN_S)
	visible = true
	_place()
	if is_inside_tree():
		grab_focus()
	print("story cg: %s (%d waiting)" % [id, _queue.size()])


## The picture fills the screen above the words' band, its shape kept; the words sit in the band, the hint in its corner.
func _place() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var band := h * CAPTION_H
	var art_h := h - band * 0.45 # the picture runs a little way under the band, into its shade
	_art.position = Vector2.ZERO
	_art.size = Vector2(w, art_h)
	_art.pivot_offset = _art.size / 2.0
	_shade.position = Vector2(0, h - band * 1.6)
	_shade.size = Vector2(w, band * 1.6)
	var text_w := minf(MAX_TEXT_W, w - 64.0)
	var x := (w - text_w) / 2.0
	_title.position = Vector2(x, h - band + 10.0)
	_title.size = Vector2(text_w, TITLE_PX + 8)
	_text.position = Vector2(x, h - band + 34.0)
	_text.size = Vector2(text_w, band - 60.0)
	_hint.position = Vector2(w - 220.0, h - 26.0)
	_hint.size = Vector2(200.0, 16.0)


func _process(dt: float) -> void:
	if not visible:
		return
	_age += dt
	_art.scale = Vector2.ONE * (1.0 + DRIFT * ease(clampf(_age / DRIFT_S, 0.0, 1.0), 0.6))
	if not _leaving:
		_hint.modulate.a = clampf((_age - HINT_AFTER_S) / 0.5, 0.0, 1.0)


func _gui_input(event: InputEvent) -> void:
	if _pressed(event):
		accept_event()
		_dismiss()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey:
		get_viewport().set_input_as_handled() # nothing under the picture hears a key while it is up
		if _pressed(event):
			_dismiss()


static func _pressed(event: InputEvent) -> bool:
	return (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)


func _dismiss() -> void:
	if _leaving or _age < GUARD_S:
		return
	print("story cg: %s read after %.1f s" % [_now.id, _age])
	if not _queue.is_empty():
		_next() # straight on to the next picture: the screen stays dark between them
		return
	_leaving = true
	_kill_fade()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, FADE_OUT_S)
	_fade.finished.connect(_close)


func _close() -> void:
	visible = false
	_now = {}
	_leaving = false
	closed.emit()


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
