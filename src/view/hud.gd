## The text around the picture, in three parts of one script (set `part`): the HEADER (where you are, how the route reads),
## the STATUS row (health, gold, the health bar) and the DOCK (the log, the commands or the talk box, the key hints).
## It only reads the game's state. Clicking a command in the dock says so with `picked`, resting the pointer on one with
## `hovered` (the scene makes it the picked one, and the tooltip shows its help).
extends Control

const Fonts = preload("res://src/view/fonts.gd")
const Content = preload("res://src/rules/content.gd")
const Overlay = preload("res://src/view/overlay.gd")
const Palette = preload("res://src/view/palette.gd")
const Survival = preload("res://src/rules/survival.gd")

enum Part { HEADER, STATUS, DOCK }

signal picked(index: int) ## a command was clicked
signal hovered(index: int) ## the pointer is over this command (-1: it left the commands)
signal page_selected(index: int) ## show the page containing this command
signal said(text: String) ## a line was typed (Enter or the SAY IT button)
signal cancelled ## Esc in the talk box

# the dock's fixed heights, so the picture above never changes size
const LOG_H := 66.0
const SLOT_H := 74.0
const KEYS_H := 26.0
const LOG_PX := 20
const LOG_SIZES_LARGE := [26, 24, 22]
static var large_text := false # the TEXT SIZE setting (the scene keeps this up to date)
const SUB_LINE_H := 20.0 # one more line of a command's help, when it wraps
const THINKING_AFTER_MS := 250 # a question out this long shows as "thinking"; a quick answer doesn't flicker it
const SAY_BUTTON := -2 # what `_hover_at` says over the talk box's button
const PAGE_BACK := -3
const PAGE_NEXT := -4
const BUTTON_H := 34.0
const GRID_SLOT_H := 98.0
const GAP := 6.0
const DOCK_H := LOG_H + SLOT_H + KEYS_H + GAP * 2.0

const TREND_S := 1.4 # how long your health bar's arrow stays after a change
const FLASH_S := 0.14
const HEAL := Color("#9ed36b")

const KEY_NAMES := {"UP / DOWN": "ud", "LEFT / RIGHT": "lr", "ARROWS": "all", "ENTER": "ENTER", "ESC": "ESC", "I": "I", "ANY KEY": "ANY KEY", "1-4": "1 - 4"}

var part := Part.HEADER
var state # State, set by the owner
## How long the oldest question to Jev has been out (Network.waiting_ms), set by the owner every frame.
var thinking_ms := 0

var _title: Font = Fonts.title()
var _body: Font = Fonts.body()
var _talk: LineEdit
var _say_button := Rect2()
var _hp_last := -1 # your health as last seen
var _hp_ghost := 1.0
var _hp_trend := 0
var _hp_trend_left := 0.0
var _hp_flash := 0.0
var _hover := -1 # the command under the pointer (or SAY_BUTTON)


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
	mouse_exited.connect(func(): _set_hover(-1))


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


func _process(dt: float) -> void:
	if part == Part.STATUS and state != null:
		_watch_health(dt)
	if part == Part.DOCK and state != null and size.x > 0.0:
		var reserve_help := _fixed_layout()
		var want := DOCK_H + (_slot_height() - SLOT_H) + (SUB_LINE_H if reserve_help or _sub_wraps() else 0.0)
		if absf(custom_minimum_size.y - want) > 0.5:
			custom_minimum_size.y = want
	queue_redraw()


## Whether the dock has been asked to wait for Jev long enough to say so.
func is_thinking() -> bool:
	return thinking_ms >= THINKING_AFTER_MS


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
	if part != Part.DOCK or state == null:
		return
	if event is InputEventMouseMotion:
		_set_hover(_hover_at(event.position))
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if state.stage == "talk":
		if _say_button.has_point(event.position):
			_submit(_talk.text)
		return
	var page := _page_at(event.position)
	if page != -1:
		var first := _first_grid_row(3) * 3
		page_selected.emit(maxi(0, first - 6) if page == PAGE_BACK else first + 6)
		return
	var i := _command_at(event.position)
	if i >= 0:
		picked.emit(i)


## The pointer is over `at` (a command, the talk box's button, or -1 for neither): a hand over what can be pressed, and the
## scene hears which command it is.
func _set_hover(at: int) -> void:
	if at == _hover:
		return
	var was := _hover
	_hover = at
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if at != -1 else Control.CURSOR_ARROW
	if at >= 0 or was >= 0:
		hovered.emit(at)


func _hover_at(at: Vector2) -> int:
	if state.stage == "talk":
		return SAY_BUTTON if _say_button.has_point(at) else -1
	var page := _page_at(at)
	if page != -1:
		return page
	return _command_at(at)


