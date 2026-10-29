## A tip over the bottom of the view (tutorial.js's box; .tip in style.css): a framed note with a Wizardry double
## rule, a TIP tag and "H TIPS" on its top edge, keycaps in the words (the one to press blinks), and the RPG "more"
## arrow blinking in the corner. It unrolls in, rolls up when cleared, and shakes when a key does nothing.
## A click dismisses it; it never takes a key.
extends "res://src/ui/widget.gd"

const Tutorial = preload("res://src/rules/tutorial.gd")
const Status = preload("res://src/rules/status.gd")

const FONT := 9
const LINE := 18.0 # font: 9px/2
const IN_MS := 200.0
const OUT_MS := 200.0
const NUDGE_MS := 350.0
const ARROW_ROT := {"↑": 0.0, "↓": PI, "←": -PI / 2.0, "→": PI / 2.0}

var hint_id := ""
var hint = null # the HINTS entry: {lines: [...]}
var accent := Css.ACCENT
var _in_at := -1e9
var _out_at := -1e9
var _nudge_at := -1e9


func show_hint(id: String, h: Dictionary, accent_color: Color) -> void:
	hint_id = id
	hint = h
	accent = accent_color
	_in_at = now_ms()
	_out_at = -1e9
	_nudge_at = -1e9
	visible = true
	queue_redraw()


func hide_hint() -> void:
	if hint == null:
		return
	_out_at = now_ms()


func nudge() -> void:
	_nudge_at = now_ms()


func animating() -> bool:
	if hint == null:
		return false
	if _out_at > 0.0 and now_ms() - _out_at >= OUT_MS:
		hint = null
		hint_id = ""
		queue_redraw()
		return false
	return true


## A keycap's width in a tip line: min 17, padding 0 3, a 1px frame, margin 0 2
func _key_w(k: String) -> float:
	if ARROW_ROT.has(k):
		return 17.0 + 4.0
	return maxf(17.0, Css.width(Css.ps(), FONT, k) + 8.0) + 4.0


func _line_w(parts: Array) -> float:
	var w := 0.0
	for p in parts:
		w += _key_w(p.key) if p.has("key") else Css.width(Css.ps(), FONT, p.text)
	return w


