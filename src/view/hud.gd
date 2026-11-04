## The text around the picture, in three parts of one script (set `part`): the HEADER (where you are, how the route reads),
## the STATUS row (health, gold, the health bar) and the DOCK (the log, the commands or the talk box, the key hints).
## It only reads the game's state. Clicking a command in the dock says so with `picked`.
extends Control

const Fonts = preload("res://src/view/fonts.gd")
const Content = preload("res://src/rules/content.gd")
const Palette = preload("res://src/view/palette.gd")

enum Part { HEADER, STATUS, DOCK }

signal picked(index: int) ## a command was clicked
signal said(text: String) ## a line was typed (Enter or the SAY IT button)
signal cancelled ## Esc in the talk box

# the dock's fixed heights, so the picture above never changes size
const LOG_H := 66.0
const SLOT_H := 74.0
const KEYS_H := 26.0
const BUTTON_H := 34.0
const GAP := 6.0
const DOCK_H := LOG_H + SLOT_H + KEYS_H + GAP * 2.0

const KEY_NAMES := {"UP / DOWN": "ud", "LEFT / RIGHT": "lr", "ARROWS": "all", "ENTER": "ENTER", "ESC": "ESC", "ANY KEY": "ANY KEY", "1-4": "1 - 4"}

var part := Part.HEADER
var state # State, set by the owner

var _title: Font = Fonts.title()
var _body: Font = Fonts.body()
var _buttons: Array[Rect2] = []
var _talk: LineEdit
var _say_button := Rect2()


func _ready() -> void:
	if part != Part.DOCK:
		return
	_talk = LineEdit.new()
	_talk.max_length = 140
	_talk.placeholder_text = "Anything. It answers to what it hears."
	_talk.visible = false
	_talk.add_theme_font_override("font", _body)
	_talk.add_theme_font_size_override("font_size", 20)
	_talk.add_theme_color_override("font_color", Palette.INK)
	_talk.add_theme_color_override("font_placeholder_color", Palette.DIM)
	_talk.add_theme_color_override("caret_color", Palette.YOU)
	_talk.add_theme_stylebox_override("normal", _box(Color.BLACK, Palette.INK, 8))
	_talk.add_theme_stylebox_override("focus", _box(Color.BLACK, Palette.YOU, 8))
	_talk.text_submitted.connect(_submit)
	_talk.gui_input.connect(_on_talk_input)
	add_child(_talk)


## Show or hide the talk box (and take the keyboard when it opens).
func set_talking(on: bool) -> void:
	if _talk == null:
		return
	_talk.visible = on
	if on:
		_talk.clear()
		_talk.call_deferred("grab_focus")
	else:
		_talk.release_focus()


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if state == null:
		return
	match part:
		Part.HEADER:
			_header()
		Part.STATUS:
			_status()
		Part.DOCK:
			_dock()


func _gui_input(event: InputEvent) -> void:
	if part != Part.DOCK or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if state.stage == "talk":
		if _say_button.has_point(event.position):
			_submit(_talk.text)
		return
	for i in _buttons.size():
		if _buttons[i].has_point(event.position):
			picked.emit(i)
			return


func _submit(text: String) -> void:
	_talk.clear()
	said.emit(text)


func _on_talk_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_talk.clear()
		cancelled.emit()
		_talk.accept_event()


func _text(font: Font, s: String, at: Vector2, px: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, at, s, align, width, px, color)


