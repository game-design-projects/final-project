## A menu on screen: a stack of pages drawn the way the game is (black, white frame, pixel font), driven by keys or the mouse.
## The main menu and the pause menu are both this panel with a different first page.
##
## A page is a Callable that returns a Dictionary, so `refresh()` can rebuild it after a value changed:
##   {"title", "items", "hint"?, "body"?, "input"?, "back"?}
## An item is {"label", "sub"?, "value"?, "disabled"?, "act"?: Callable, "adjust"?: Callable(dir)}. `act` runs on Enter or a
## click; `adjust(dir)` on Left / Right (and on Enter when there is no `act`). `body` is a page of text that scrolls, `input` a
## one-line text box {"text", "submit": Callable(text)}. Esc goes back one page (or runs the page's `back`); going back from
## the first page emits `closed`.
extends Control

const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")

signal closed ## the first page was left with cancel

const ROW := 40.0
const ROW_SUB := 58.0
const WIDTH := 600.0
const PAD := 24.0
const TITLE_H := 16.0
const HINT_H := 18.0
const BODY_H := 300.0
const INPUT_H := 40.0
const SELECTED_FILL := Color("#313135")

## 0..1: how much of what is behind the panel it hides (the main menu is opaque, the pause menu is not)
var backdrop := 1.0

var _pages: Array[Callable] = []
var _selected_at: Array[int] = [] # the picked row of each page below the current one
var _page := {}
var _selected := 0
var _body: RichTextLabel
var _line: LineEdit


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = true
	_body.add_theme_font_override("normal_font", Fonts.body())
	_body.add_theme_font_size_override("normal_font_size", 20)
	_body.add_theme_color_override("default_color", Palette.INK)
	_body.visible = false
	add_child(_body)
	_line = LineEdit.new()
	_line.max_length = 24
	_line.add_theme_font_override("font", Fonts.title())
	_line.add_theme_font_size_override("font_size", 14)
	_line.add_theme_stylebox_override("normal", _box(Palette.INK))
	_line.add_theme_stylebox_override("focus", _box(Palette.MERCY))
	_line.text_submitted.connect(_on_line_submitted)
	_line.visible = false
	add_child(_line)


