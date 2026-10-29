## The vow ledger (renderVows in game.js; .vows in style.css): every promise and who it was sworn to, in that
## monster's colour. A broken vow gets a red slash drawn across it, once (the slash sweeps in), and the box shakes.
extends "res://src/ui/widget.gd"

const Species = preload("res://src/rules/species.gd")

const LINE := 18 # .vows li { font-size: 18px; line-height: 1.1 }
const TO := 16 # .vow-to { font-size: 16px }
const SLASH_MS := 450.0
const SHAKE_MS := 400.0
const SHAKE_DELAY := 350.0

var vows: Array = []
var natural_h := 0.0
var _sig := ""
var _slash_at := {} # vow id -> when its slash started sweeping
var _shake_at := -1e9


## renderVows(): only when something changed, so a fresh slash animates exactly once
func set_vows(list: Array) -> void:
	var parts := []
	for v in list:
		parts.append("%s:%s" % [v.id, v.status])
	var sig := "|".join(parts)
	if sig == _sig:
		return
	_sig = sig
	vows = list
	var t := now_ms()
	for v in vows:
		if v.status == "broken" and v.get("fresh", false):
			_slash_at[v.id] = t
		v.fresh = false
	if vows.any(func(v): return v.status == "broken" and v.get("justBroken", false)):
		_shake_at = t + SHAKE_DELAY
		for v in vows:
			v.justBroken = false
	natural_h = _measure(size.x)
	queue_redraw()


## Forget what was drawn (a recruit hands vows over to the new ally)
func reset() -> void:
	_sig = ""


func animating() -> bool:
	var t := now_ms()
	if t - _shake_at < SHAKE_MS:
		return true
	for at in _slash_at.values():
		if t - at < SLASH_MS:
			return true
	return false


func _lines(v: Dictionary, w: float) -> Array:
	# words of the vow in 18px, then "TO NAME" in 16px; wrapped as one paragraph
	var words := []
	for s in str(v.text).split(" ", false):
		words.append([s, LINE, false])
	for s in ("TO " + str(v.toName).to_upper()).split(" ", false):
		words.append([s, TO, true])
	var lines := [[]]
	var x := 0.0
	var space := Css.width(Css.vt(), LINE, " ")
	for wd in words:
		var ww := Css.width(Css.vt(), wd[1], wd[0])
		if x > 0.0 and x + ww > w:
			lines.append([])
			x = 0.0
		lines[lines.size() - 1].append([wd[0], wd[1], wd[2], x])
		x += ww + space
	return lines


func _measure(w: float) -> float:
	if vows.is_empty():
		return 0.0
	var h := 1.0 + 6.0 + 9.0 + 4.0
	for i in vows.size():
		h += _lines(vows[i], w - 18.0).size() * 20.0 + (4.0 if i > 0 else 0.0)
	return h + 6.0 + 1.0


func paint() -> void:
	if vows.is_empty():
		return
	var t := now_ms()
	var dx := 0.0
	var border := Css.FAINT
	var age := t - _shake_at
	if age >= 0.0 and age < SHAKE_MS:
		var n := Css.nudge(age, SHAKE_MS, 4.0)
		dx = n[0]
		if age > SHAKE_MS * 0.1 and age < SHAKE_MS * 0.9:
			border = Css.WARN
	var box := Rect2(dx, 0, size.x, natural_h)
	Css.frame(self, box, border, 1.0)
	Css.text(self, Css.ps(), 9, dx + 9.0, 7.0, "VOWS", Css.DIM, 9)
	var y := 7.0 + 9.0 + 4.0
	for i in vows.size():
		var v: Dictionary = vows[i]
		if i > 0:
			y += 4.0
		var broken: bool = v.status == "broken"
		var color := Css.css(Species.SPECIES.get(v.get("toSpecies"), {}).get("color", "#e8e8e8"))
		var lines := _lines(v, size.x - 18.0)
		var top := y
		for line in lines:
			for wd in line:
				var c := color if wd[2] else (Css.DIM if broken else Css.INK)
				Css.text(self, Css.vt(), wd[1], dx + 9.0 + wd[3], y + (2.0 if wd[1] == TO else 0.0), wd[0], c, 20.0 - (2.0 if wd[1] == TO else 0.0))
			y += 20.0
		if broken:
			# the red slash across the vow: 3px, glowing, a touch off level, swept in from the left once
			var p := 1.0
			if _slash_at.has(v.id):
				p = clampf((t - _slash_at[v.id]) / SLASH_MS, 0.0, 1.0)
				p = 1.0 - pow(1.0 - p, 3.0)
			var a := Vector2(dx + 9.0 - 2.0, top + (y - top) / 2.0)
			var len := (size.x - 18.0 + 4.0) * p
			var dir := Vector2(cos(deg_to_rad(-1.5)), sin(deg_to_rad(-1.5)))
			if len > 0.5:
				draw_line(a, a + dir * len, Css.alpha(Css.WARN, 0.35), 7.0)
				draw_line(a, a + dir * len, Css.WARN, 3.0)
