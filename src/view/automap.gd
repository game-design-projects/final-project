## The automap: a small panel in the picture's top right corner, drawn outside the post-processing so it stays crisp. Floor
## you have seen is dark, floor you stood on lighter, walls are lines on the edges of seen floor (in the view walls are faces
## with no thickness, and a block would look like unexplored dark). The stairs are a ring; monsters you have seen are dots;
## the champion is marked in red from the start, so you can choose to hunt it. It only reads the game's state.
extends Control

const Palette = preload("res://src/view/palette.gd")

const PANEL := 115.0 # the whole panel, border and margin included
const MARGIN := 5.0 # border and margin round the map
const MAP_PX := 105
const SEEN := Color("#262626")
const VISITED := Color("#5a5a5a")
const YOU := Color.WHITE

var state # State, set by the owner
var _drawn_key := []


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL, PANEL)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The width of a cell on the map, in pixels.
func cell_px() -> int:
	return maxi(1, floori(float(MAP_PX) / state.floor_map.size))


## The dots of the monsters: [{"rect": Rect2 (map pixels), "color": Color}]. A seen monster is a dot inside its cell; the
## champion fills its cell, seen or not.
func monster_marks() -> Array:
	var s := cell_px()
	var out := []
	for m in state.floor_map.monsters:
		if m.is_gone():
			continue
		if m.boss and state.viewing("boss-at-exit") and not state.seen.has(m.cell):
			continue
		if m.boss:
			out.append({"rect": Rect2(Vector2(m.cell) * s, Vector2(s, s)), "color": Palette.BOSS})
		elif state.seen.has(m.cell):
			var dot := maxf(2.0, s - 4.0)
			out.append({"rect": Rect2(Vector2(m.cell) * s + Vector2.ONE * (s - dot) / 2.0, Vector2(dot, dot)), "color": Palette.monster(m)})
	return out


## The lines where seen floor meets a wall, as Rect2s 1 pixel thick (map pixels).
func wall_lines() -> Array:
	var f = state.floor_map
	var s := cell_px()
	var out := []
	for c in state.seen:
		var at := Vector2(c) * s
		for side in 4:
			if f.is_open(c + f.DIRS[side]):
				continue
			match side:
				0: out.append(Rect2(at, Vector2(s, 1)))
				1: out.append(Rect2(at + Vector2(s - 1, 0), Vector2(1, s)))
				2: out.append(Rect2(at + Vector2(0, s - 1), Vector2(s, 1)))
				_: out.append(Rect2(at, Vector2(1, s)))
	return out


## The stairs' ring (outer and inner squares, map pixels) once they are seen, or an empty list.
func stairs_mark() -> Array:
	var f = state.floor_map
	if not state.seen.has(f.stairs):
		return []
	var s := cell_px()
	var at := Vector2(f.stairs) * s
	return [Rect2(at + Vector2(1, 1), Vector2(s - 2, s - 2)), Rect2(at + Vector2(2, 2), Vector2(s - 4, s - 4))]


func _process(_dt: float) -> void:
	if state == null or state.floor_map == null:
		return
	var key := [state, state.cell, state.facing, state.seen.size(), state.visited.size(), state.floor_map.monsters_left()]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func _draw() -> void:
	if state == null or state.floor_map == null:
		return
	var f = state.floor_map
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	draw_rect(Rect2(Vector2.ZERO, size).grow(-0.5), Palette.FAINT, false, 1.0)
	draw_set_transform(Vector2(MARGIN, MARGIN))
	var s := cell_px()
	for c in state.seen:
		draw_rect(Rect2(Vector2(c) * s, Vector2(s, s)), VISITED if state.visited.has(c) else SEEN)
	var wall: Color = Palette.for_run(state.palette_id).wall
	for r in wall_lines():
		draw_rect(r, wall)
	var ring := stairs_mark()
	if not ring.is_empty():
		draw_rect(ring[0], Palette.INK)
		draw_rect(ring[1], Color.BLACK)
	for mark in monster_marks():
		draw_rect(mark.rect, mark.color)
	var me := (Vector2(state.cell) + Vector2(0.5, 0.5)) * s
	var d := Vector2(f.DIRS[state.facing])
	draw_colored_polygon([me + d * s * 0.6, me - d * s * 0.4 + d.orthogonal() * s * 0.4, me - d * s * 0.4 - d.orthogonal() * s * 0.4], YOU)
