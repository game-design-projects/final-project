## A generator with no plan: rock and air at random, smoothed a few times by each cell taking after its neighbours, which leaves
## wide irregular caves. Only the cave joined to the champion's hall is kept, and you start at the end of it nearest the corner.
extends RefCounted

const Grid = preload("res://src/rules/maps/grid.gd")

const CROWD := 5 # a cell with this many walls in its 3x3 is wall


## {grid, start, hall}. `params`: {fill, passes}: how much starts as rock, and how many times it is smoothed.
static func carve(rng, size: int, params: Dictionary) -> Dictionary:
	var fill := float(params.get("fill", 0.43))
	var grid := Grid.blank(size)
	for y in range(1, size - 1):
		for x in range(1, size - 1):
			grid[y][x] = 0 if rng.chance(fill) else 1
	for _i in int(params.get("passes", 4)):
		grid = _smoothed(grid)
	var hall := Grid.middle(size)
	Grid.open_hall(grid, hall)
	var kept := Grid.flood(grid, hall)
	for y in size:
		for x in size:
			if grid[y][x] == 1 and not kept.has(Vector2i(x, y)):
				grid[y][x] = 0
	return {"grid": grid, "start": Grid.nearest_open(grid, Vector2i(1, 1)), "hall": hall}


static func _smoothed(grid: Array) -> Array:
	var size := grid.size()
	var out := Grid.blank(size)
	for y in range(1, size - 1):
		for x in range(1, size - 1):
			var walls := 0
			for ny in range(y - 1, y + 2):
				for nx in range(x - 1, x + 2):
					if grid[ny][nx] == 0:
						walls += 1
			out[y][x] = 0 if walls >= CROWD else 1
	return out
