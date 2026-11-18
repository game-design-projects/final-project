## A small moving picture of what the walk has stopped at: the gate and its chain, the keepsakes a champion left, the shut
## door, the stairs, the way out, the camp's fire. A stage names it in `state.vignette`; the choice popup draws it over the
## picture, because the corridor behind shows a wall where the words say a gate. Lines only, in the run's wall colour with
## its accent, like the halls themselves. Every drawing takes the box it is given and the time, and keeps nothing.
extends RefCounted

const Palette = preload("res://src/view/palette.gd")

## The pictures there are: a stage may only name one of these (meta: features_test checks the stages against it).
const KNOWN := ["keepsakes", "gate", "door", "stairs", "ending", "camp"]
const RATIO := 2.0 # as wide as this many of its height


## Draw `id` into `box` on `c` at time `t` (seconds). An id there is no picture for draws nothing.
static func draw(c: CanvasItem, id: String, box: Rect2, t: float, wall: Color, accent: Color) -> void:
	var at := func(x: float, y: float) -> Vector2: return box.position + Vector2(x, y) * box.size
	var w := maxf(1.5, box.size.y / 60.0) # a line's width, in step with the picture's size
	match id:
		"keepsakes":
			_keepsakes(c, at, w, t, wall, accent)
		"gate":
			_gate(c, at, w, t, wall, accent)
		"door":
			_door(c, at, w, t, wall, accent)
		"stairs":
			_stairs(c, at, w, t, wall, accent, false)
		"ending":
			_stairs(c, at, w, t, wall, accent, true)
		"camp":
			_camp(c, at, w, t, wall, accent)


## Three things on three stands, each rising and falling a little, and a glint that goes from one to the next.
static func _keepsakes(c: CanvasItem, at: Callable, w: float, t: float, wall: Color, accent: Color) -> void:
	var lit := int(t * 1.1) % 3
	for i in 3:
		var x := 0.2 + i * 0.3
		var lift := 0.03 * sin(t * 2.0 + i * 2.1)
		c.draw_polyline([at.call(x - 0.07, 0.92), at.call(x - 0.05, 0.74), at.call(x + 0.05, 0.74), at.call(x + 0.07, 0.92)], Color(wall, 0.8), w)
		var ink: Color = Palette.MERCY if i == lit else accent
		var y := 0.46 + lift
		match i:
			0: # a heart
				c.draw_polyline([at.call(x, y + 0.2), at.call(x - 0.08, y + 0.02), at.call(x - 0.08, y - 0.1), at.call(x - 0.04, y - 0.16), at.call(x, y - 0.08), at.call(x + 0.04, y - 0.16), at.call(x + 0.08, y - 0.1), at.call(x + 0.08, y + 0.02), at.call(x, y + 0.2)], ink, w)
			1: # a cut stone
				c.draw_polyline([at.call(x, y + 0.2), at.call(x - 0.08, y - 0.04), at.call(x - 0.04, y - 0.16), at.call(x + 0.04, y - 0.16), at.call(x + 0.08, y - 0.04), at.call(x, y + 0.2)], ink, w)
				c.draw_line(at.call(x - 0.08, y - 0.04), at.call(x + 0.08, y - 0.04), ink, w)
			2: # a ring
				c.draw_arc(at.call(x, y + 0.04), (at.call(0.0, 0.14) - at.call(0.0, 0.0)).y, 0.0, TAU, 24, ink, w)
				c.draw_polyline([at.call(x - 0.03, y - 0.1), at.call(x, y - 0.18), at.call(x + 0.03, y - 0.1)], ink, w)
		if i == lit:
			var glow := 0.5 + 0.5 * sin(t * 1.1 * TAU)
			var s := 0.05 * (0.6 + 0.4 * glow)
			var g: Vector2 = at.call(x + 0.07, y - 0.2)
			var arm: float = (at.call(0.0, s * 2.0) - at.call(0.0, 0.0)).y
			c.draw_line(g - Vector2(arm, 0), g + Vector2(arm, 0), Color(Palette.INK, 0.5 + 0.5 * glow), w)
			c.draw_line(g - Vector2(0, arm), g + Vector2(0, arm), Color(Palette.INK, 0.5 + 0.5 * glow), w)


