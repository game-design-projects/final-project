## One focused social decision surface, using the game's fonts and palette. Reads state and emits input only.
extends Control

const Fonts = preload("res://src/view/fonts.gd")
const Moods = preload("res://src/rules/moods.gd")
const Palette = preload("res://src/view/palette.gd")

signal hovered(index: int)
signal picked(index: int)
signal said(text: String)
signal cancelled

var state
var suspended := false
var _panel: PanelContainer
var _heading: Label
var _cue: Label
var _speech: Label
var _detail: Label
var _note: Label
var _buttons: Array[Button] = []
var _input: LineEdit
var _send: Button
var _typing := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.76)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box(Palette.MERCY, 14))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	_panel.add_child(column)
	_heading = _label(column, Fonts.title(), 13, Palette.MERCY)
	_cue = _label(column, Fonts.body(), 18, Palette.YOU)
	_speech = _label(column, Fonts.body(), 22, Palette.INK)
	for i in 5:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", Fonts.body())
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", Palette.INK)
		b.add_theme_stylebox_override("hover", _box(Palette.INK, 7))
		b.pressed.connect(func(): picked.emit(i))
		b.mouse_entered.connect(func(): hovered.emit(i))
		column.add_child(b)
		_buttons.append(b)
	_input = LineEdit.new()
	_input.max_length = 140
	_input.placeholder_text = "Your reply (Enter previews its meaning)"
	_input.add_theme_font_override("font", Fonts.body())
	_input.add_theme_font_size_override("font_size", 20)
	_input.add_theme_stylebox_override("normal", _box(Palette.DIM, 8))
	_input.add_theme_stylebox_override("focus", _box(Palette.YOU, 8))
	_input.text_submitted.connect(func(text): said.emit(text))
	_input.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			cancelled.emit()
			_input.accept_event())
	_detail = _label(column, Fonts.body(), 19, Palette.YOU)
	column.add_child(_input)
	_send = Button.new()
	_send.text = "PREVIEW REPLY"
	_send.focus_mode = Control.FOCUS_NONE
	_send.add_theme_font_override("font", Fonts.body())
	_send.add_theme_font_size_override("font_size", 18)
	_send.pressed.connect(func(): said.emit(_input.text))
	column.add_child(_send)
	_note = _label(column, Fonts.body(), 18, Palette.DIM)
	visible = false

func _label(parent: Node, font: Font, px: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

static func _box(border: Color, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.BLACK
	box.border_color = border
	box.set_border_width_all(2)
	box.set_content_margin_all(pad)
	return box

func _process(_dt: float) -> void:
	visible = state != null and state.stage == "social" and not state.social_offer.is_empty() and not suspended
	if not visible:
		return
	var width := minf(740.0, size.x - 32.0)
	_panel.size = Vector2(width, _panel.get_combined_minimum_size().y)
	_panel.position = Vector2((size.x - width) / 2.0, maxf(10.0, (size.y - _panel.size.y) / 2.0))
	var m = state.foe
	_heading.text = "%s STARTED A CONVERSATION" % m.name
	var emotion := Moods.of(m)
	_cue.add_theme_color_override("font_color", Palette.WARN if emotion == "angry" else (Palette.MERCY if emotion == "happy" else Palette.YOU))
	_cue.text = "%s\nWANTS: %s" % [state.social_offer.cue, state.social_offer.goal]
	_speech.text = '"%s"' % state.social_offer.speech
	for i in _buttons.size():
		var selected: bool = state.selected == i
		_buttons[i].text = "%s%d  %s" % ["> " if selected else "  ", i + 1, state.menu[i].label]
		_buttons[i].tooltip_text = state.menu[i].sub
		_buttons[i].add_theme_stylebox_override("normal", _box(Palette.YOU if selected else Palette.FAINT, 7))
		_buttons[i].visible = not state.social_typing
	_detail.text = state.menu[state.selected].sub
	_detail.visible = not state.social_typing
	_input.visible = state.social_typing
	_send.visible = state.social_typing
	if state.social_typing and not _typing:
		_input.clear()
		_input.call_deferred("grab_focus")
	elif not state.social_typing and _typing:
		_input.release_focus()
	_typing = state.social_typing
	_note.text = state.social_note + "\nARROWS choose · ENTER confirm · 1–5 select · ESC " + ("back" if _typing else "ignore")
