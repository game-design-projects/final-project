## A yes/no question over the view (renderModal and nudgeModal in game.js; .modal in style.css): a lit box in the
## floor's accent, where your eyes already are, with clickable answers. It pops in, its glow breathes, and a key
## it doesn't take shakes it.
extends "res://src/ui/widget.gd"

const FONT := 11
const LINE := 17.6 # font: 11px/1.6
const IN_MS := 180.0
const NUDGE_MS := 350.0

var prompt = null
var accent := Css.ACCENT
var _shown_at := -1e9
var _nudge_at := -1e9


func set_prompt(p, accent_color: Color) -> void:
	if p != null and not is_same(p, prompt):
		_shown_at = now_ms()
		_nudge_at = -1e9
	prompt = p
	accent = accent_color
	visible = p != null
	queue_redraw()


func nudge() -> void:
	_nudge_at = now_ms()


func animating() -> bool:
	return prompt != null


func _button_w(cap: String, label: String) -> float:
	return 2.0 + 10.0 + Css.width(Css.ps(), FONT, cap + " " + label) + 10.0 + 2.0


func paint() -> void:
	if prompt == null:
		return
	var t := now_ms()
	var font := Css.ps()
	var w := minf(size.x * 0.86, 380.0)
	var lines := Css.wrap(font, FONT, str(prompt.text), w - 4.0 - 32.0)
	var has_no := prompt.get("no") != null and str(prompt.no) != ""
	var aside: bool = prompt.get("walkAway", false)
	var h := 2.0 + 14.0 + lines.size() * LINE + 12.0 + 33.6 + (10.0 + 12.8 if aside else 0.0) + 12.0 + 2.0
	var box := Rect2(((size - Vector2(w, h)) / 2.0).round(), Vector2(w, h).round())

	# modal-in, then modal-glow; a nudge shakes it and flares the glow
	var age := Css.age(t - _shown_at)
	var a := 1.0
	var s := 1.0
	if age < IN_MS:
		var k := 1.0 - pow(1.0 - age / IN_MS, 2.0)
		a = k
		s = lerpf(0.92, 1.0, k)
	var glow := 18.0 + 12.0 * Css.pulse(age - IN_MS, 1400.0)
	var n := Css.nudge(t - _nudge_at, NUDGE_MS, 8.0)
	if t - _nudge_at < NUDGE_MS:
		glow = lerpf(18.0, 40.0, n[1])
	var c := box.get_center()
	draw_set_transform(c - c * s + Vector2(n[0], 0), 0.0, Vector2(s, s))
	Css.glow(self, box, Css.alpha(accent, a), glow, 4.0)
	draw_rect(box.grow(4.0), Css.alpha(Color.BLACK, a))
	draw_rect(box, Color(0, 0, 0, 0.92 * a))
	Css.frame(self, box, Css.alpha(accent, a), 2.0)
	var y := box.position.y + 2.0 + 14.0
	for l in lines:
		var lw := Css.width(font, FONT, l)
		Css.text(self, font, FONT, c.x - lw / 2.0, y, l, Css.alpha(Css.INK, a), LINE)
		y += LINE
	y += 12.0
	# the answers: Y on the accent, N in a frame
	var yes_w := _button_w("Y", str(prompt.yes))
	var no_w := _button_w("N", str(prompt.no)) if has_no else 0.0
	var total := yes_w + (10.0 + no_w if has_no else 0.0)
	var x := c.x - total / 2.0
	_button(_round(Rect2(x, y, yes_w, 33.6)), "y", "Y", str(prompt.yes), true, a)
	if has_no:
		_button(_round(Rect2(x + yes_w + 10.0, y, no_w, 33.6)), "n", "N", str(prompt.no), false, a)
	y += 33.6
	if aside:
		var text := "OR JUST WALK AWAY"
		Css.text(self, font, 8, c.x - Css.width(font, 8, text) / 2.0, y + 10.0, text, Css.alpha(Css.DIM, a), 12.8)
	draw_set_transform(Vector2.ZERO)
	add_hit(box, {"id": "modal", "panel": "#modal"})
	hits.push_front(hits.pop_back())


static func _round(r: Rect2) -> Rect2:
	return Rect2(r.position.round(), r.size.round())


func _button(r: Rect2, key: String, cap: String, label: String, first: bool, a: float) -> void:
	var id := "modal:" + key
	if hover_id == id:
		Css.frame(self, r.grow(4.0), Css.alpha(Css.INK, a), 2.0)
	draw_rect(r, Css.alpha(accent if first else Color.BLACK, a))
	Css.frame(self, r, Css.alpha(accent, a), 2.0)
	var fg := Color.BLACK if first else Css.INK
	var font := Css.ps()
	var x := r.position.x + 12.0
	var cw := Css.text(self, font, FONT, x, r.position.y + 2.0 + 6.0, cap, Css.alpha(fg, a), LINE)
	# kbd: underlined
	draw_rect(Rect2(x, r.position.y + 8.0 + (LINE + FONT) / 2.0 + 1.0, cw, 2.0), Css.alpha(fg, a))
	Css.text(self, font, FONT, x + cw + Css.width(font, FONT, " "), r.position.y + 8.0, label, Css.alpha(fg, a), LINE)
	add_hit(r, {"id": id, "key": key})


func _pressed(h: Dictionary) -> void:
	if h.has("key") and ui != null:
		ui.press_key(h.key)
