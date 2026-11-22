## A small moving picture of what the walk has stopped at: the gate and its chain, the keepsakes a champion left, the shut
## door, the stairs, the way out, the camp's fire. A stage names it in `state.vignette`; the choice popup draws it over the
## picture, because the corridor behind shows a wall where the words say a gate. Each is a hand drawing from the `events`
## sheet (tools/art/source/events.png), in the run's wall colour with its accent on what matters, and the game moves a part
## of it: the bars sink, the fire leans, a glint goes from one keepsake to the next. Every drawing takes the box it is given
## and the time, and keeps nothing.
extends RefCounted

const Palette = preload("res://src/view/palette.gd")
const Sprites = preload("res://src/view/sprites.gd")

## The pictures there are: a stage may only name one of these (meta: features_test checks the stages against it).
const KNOWN := ["keepsakes", "gate", "door", "stairs", "ending", "camp"]
const RATIO := 2.0 # as wide as this many of its height
const SHEET := "events"

# Where the parts of each drawing are, as shares of that drawing's own ink (0..1 across and down). They were measured on the
# sheet, so a drawing that is redrawn needs its parts measured again.
const KEEPSAKES := [Rect2(0.036, 0.2, 0.24, 0.45), Rect2(0.367, 0.2, 0.263, 0.45), Rect2(0.7335, 0.0, 0.2363, 0.67)] # the heart, the stone, the charm
const FLAME_FROM := 0.611 # the fire above this moves; the logs under it don't
const FLAME_FOOT := Rect2(0.339, 0.611, 0.362, 0.093) # the foot of the flame, between the logs
const GATE_BARS := Rect2(0.2072, 0.2052, 0.519, 0.5597) # where `gate_bars` and `gate_chain` sit in `gate`
const GATE_CHAIN := Rect2(0.8859, 0.2687, 0.1065, 0.597)
const GATE_DROP := 0.17 # how far the bars sink, as a share of the gate's height: just short of the floor
const DOOR_HANDLES := [Rect2(0.3868, 0.5331, 0.0868, 0.2021), Rect2(0.5472, 0.5331, 0.0887, 0.2021)] # yours, and the one that waits
const DOORWAY := Rect2(0.69, 0.3, 0.118, 0.29) # the way out's opening
const RAYS := [
	Rect2(0.529, 0.3051, 0.0634, 0.0302), Rect2(0.567, 0.148, 0.0562, 0.0755), Rect2(0.6467, 0.0423, 0.038, 0.0967), Rect2(0.7591, 0.0, 0.0181, 0.1057),
	Rect2(0.8496, 0.0483, 0.0417, 0.0967), Rect2(0.9022, 0.1541, 0.0634, 0.0725), Rect2(0.9257, 0.3051, 0.0652, 0.0332),
]
const STEPS_DOWN := [Vector2(0.165, 0.013), Vector2(0.316, 0.242), Vector2(0.479, 0.445), Vector2(0.629, 0.652), Vector2(0.794, 0.828)] # the middle of each tread
const STEPS_UP := [Vector2(0.223, 0.834), Vector2(0.335, 0.758), Vector2(0.453, 0.668), Vector2(0.558, 0.562), Vector2(0.748, 0.607)] # the last is the doorway's sill


## Draw `id` into `box` on `c` at time `t` (seconds). An id there is no picture for draws nothing.
static func draw(c: CanvasItem, id: String, box: Rect2, t: float, wall: Color, accent: Color) -> void:
	if not KNOWN.has(id):
		return
	var to := fit(id, box)
	var w := maxf(1.5, box.size.y / 60.0) # a line's width for what is drawn in code, in step with the picture's size
	match id:
		"keepsakes":
			_keepsakes(c, to, t, wall, accent)
		"gate":
			_gate(c, to, t, wall, accent)
		"door":
			_door(c, to, t, wall, accent)
		"stairs":
			_whole(c, id, to, wall)
			_walker(c, to, STEPS_DOWN, w, t, 1.0)
		"ending":
			_ending(c, to, w, t, wall)
		"camp":
			_camp(c, to, w, t, wall, accent)


## Where the drawing `id` goes in `box`: its ink as big as fits, in the middle, standing on the box's floor.
static func fit(id: String, box: Rect2) -> Rect2:
	var ink := Sprites.ink(SHEET, id)
	var size := ink.size * minf(box.size.x / ink.size.x, box.size.y / ink.size.y)
	return Rect2(box.position + Vector2((box.size.x - size.x) / 2.0, box.size.y - size.y), size)


## The part `part` of drawing `id` (a share of its ink), where it belongs when the whole ink goes to `to`.
static func _part(c: CanvasItem, id: String, to: Rect2, part: Rect2, colour: Color) -> void:
	var ink := Sprites.ink(SHEET, id)
	var from := Rect2(Sprites.drawing_rect(SHEET, id).position + ink.position + part.position * ink.size, part.size * ink.size)
	c.draw_texture_rect_region(Sprites.texture(SHEET), Rect2(to.position + part.position * to.size, part.size * to.size), from, colour)


static func _whole(c: CanvasItem, id: String, to: Rect2, colour: Color) -> void:
	_part(c, id, to, Rect2(0, 0, 1, 1), colour)


## A drawing of its own that belongs at `place` in another whose ink is at `to`: moved by `shift`, and with `cut` of its top
## left off and the rest drawn from where the top was (a chain running up over its wheel).
static func _layer(c: CanvasItem, id: String, to: Rect2, place: Rect2, colour: Color, shift := Vector2.ZERO, cut := 0.0) -> void:
	var ink := Sprites.ink(SHEET, id)
	var from := Rect2(Sprites.drawing_rect(SHEET, id).position + ink.position + Vector2(0.0, ink.size.y * cut), Vector2(ink.size.x, ink.size.y * (1.0 - cut)))
	var at := Rect2(to.position + place.position * to.size + shift, Vector2(place.size.x, place.size.y * (1.0 - cut)) * to.size)
	c.draw_texture_rect_region(Sprites.texture(SHEET), at, from, colour)


