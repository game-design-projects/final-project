## What the party can see from where it stands: the cell it is in and the corridor straight ahead, up to a few cells,
## until a wall. (The side openings show as gaps in the walls, not as cells you can see into.) Used for the automap and
## for which monsters are in view.
extends RefCounted

const FloorMap = preload("res://src/rules/floor_map.gd")

const DEPTH := 6 # how many cells ahead you see


## The cells in view, nearest first, starting with your own.
static func ahead(floor_map, from: Vector2i, facing: int) -> Array:
	var out := [from]
	var c: Vector2i = from
	for _i in DEPTH:
		c += FloorMap.DIRS[facing]
		if not floor_map.is_open(c):
			break
		out.append(c)
	return out