static func _box(bg: Color, border: Color, pad: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_content_margin_all(pad)
	return s


# ---------------------------------------------------------------- the header

func _header() -> void:
	var where: String = "THE GENRE HALLS"
	if state.foe != null and state.stage != "explore" and state.stage != "end":
		var genre: String = _genre_of(state.foe)
		where = "%s ENCOUNTER" % Content.table("encounter").genres[genre].name
	var y := size.y * 0.5 + 4.0
	_text(_title, "B%dF " % state.depth, Vector2(0, y), 9, Palette.DIM)
	_text(_title, where, Vector2(_title.get_string_size("B%dF " % state.depth, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, y), 9, Palette.INK)
	var spared: int = state.tally.spared
	var slain: int = state.tally.slain
	var route := "UNWRITTEN" if spared + slain == 0 else "%d SPARED · %d SLAIN" % [spared, slain]
	var w := _title.get_string_size(route, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_text(_title, route, Vector2(size.x - w, y), 9, Palette.INK)
	_text(_title, "ROUTE ", Vector2(size.x - w - _title.get_string_size("ROUTE ", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, y), 9, Palette.DIM)


func _genre_of(m) -> String:
	if not m.boss:
		return m.genre
	var genres: Array = Content.table("encounter").boss.genres
	return genres[m.turn % genres.size()]


# ---------------------------------------------------------------- the status row

func _status() -> void:
	var y := size.y * 0.5 + 4.0
	var x := 0.0
	for piece in [["HP ", Palette.DIM], ["%d/%d" % [maxi(0, state.hp), state.max_hp], Palette.YOU], ["   GOLD ", Palette.DIM], ["%d" % state.gold, Palette.MERCY]]:
		_text(_title, piece[0], Vector2(x, y), 9, piece[1])
		x += _title.get_string_size(piece[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var bar := Rect2(maxf(x, 150.0) + 12.0, size.y * 0.5 - 6.0, 0.0, 12.0)
	bar.size.x = size.x - bar.position.x
	var frac: float = clampf(float(state.hp) / state.max_hp, 0.0, 1.0)
	draw_rect(bar, Color(Palette.YOU, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Palette.YOU if frac > 0.3 else Palette.WARN)


# ---------------------------------------------------------------- the dock

func _dock() -> void:
	_log(Rect2(0, 0, size.x, LOG_H))
	var slot := Rect2(0, LOG_H + GAP, size.x, SLOT_H)
	if state.stage == "talk":
		_talk_row(slot)
	else:
		_commands(slot)
	_keys(Rect2(0, LOG_H + SLOT_H + GAP * 2.0, size.x, KEYS_H))


## How tall a log line is at this width: the speaker's name and the text, wrapped.
static func _log_line_h(l: Dictionary, width: float) -> float:
	var who: String = l.who if l.kind == "say" else ""
	var head := "%s: " % who if who != "" else ""
	return Fonts.body().get_multiline_string_size(head + l.text, HORIZONTAL_ALIGNMENT_LEFT, width, 20).y


## How many of the first lines fit the log box, which cuts off at the first one that would run past its bottom.
static func log_fits(lines: Array, width: float) -> int:
	var y := 0.0
	for i in lines.size():
		var h := _log_line_h(lines[i], width)
		if y + h > LOG_H + 4.0:
			return i
		y += h
	return lines.size()


## The log: the lines the game last said, top down, a speaker's name in gold.
func _log(area: Rect2) -> void:
	var y := area.position.y
	for l in state.lines:
		var who: String = l.who if l.kind == "say" else ""
		var head := "%s: " % who if who != "" else ""
		var text: String = l.text
		var rich_h := _log_line_h(l, area.size.x)
		if y + rich_h > area.end.y + 4.0:
			break
		if head != "":
			_text(_body, head, Vector2(0, y + 17.0), 20, Palette.MERCY)
		var indent := _body.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_multiline_string(_body, Vector2(indent, y + 17.0), text, HORIZONTAL_ALIGNMENT_LEFT, area.size.x - indent, 20, -1, Palette.INK if l.kind == "say" else Palette.DIM)
		y += rich_h


## The commands: up to four across, a second row after that. The picked one has a bright border.
func _commands(slot: Rect2) -> void:
	_buttons.clear()
	var items: Array = state.menu
	if items.is_empty():
		return
	var cols := clampi(items.size(), 1, 4)
	var w := (slot.size.x - GAP * (cols - 1)) / cols
	for i in items.size():
		var r := Rect2(slot.position + Vector2((i % cols) * (w + GAP), floori(float(i) / cols) * (BUTTON_H + GAP)), Vector2(w, BUTTON_H))
		if r.end.y > slot.end.y + 1.0:
			break
		_buttons.append(r)
		var picked_one: bool = i == state.selected
		var gold: bool = items[i].get("gold", false)
		draw_rect(r, Color.BLACK)
		draw_rect(r.grow(-1.0), Palette.INK if picked_one else Palette.FAINT, false, 2.0)
		var base := r.position + Vector2(12.0, BUTTON_H * 0.5 + 4.0)
		if picked_one:
			draw_colored_polygon([base + Vector2(0, -8), base + Vector2(8, -4), base + Vector2(0, 0)], Palette.YOU)
		_text(_title, str(i + 1), base + Vector2(14, 0), 9, Palette.DIM)
		_text(_title, items[i].label, base + Vector2(14 + 18, 0), 9, Palette.MERCY if gold else Palette.INK)


func _talk_row(slot: Rect2) -> void:
	var say_w := _title.get_string_size("SAY IT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 28.0
	_text(_title, "SAY", Vector2(0, slot.position.y + 24.0), 9, Palette.MERCY)
	var left := 40.0
	_talk.position = Vector2(left, slot.position.y + 2.0)
	_talk.size = Vector2(slot.size.x - left - say_w - 8.0, 34.0)
	_say_button = Rect2(slot.size.x - say_w, slot.position.y + 2.0, say_w, 34.0)
	draw_rect(_say_button, Color.BLACK)
	draw_rect(_say_button.grow(-1.0), Palette.FAINT, false, 2.0)
	_text(_title, "SAY IT", _say_button.position + Vector2(14.0, 22.0), 9, Palette.INK)


## The key hints, with a keycap for each key, and under them what the picked command does.
func _keys(area: Rect2) -> void:
	var x := 0.0
	var y := area.position.y + 9.0
	for segment in state.hint.split(" · "):
		var key := ""
		for name in KEY_NAMES:
			if segment.begins_with(name) and name.length() > key.length():
				key = name
		if key != "":
			x += _keycap(KEY_NAMES[key], Vector2(x, y)) + 6.0
			segment = segment.substr(key.length()).strip_edges()
		if segment != "":
			_text(_title, segment, Vector2(x, y), 8, Palette.DIM)
			x += _title.get_string_size(segment, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		x += 22.0
	if state.stage == "menu" or state.stage == "act":
		var sub: String = state.menu[state.selected].get("sub", "") if not state.menu.is_empty() else ""
		if sub != "":
			_text(_body, sub, Vector2(0, y + 18.0), 17, Palette.DIM)


## A small dark key with its name or arrows on it; returns its width.
func _keycap(name: String, at: Vector2) -> float:
	var arrows := {"ud": [0, 2], "lr": [3, 1], "all": [0, 2, 3, 1]}
	var top := at.y - 9.0
	if arrows.has(name):
		var dirs: Array = arrows[name]
		var w := 12.0 + dirs.size() * 14.0
		draw_rect(Rect2(at.x, top, w, 14.0), Palette.FAINT)
		for i in dirs.size():
			_arrow(Vector2(at.x + 12.0 + i * 14.0 - 2.0, top + 7.0), dirs[i])
		return w
	var w := _title.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 16.0
	draw_rect(Rect2(at.x, top, w, 14.0), Palette.FAINT)
	_text(_title, name, Vector2(at.x + 8.0, at.y), 8, Palette.INK)
	return w


func _arrow(c: Vector2, dir: int) -> void:
	var d := Vector2([Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][dir])
	draw_colored_polygon([c + d * 4.0, c - d * 3.0 + d.orthogonal() * 3.5, c - d * 3.0 - d.orthogonal() * 3.5], Palette.INK)