## Three things on three stands, and a glint that goes from one to the next: the one it is on is lit.
static func _keepsakes(c: CanvasItem, to: Rect2, t: float, wall: Color, accent: Color) -> void:
	_whole(c, "keepsakes", to, wall)
	var lit := int(t * 1.1) % 3
	for i in 3:
		_part(c, "keepsakes", to, KEEPSAKES[i], Palette.MERCY if i == lit else accent)
	var glow := 0.5 + 0.5 * sin(t * 1.1 * TAU)
	var on: Rect2 = KEEPSAKES[lit]
	var size := Vector2.ONE * to.size.y * (0.16 + 0.1 * glow)
	var at := to.position + Vector2(on.end.x - 0.01, on.position.y + 0.06) * to.size
	c.draw_texture_rect_region(Sprites.texture("props"), Rect2(at - size / 2.0, size), _prop("sparkle"), Color(Palette.INK, 0.45 + 0.55 * glow))


## A drawing of the props sheet, cut to its ink.
static func _prop(drawing: String) -> Rect2:
	var ink := Sprites.ink("props", drawing)
	return Rect2(Sprites.drawing_rect("props", drawing).position + ink.position, ink.size)


## A gate in its arch that sinks on its chain and is hauled back up, over and over: it drops unless someone holds it.
static func _gate(c: CanvasItem, to: Rect2, t: float, wall: Color, accent: Color) -> void:
	var phase := fmod(t, 2.6) / 2.6
	var down := phase / 0.82 if phase < 0.82 else 1.0 - (phase - 0.82) / 0.18 # sinks slowly, comes up fast
	var jolt := 0.012 * sin(t * 40.0) if phase >= 0.82 else 0.0
	_whole(c, "gate", to, wall)
	_layer(c, "gate_bars", to, GATE_BARS, accent, Vector2(0.0, (GATE_DROP * down + jolt) * to.size.y))
	# the chain runs up over its wheel as the bars go down, and the ring someone has to hold rises with it
	_layer(c, "gate_chain", to, GATE_CHAIN, Palette.MERCY, Vector2.ZERO, clampf(0.3 * down + jolt, 0.0, 0.5))


## Two leaves, shut, with a ring on each: yours is lit, the other waits for someone.
static func _door(c: CanvasItem, to: Rect2, t: float, wall: Color, accent: Color) -> void:
	_whole(c, "door", to, wall)
	_part(c, "door", to, DOOR_HANDLES[0], Palette.YOU)
	_part(c, "door", to, DOOR_HANDLES[1], Color(accent, 0.25 + 0.75 * absf(sin(t * 2.2))))


## The steps climb to a lit doorway: its rays come and go, and a mark goes up to it.
static func _ending(c: CanvasItem, to: Rect2, w: float, t: float, wall: Color) -> void:
	_whole(c, "ending", to, wall)
	var shine := 0.6 + 0.4 * sin(t * 2.0)
	c.draw_rect(Rect2(to.position + DOORWAY.position * to.size, DOORWAY.size * to.size), Color(Palette.MERCY, 0.3 * shine))
	for i in RAYS.size():
		_part(c, "ending", to, RAYS[i], Color(Palette.MERCY, clampf(0.55 + 0.45 * sin(t * 2.0 + i * 0.9), 0.0, 1.0)))
	_walker(c, to, STEPS_UP, w, t, -1.0)


## A mark that goes down the steps, or up them (`way` -1), hopping from tread to tread: you.
static func _walker(c: CanvasItem, to: Rect2, steps: Array, w: float, t: float, way: float) -> void:
	var step := fmod(t * 1.6, float(steps.size()))
	var on: Vector2 = steps[int(step)]
	var at := to.position + on * to.size - Vector2(0.0, (0.09 + 0.04 * absf(sin(step * PI))) * to.size.y)
	var arm := to.size.y * 0.045
	c.draw_polyline([at + Vector2(-arm, -arm * way), at + Vector2(0.0, arm * way), at + Vector2(arm, -arm * way)], Palette.YOU, w * 1.3)


## A fire on crossed logs: the flame leans and stretches and never holds still, and sparks go up.
static func _camp(c: CanvasItem, to: Rect2, w: float, t: float, wall: Color, accent: Color) -> void:
	_part(c, "camp", to, Rect2(0.0, FLAME_FROM, 1.0, 1.0 - FLAME_FROM), wall)
	_part(c, "camp", to, FLAME_FOOT, accent)
	# the flame above the logs, pinned where it meets them
	var foot := to.position + Vector2(0.5, FLAME_FROM) * to.size
	var tall := 1.0 + 0.05 * sin(t * 6.1) + 0.03 * sin(t * 9.7 + 1.0)
	var lean := 0.07 * sin(t * 3.3) + 0.03 * sin(t * 7.9)
	c.draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(lean, tall), Vector2(-lean * foot.y, foot.y * (1.0 - tall))))
	_part(c, "camp", to, Rect2(0.0, 0.0, 1.0, FLAME_FROM), accent)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	for k in 5:
		var life := fmod(t * 0.6 + k * 0.23, 1.0)
		var x := 0.5 + 0.12 * sin(k * 2.4 + life * 3.0)
		c.draw_circle(to.position + Vector2(x, 0.3 - life * 0.42) * to.size, w * 0.9, Color(Palette.MERCY, 1.0 - life))
