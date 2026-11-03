## The monsters as line art, for the flat battle screen: one colour, no fills, drawn on the 448x288 picture. Each species is
## a handful of strokes (lines, circles, curves) with one thing that moves (a wobble, a sway, a flap) so they are never still.
## `Art.draw` puts one on a CanvasItem; `cx` is where its middle goes, `by` where its feet go, `s` how big (1 = fills the view).
extends RefCounted

const W := 448.0
const H := 288.0

var _ci: CanvasItem
var _color := Color.WHITE
var _width := 2.0
var _xf := Transform2D.IDENTITY


## Draw `species` on `ci`. `t` is the clock in ms, `hurt` (0..1) shakes it.
static func draw(ci: CanvasItem, species: String, t: float, color: Color, cx := W / 2.0, by := 270.0, s := 0.85, hurt := 0.0) -> void:
	var art = new()
	art._ci = ci
	art._color = color
	art._width = maxf(1.0, 2.0 * s / maxf(s, 0.6))
	art._xf = Transform2D(0.0, Vector2(s, s), 0.0, Vector2(cx - 224.0 * s, by - 284.0 * s))
	if hurt > 0.0:
		art._xf = art._xf.translated_local(Vector2(sin(t / 20.0) * hurt * 6.0, 0.0))
	match species:
		"slime":
			art._slime(t)
		"bandit":
			art._bandit(t)
		"snake":
			art._snake(t)
		"rock":
			art._rock(t)
		"dragon":
			art._dragon(t)
		_:
			push_error("art: no monster called '%s'" % species)


# ---------------------------------------------------------------- the pen

## A line through flat x,y numbers; `close` joins the ends.
func _l(xy: Array, close := false) -> void:
	var pts := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		pts.append(_xf * Vector2(xy[i], xy[i + 1]))
	if close:
		pts.append(pts[0])
	_ci.draw_polyline(pts, _color, _width, true)


func _ellipse(x: float, y: float, rx: float, ry: float) -> void:
	var xy := []
	for i in 40:
		var a := TAU * i / 40.0
		xy.append_array([x + cos(a) * rx, y + sin(a) * ry])
	_l(xy, true)


func _circle(x: float, y: float, r: float) -> void:
	_ellipse(x, y, r, r)


func _dot(x: float, y: float, r := 2.0) -> void:
	_ci.draw_circle(_xf * Vector2(x, y), r * _xf.get_scale().x, _color)


## A chain of cubic curves: start x,y then (c1x,c1y,c2x,c2y,ex,ey) per piece.
func _curve(start: Array, pieces: Array) -> void:
	var p0 := Vector2(start[0], start[1])
	var xy := [p0.x, p0.y]
	for piece in pieces:
		var c1 := Vector2(piece[0], piece[1])
		var c2 := Vector2(piece[2], piece[3])
		var p1 := Vector2(piece[4], piece[5])
		for i in range(1, 13):
			var q := p0.bezier_interpolate(c1, c2, p1, i / 12.0)
			xy.append_array([q.x, q.y])
		p0 = p1
	_l(xy)


func _sway(dx: float, dy := 0.0) -> void:
	_xf = _xf.translated_local(Vector2(dx, dy))


# ---------------------------------------------------------------- the species

## Orange slime: a wobbling dome with a blank, unblinking stare.
func _slime(t: float) -> void:
	var wob := sin(t / 380.0) * 4.0
	var keep := _xf
	_xf = _xf.translated_local(Vector2(224, 236)).scaled_local(Vector2(1.0 + wob / 200.0, 1.0 - wob / 160.0)).translated_local(Vector2(-224, -236))
	_curve([136, 236], [[128, 160, 172, 96, 224, 96], [276, 96, 320, 160, 312, 236], [292, 244, 272, 230, 252, 240], [232, 250, 212, 232, 192, 240], [172, 248, 154, 238, 136, 236]])
	var shine := []
	for i in 9:
		var a := lerpf(PI * 1.18, PI * 1.36, i / 8.0)
		shine.append_array([224 + cos(a) * 76, 190 + sin(a) * 76])
	_l(shine)
	_l([170, 243, 170, 256])
	_circle(170, 260, 3)
	_l([262, 238, 262, 250])
	_circle(262, 254, 2.5)
	for x in [196, 252]: # big empty eyes, pinprick pupils dead centre
		_circle(x, 162, 14)
		_dot(x, 162, 1.8)
	_l([214, 200, 234, 200])
	_xf = keep
	_ellipse(224, 252, 104, 9) # the puddle


