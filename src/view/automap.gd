## The automap: a small panel in the picture's top right corner, drawn outside the post-processing so it stays crisp. Floor
## you have seen is dark, floor you stood on lighter, walls are lines on the edges of seen floor (in the view walls are faces
## with no thickness, and a block would look like unexplored dark). The stairs are a ring; monsters you have seen are dots;
## the champion is marked in red from the start, so you can choose to hunt it. The wall with writing on it is a gold edge, grey once read.
## A big floor shows through a window that follows you. Floor you haven't seen but know from a map or your instinct (rules/chart.gd)
## is a dark blue with dim walls: the layout and the stairs, and nothing of who or what is there.
## The same node drawn `full` is the whole floor over the picture (M, or a click on the corner map): it fills its parent, dims the
## picture behind it, fits every cell of the floor, and says which floor it is and how much of it you have seen.
## It only reads the game's state.
extends Control

const Chart = preload("res://src/rules/chart.gd")
const Content = preload("res://src/rules/content.gd")
const Floors = preload("res://src/rules/floors.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")

const PANEL := 115.0 # the whole panel, border and margin included
const MARGIN := 5.0 # border and margin round the map
const MAP_PX := 105
const LAST_SEEN_DARK := 0.45 # a monster out of sight is darker, because it may not be there now
const LORE_EDGE := 2.0 # how deep the writing's edge is
const MIN_CELL_PX := 7 # a smaller cell has no room for a dot in it; a floor that would need one scrolls instead
const SEEN := Color("#262626")
const VISITED := Color("#5a5a5a")
const CHARTED := Color("#15202e") # floor known from a map, not from your eyes
const CHARTED_WALL_DARK := 0.5 # and its walls, darker than the ones you saw
const YOU := Color.WHITE
const FULL_MIN_CELL_PX := 4 # the full map's smallest cell: under it the dots and the stairs' ring run together, so it scrolls instead
const FULL_MAX_CELL_PX := 14 # and its largest: a small floor stays a map, not a board
const FULL_PAD := 12.0 # the least room left round the full map
const FULL_TEXT := 22.0 # the room above and below it, for its two lines
const FULL_DIM := 0.72 # how dark the picture goes behind it
const FULL_FONT_PX := 8
const FULL_TEXT_GAP := 16.0 # the least room between the floor's name and how much of it is seen, on the one line they share

var state # State, set by the owner
var full := false # the whole floor over the picture, instead of the corner's window
var _drawn_key := []


func _ready() -> void:
	if not full:
		custom_minimum_size = Vector2(PANEL, PANEL)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The side of the square the map may fill, in pixels: the corner panel's, or what the picture leaves the full map.
func map_px() -> int:
	if not full:
		return MAP_PX
	return maxi(MAP_PX, floori(minf(size.x - FULL_PAD * 2.0, size.y - FULL_TEXT * 2.0) - MARGIN * 2.0))


## The width of a cell on the map, in pixels.
func cell_px() -> int:
	var fit := floori(float(map_px()) / state.floor_map.size)
	if full:
		return clampi(fit, FULL_MIN_CELL_PX, FULL_MAX_CELL_PX)
	return maxi(MIN_CELL_PX, fit)


## How many cells the window shows across.
func window_cells() -> int:
	return mini(state.floor_map.size, floori(float(map_px()) / cell_px()))


## The panel the map is drawn in (this node's pixels): the whole corner node, or a square in the middle of the picture.
func panel_rect() -> Rect2:
	if not full:
		return Rect2(Vector2.ZERO, size)
	var side := window_cells() * cell_px() + MARGIN * 2.0
	return Rect2(((size - Vector2(side, side)) / 2.0).floor(), Vector2(side, side))


## The full map's two lines: which floor this is and how much of it is seen, and the keys.
func full_lines() -> Dictionary:
	var f = state.floor_map
	var where := "PRACTICE" if state.practice else (str(Content.table("floors").test_room.header) if state.testing else "B%dF" % state.depth)
	if state.visiting != "": # a clan's hall is no floor of the count
		where = str(Content.table("envoys").clans[state.visiting].hall.name)
	var biome := str(Floors.biome_named(f.biome).get("name", "")) if f.biome != "" else ""
	if biome != "":
		where += " · " + biome
	var seen := "%d%% SEEN" % floori(Chart.share(state) * 100.0)
	if not state.charted.is_empty():
		seen += " · CHARTED"
	return {"where": where, "seen": seen, "keys": "M CLOSE · ARROWS WALK"}


