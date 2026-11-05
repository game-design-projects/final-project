## What the party can see from where it stands, for the automap: every cell the camera has in its field of view with a clear
## line over the floor, and always the cells straight ahead, as far as the corridor runs. This is worked out on the floor
## plan, so it is the same with no window. The 3D set shows every monster and lets the walls hide them; it only asks here
## whether a monster's name tag has a line to it.
extends RefCounted

const FloorMap = preload("res://src/rules/floor_map.gd")

const RANGE := 12 # the farthest a cell can be seen, along either axis: the classic floor fits inside it, so a big one costs no more
const STEP := 0.1 # how finely a line of sight is walked, in cells
const BACK := 0.38 # how far behind the middle of your cell the camera stands, in cells (stage.gd stands it there)
const CLOSE_BACK := 0.2 # the same with close-camera
const VIEW_TAN := 1.0493 # the camera's field of view: tan of half its width, for FOV 68 at 448:288 (tools/view_test.gd checks it)
static var back := BACK # where the camera stands now (the flow sets it, by close-camera)
static var view_tan := VIEW_TAN # and how wide it sees (the scene sets it, as wide as the picture is)

const SAMPLES := [Vector2(0, 0), Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(-0.4, 0.4), Vector2(0.4, 0.4)] # where in a cell a line may end, from its middle


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


## The cells the camera sees from `from`, your own among them: some sample point of the cell is inside its field of view, and
## a straight line from the middle of your cell reaches that point over open floor only.
static func sight(floor_map, from: Vector2i, facing: int) -> Array:
	var fwd := Vector2(FloorMap.DIRS[facing])
	var side := fwd.orthogonal()
	var mid := Vector2(from) + Vector2(0.5, 0.5)
	var eye := mid - fwd * back
	var out := [from]
	for y in range(maxi(0, from.y - RANGE), mini(floor_map.size, from.y + RANGE + 1)):
		for x in range(maxi(0, from.x - RANGE), mini(floor_map.size, from.x + RANGE + 1)):
			var c := Vector2i(x, y)
			if c == from or not floor_map.is_open(c):
				continue
			var centre := Vector2(c) + Vector2(0.5, 0.5)
			for o in SAMPLES:
				var p: Vector2 = centre + o
				var z := (p - eye).dot(fwd)
				if z > 0.0 and absf((p - eye).dot(side)) <= z * view_tan and clear_line(floor_map, mid, p):
					out.append(c)
					break
	return out


## Whether a straight line from a point of the floor plan (a cell spans x..x+1, y..y+1) reaches any sample point of `cell`.
static func reaches(floor_map, from: Vector2, cell: Vector2i) -> bool:
	var centre := Vector2(cell) + Vector2(0.5, 0.5)
	for o in SAMPLES:
		if clear_line(floor_map, from, centre + o):
			return true
	return false


## Whether open floor lies all the way between two points of the floor plan.
static func clear_line(floor_map, a: Vector2, b: Vector2) -> bool:
	var n := maxi(1, ceili(a.distance_to(b) / STEP))
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if not floor_map.is_open(Vector2i(floori(p.x), floori(p.y))):
			return false
	return true