## Red bandit: hooded, masked, a knife in each hand.
func _bandit(t: float) -> void:
	_sway(sin(t / 450.0) * 3.0)
	_l([224, 38, 190, 66, 176, 106, 184, 138]) # hood
	_l([224, 38, 258, 66, 272, 106, 264, 138])
	_ellipse(224, 98, 26, 32)
	_l([208, 90, 218, 88])
	_l([230, 88, 240, 90])
	_dot(213, 90, 1.8)
	_dot(235, 90, 1.8)
	_l([199, 104, 249, 104]) # the mask
	_l([200, 104, 206, 122, 224, 128, 242, 122, 248, 104])
	_l([249, 106, 268, 112, 262, 122])
	_l([249, 106, 272, 104])
	_l([184, 138, 150, 150, 130, 190, 124, 262]) # cloak
	_l([264, 138, 298, 150, 318, 190, 324, 262])
	_l([124, 262, 140, 254, 152, 264, 166, 254, 180, 262])
	_l([268, 262, 282, 254, 296, 264, 310, 254, 324, 262])
	_l([198, 140, 224, 170, 250, 140])
	_l([190, 146, 194, 252])
	_l([258, 146, 254, 252])
	_l([188, 204, 260, 204]) # belt, buckle, coin pouch
	_l([188, 212, 260, 212])
	_l([216, 202, 232, 202, 232, 214, 216, 214], true)
	_l([240, 214, 256, 214, 256, 230, 240, 230], true)
	_l([202, 252, 198, 270])
	_l([246, 252, 250, 270])
	_l([150, 150, 140, 190, 158, 212]) # left arm, knife forward
	_circle(162, 214, 6)
	_l([166, 208, 194, 184])
	_l([160, 200, 172, 212])
	_l([298, 150, 322, 128, 332, 100]) # right arm, knife raised
	_circle(334, 96, 6)
	_l([338, 90, 352, 60])
	_l([328, 88, 344, 96])


## Green snake person: a hooded serpent rising from its coils, tongue flicking.
func _snake(t: float) -> void:
	_ellipse(224, 252, 112, 18) # the coils
	_ellipse(224, 236, 90, 15)
	_ellipse(230, 222, 66, 12)
	_l([322, 254, 354, 248, 374, 236, 380, 222, 370, 214])
	_sway(sin(t / 500.0) * 4.0)
	_l([202, 222, 196, 190, 204, 160, 212, 140]) # body
	_l([254, 222, 252, 190, 244, 160, 236, 140])
	for y in [208, 192, 176, 160]:
		_l([204, y, 224, y + 6, 248, y])
	_l([212, 140, 184, 132, 170, 140]) # shoulders and clawed arms
	_l([236, 140, 264, 132, 278, 140])
	_l([172, 140, 150, 170, 156, 196])
	_l([156, 196, 148, 206])
	_l([156, 196, 156, 208])
	_l([156, 196, 164, 206])
	_l([276, 140, 300, 166, 294, 194])
	_l([294, 194, 286, 204])
	_l([294, 194, 294, 206])
	_l([294, 194, 302, 204])
	_l([214, 132, 216, 118])
	_l([234, 132, 232, 118])
	_l([216, 118, 190, 104, 180, 80, 194, 56, 224, 46, 254, 56, 268, 80, 258, 104, 232, 118]) # the hood
	_l([196, 70, 206, 86])
	_l([252, 70, 242, 86])
	_l([210, 96, 210, 74, 224, 64, 238, 74, 238, 96, 224, 106], true) # head
	_l([213, 82, 221, 84])
	_l([227, 84, 235, 82])
	_dot(217, 83, 1.6)
	_dot(231, 83, 1.6)
	if sin(t / 220.0) > 0.2:
		_l([224, 106, 224, 118, 218, 124])
		_l([224, 118, 230, 124])