## Where the full map's lines are written: x is the left end and y the width, in this node's pixels. The panel's own width on a
## big floor. A small floor's panel (the practice floor, B1F) is narrower than the words, so there the span is as wide as they
## need, centred on the panel and kept inside the picture: the name and the share on the top line don't meet, and the keys aren't cut.
func lines_span(lines: Dictionary) -> Vector2:
	var font: Font = Fonts.title()
	var panel := panel_rect()
	var top := font.get_string_size(lines.where, HORIZONTAL_ALIGNMENT_LEFT, -1, FULL_FONT_PX).x + FULL_TEXT_GAP + font.get_string_size(lines.seen, HORIZONTAL_ALIGNMENT_LEFT, -1, FULL_FONT_PX).x
	var keys := font.get_string_size(lines.keys, HORIZONTAL_ALIGNMENT_LEFT, -1, FULL_FONT_PX).x
	var width := minf(size.x, ceilf(maxf(panel.size.x, maxf(top, keys))))
	return Vector2(clampf(floorf(panel.get_center().x - width / 2.0), 0.0, size.x - width), width)


## The floor cell at the window's top left corner: you in the middle of it, as far as the floor goes.
func window_origin() -> Vector2i:
	var cells := window_cells()
	var most: int = state.floor_map.size - cells
	return Vector2i(clampi(state.cell.x - cells / 2, 0, most), clampi(state.cell.y - cells / 2, 0, most))


func _in_window(c: Vector2i) -> bool:
	var o := window_origin()
	var cells := window_cells()
	return c.x >= o.x and c.y >= o.y and c.x < o.x + cells and c.y < o.y + cells


## The cells you have seen that are in the window.
func _shown() -> Array:
	return _in_window_of(state.seen)


## The cells in the window you know only from a map (rules/chart.gd).
func charted_shown() -> Array:
	if state.charted.is_empty():
		return []
	return _in_window_of(state.charted).filter(func(c): return not state.seen.has(c))


func _in_window_of(cells_known: Dictionary) -> Array:
	var o := window_origin()
	var cells := window_cells()
	var out := []
	for y in range(o.y, o.y + cells):
		for x in range(o.x, o.x + cells):
			var c := Vector2i(x, y)
			if cells_known.has(c):
				out.append(c)
	return out


## The dots of the monsters: [{"rect": Rect2 (map pixels), "color": Color}]. A seen monster is a dot inside its cell; the
## champion fills its cell, seen or not.
func monster_marks() -> Array:
	var s := cell_px()
	var out := []
	var roaming: bool = state.viewing("roaming")
	for m in state.floor_map.monsters:
		var at: Vector2i = m.cell
		if roaming and (not m.boss or m.hunting):
			at = m.last_seen # a monster on the move shows where you last saw it, never through a wall
		if m.is_gone() or at.x < 0 or not _in_window(at):
			continue
		if m.boss and not state.seen.has(m.cell):
			continue
		if m.boss:
			out.append({"rect": Rect2(Vector2(at) * s, Vector2(s, s)), "color": Palette.BOSS})
		elif roaming or state.seen.has(at):
			var dot := maxf(2.0, s - 4.0)
			var look: Color = Palette.STIR if m.lurking else Palette.monster(m)
			if roaming and not state.in_sight.has(m.cell):
				look = look.darkened(LAST_SEEN_DARK)
			out.append({"rect": Rect2(Vector2(at) * s + Vector2.ONE * (s - dot) / 2.0, Vector2(dot, dot)), "color": look})
	return out


## The lines where seen floor meets a wall, as Rect2s 1 pixel thick (map pixels). With `cells`, the lines round those instead.
func wall_lines(cells = null) -> Array:
	var f = state.floor_map
	var s := cell_px()
	var out := []
	for c in _shown() if cells == null else cells:
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


## The stairs' ring (outer and inner squares, map pixels) once they are seen or charted, or an empty list.
func stairs_mark() -> Array:
	var f = state.floor_map
	if not Chart.known(state, f.stairs) or not _in_window(f.stairs):
		return []
	var s := cell_px()
	var at := Vector2(f.stairs) * s
	return [Rect2(at + Vector2(1, 1), Vector2(s - 2, s - 2)), Rect2(at + Vector2(2, 2), Vector2(s - 4, s - 4))]


