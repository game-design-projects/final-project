## Achievement unlock toasts (achievements.js showToast; .ach-toast in style.css): gold notes that slide down from
## the top edge of the view and stack, a light sweeping across each once it lands. They never take a click or a
## key. The queue (at most two at once, staggered) is the achievements wrapper's; this paints what it shows.
extends "res://src/ui/widget.gd"

const Achievements = preload("res://src/rules/achievements.gd")

const IN_MS := 420.0
const OUT_MS := 260.0
const SHINE_DELAY := 500.0
const SHINE_MS := 1100.0
const H := 64.0
const GOLD := Color("#ffd27a")

var toasts: Array = [] # {a, count, t0, out}
## Called with no arguments when a toast has gone (the wrapper shows the next one)
var on_gone := Callable()


func _init() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_toast(a: Dictionary, count) -> void:
	toasts.append({"a": a, "count": count, "t0": now_ms(), "out": -1.0})
	queue_redraw()


func animating() -> bool:
	var t := now_ms()
	var kept := []
	for to in toasts:
		if to.out < 0.0 and t - to.t0 >= Achievements.TOAST_MS:
			to.out = t
		if to.out >= 0.0 and t - to.out >= OUT_MS:
			if on_gone.is_valid():
				on_gone.call_deferred()
			continue
		kept.append(to)
	toasts = kept
	return not toasts.is_empty()


func _txt_lines(a: Dictionary, w: float) -> Array:
	return [Css.wrap(Css.ps(), 10, str(a.name), w), Css.wrap(Css.vt(), 17, str(a.desc), w)]


func paint() -> void:
	var t := now_ms()
	var w := minf(size.x - 20.0, 440.0)
	var y := 2.0 + 6.0
	for to in toasts:
		var a: Dictionary = to.a
		var g := Css.css(Achievements.color_of(a))
		var txt_w := w - 2.0 - 7.0 - 34.0 - 10.0 - 10.0 - 30.0 - 12.0 - 2.0
		var L := _txt_lines(a, txt_w)
		var h := maxf(H, 2.0 + 7.0 + 10.0 + 3.0 + L[0].size() * 13.0 + 3.0 + L[1].size() * 17.0 + 7.0 + 2.0)
		var box := Rect2(roundf((size.x - w) / 2.0), y, roundf(w), h)
		# ach-in: steps(6) down from above the view; ach-out: steps(4) back up and gone
		var dy := 0.0
		var alpha := 1.0
		var age: float = Css.age(t - to.t0)
		if age < IN_MS:
			dy = -1.3 * (h + y) * (1.0 - Css.steps(age / IN_MS, 6))
		if to.out >= 0.0:
			var k := Css.steps(Css.age(t - to.out) / OUT_MS, 4)
			dy = -1.3 * (h + y) * k
			alpha = 1.0 - k
		box.position.y += roundf(dy)
		_toast(box, a, to.count, g, t - to.t0, alpha)
		y += h + 6.0


func _toast(box: Rect2, a: Dictionary, count, g: Color, age: float, alpha: float) -> void:
	Css.glow(self, box, Color(1.0, 0.82, 0.48, 0.45 * alpha), 18.0)
	draw_rect(box.grow(3.0), Color(0, 0, 0, alpha))
	draw_rect(box, Color(0, 0, 0, 0.93 * alpha))
	# ach-shine: a light band sweeps across once it has landed
	var s := (age - SHINE_DELAY) / SHINE_MS
	if s > 0.0 and s < 1.0:
		var k := 1.0 - pow(1.0 - s, 2.0)
		var cx := box.position.x + box.size.x * lerpf(1.3, -0.3, k)
		var band := box.size.x * 0.16
		var pts := PackedVector2Array([Vector2(cx - band / 2.0 + 10, box.position.y), Vector2(cx + band / 2.0 + 10, box.position.y), Vector2(cx + band / 2.0 - 10, box.end.y), Vector2(cx - band / 2.0 - 10, box.end.y)])
		var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]))
		for poly in clipped:
			draw_colored_polygon(poly, Color(1.0, 0.925, 0.745, 0.16 * alpha))
	Css.frame(self, box, Css.alpha(GOLD, alpha), 2.0)
	Css.frame(self, box.grow(-5.0), Color(1.0, 0.82, 0.48, 0.35 * alpha), 1.0)
	# the badge
	var ico := Rect2(box.position.x + 2.0 + 7.0, box.get_center().y - 17.0, 34, 34)
	Css.glow(self, ico, Css.alpha(g, 0.7 * alpha), 10.0)
	draw_rect(ico, Css.alpha(Css.mix(g, 0.18), alpha))
	Css.frame(self, ico, Css.alpha(g, alpha), 2.0)
	Css.glyph(self, Achievements.GLYPHS.get(a.icon, Achievements.GLYPHS["secret"]), ico.get_center() - Vector2(10.5, 10.5), 21.0, Css.alpha(g, alpha))
	# the words: the tag, the name in gold, what it was for
	var x := ico.end.x + 10.0
	var y := box.position.y + 2.0 + 7.0
	var txt_w := box.end.x - 12.0 - 2.0 - 40.0 - x
	var tag := "ACHIEVEMENT UNLOCKED"
	var tag_r := Rect2(x, y, Css.width(Css.ps(), 7, tag) + 8.0, 10.0)
	draw_rect(tag_r, Css.alpha(GOLD, alpha))
	Css.text(self, Css.ps(), 7, x + 4.0, y + 2.0, tag, Color(0, 0, 0, alpha), 7)
	y += 13.0
	var L := _txt_lines(a, txt_w)
	for l in L[0]:
		Css.text(self, Css.ps(), 10, x, y, l, Css.alpha(GOLD, alpha), 13.0)
		y += 13.0
	y += 3.0
	for l in L[1]:
		Css.text(self, Css.vt(), 17, x, y, l, Css.alpha(Css.INK, alpha), 17.0)
		y += 17.0
	if count is Dictionary and count.get("total"):
		var n := "%d/%d" % [count.earned, count.total]
		Css.text(self, Css.ps(), 7, box.end.x - 12.0 - Css.width(Css.ps(), 7, n), box.position.y + 2.0 + 7.0 + 2.0, n, Css.alpha(Css.DIM, alpha), 7)