## Grey rock: a living heap of boulders with one glowing crack for an eye.
func _rock(t: float) -> void:
	_l([96, 264, 352, 264])
	_l([150, 264, 160, 256, 172, 264])
	_l([272, 264, 284, 255, 296, 264])
	_sway(0.0, sin(t / 900.0) * 2.0)
	_l([142, 252, 128, 202, 146, 152, 178, 120, 224, 106, 272, 118, 304, 150, 320, 200, 308, 252], true)
	_l([200, 142, 212, 168, 204, 190, 218, 214]) # cracks
	_l([278, 152, 264, 178, 272, 202])
	_l([162, 200, 182, 212, 176, 230])
	_dot(250, 230)
	_dot(190, 238)
	_dot(286, 228)
	_l([190, 120, 184, 88, 204, 62, 238, 58, 262, 80, 262, 114], true) # head
	_l([198, 90, 210, 84, 218, 92, 230, 82, 242, 90, 252, 86]) # the crack that is its eye
	_l([204, 94, 216, 98, 230, 92, 244, 96])
	_l([134, 160, 104, 168, 92, 202, 112, 216, 132, 202], true) # arms
	_l([96, 214, 84, 242, 100, 260, 124, 252, 120, 222], true)
	_l([314, 160, 344, 168, 356, 202, 336, 216, 316, 202], true)
	_l([352, 214, 364, 242, 348, 260, 324, 252, 328, 222], true)


## Yellow dragon: wings spread, horned head, coiled tail.
func _dragon(t: float) -> void:
	var flap := sin(t / 600.0) * 6.0
	_l([196, 160, 140, 90 - flap, 60, 40 - flap, 72, 110, 30, 150, 88, 144, 70, 190, 124, 168, 118, 210, 170, 182]) # wings
	_l([140, 90 - flap, 88, 144])
	_l([140, 90 - flap, 124, 168])
	_l([252, 160, 308, 90 - flap, 388, 40 - flap, 376, 110, 418, 150, 360, 144, 378, 190, 324, 168, 330, 210, 278, 182])
	_l([308, 90 - flap, 360, 144])
	_l([308, 90 - flap, 324, 168])
	_ellipse(224, 212, 66, 44) # body and belly plates
	_l([196, 190, 206, 226, 224, 236, 242, 226, 252, 190])
	_l([204, 206, 244, 206])
	_l([210, 222, 238, 222])
	_l([204, 176, 210, 140, 214, 114]) # neck
	_l([244, 176, 238, 140, 234, 114])
	_l([208, 112, 198, 84, 210, 66, 238, 66, 250, 84, 240, 112, 232, 126, 216, 126], true) # head
	_l([206, 70, 182, 30, 214, 64]) # horns
	_l([242, 70, 266, 30, 234, 64])
	_l([208, 86, 218, 84])
	_l([230, 84, 240, 86])
	_dot(218, 118, 1.8)
	_dot(230, 118, 1.8)
	_l([212, 112, 216, 106, 220, 112, 224, 106, 228, 112, 232, 106, 236, 112]) # teeth
	_l([180, 240, 170, 262, 160, 270]) # legs and claws
	_l([170, 262, 170, 274])
	_l([170, 262, 182, 272])
	_l([268, 240, 278, 262, 288, 270])
	_l([278, 262, 278, 274])
	_l([278, 262, 266, 272])
	_curve([284, 228], [[350, 262, 404, 262, 414, 226]]) # the tail
	_l([406, 232, 428, 214, 418, 240], true)
