## The achievements' own panel: how many are earned and a meter of it, then every one there is, group by group, each with
## its badge. An earned one is lit in its group's colour and says the day; one still to earn is grey and says what to do; a
## counted one shows how far along it is; a secret says only that it is one. It is opened over the main menu, over the pause
## menu, or over the game with K, and whoever opens it gives it Achievements.board(). Up / Down scroll, Esc (or K, Enter, a
## click beside the frame) closes it.
extends Control

const Badges = preload("res://src/view/badges.gd")
const Content = preload("res://src/rules/content.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")

signal closed

const WIDTH := 980.0
const PAD := 22.0
const HEAD_H := 58.0 # the title, the count and the meter
const HINT_H := 26.0
const GROUP_H := 30.0 # a group's heading
const CELL_W_MIN := 268.0
const CELL_H := 86.0
const GAP := 8.0
const COLS_MAX := 3
const BADGE := 52.0
const NAME_PX := 10
const TEXT_PX := 16
const META_PX := 7
const STEP := 56.0 # what Up and Down scroll by
const CLOSE_KEYS := [KEY_ESCAPE, KEY_X, KEY_K, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z]

## 0..1: how much of what is behind the panel it hides.
var backdrop := 0.88

var _board: Array = []
var _earned := 0
var _total := 0
var _scroll := 0.0
var _clip: Control
var _sheet: Control
var _title: Font = Fonts.title()
var _body: Font = Fonts.body()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_sheet = Control.new()
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.draw.connect(_draw_sheet)
	_clip.add_child(_sheet)


## Show this board (Achievements.board()), from its top.
func open(board: Array) -> void:
	_board = board
	_earned = 0
	_total = 0
	for g in board:
		_earned += int(g.got)
		_total += g.cards.size()
	_scroll = 0.0
	visible = true
	_place()
	if is_inside_tree():
		grab_focus()
	print("trophy panel: open, %d of %d" % [_earned, _total])


func close() -> void:
	if not visible:
		return
	visible = false
	print("trophy panel: closed")
	closed.emit()


## [earned, of] as the header says them.
func count() -> Array:
	return [_earned, _total]


# ---------------------------------------------------------------- layout

func _cols(inner_w: float) -> int:
	return clampi(int((inner_w + GAP) / (CELL_W_MIN + GAP)), 1, COLS_MAX)


## Where everything is: {frame, list (the window the cards scroll in), cols, cell_w, sheet_h, cells: [{rect, card}], heads:
## [{y, group}]}. The cells and headings are placed on the sheet, which is as tall as it needs and moves under the window.
func layout() -> Dictionary:
	var w := minf(WIDTH, size.x - 24.0)
	var inner_w := w - PAD * 2.0
	var cols := _cols(inner_w)
	var cell_w := (inner_w - GAP * (cols - 1)) / cols
	var cells := []
	var heads := []
	var y := 0.0
	for g in _board:
		heads.append({"y": y, "group": g})
		y += GROUP_H
		for n in g.cards.size():
			cells.append({"rect": Rect2((n % cols) * (cell_w + GAP), y + (n / cols) * (CELL_H + GAP), cell_w, CELL_H), "card": g.cards[n]})
		y += ceili(float(g.cards.size()) / cols) * (CELL_H + GAP) + 6.0
	var sheet_h := maxf(0.0, y - GAP - 6.0)
	var chrome := PAD + HEAD_H + 10.0 + 8.0 + HINT_H + PAD * 0.5
	var h := minf(size.y - 24.0, chrome + sheet_h)
	var frame := Rect2(((size - Vector2(w, h)) / 2.0).floor(), Vector2(w, h))
	var list := Rect2(frame.position + Vector2(PAD, PAD + HEAD_H + 10.0), Vector2(inner_w, maxf(0.0, h - chrome)))
	return {"frame": frame, "list": list, "cols": cols, "cell_w": cell_w, "sheet_h": sheet_h, "cells": cells, "heads": heads}


## How far the cards can scroll.
func scroll_room() -> float:
	var lay := layout()
	return maxf(0.0, lay.sheet_h - lay.list.size.y)


func _place() -> void:
	if not visible:
		return
	var lay := layout()
	_scroll = clampf(_scroll, 0.0, maxf(0.0, lay.sheet_h - lay.list.size.y))
	_clip.position = lay.list.position
	_clip.size = lay.list.size
	_sheet.position = Vector2(0.0, -_scroll)
	_sheet.size = Vector2(lay.list.size.x, lay.sheet_h)
	_sheet.queue_redraw()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


