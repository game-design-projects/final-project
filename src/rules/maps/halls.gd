## The first generator: a maze carved by random walk, a few shortcuts knocked through so it isn't a pure tree, a few small rooms
## if asked for, and the champion's hall in the middle. The classic floor is this at 13x13, drawing the numbers it always drew.
extends RefCounted

const FloorMap = preload("res://src/rules/floor_map.gd")
const Grid = preload("res://src/rules/maps/grid.gd")

const FLOOR_AREA := 169.0 # 13x13: the shortcuts asked for are for a floor this big, and more on a bigger one


## {grid, start, hall}. `params`: {shortcuts, rooms}. `size` is odd, so the carved cells land on odd coordinates and walls on even.
static func carve(rng, size: int, params: Dictionary) -> Dictionary:
	var grid := Grid.blank(size)
	var stack: Array = [Vector2i(1, 1)]
	grid[1][1] = 1
	while not stack.is_empty():
		var at: Vector2i = stack[-1]
		var options := []
		for d in FloorMap.DIRS:
			var far: Vector2i = at + d * 2
			if far.x > 0 and far.y > 0 and far.x < size - 1 and far.y < size - 1 and grid[far.y][far.x] == 0:
				options.append([at + d, far])
		if options.is_empty():
			stack.pop_back()
			continue
		var pick: Array = rng.pick(options)
		grid[pick[0].y][pick[0].x] = 1
		grid[pick[1].y][pick[1].x] = 1
		stack.append(pick[1])
	for _i in roundi(float(params.get("shortcuts", 0)) * size * size / FLOOR_AREA):
		var c := Vector2i(rng.int_range(1, size - 2), rng.int_range(1, size - 2))
		if grid[c.y][c.x] == 1:
			continue
		var across_x: bool = grid[c.y][c.x - 1] == 1 and grid[c.y][c.x + 1] == 1
		var across_y: bool = grid[c.y - 1][c.x] == 1 and grid[c.y + 1][c.x] == 1
		if across_x or across_y:
			grid[c.y][c.x] = 1
	for _i in int(params.get("rooms", 0)):
		_room(grid, Vector2i(rng.int_range(1, (size - 3) / 2) * 2, rng.int_range(1, (size - 3) / 2) * 2))
	var hall := Grid.middle(size)
	Grid.open_hall(grid, hall)
	return {"grid": grid, "start": Vector2i(1, 1), "hall": hall}


## A 3x3 room round an even corner of the maze, which the cells at its corners already reach.
static func _room(grid: Array, mid: Vector2i) -> void:
	for y in range(mid.y - 1, mid.y + 2):
		for x in range(mid.x - 1, mid.x + 2):
			grid[y][x] = 1