func paint() -> void:
	if hint == null:
		return
	var t := now_ms()
	var lines := []
	var inner := 0.0
	for l in hint.lines:
		var parts := Tutorial.parse_line(l)
		lines.append(parts)
		inner = maxf(inner, _line_w(parts))
	var w := minf(size.x - 20.0, 2.0 + 14.0 + inner + 30.0 + 2.0)
	var h := 2.0 + 12.0 + lines.size() * LINE + 7.0 + 2.0
	var box := Rect2(roundf((size.x - w) / 2.0), size.y - 8.0 - h, roundf(w), h)

	# tip-in (steps(4)) from a sliver at its bottom edge, tip-out (steps(3)) back to one, tip-nudge
	var sy := 1.0
	var a := 1.0
	var age := Css.age(t - _in_at)
	if age < IN_MS:
		var k := Css.steps(age / IN_MS, 4)
		sy = lerpf(0.1, 1.0, k)
		a = lerpf(0.4, 1.0, k)
	if _out_at > 0.0:
		var k := Css.steps(Css.age(t - _out_at) / OUT_MS, 3)
		sy = lerpf(1.0, 0.1, k)
		a = 1.0 - k
	var n := Css.nudge(t - _nudge_at, NUDGE_MS, 6.0)
	var nudging := t - _nudge_at < NUDGE_MS
	var origin := Vector2(box.get_center().x, box.end.y)
	draw_set_transform(Vector2(n[0], origin.y - origin.y * sy), 0.0, Vector2(1.0, sy))

	Css.glow(self, box, Color(0, 0, 0, 0.8 * a), 16.0)
	if nudging:
		Css.glow(self, box, Css.alpha(accent, n[1] * a), 24.0)
	draw_rect(box.grow(3.0), Css.alpha(Color.BLACK, a))
	draw_rect(box, Color(0, 0, 0, 0.9 * a))
	Css.frame(self, box, Css.alpha(accent if nudging else Css.INK, a), 2.0)
	# the double rule: 3px of black inside the border, then a faint line
	Css.frame(self, box.grow(-5.0), Css.alpha(Css.FAINT, a), 1.0)

	var y := box.position.y + 2.0 + 12.0
	for parts in lines:
		var x := box.position.x + 2.0 + 14.0
		for p in parts:
			if p.has("key"):
				x += _keycap(Vector2(x, y + 1.0), p.key, p.hot, t, a)
			else:
				x += Css.text(self, Css.ps(), FONT, x, y, p.text, Css.alpha(Css.INK, a), LINE)
		y += LINE

	# the tag and the switch on the top edge
	var tag := Rect2(box.position.x + 12.0, box.position.y - 7.0, Css.width(Css.ps(), 8, "TIP") + 12.0, 12.0)
	draw_rect(tag, Css.alpha(accent, a))
	Css.text(self, Css.ps(), 8, tag.position.x + 6.0, tag.position.y + 2.0, "TIP", Css.alpha(Color.BLACK, a), 8)
	var opt_w := Css.width(Css.ps(), 7, "H TIPS") + 12.0
	var opt := Rect2(box.end.x - 12.0 - opt_w, box.position.y - 7.0, opt_w, 11.0)
	draw_rect(opt, Css.alpha(Color.BLACK, a))
	var hx := opt.position.x + 6.0
	var hw := Css.text(self, Css.ps(), 7, hx, opt.position.y + 2.0, "H", Css.alpha(Css.INK, a), 7)
	draw_rect(Rect2(hx, opt.position.y + 10.0, hw, 1.0), Css.alpha(Css.INK, a))
	Css.text(self, Css.ps(), 7, hx + hw, opt.position.y + 2.0, " TIPS", Css.alpha(Css.DIM, a), 7)
	# the "more" arrow, blinking
	var m := Vector2(box.end.x - 12.0 - 5.0, box.end.y - 10.0 - 6.0)
	draw_colored_polygon(PackedVector2Array([m, m + Vector2(10, 0), m + Vector2(5, 6)]), Css.alpha(Css.INK, a * Css.blink(t, 1000.0)))
	draw_set_transform(Vector2.ZERO)
	add_hit(box, {"id": "tip", "click": true, "tip": "Click to dismiss. H turns tips off (and back on from the start)."})


## A keycap in a tip line; the hot one (the key to press) is filled and blinks. Returns the width it takes.
func _keycap(pos: Vector2, k: String, hot: bool, t: float, a: float) -> float:
	var w := _key_w(k) - 4.0
	var r := Rect2(pos.x + 2.0, pos.y, w, 16.0)
	var lit := hot and fposmod(t, 1000.0) < 500.0
	if lit:
		Css.glow(self, r, Css.alpha(accent, a), 8.0)
	draw_rect(r, Css.alpha(accent if lit else Color.BLACK, a))
	# 1px frame, 3px at the bottom
	Css.frame(self, Rect2(r.position, Vector2(r.size.x, r.size.y - 2.0)), Css.alpha(accent, a), 1.0)
	draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x, 3.0), Css.alpha(accent, a))
	var fg := Css.alpha(Color.BLACK if lit else accent, a)
	if ARROW_ROT.has(k):
		# the 7x7 arrow, turned by the keycap
		var c := r.get_center() - Vector2(0, 1)
		_arrow(c, ARROW_ROT[k], fg)
	else:
		Css.text(self, Css.ps(), FONT, r.position.x + (w - Css.width(Css.ps(), FONT, k)) / 2.0, r.position.y, k, fg, 13.0)
	return w + 4.0


func _arrow(c: Vector2, rot: float, color: Color) -> void:
	var rows: Array = Status.ICONS["up"]
	for y in 7:
		for x in 7:
			if rows[y][x] == "#":
				var p := Vector2(x - 3.5, y - 3.5).rotated(rot)
				draw_rect(Rect2((c + p).floor(), Vector2(1, 1)), color)


func _pressed(h: Dictionary) -> void:
	if h.id == "tip" and ui != null:
		ui.dismiss_tip()