func scroll_by(by: float) -> void:
	_scroll += by
	_place()


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in CLOSE_KEYS:
			if not event.echo:
				close()
		elif event.keycode in [KEY_UP, KEY_W]:
			scroll_by(-STEP)
		elif event.keycode in [KEY_DOWN, KEY_S]:
			scroll_by(STEP)
		elif event.keycode == KEY_PAGEUP:
			scroll_by(-layout().list.size.y)
		elif event.keycode == KEY_PAGEDOWN:
			scroll_by(layout().list.size.y)
		accept_event() # nothing under the panel hears a key while it is up
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_by(-STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_by(STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT and not layout().frame.has_point(event.position):
			close()
		accept_event()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, backdrop))
	var lay := layout()
	var frame: Rect2 = lay.frame
	draw_rect(frame, Color.BLACK)
	draw_rect(frame.grow(-1.0), Palette.INK, false, 2.0)
	var x := frame.position.x + PAD
	var y := frame.position.y + PAD
	var inner_w := frame.size.x - PAD * 2.0
	Badges.glyph(self, "trophy", Rect2(x, y, 28.0, 28.0), Palette.MERCY)
	draw_string(_title, Vector2(x + 40.0, y + 22.0), str(Content.table("achievements").title), HORIZONTAL_ALIGNMENT_LEFT, inner_w - 160.0, 16, Palette.MERCY)
	var of := " / %d" % _total
	var of_w := _title.get_string_size(of, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(_title, Vector2(x + inner_w - of_w, y + 22.0), of, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.DIM)
	draw_string(_title, Vector2(x, y + 22.0), str(_earned), HORIZONTAL_ALIGNMENT_RIGHT, inner_w - of_w, 16, Palette.INK)
	var meter := Rect2(x, y + 40.0, inner_w, 8.0)
	draw_rect(meter, Color("#232326"))
	if _total > 0 and _earned > 0:
		draw_rect(Rect2(meter.position, Vector2(maxf(4.0, meter.size.x * _earned / _total), meter.size.y)), Palette.MERCY)
	draw_rect(meter, Palette.FAINT, false, 1.0)
	var list: Rect2 = lay.list
	var more: float = lay.sheet_h - list.size.y
	if more > 0.5: # where you are in it, on the right edge
		var track := Rect2(frame.end.x - 12.0, list.position.y, 4.0, list.size.y)
		draw_rect(track, Color("#232326"))
		var bar_h := maxf(24.0, track.size.y * list.size.y / lay.sheet_h)
		draw_rect(Rect2(track.position.x, track.position.y + (track.size.y - bar_h) * _scroll / more, 4.0, bar_h), Palette.DIM)
	var keys := "UP / DOWN SCROLL   ESC BACK" if more > 0.5 else "ESC BACK"
	draw_string(_body, Vector2(x, frame.end.y - PAD * 0.5 - 6.0), keys, HORIZONTAL_ALIGNMENT_LEFT, inner_w, 18, Palette.DIM)


func _draw_sheet() -> void:
	var lay := layout()
	for head in lay.heads:
		var g: Dictionary = head.group
		var colour := Color(str(g.color))
		var hy: float = head.y
		_sheet.draw_string(_title, Vector2(0.0, hy + 18.0), str(g.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, colour)
		var lw := _title.get_string_size(str(g.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_sheet.draw_string(_title, Vector2(lw + 12.0, hy + 18.0), "%d/%d" % [g.got, g.cards.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.DIM)
		_sheet.draw_rect(Rect2(lw + 60.0, hy + 13.0, maxf(0.0, lay.list.size.x - lw - 60.0), 1.0), Color(colour, 0.35))
	for cell in lay.cells:
		_card(cell.rect, cell.card)


func _card(r: Rect2, card: Dictionary) -> void:
	var colour := Color(str(card.color))
	var earned: bool = card.earned
	_sheet.draw_rect(r, Color("#0c0c0e"))
	_sheet.draw_rect(r.grow(-0.5), Color(colour, 0.55) if earned else Color("#2a2a2e"), false, 1.0)
	Badges.badge(_sheet, str(card.icon), Rect2(r.position + Vector2(10.0, (r.size.y - BADGE) / 2.0), Vector2(BADGE, BADGE)), colour, earned)
	var x := r.position.x + BADGE + 22.0
	var room := r.end.x - 8.0 - x
	_sheet.draw_string(_title, Vector2(x, r.position.y + 19.0), str(card.label), HORIZONTAL_ALIGNMENT_LEFT, room, NAME_PX, Palette.INK if earned else Palette.DIM)
	_sheet.draw_multiline_string(_body, Vector2(x, r.position.y + 37.0), str(card.text), HORIZONTAL_ALIGNMENT_LEFT, room, TEXT_PX, 2, Palette.DIM if earned else Palette.FAINT.lightened(0.25))
	var my := r.end.y - 9.0
	var progress: Array = card.progress
	if earned:
		var day := Badges.day(int(card.at))
		_sheet.draw_string(_title, Vector2(x, my), "EARNED %s" % day if day != "" else "EARNED", HORIZONTAL_ALIGNMENT_LEFT, room, META_PX, colour)
	elif progress.size() == 2 and int(progress[1]) > 0:
		var bar := Rect2(x, my - 7.0, minf(110.0, room - 60.0), 7.0)
		_sheet.draw_rect(bar, Color("#232326"))
		_sheet.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(progress[0]) / float(progress[1]), bar.size.y)), Badges.LOCKED.lightened(0.3))
		_sheet.draw_string(_title, Vector2(bar.end.x + 8.0, my), "%d/%d" % [progress[0], progress[1]], HORIZONTAL_ALIGNMENT_LEFT, -1, META_PX, Palette.DIM)
	elif card.hidden:
		_sheet.draw_string(_title, Vector2(x, my), "SECRET", HORIZONTAL_ALIGNMENT_LEFT, room, META_PX, Badges.LOCKED)
