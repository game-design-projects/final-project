## Pixel-art tooltips (tooltip.js; .pxtip in style.css) in place of a system tooltip: a framed note in the floor's
## accent with notched corners, a hard drop shadow and a pixel arrow toward what you're hovering. "A · B · C" titles
## become one line each (the first a heading), a run of ability scores a small table (tooltip.gd's tip_model).
## Shows after 220ms, at once when moving from one tooltip to the next; a key, a scroll or a resize hides it.
extends Control

const Css = preload("res://src/ui/css.gd")
const Tooltip = preload("res://src/rules/tooltip.gd")

const DELAY_MS := 220.0
const MAX_W := 320.0
const BODY := 18 # font: 18px/1.05 VT323
const LINE := 18.9
const HEAD := 9 # p.head: 9px/1.6 Press Start 2P
const HEAD_LINE := 14.4

var accent := Css.ACCENT
var _owner = null
var _anchor := Rect2()
var _text := ""
var _due := -1.0
var _shown := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50


## The mouse is over `rect` (global) of `owner`, whose title is `text`
func hover(owner, rect: Rect2, text: String, accent_color: Color) -> void:
	if text == "":
		leave(owner)
		return
	if _shown and owner == _owner and text == _text and rect == _anchor:
		return
	var was_up := _shown
	_owner = owner
	_anchor = rect
	_text = text
	accent = accent_color
	_due = Time.get_ticks_msec() + (0.0 if was_up else DELAY_MS)
	_shown = was_up
	queue_redraw()


func leave(owner) -> void:
	if owner != _owner:
		return
	hide_now()


func hide_now() -> void:
	_owner = null
	_shown = false
	_due = -1.0
	queue_redraw()


## Called every frame: shows the note once its delay is over
func tick() -> void:
	if _due >= 0.0 and Time.get_ticks_msec() >= _due:
		_due = -1.0
		_shown = true
		queue_redraw()


func _draw() -> void:
	if not _shown or _text == "":
		return
	var model := Tooltip.tip_model(_text)
	var lines: Array = model.lines
	var stats: Array = model.stats
	# measure: the heading in Press Start, the rest in VT323, wrapped at 320 - padding
	var inner_max := MAX_W - 20.0
	var blocks := []
	var w := 0.0
	for i in lines.size():
		var head := i == 0 and lines.size() > 1
		var font := Css.ps() if head else Css.vt()
		var fsize := HEAD if head else BODY
		var wrapped := Css.wrap(font, fsize, lines[i], inner_max)
		for l in wrapped:
			w = maxf(w, Css.width(font, fsize, l))
		blocks.append({"head": head, "lines": wrapped})
	var stat_cols := []
	if not stats.is_empty():
		# three columns: the name (7px, dim) and the value side by side
		for c in 3:
			stat_cols.append(0.0)
		for i in stats.size():
			var cw := Css.width(Css.ps(), 7, str(stats[i][0])) + 6.0 + Css.width(Css.vt(), BODY, _signed(stats[i][1]))
			stat_cols[i % 3] = maxf(stat_cols[i % 3], cw)
		w = maxf(w, stat_cols[0] + stat_cols[1] + stat_cols[2] + 24.0)
	var h := 0.0
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		h += b.lines.size() * (HEAD_LINE if b.head else LINE)
		if i < blocks.size() - 1:
			h += 5.0 if b.head else 3.0
	if not stats.is_empty():
		h += 6.0 + 2.0 + 6.0 + ceili(stats.size() / 3.0) * 16.0 + (ceili(stats.size() / 3.0) - 1) * 2.0
	var box_size := Vector2(ceilf(w) + 20.0, ceilf(h) + 17.0)

	# below the anchor if it fits, otherwise above; kept inside the window
	var view := get_viewport_rect().size
	var margin := 8.0
	var below := _anchor.end.y + 10.0 + box_size.y <= view.y - margin
	var top := _anchor.end.y + 10.0 if below else maxf(margin, _anchor.position.y - 10.0 - box_size.y)
	var left := clampf(_anchor.get_center().x - box_size.x / 2.0, margin, maxf(margin, view.x - box_size.x - margin))
	var box := Rect2(Vector2(left, top).round(), box_size)

	# hard shadow, then the 2px border without its corners, then the note
	draw_rect(Rect2(box.position + Vector2(4, 4), box.size).grow(3.0), Css.mix(accent, 0.35))
	draw_rect(Rect2(box.position + Vector2(4, 4), box.size).grow(2.0), Color.BLACK)
	draw_rect(Rect2(box.position.x - 2.0, box.position.y, 2.0, box.size.y), accent)
	draw_rect(Rect2(box.end.x, box.position.y, 2.0, box.size.y), accent)
	draw_rect(Rect2(box.position.x, box.position.y - 2.0, box.size.x, 2.0), accent)
	draw_rect(Rect2(box.position.x, box.end.y, box.size.x, 2.0), accent)
	draw_rect(box, Color.BLACK)
	# the arrow toward the anchor
	var ax := clampf(_anchor.get_center().x - box.position.x, 10.0, box.size.x - 10.0) + box.position.x
	if below:
		draw_colored_polygon(PackedVector2Array([Vector2(ax, box.position.y - 8.0), Vector2(ax + 4.0, box.position.y - 2.0), Vector2(ax - 4.0, box.position.y - 2.0)]), accent)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(ax - 4.0, box.end.y + 2.0), Vector2(ax + 4.0, box.end.y + 2.0), Vector2(ax, box.end.y + 8.0)]), accent)

	var y := box.position.y + 8.0
	var x := box.position.x + 10.0
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		for l in b.lines:
			if b.head:
				Css.text(self, Css.ps(), HEAD, x, y, l, accent, HEAD_LINE)
				y += HEAD_LINE
			else:
				Css.text(self, Css.vt(), BODY, x, y, l, Css.INK, LINE)
				y += LINE
		if i < blocks.size() - 1:
			y += 5.0 if b.head else 3.0
	if not stats.is_empty():
		y += 6.0
		var dx := x
		while dx < box.end.x - 10.0:
			draw_rect(Rect2(dx, y, 2, 2), Color("#333333"))
			dx += 4.0
		y += 2.0 + 6.0
		for i in stats.size():
			var col := i % 3
			var cx := x
			for c in col:
				cx += stat_cols[c] + 12.0
			var ry := y + floori(i / 3.0) * 18.0
			Css.text(self, Css.ps(), 7, cx, ry, str(stats[i][0]), Css.DIM, 16)
			var v = stats[i][1]
			var vc := Color("#6bd36b") if v > 0 else (Css.WARN if v < 0 else Css.INK)
			var vs := _signed(v)
			Css.text(self, Css.vt(), BODY, cx + stat_cols[col] - Css.width(Css.vt(), BODY, vs), ry - 1.0, vs, vc, 16)


static func _signed(v) -> String:
	var n := int(v)
	return "+%d" % n if n > 0 else str(n)