## A gate between two posts that sinks on its chain and is hauled back up, over and over: it drops unless someone holds it.
static func _gate(c: CanvasItem, at: Callable, w: float, t: float, wall: Color, accent: Color) -> void:
	var phase := fmod(t, 2.6) / 2.6
	var drop := 0.26 * (phase / 0.82 if phase < 0.82 else 1.0 - (phase - 0.82) / 0.18) # sinks slowly, comes up fast
	var jolt := 0.012 * sin(t * 40.0) if phase >= 0.82 else 0.0
	c.draw_polyline([at.call(0.14, 0.96), at.call(0.14, 0.08), at.call(0.72, 0.08), at.call(0.72, 0.96)], Color(wall, 0.9), w * 1.3)
	c.draw_line(at.call(0.06, 0.96), at.call(0.94, 0.96), Color(wall, 0.5), w)
	var top := 0.1 + drop + jolt
	var foot := top + 0.56
	for i in 6:
		var x := 0.2 + i * 0.092
		c.draw_line(at.call(x, top), at.call(x, foot), accent, w)
		c.draw_polyline([at.call(x - 0.02, foot), at.call(x, foot + 0.06), at.call(x + 0.02, foot)], accent, w)
	for y in [top + 0.14, top + 0.38]:
		c.draw_line(at.call(0.18, y), at.call(0.68, y), accent, w)
	# the chain: up from the gate, over a wheel, and down to the ring someone has to hold
	var wheel: Vector2 = at.call(0.84, 0.14)
	var r: float = (at.call(0.0, 0.07) - at.call(0.0, 0.0)).y
	c.draw_arc(wheel, r, 0.0, TAU, 20, Color(wall, 0.9), w)
	c.draw_dashed_line(at.call(0.72, 0.1), at.call(0.8, 0.1), Palette.MERCY, w, w * 2.5)
	var ring_y := 0.74 - drop * 1.3 - jolt
	c.draw_dashed_line(at.call(0.88, 0.16), at.call(0.88, ring_y - 0.07), Palette.MERCY, w, w * 2.5)
	c.draw_arc(at.call(0.88, ring_y), r * 0.9, 0.0, TAU, 20, Palette.MERCY, w * 1.3)


## Two tall leaves, shut. A hand's mark on each: yours is lit, the other is empty and waits for someone.
static func _door(c: CanvasItem, at: Callable, w: float, t: float, wall: Color, accent: Color) -> void:
	c.draw_polyline([at.call(0.3, 0.96), at.call(0.3, 0.3), at.call(0.36, 0.14), at.call(0.5, 0.06), at.call(0.64, 0.14), at.call(0.7, 0.3), at.call(0.7, 0.96)], Color(wall, 0.9), w * 1.3)
	c.draw_line(at.call(0.5, 0.06), at.call(0.5, 0.96), Color(wall, 0.9), w)
	c.draw_line(at.call(0.16, 0.96), at.call(0.84, 0.96), Color(wall, 0.5), w)
	for x in [0.36, 0.64]:
		c.draw_line(at.call(x, 0.3), at.call(x, 0.9), Color(wall, 0.35), w)
	var r: float = (at.call(0.0, 0.08) - at.call(0.0, 0.0)).y
	c.draw_circle(at.call(0.43, 0.56), r, Palette.YOU)
	var waits := 0.25 + 0.75 * absf(sin(t * 2.2))
	c.draw_arc(at.call(0.57, 0.56), r, 0.0, TAU, 20, Color(accent, waits), w * 1.3)