func _command_at(at: Vector2) -> int:
	var rects := command_rects()
	for i in rects.size():
		if rects[i].has_point(at) and not state.menu[i].get("disabled", false):
			return i
	return -1


func _grid() -> bool:
	return state != null and not state.menu.is_empty() and ((state.stage == "menu" and state.viewing("combat-grid")) or (state.stage in ["act", "items", "ask", "dead", "camp", "trade", "request", "end"] and state.viewing("choice-grid")))


## Reserve the same space while walking and in menus, so opening a grid never resizes the picture.
func _fixed_layout() -> bool:
	return state != null and (state.viewing("combat-grid") or state.viewing("choice-grid"))


func _slot_height() -> float:
	return GRID_SLOT_H if _fixed_layout() else SLOT_H


func _first_grid_row(cols: int) -> int:
	return (int(state.selected / cols) / 2) * 2


func _page_rect(next: bool) -> Rect2:
	return Rect2(size.x - (43.0 if next else 87.0), LOG_H + _slot_height() + GAP * 2.0 - 4.0, 40.0, 20.0)


func _page_at(at: Vector2) -> int:
	if not _grid() or state.menu.size() <= 6:
		return -1
	var first := _first_grid_row(3) * 3
	if first > 0 and _page_rect(false).has_point(at):
		return PAGE_BACK
	if first + 6 < state.menu.size() and _page_rect(true).has_point(at):
		return PAGE_NEXT
	return -1


## Where each command of the menu is, in the dock's own pixels.
func command_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if state == null or state.stage == "talk" or state.menu.is_empty():
		return out
	var slot := Rect2(0, LOG_H + GAP, size.x, _slot_height())
	var cols := mini(3, state.menu.size()) if _grid() else clampi(state.menu.size(), 1, 4)
	var button_h := (GRID_SLOT_H - GAP) / 2.0 if _grid() else BUTTON_H
	var w := (slot.size.x - GAP * (cols - 1)) / cols
	var first_row := _first_grid_row(cols) if _grid() else 0
	for i in state.menu.size():
		var row := floori(float(i) / cols) - first_row
		if _grid() and (row < 0 or row >= 2):
			out.append(Rect2())
			continue
		var r := Rect2(slot.position + Vector2((i % cols) * (w + GAP), row * (button_h + GAP)), Vector2(w, button_h))
		if r.end.y > slot.end.y + 1.0:
			break
		out.append(r)
	return out