static func _box(border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.BLACK
	s.border_color = border
	s.set_border_width_all(2)
	s.set_content_margin_all(10)
	return s


# ---------------------------------------------------------------- the stack

## Start again from this page.
func open(page: Callable) -> void:
	_pages = [page]
	_selected_at = []
	_selected = 0
	visible = true
	_load()
	grab_focus()


func push(page: Callable) -> void:
	_selected_at.append(_selected)
	_pages.append(page)
	_selected = 0
	_load()


## Back one page; from the first page, `closed`.
func pop() -> void:
	if _pages.size() <= 1:
		closed.emit()
		return
	_pages.pop_back()
	_selected = _selected_at.pop_back()
	_load()


## Build the current page again (after a value changed).
func refresh() -> void:
	_load()


func _load() -> void:
	_page = _pages.back().call()
	_selected = clampi(_selected, 0, maxi(0, _page.items.size() - 1))
	_skip_disabled(1)
	_body.visible = _page.has("body")
	_line.visible = _page.has("input")
	if _page.has("body"):
		_body.text = _page.body
		_body.scroll_to_line(0)
	if _page.has("input"):
		_line.text = _page.input.text
		_line.call_deferred("grab_focus")
		_line.call_deferred("select_all")
	else:
		grab_focus()
	_place_children()
	queue_redraw()


func _on_line_submitted(text: String) -> void:
	var input: Dictionary = _page.input
	input.submit.call(text)
	pop()


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var i := _item_at(event.position)
		if i >= 0 and i != _selected and not _page.items[i].get("disabled", false):
			_selected = i
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _item_at(event.position)
		if i >= 0:
			_selected = i
			_activate()
	elif event is InputEventKey and event.pressed:
		if not _handle_key(event.keycode):
			return
		accept_event()


func _handle_key(code: int) -> bool:
	match code:
		KEY_UP, KEY_W:
			_up_down(-1)
		KEY_DOWN, KEY_S:
			_up_down(1)
		KEY_LEFT, KEY_A:
			_adjust(-1)
		KEY_RIGHT, KEY_D:
			_adjust(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z:
			_activate()
		KEY_ESCAPE, KEY_X:
			_cancel()
		_:
			return false
	return true


## Esc: the page's own way back if it has one, else the page before.
func _cancel() -> void:
	if _page.has("back") and _pages.size() == 1:
		_page.back.call()
	else:
		pop()


func _up_down(dir: int) -> void:
	if _page.has("body"):
		_body.get_v_scroll_bar().value += dir * 40.0
		return
	if _page.items.is_empty():
		return
	_selected = posmod(_selected + dir, _page.items.size())
	_skip_disabled(dir)
	queue_redraw()


func _skip_disabled(dir: int) -> void:
	var items: Array = _page.items
	for _i in items.size():
		if not items[_selected].get("disabled", false):
			return
		_selected = posmod(_selected + dir, items.size())


func _activate() -> void:
	if _page.items.is_empty():
		return
	var item: Dictionary = _page.items[_selected]
	if item.get("disabled", false):
		return
	if item.has("act"):
		item.act.call()
	elif item.has("adjust"):
		item.adjust.call(1)
		refresh()


func _adjust(dir: int) -> void:
	if _page.items.is_empty():
		return
	var item: Dictionary = _page.items[_selected]
	if item.has("adjust") and not item.get("disabled", false):
		item.adjust.call(dir)
		refresh()


# ---------------------------------------------------------------- layout and drawing

## Where everything goes: the frame, a rectangle for each item, and the area of a body or input page.
func _layout() -> Dictionary:
	var rows: Array[Rect2] = []
	var inner := 0.0
	if _page.has("body"):
		inner = BODY_H
	elif _page.has("input"):
		inner = INPUT_H
	else:
		for item in _page.items:
			inner += ROW_SUB if item.get("sub", "") != "" else ROW
	var total := PAD + TITLE_H + 12.0 + inner + 12.0 + HINT_H + PAD
	var frame := Rect2(Vector2((size.x - WIDTH) * 0.5, (size.y - total) * 0.5).floor(), Vector2(WIDTH, total))
	var y := frame.position.y + PAD + TITLE_H + 12.0
	for item in _page.items:
		var rh: float = ROW_SUB if item.get("sub", "") != "" else ROW
		rows.append(Rect2(frame.position.x + PAD - 4.0, y, WIDTH - PAD * 2.0 + 8.0, rh))
		y += rh
	var inner_rect := Rect2(frame.position.x + PAD, frame.position.y + PAD + TITLE_H + 12.0, WIDTH - PAD * 2.0, inner)
	return {"frame": frame, "rows": rows, "inner": inner_rect}


func _place_children() -> void:
	if _page.is_empty():
		return
	var inner: Rect2 = _layout().inner
	_body.position = inner.position
	_body.size = inner.size
	_line.position = inner.position
	_line.size = Vector2(inner.size.x, INPUT_H)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_children()


func _item_at(at: Vector2) -> int:
	if _page.is_empty():
		return -1
	var rows: Array = _layout().rows
	for i in rows.size():
		if rows[i].has_point(at):
			return i
	return -1


func _draw() -> void:
	if _page.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, backdrop)) # over a game, it dims it
	var lay := _layout()
	var frame: Rect2 = lay.frame
	draw_rect(frame, Color.BLACK)
	draw_rect(frame.grow(-1.0), Palette.INK, false, 2.0)
	var title := Fonts.title()
	var body := Fonts.body()
	draw_string(title, frame.position + Vector2(PAD, PAD + 16.0), _page.get("title", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.MERCY)
	for i in _page.items.size():
		var item: Dictionary = _page.items[i]
		var r: Rect2 = lay.rows[i]
		var off: bool = item.get("disabled", false)
		var picked: bool = i == _selected
		var color: Color = Palette.FAINT if off else (Palette.MERCY if picked else Palette.INK)
		if picked:
			draw_rect(r, SELECTED_FILL)
			draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), Palette.MERCY)
		draw_string(title, r.position + Vector2(16.0, 24.0), item.label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 13, color)
		if item.has("value"):
			var shown: String = "‹ %s ›" % item.value if picked else item.value
			draw_string(title, r.position + Vector2(0.0, 24.0), shown, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14.0, 12, Palette.YOU)
		if item.get("sub", "") != "":
			draw_string(body, r.position + Vector2(16.0, 46.0), item.sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 18, Palette.FAINT if off else Palette.DIM)
	var hint: String = _page.get("hint", "UP / DOWN CHOOSE · ENTER PICK · ESC BACK").replace(" · ", "   ")
	draw_string(body, frame.position + Vector2(PAD, frame.size.y - PAD - 2.0), hint, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - PAD * 2.0, 18, Palette.DIM)
