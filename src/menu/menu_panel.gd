## A stack of menu pages, drawn the way Genre Halls is (black, white frame, pixel font), driven by keys or the mouse.
## The main menu and the pause menu are both one of these. A page is a Dictionary made by a builder Callable, so
## `refresh()` can rebuild it after a value changes:
##   {title, items: [{label, value?, sub?, enabled?, run?, adjust?: Callable(dir)}], hint?, body?, input?}
## `run` is Enter / click; `adjust(dir)` is Left / Right (and Enter / click when there is no `run`: it steps forward;
## right-click steps back). `body` is a scrolling text page, `input` a one-line text box ({text, submit: Callable(text)}).
## Esc pops a page; popping the first page emits `closed`. Keys go through `on_key(raw)` with the browser's key names
## ("ArrowUp", "Enter", "Escape"), the same words Genre Halls uses, so tests drive it without events.
extends Control

const Canvas2D = preload("res://src/view/canvas2d.gd")

const C_BG := Color("#000000")
const C_INK := Color("#e8e8e8")
const C_DIM := Color("#8a8a8a")
const C_FAINT := Color("#2e2e33")
const C_GOLD := Color("#ffd27a")
const C_YOU := Color("#8fd3ff")
const C_WARN := Color("#ff5a4a")
const WIDTH := 600.0
const ROW_H := 40.0
const ROW_H_SUB := 58.0

signal closed

## 0..1: how much of what is behind the panel it hides (the main menu is opaque, the pause menu is not)
var backdrop := 1.0

var page := {}
var sel := 0

var _builders: Array[Callable] = []
var _sels: Array[int] = []
var _pix: Font
var _term: Font
var _column: VBoxContainer
var _rows: Array = []
var _title: Label
var _hint: Label
var _scroll: ScrollContainer
var _body: RichTextLabel
var _line: LineEdit


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pix = Canvas2D.pixel_font("press start 2p")
	_term = Canvas2D.pixel_font("vt323")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(WIDTH, 0)
	frame.add_theme_stylebox_override("panel", _box(C_BG, C_INK, 2, 24))
	center.add_child(frame)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
	frame.add_child(_column)
	_title = _label(16, C_GOLD)
	_column.add_child(_title)
	_hint = _label(18, C_DIM, true)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(WIDTH - 52, 0)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH - 52, 300)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(WIDTH - 70, 0)
	_body.add_theme_font_override("normal_font", _term)
	_body.add_theme_font_size_override("normal_font_size", 20)
	_body.add_theme_color_override("default_color", C_INK)
	_scroll.add_child(_body)
	_line = LineEdit.new()
	_line.max_length = 24
	_line.add_theme_font_override("font", _pix)
	_line.add_theme_font_size_override("font_size", 14)
	_line.add_theme_stylebox_override("normal", _box(C_BG, C_INK, 2, 10))
	_line.add_theme_stylebox_override("focus", _box(C_BG, C_GOLD, 2, 10))
	_line.text_submitted.connect(_on_line_submitted)
	visible = false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, backdrop))


static func _box(bg: Color, border: Color, w := 2, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_content_margin_all(pad)
	return s


func _label(px: int, color: Color, terminal := false) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _term if terminal else _pix)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- the stack

## Open the menu on a first page
func open(builder: Callable) -> void:
	_builders.clear()
	_sels.clear()
	visible = true
	push(builder)


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	_builders.clear()
	_sels.clear()
	closed.emit()


func push(builder: Callable) -> void:
	if not _builders.is_empty():
		_sels[_sels.size() - 1] = sel
	_builders.append(builder)
	_sels.append(0)
	sel = 0
	_show()


func pop() -> void:
	if _builders.size() <= 1:
		close()
		return
	_builders.pop_back()
	_sels.pop_back()
	sel = _sels[_sels.size() - 1]
	_show()


## Back to the first page
func pop_to_root() -> void:
	while _builders.size() > 1:
		_builders.pop_back()
		_sels.pop_back()
	sel = _sels[0] if not _sels.is_empty() else 0
	_show()


func depth() -> int:
	return _builders.size()


## Rebuild the page after something it shows changed, keeping the highlight
func refresh() -> void:
	_show()


func _show() -> void:
	if _builders.is_empty():
		return
	page = _builders[_builders.size() - 1].call()
	var items: Array = page.get("items", [])
	sel = clampi(sel, 0, maxi(items.size() - 1, 0))
	if not _enabled(sel):
		sel = _next_enabled(sel, 1)
	for c in _column.get_children():
		if c != _title:
			_column.remove_child(c)
			if c != _hint and c != _scroll and c != _line:
				c.queue_free()
	_rows.clear()
	_title.text = str(page.get("title", ""))
	if page.has("body"):
		_body.text = str(page.body)
		_scroll.scroll_vertical = 0
		_column.add_child(_scroll)
	if page.has("input"):
		_line.text = str(page.input.get("text", ""))
		_column.add_child(_line)
		_focus_line.call_deferred()
	elif _line.is_inside_tree():
		_line.release_focus()
	for i in items.size():
		var row := Row.new()
		row.setup(self, i, items[i], _pix, _term)
		_column.add_child(row)
		_rows.append(row)
	if page.has("hint") and str(page.hint) != "":
		_hint.text = str(page.hint)
		_column.add_child(_hint)
	_paint_selection()
	queue_redraw()