## Command `i`'s place on the screen, for a tooltip to sit above it.
func command_screen_rect(i: int) -> Rect2:
	var rects := command_rects()
	return Rect2(get_global_rect().position + rects[i].position, rects[i].size) if i >= 0 and i < rects.size() else Rect2()


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
		var genre: String = state.genre_of(state.foe)
		where = "%s ENCOUNTER" % Content.table("encounter").genres[genre].name
	var y := size.y * 0.5 + 4.0
	var floor_name: String = "B%dF OF %d " % [state.depth, state.floors_of] if state.floors_of > 0 else "B%dF " % state.depth
	_text(_title, floor_name, Vector2(0, y), 9, Palette.DIM)
	_text(_title, where, Vector2(_title.get_string_size(floor_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, y), 9, Palette.INK)
	var spared: int = state.tally.spared
	var slain: int = state.tally.slain
	var route := "UNWRITTEN" if spared + slain == 0 else "%d SPARED · %d SLAIN" % [spared, slain]
	var w := _title.get_string_size(route, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_text(_title, route, Vector2(size.x - w, y), 9, Palette.INK)
	_text(_title, "ROUTE ", Vector2(size.x - w - _title.get_string_size("ROUTE ", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, y), 9, Palette.DIM)


# ---------------------------------------------------------------- the status row

func _status() -> void:
	var y := size.y * 0.5 + 4.0
	var x := 0.0
	for piece in [["HP ", Palette.DIM], ["%d/%d" % [maxi(0, state.hp), state.max_hp], Palette.YOU], ["   GOLD ", Palette.DIM], ["%d" % state.gold, Palette.MERCY]]:
		_text(_title, piece[0], Vector2(x, y), 9, piece[1])
		x += _title.get_string_size(piece[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var hunger: String = Survival.stage_of(state.hunger).to_upper() if state.viewing("hunger") else ""
	if hunger != "":
		_text(_title, "   " + hunger, Vector2(x, y), 9, Palette.WARN if hunger == "STARVING" else Palette.MERCY)
		x += _title.get_string_size("   " + hunger, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var bar := Rect2(maxf(x, 150.0) + 12.0, size.y * 0.5 - 6.0, 0.0, 12.0)
	bar.size.x = size.x - bar.position.x
	var frac: float = clampf(float(state.hp) / state.max_hp, 0.0, 1.0)
	draw_rect(bar, Palette.FAINT)
	var clear: bool = state.viewing("clear-hp")
	if clear and _hp_ghost > frac:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _hp_ghost, bar.size.y)), Palette.INK)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color.WHITE if clear and _hp_flash > 0.0 else hp_color(frac))
	draw_rect(bar.grow(-0.5), Palette.DIM, false, 1.0)
	var moving := trend()
	if clear and moving != 0:
		_trend_arrow(Vector2(bar.position.x + bar.size.x * frac, bar.get_center().y), moving)


## Which way your health is moving: -1, 0 or 1, for a moment after it changed. Like the arrow on a flight display's speed tape.
func trend() -> int:
	return _hp_trend if _hp_trend_left > 0.0 else 0


func _trend_arrow(tip: Vector2, dir: int) -> void:
	var length := 12.0 * dir
	var ink: Color = Palette.WARN if dir < 0 else HEAL
	draw_colored_polygon(PackedVector2Array([tip + Vector2(length, 0.0), tip + Vector2(0.0, -6.0), tip + Vector2(0.0, 6.0)]), ink)


## Keeps the trail, the flash and the arrow of your health bar up to date.
func _watch_health(dt: float) -> void:
	var frac: float = clampf(float(state.hp) / state.max_hp, 0.0, 1.0)
	if _hp_last < 0:
		_hp_last = state.hp
		_hp_ghost = frac
	if state.hp != _hp_last:
		_hp_trend = 1 if state.hp > _hp_last else -1
		_hp_trend_left = TREND_S
		_hp_flash = FLASH_S if state.hp < _hp_last else 0.0
		_hp_last = state.hp
	_hp_trend_left = maxf(0.0, _hp_trend_left - dt)
	_hp_flash = maxf(0.0, _hp_flash - dt)
	_hp_ghost = Overlay.ghost_after(_hp_ghost, frac, dt)


## The health bar's colour at this share of your health: red once it is under 40%.
static func hp_color(frac: float) -> Color:
	return Palette.WARN if frac < 0.4 else Palette.YOU


# ---------------------------------------------------------------- the dock

func _dock() -> void:
	_log(Rect2(0, 0, size.x, LOG_H))
	var slot := Rect2(0, LOG_H + GAP, size.x, _slot_height())
	if state.stage == "talk":
		_talk_row(slot)
	else:
		_commands(slot)
	_keys(Rect2(0, LOG_H + _slot_height() + GAP * 2.0, size.x, KEYS_H))


## A log line's speaker, as drawn in front of its text: "ROOK: ", or nothing for a line of the game's own.
static func _log_head(l: Dictionary) -> String:
	return "%s: " % l.who if l.kind == "say" and l.who != "" else ""


## The size the log writes these lines at: with the TEXT SIZE setting, as large as still shows them all, so a larger size never costs a line.
static func log_px(lines: Array, width: float) -> int:
	if large_text:
		for px in LOG_SIZES_LARGE:
			if log_fits(lines, width, px) == lines.size():
				return px
	return LOG_PX


## How tall a log line is at this width, as `_log` draws it: the text wraps after the speaker's name.
static func _log_line_h(l: Dictionary, width: float, px := LOG_PX) -> float:
	var indent := Fonts.body().get_string_size(_log_head(l), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	return Fonts.body().get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, width - indent, px).y


## How many of the first lines fit the log box, which cuts off at the first one that would run past its bottom.
static func log_fits(lines: Array, width: float, px := LOG_PX) -> int:
	var y := 0.0
	for i in lines.size():
		var h := _log_line_h(lines[i], width, px)
		if y + h > LOG_H + 4.0:
			return i
		y += h
	return lines.size()


## What the log shows: what the foe says has a box of its own on the picture (the feature chat) while the fight waits on it.
func _log_lines() -> Array:
	if not state.viewing("chat") or state.foe == null or not state.stage in Overlay.SPEECH_STAGES:
		return state.lines
	return state.lines.filter(func(l): return not (l.kind == "say" and l.who == state.foe.name))


## The log: the lines the game last said, top down, a speaker's name in gold.
func _log(area: Rect2) -> void:
	var y := area.position.y
	var shown := _log_lines()
	var px := log_px(shown, area.size.x)
	var baseline := float(px) - 3.0
	for l in shown:
		var head := _log_head(l)
		var rich_h := _log_line_h(l, area.size.x, px)
		if y + rich_h > area.end.y + 4.0:
			break
		if head != "":
			_text(_body, head, Vector2(0, y + baseline), px, Palette.MERCY)
		var indent := _body.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_multiline_string(_body, Vector2(indent, y + baseline), l.text, HORIZONTAL_ALIGNMENT_LEFT, area.size.x - indent, px, -1, Palette.INK if l.kind == "say" else Palette.DIM)
		y += rich_h
	if is_thinking():
		var dots := ".".repeat(1 + int(Time.get_ticks_msec() / 300.0) % 3)
		_text(_title, "THINKING" + dots, Vector2(0, area.end.y - 4.0), 8, Palette.YOU, HORIZONTAL_ALIGNMENT_RIGHT, area.size.x)


## The commands: up to four across, a second row after that. The picked one has a bright border.
func _commands(_slot: Rect2) -> void:
	var items: Array = state.menu
	var rects := command_rects()
	for i in rects.size():
		var r: Rect2 = rects[i]
		if not r.has_area():
			continue
		var picked_one: bool = i == state.selected
		var gold: bool = items[i].get("gold", false)
		var disabled: bool = items[i].get("disabled", false)
		draw_rect(r, Color.BLACK)
		draw_rect(r.grow(-1.0), Palette.INK if picked_one or i == _hover else Palette.FAINT, false, 2.0)
		var base := r.position + Vector2(12.0, r.size.y * 0.5 + (6.0 if _grid() else 4.0))
		if picked_one:
			draw_colored_polygon([base + Vector2(0, -8), base + Vector2(8, -4), base + Vector2(0, 0)], Palette.YOU)
		var px := 14 if _grid() else 9
		if _grid():
			while px > 8 and _title.get_string_size(str(items[i].label), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > r.size.x - 55.0:
				px -= 1
		_text(_title, str(i + 1), base + Vector2(14, 0), px, Palette.FAINT if disabled else Palette.DIM)
		var label_at := base + Vector2(14 + (24 if _grid() else 18), 0)
		_text(_title, items[i].label, label_at, px, Palette.FAINT if disabled else (Palette.MERCY if gold else Palette.INK), HORIZONTAL_ALIGNMENT_LEFT, r.end.x - label_at.x - 6.0)


func _talk_row(slot: Rect2) -> void:
	var say_w := _title.get_string_size("SAY IT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 28.0
	_text(_title, "SAY", Vector2(0, slot.position.y + 24.0), 9, Palette.MERCY)
	var left := 40.0
	_talk.position = Vector2(left, slot.position.y + 2.0)
	_talk.size = Vector2(slot.size.x - left - say_w - 8.0, 34.0)
	_say_button = Rect2(slot.size.x - say_w, slot.position.y + 2.0, say_w, 34.0)
	draw_rect(_say_button, Color.BLACK)
	draw_rect(_say_button.grow(-1.0), Palette.INK if _hover == SAY_BUTTON else Palette.FAINT, false, 2.0)
	_text(_title, "SAY IT", _say_button.position + Vector2(14.0, 22.0), 9, Palette.INK)


## The key hints, with a keycap for each key, and under them what the picked command does.
func _keys(area: Rect2) -> void:
	var x := 0.0
	var y := area.position.y + 9.0
	var hint: String = state.hint
	if _grid() and state.stage != "menu":
		hint = "ARROWS / WASD CHOOSE · " + hint
	if _grid() and state.menu.size() > 6:
		hint = "ARROWS / WASD · ENTER PICK"
	for segment in hint.split(" · "):
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
	var sub := sub_text()
	if sub != "":
		draw_multiline_string(_body, Vector2(0, y + 18.0), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x, 17, 2, Palette.DIM)
	if _grid() and state.menu.size() > 6:
		var first := _first_grid_row(3) * 3
		for next in [false, true]:
			var available: bool = first + 6 < state.menu.size() if next else first > 0
			var r := _page_rect(next)
			draw_rect(r, Palette.FAINT, false, 1.0)
			_text(_title, ">" if next else "<", r.position + Vector2(0, 14), 9, Palette.INK if available else Palette.FAINT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## What the picked command does, for the line under the key hints ("" when there is nothing to say).
func sub_text() -> String:
	if state == null or not state.stage in ["menu", "act"] or state.menu.is_empty():
		return ""
	return str(state.menu[clampi(state.selected, 0, state.menu.size() - 1)].get("sub", ""))


## Does any command's help in this menu run past the dock's width (a narrow window)? Then the dock has room for a second line.
func _sub_wraps() -> bool:
	if not state.stage in ["menu", "act"]:
		return false
	for item in state.menu:
		if _body.get_string_size(str(item.get("sub", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x > size.x:
			return true
	return false


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