## What you have found of the floor's secrets: [{"rect": Rect2 (map pixels), "color": Color}]. A pad is a square of your colour, a
## chest one of gold, in the middle of the cell.
func secret_marks() -> Array:
	var f = state.floor_map
	var s := cell_px()
	var out := []
	for t in f.teleports:
		for end in [t.a, t.b]:
			if state.seen.has(end) and _in_window(end):
				out.append({"rect": Rect2(Vector2(end) * s + Vector2.ONE * 1.0, Vector2.ONE * (s - 2.0)), "color": Palette.YOU})
	for t in f.treasure:
		if state.seen.has(t.cell) and _in_window(t.cell):
			out.append({"rect": Rect2(Vector2(t.cell) * s + Vector2.ONE * 2.0, Vector2.ONE * (s - 4.0)), "color": Palette.MERCY})
	for p in f.pickups:
		if state.seen.has(p.cell) and _in_window(p.cell):
			out.append({"rect": Rect2(Vector2(p.cell) * s + Vector2.ONE * 2.0, Vector2.ONE * (s - 4.0)), "color": Palette.MERCY})
	if not f.merchant.is_empty() and state.seen.has(f.merchant.cell) and _in_window(f.merchant.cell):
		out.append({"rect": Rect2(Vector2(f.merchant.cell) * s + Vector2.ONE, Vector2.ONE * (s - 2.0)), "color": Palette.INK})
	if not f.quester.is_empty() and state.seen.has(f.quester.cell) and _in_window(f.quester.cell):
		out.append({"rect": Rect2(Vector2(f.quester.cell) * s + Vector2.ONE, Vector2.ONE * (s - 2.0)), "color": Palette.YOU})
	for e in f.envoys: # a clan's asker, or in its hall the lord
		if state.seen.has(e.cell) and _in_window(e.cell):
			out.append({"rect": Rect2(Vector2(e.cell) * s + Vector2.ONE, Vector2.ONE * (s - 2.0)), "color": Palette.MERCY if e.get("lord", false) else Palette.YOU})
	if not f.lore.is_empty() and state.seen.has(f.lore.cell) and _in_window(f.lore.cell):
		out.append({"rect": _edge(f.lore.cell, f.lore.side, LORE_EDGE), "color": Palette.DIM if f.lore.read else Palette.MERCY})
	return out


## A strip `thick` pixels deep along one side of a cell, inside it (map pixels).
func _edge(c: Vector2i, side: int, thick: float) -> Rect2:
	var s := float(cell_px())
	var at := Vector2(c) * s
	match side:
		0: return Rect2(at, Vector2(s, thick))
		1: return Rect2(at + Vector2(s - thick, 0), Vector2(thick, s))
		2: return Rect2(at + Vector2(0, s - thick), Vector2(s, thick))
		_: return Rect2(at, Vector2(thick, s))


func _process(_dt: float) -> void:
	if state == null or state.floor_map == null:
		return
	if full and not is_visible_in_tree():
		return
	var key := [state, state.cell, state.facing, state.seen.size(), state.visited.size(), state.floor_map.monsters_left(), state.floor_map.treasure.size(), state.floor_map.pickups.size(), state.floor_map.changes, state.floor_map.quester.size(), state.floor_map.steps, state.floor_map.lore.get("read", false), state.charted.size(), size]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func _draw() -> void:
	if state == null or state.floor_map == null:
		return
	var f = state.floor_map
	var panel := panel_rect()
	if full:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, FULL_DIM))
		var lines := full_lines()
		var span := lines_span(lines)
		var font: Font = Fonts.title()
		draw_string(font, Vector2(span.x, panel.position.y - 6.0), lines.where, HORIZONTAL_ALIGNMENT_LEFT, -1, FULL_FONT_PX, Palette.INK)
		draw_string(font, Vector2(span.x, panel.position.y - 6.0), lines.seen, HORIZONTAL_ALIGNMENT_RIGHT, span.y, FULL_FONT_PX, Palette.DIM)
		draw_string(font, Vector2(span.x, panel.end.y + 6.0 + FULL_FONT_PX), lines.keys, HORIZONTAL_ALIGNMENT_CENTER, span.y, FULL_FONT_PX, Palette.DIM)
		print_verbose("automap: the full map drawn in %s, %d cells across at %d px, %s, its lines %d px wide from %d" % [size, window_cells(), cell_px(), lines.seen, span.y, span.x])
	draw_rect(panel, Color.BLACK)
	draw_rect(panel.grow(-0.5), Palette.FAINT, false, 1.0)
	var s := cell_px()
	draw_set_transform(panel.position + Vector2(MARGIN, MARGIN) - Vector2(window_origin()) * s)
	var wall: Color = Palette.for_run(state.palette_id).wall
	var charted := charted_shown()
	for c in charted:
		draw_rect(Rect2(Vector2(c) * s, Vector2(s, s)), CHARTED)
	for r in wall_lines(charted):
		draw_rect(r, wall.darkened(CHARTED_WALL_DARK))
	var seen_cells := _shown() # asked once: the full map's window is the whole floor
	for c in seen_cells:
		draw_rect(Rect2(Vector2(c) * s, Vector2(s, s)), VISITED if state.visited.has(c) else SEEN)
	for r in wall_lines(seen_cells):
		draw_rect(r, wall)
	var ring := stairs_mark()
	if not ring.is_empty():
		draw_rect(ring[0], Palette.INK)
		draw_rect(ring[1], Color.BLACK)
	for mark in secret_marks():
		draw_rect(mark.rect, mark.color)
	for mark in monster_marks():
		draw_rect(mark.rect, mark.color)
	var me := (Vector2(state.cell) + Vector2(0.5, 0.5)) * s
	var d := Vector2(f.DIRS[state.facing])
	draw_colored_polygon([me + d * s * 0.6, me - d * s * 0.4 + d.orthogonal() * s * 0.4, me - d * s * 0.4 - d.orthogonal() * s * 0.4], YOU)
