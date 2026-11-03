## One floor: a square grid of walls and open cells, the stairs, and the monsters standing on it.
## `grid[y][x]` is 1 for open and 0 for wall. Facing is an int 0..3 for north, east, south, west (DIRS).
extends RefCounted

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIR_NAMES := ["N", "E", "S", "W"]

var size := 0
var grid: Array = []
var stairs := Vector2i.ZERO
var start := Vector2i(1, 1)
var monsters: Array = [] # Monster; the champion (boss) is the last one, in the middle hall
var seed_value := 0


func is_open(c: Vector2i) -> bool:
	if c.y < 0 or c.y >= grid.size():
		return false
	var row: Array = grid[c.y]
	return c.x >= 0 and c.x < row.size() and row[c.x] == 1


## The monster standing in this cell that is still around, or null.
func monster_at(c: Vector2i):
	for m in monsters:
		if m.cell == c and not m.is_gone():
			return m
	return null


func monsters_left() -> int:
	var n := 0
	for m in monsters:
		if not m.is_gone():
			n += 1
	return n


## Which way to face at the start: toward the first open neighbour.
func start_facing() -> int:
	for i in 4:
		if is_open(start + DIRS[i]):
			return i
	return 0


func to_dict() -> Dictionary:
	return {
		"size": size, "grid": grid, "stairs": [stairs.x, stairs.y], "start": [start.x, start.y], "seed": seed_value,
		"monsters": monsters.map(func(m): return m.to_dict()),
	}


static func from_dict(d: Dictionary, monster_script):
	var f = new()
	f.size = int(d.get("size", 0))
	f.grid = d.get("grid", []).map(func(row): return row.map(func(v): return int(v)))
	var s: Array = d.get("stairs", [0, 0])
	f.stairs = Vector2i(int(s[0]), int(s[1]))
	var st: Array = d.get("start", [1, 1])
	f.start = Vector2i(int(st[0]), int(st[1]))
	f.seed_value = int(d.get("seed", 0))
	f.monsters = d.get("monsters", []).map(func(md): return monster_script.from_dict(md))
	return f
