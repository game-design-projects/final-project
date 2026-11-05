## A generator of authored pieces: a small maze plans the floor, one slot per chunk, and each slot takes a chunk from
## data/chunks.json whose openings fit. A chunk is 7x7 and shares its border with the next, so a floor of n chunks across is
## 6n + 1 cells. A chunk opens only at the middle of a side, so any two fit that agree on the side between them.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Grid = preload("res://src/rules/maps/grid.gd")

const SPAN := 6 # a chunk's share of the floor: it is 7 across, and its last row is the next one's first
const MID := 3
const SIDES := [1, 2, 4, 8] # the mask's bit for north, east, south, west (FloorMap.DIRS)

static var _library = null # every chunk in every turn: [{id, rows, mask}]


## {grid, start, hall}. `params`: {loops}, the chance a slot's wall to its neighbour is opened as well as the plan's own, and {long},
## the chance the floor is long or tall instead of square: some rows or columns of slots stay rock. The grid stays square, so
## nothing else has to know.
static func carve(rng, size: int, params: Dictionary) -> Dictionary:
	var slots := maxi(1, (size - 1) / SPAN)
	var cells := slots * SPAN + 1
	var shape := _shape(rng, slots, float(params.get("long", 0.0)))
	var plan := _plan(rng, shape, float(params.get("loops", 0.0)))
	var grid := Grid.blank(cells)
	var by_mask := _by_mask()
	for sy in shape.y:
		for sx in shape.x:
			var options: Array = by_mask[plan[sy][sx]]
			_stamp(grid, rng.pick(options).rows, Vector2i(sx, sy) * SPAN)
	var hall := (shape * SPAN + Vector2i.ONE) / 2 if shape != Vector2i(slots, slots) else Grid.middle(cells)
	Grid.open_hall(grid, hall)
	var start := Grid.nearest_open(grid, Vector2i(1, 1))
	Grid.join_up(grid, start)
	return {"grid": grid, "start": start, "hall": hall}


## Every chunk in all its turns.
static func library() -> Array:
	if _library == null:
		_library = []
		for c in Content.table("chunks").chunks:
			var rows: Array = c.rows
			var seen := {}
			for turn in 4:
				var key := "".join(rows)
				if not seen.has(key):
					seen[key] = true
					_library.append({"id": "%s/%d" % [c.id, turn], "rows": rows, "mask": _mask(rows)})
				rows = _turned(rows)
	return _library


## What is wrong with a chunk, or "".
static func problem(chunk: Dictionary) -> String:
	var rows: Array = chunk.rows
	if rows.size() != SPAN + 1 or rows.any(func(r): return r.length() != SPAN + 1):
		return "not 7x7"
	var open := []
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] != ".":
				continue
			open.append(Vector2i(x, y))
			var on_edge: bool = x == 0 or y == 0 or x == SPAN or y == SPAN
			if on_edge and x != MID and y != MID:
				return "open at the edge away from the middle"
	if open.is_empty():
		return "no floor"
	var grid := Grid.blank(SPAN + 1)
	_stamp(grid, rows, Vector2i.ZERO)
	if Grid.flood(grid, open[0]).size() != open.size():
		return "in more than one piece"
	return ""


static func _by_mask() -> Dictionary:
	var out := {}
	for c in library():
		if not out.has(c.mask):
			out[c.mask] = []
		out[c.mask].append(c)
	return out


static func _mask(rows: Array) -> int:
	var mask := 0
	if rows[0][MID] == ".":
		mask |= SIDES[0]
	if rows[MID][SPAN] == ".":
		mask |= SIDES[1]
	if rows[SPAN][MID] == ".":
		mask |= SIDES[2]
	if rows[MID][0] == ".":
		mask |= SIDES[3]
	return mask


## A quarter turn clockwise.
static func _turned(rows: Array) -> Array:
	var out := []
	for y in rows.size():
		var row := ""
		for x in rows.size():
			row += rows[rows.size() - 1 - x][y]
		out.append(row)
	return out


## Only opens floor, so the border two chunks share is open if either says so.
static func _stamp(grid: Array, rows: Array, at: Vector2i) -> void:
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == ".":
				grid[at.y + y][at.x + x] = 1


## How many slots across and down: all of them, or, by the chance `long`, down to half of them one way.
static func _shape(rng, slots: int, long: float) -> Vector2i:
	if slots < 2 or not rng.chance(long):
		return Vector2i(slots, slots)
	var short: int = rng.int_range(ceili(slots / 2.0), slots - 1)
	return Vector2i(slots, short) if rng.chance(0.5) else Vector2i(short, slots)


## The maze of slots, as each slot's mask of open sides: a random walk from the first slot, and some walls opened besides.
static func _plan(rng, shape: Vector2i, loops: float) -> Array:
	var masks := Grid.blank(maxi(shape.x, shape.y))
	var seen := {Vector2i.ZERO: true}
	var stack: Array = [Vector2i.ZERO]
	while not stack.is_empty():
		var at: Vector2i = stack[-1]
		var options := []
		for side in 4:
			var next: Vector2i = at + FloorMap.DIRS[side]
			if next.x >= 0 and next.y >= 0 and next.x < shape.x and next.y < shape.y and not seen.has(next):
				options.append(side)
		if options.is_empty():
			stack.pop_back()
			continue
		var side: int = rng.pick(options)
		var next: Vector2i = at + FloorMap.DIRS[side]
		_link(masks, at, side)
		seen[next] = true
		stack.append(next)
	for y in shape.y:
		for x in shape.x:
			for side in [1, 2]: # east and south, so each wall is rolled once
				var next: Vector2i = Vector2i(x, y) + FloorMap.DIRS[side]
				if next.x < shape.x and next.y < shape.y and rng.chance(loops):
					_link(masks, Vector2i(x, y), side)
	return masks


static func _link(masks: Array, at: Vector2i, side: int) -> void:
	var next: Vector2i = at + FloorMap.DIRS[side]
	masks[at.y][at.x] |= SIDES[side]
	masks[next.y][next.x] |= SIDES[(side + 2) % 4]