## Steps going down into the dark, and a mark that goes down them. `up` is the way out instead: the steps climb to a lit door.
static func _stairs(c: CanvasItem, at: Callable, w: float, t: float, wall: Color, accent: Color, up: bool) -> void:
	var steps := 6
	var pts: Array = []
	for i in steps + 1:
		var x := 0.14 + i * 0.1
		var y := (0.9 - i * 0.11) if up else (0.24 + i * 0.11)
		pts.append(at.call(x, y))
		if i < steps:
			pts.append(at.call(x + 0.1, y))
	c.draw_polyline(PackedVector2Array(pts), Color(wall, 0.9), w * 1.3)
	for i in steps: # each step fainter the further down it is
		var x := 0.14 + i * 0.1
		var y := (0.9 - i * 0.11) if up else (0.24 + i * 0.11)
		var far := float(i) / steps
		c.draw_line(at.call(x, y), at.call(x, 0.96), Color(wall, 0.35 * (far if up else 1.0 - far) + 0.08), w)
	var step := fmod(t * 1.6, float(steps))
	var i := int(step)
	var mx := 0.19 + i * 0.1
	var my := ((0.9 - i * 0.11) if up else (0.24 + i * 0.11)) - 0.07 - 0.03 * absf(sin(step * PI))
	var d := -1.0 if up else 1.0
	c.draw_polyline([at.call(mx - 0.03, my - 0.04 * d), at.call(mx, my + 0.04 * d), at.call(mx + 0.03, my - 0.04 * d)], Palette.YOU, w * 1.3)
	if up:
		var door := Rect2(at.call(0.78, 0.06), at.call(0.14, 0.26) - at.call(0.0, 0.0))
		var shine := 0.6 + 0.4 * sin(t * 2.0)
		c.draw_rect(door, Color(Palette.MERCY, 0.25 * shine))
		c.draw_rect(door, Palette.MERCY, false, w * 1.3)
		for k in 5:
			var a := -2.6 + k * 0.5 + 0.1 * sin(t + k)
			var from: Vector2 = door.get_center() + Vector2(cos(a), sin(a)) * door.size.y * 0.75
			c.draw_line(from, from + Vector2(cos(a), sin(a)) * door.size.y * (0.3 + 0.15 * shine), Color(Palette.MERCY, 0.7 * shine), w)
	else:
		c.draw_polyline([at.call(0.78, 0.7), at.call(0.84, 0.84), at.call(0.9, 0.7)], Color(accent, 0.4 + 0.6 * absf(sin(t * 2.4))), w * 1.3)


## A fire of crossed logs: three tongues that never hold still, and sparks going up.
static func _camp(c: CanvasItem, at: Callable, w: float, t: float, wall: Color, accent: Color) -> void:
	c.draw_line(at.call(0.12, 0.92), at.call(0.88, 0.92), Color(wall, 0.5), w)
	c.draw_line(at.call(0.34, 0.9), at.call(0.66, 0.76), Color(wall, 0.9), w * 1.6)
	c.draw_line(at.call(0.34, 0.76), at.call(0.66, 0.9), Color(wall, 0.9), w * 1.6)
	for k in 3:
		var x := 0.42 + k * 0.08
		var tall := 0.3 + 0.12 * sin(t * (5.0 + k * 1.7) + k * 2.0) + (0.14 if k == 1 else 0.0)
		var lean := 0.03 * sin(t * 3.3 + k)
		c.draw_polyline([at.call(x - 0.05, 0.78), at.call(x + lean, 0.78 - tall), at.call(x + 0.05, 0.78)], Palette.MERCY if k == 1 else accent, w * 1.3)
	for k in 5:
		var life := fmod(t * 0.6 + k * 0.23, 1.0)
		var x := 0.5 + 0.12 * sin(k * 2.4 + life * 3.0)
		c.draw_circle(at.call(x, 0.4 - life * 0.34), w * 0.9, Color(Palette.MERCY, 1.0 - life))