func _focus_line() -> void:
	if is_instance_valid(_line) and _line.is_inside_tree() and page.has("input"):
		_line.grab_focus()
		_line.select_all()


func _paint_selection() -> void:
	for i in _rows.size():
		_rows[i].selected = i == sel
		_rows[i].queue_redraw()


func _enabled(i: int) -> bool:
	var items: Array = page.get("items", [])
	return i >= 0 and i < items.size() and items[i].get("enabled", true)


func _next_enabled(from: int, dir: int) -> int:
	var items: Array = page.get("items", [])
	if items.is_empty():
		return 0
	var i := from
	for _n in items.size():
		i = posmod(i + dir, items.size())
		if _enabled(i):
			return i
	return from


# ---------------------------------------------------------------- input

func move(dir: int) -> void:
	sel = _next_enabled(sel, dir)
	_paint_selection()


func select(i: int) -> void:
	if i != sel and _enabled(i):
		sel = i
		_paint_selection()


func adjust(dir: int) -> void:
	var items: Array = page.get("items", [])
	if sel < items.size() and _enabled(sel) and items[sel].has("adjust"):
		items[sel].adjust.call(dir)
		refresh()


func activate() -> void:
	var items: Array = page.get("items", [])
	if sel >= items.size() or not _enabled(sel):
		return
	var it: Dictionary = items[sel]
	if it.has("run"):
		it.run.call()
	elif it.has("adjust"):
		adjust(1)


## `raw` is a browser key name. Returns true when the menu used the key (it uses every key while open).
func on_key(raw: String) -> bool:
	if not visible:
		return false
	if page.has("input"):
		if raw == "Escape":
			pop()
		return true
	if page.has("body"):
		match raw:
			"ArrowDown", "s", "S":
				_scroll.scroll_vertical += 48
			"ArrowUp", "w", "W":
				_scroll.scroll_vertical -= 48
			"PageDown":
				_scroll.scroll_vertical += 240
			"PageUp":
				_scroll.scroll_vertical -= 240
			"Escape", "Enter", "x", "X", " ":
				_back()
		return true
	match raw:
		"ArrowUp", "w", "W":
			move(-1)
		"ArrowDown", "s", "S":
			move(1)
		"ArrowLeft", "a", "A":
			adjust(-1)
		"ArrowRight", "d", "D":
			adjust(1)
		"Enter", " ", "z", "Z":
			activate()
		"Escape", "x", "X":
			_back()
		_:
			if raw.length() == 1 and raw >= "1" and raw <= "9":
				var i := int(raw) - 1
				if _enabled(i):
					sel = i
					_paint_selection()
					activate()
	return true


func _back() -> void:
	if page.has("back"):
		page.back.call()
	else:
		pop()


func _on_line_submitted(text: String) -> void:
	if page.has("input"):
		var submit: Callable = page.input.submit
		pop()
		submit.call(text)


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed:
		return
	if event.meta_pressed or event.ctrl_pressed or event.alt_pressed:
		return
	if page.has("input") and _line.has_focus():
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			pop()
		return
	var raw := _raw(event)
	if raw == "":
		return
	get_viewport().set_input_as_handled()
	on_key(raw)


static func _raw(event: InputEventKey) -> String:
	match event.keycode:
		KEY_UP:
			return "ArrowUp"
		KEY_DOWN:
			return "ArrowDown"
		KEY_LEFT:
			return "ArrowLeft"
		KEY_RIGHT:
			return "ArrowRight"
		KEY_ENTER, KEY_KP_ENTER:
			return "Enter"
		KEY_ESCAPE:
			return "Escape"
		KEY_SPACE:
			return " "
		KEY_PAGEUP:
			return "PageUp"
		KEY_PAGEDOWN:
			return "PageDown"
	return char(event.unicode) if event.unicode > 31 else ""


## One line of a page: the label on the left, its value on the right, an optional dim line under it
class Row:
	extends Control
	var panel
	var index := 0
	var item := {}
	var selected := false
	var pix: Font
	var term: Font

	func setup(p, i: int, it: Dictionary, pf: Font, tf: Font) -> void:
		panel = p
		index = i
		item = it
		pix = pf
		term = tf
		custom_minimum_size = Vector2(0, ROW_H_SUB if str(it.get("sub", "")) != "" else ROW_H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): panel.select(index))
		gui_input.connect(_on_gui_input)

	func _on_gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton or not event.pressed:
			return
		panel.select(index)
		if event.button_index == MOUSE_BUTTON_LEFT:
			panel.activate()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			panel.adjust(-1)

	func _draw() -> void:
		var on: bool = item.get("enabled", true)
		var r := Rect2(Vector2.ZERO, size)
		if selected and on:
			draw_rect(r, C_FAINT)
			draw_rect(Rect2(0, 0, 4, size.y), C_GOLD)
		var color := C_INK if on else C_FAINT
		if selected and on:
			color = C_GOLD
		draw_string(pix, Vector2(16, 26), str(item.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.6, 12, color)
		var value := str(item.get("value", ""))
		if value != "":
			if item.has("adjust") and on and selected:
				value = "< " + value + " >"
			var vc := C_YOU if on else C_FAINT
			draw_string(term, Vector2(0, 26), value, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14, 22, vc)
		var sub := str(item.get("sub", ""))
		if sub != "":
			draw_string(term, Vector2(16, 48), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 18, C_DIM if on else C_FAINT)
