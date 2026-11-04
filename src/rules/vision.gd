## What the party can see from where it stands. The automap learns the cells straight ahead, as far as the corridor runs
## (the side openings show as gaps in the walls, not as cells you can see into). A monster is in view when it is in front
## of you and nothing stands between: down the corridor, but also across a hall, off to one side. This is what the 3D set
## draws (its walls go as far as the camera does), so a monster in the picture is never left out of it.
extends RefCounted

const FloorMap = preload("res://src/rules/floor_map.gd")

const STEP := 0.1 # how finely a line of sight is walked, in cells


## The cells straight ahead, nearest first, starting with your own, until a wall.
static func ahead(floor_map, from: Vector2i, facing: int) -> Array:
	var out := [from]
	var c: Vector2i = from
	while true:
		c += FloorMap.DIRS[facing]
		if not floor_map.is_open(c):
			break
		out.append(c)
	return out


## Whether `target` is in front of you (not beside or behind) with open ground all the way between the two cell centres.
static func sees(floor_map, from: Vector2i, facing: int, target: Vector2i) -> bool:
	var d := target - from
	if d == Vector2i.ZERO or d.x * FloorMap.DIRS[facing].x + d.y * FloorMap.DIRS[facing].y <= 0:
		return false
	var a := Vector2(from) + Vector2(0.5, 0.5)
	var b := Vector2(target) + Vector2(0.5, 0.5)
	var n := ceili(a.distance_to(b) / STEP)
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if not floor_map.is_open(Vector2i(floori(p.x), floori(p.y))):
			return false
	return true


## The monsters still around that you can see from here, nearest first.
static func monsters(floor_map, from: Vector2i, facing: int) -> Array:
	var out := []
	for m in floor_map.monsters:
		if not m.is_gone() and sees(floor_map, from, facing, m.cell):
			out.append(m)
	out.sort_custom(func(x, y): return (x.cell - from).length_squared() < (y.cell - from).length_squared())
	return out
