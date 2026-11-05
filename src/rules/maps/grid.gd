## What the map generators share: a blank grid, the champion's hall, and joining up floor that came out in separate pieces.
## `grid[y][x]` is 1 for open and 0 for wall (floor_map.gd).
extends RefCounted

const FloorMap = preload("res://src/rules/floor_map.gd")

const HALL_RADIUS := 2 # the hall is 5x5


static func blank(size: int) -> Array:
	var grid := []
	for _y in size:
		var row := []
		row.resize(size)
		row.fill(0)
		grid.append(row)
	return grid


static func middle(size: int) -> Vector2i:
	var mid := floori(size / 2.0)
	return Vector2i(mid, mid)


static func open_hall(grid: Array, hall: Vector2i) -> void:
	for y in range(hall.y - HALL_RADIUS, hall.y + HALL_RADIUS + 1):
		for x in range(hall.x - HALL_RADIUS, hall.x + HALL_RADIUS + 1):
			grid[y][x] = 1


static func in_hall(c: Vector2i, hall: Vector2i) -> bool:
	return absi(c.x - hall.x) <= HALL_RADIUS and absi(c.y - hall.y) <= HALL_RADIUS


static func is_open(grid: Array, c: Vector2i) -> bool:
	return c.y >= 0 and c.y < grid.size() and c.x >= 0 and c.x < grid[c.y].size() and grid[c.y][c.x] == 1


## The open floor joined to `from`, as a set of cells.
static func flood(grid: Array, from: Vector2i) -> Dictionary:
	var reached := {from: true}
	var queue: Array = [from]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for d in FloorMap.DIRS:
			var next: Vector2i = at + d
			if is_open(grid, next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	return reached


## The open cell nearest to `to`, searching the grid in a fixed order so the same grid gives the same answer.
static func nearest_open(grid: Array, to: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for y in grid.size():
		for x in grid[y].size():
			if grid[y][x] != 1:
				continue
			var d: int = (x - to.x) * (x - to.x) + (y - to.y) * (y - to.y)
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


## Joins every piece of open floor to the piece holding `from`, by a straight tunnel from the nearest pair of cells.
static func join_up(grid: Array, from: Vector2i) -> void:
	var main := flood(grid, from)
	for y in grid.size():
		for x in grid[y].size():
			var c := Vector2i(x, y)
			if grid[y][x] != 1 or main.has(c):
				continue
			var piece := flood(grid, c)
			var pair := _nearest_pair(piece, main)
			_tunnel(grid, pair[0], pair[1])
			main = flood(grid, from)


static func _nearest_pair(a: Dictionary, b: Dictionary) -> Array:
	var best := []
	var best_d := 1 << 30
	for p: Vector2i in a:
		for q: Vector2i in b:
			var d := absi(p.x - q.x) + absi(p.y - q.y)
			if d < best_d or (d == best_d and (p.y < best[0].y or (p.y == best[0].y and p.x < best[0].x))):
				best_d = d
				best = [p, q]
	return best


## Across, then along.
static func _tunnel(grid: Array, from: Vector2i, to: Vector2i) -> void:
	var at := from
	while at.x != to.x:
		at.x += signi(to.x - at.x)
		grid[at.y][at.x] = 1
	while at.y != to.y:
		at.y += signi(to.y - at.y)
		grid[at.y][at.x] = 1
