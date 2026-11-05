## One floor: a square grid of walls and open cells, the stairs, the monsters standing on it, and what it hides.
## `grid[y][x]` is 1 for open, 0 for wall, 2 for a cracked wall (a wall until it is broken). Facing is an int 0..3 for north, east,
## south, west (DIRS).
extends RefCounted

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIR_NAMES := ["N", "E", "S", "W"]
const CRACKED := 2

var size := 0
var grid: Array = []
var stairs := Vector2i.ZERO
var start := Vector2i(1, 1)
var monsters: Array = [] # Monster; the champion (boss) is the last one, in the middle hall
var seed_value := 0
var biome := "" # its id in data/biomes.json, "" for a floor with none
var treasure: Array = [] # {cell: Vector2i, gold: int}, the chests still to find
var teleports: Array = [] # {a: Vector2i, b: Vector2i}, pairs of pads
var pickups: Array = [] # {cell: Vector2i, item: String}, things lying about
var merchant := {} # {cell: Vector2i, stock: [item id]}, or empty when no trader is here
var quester := {} # {cell, species, name, kind, target, want, taken} (rules/requests.gd), or empty when nobody here is asking
var steps := 0 # how many steps have been taken here, which the monsters' moves are worked out from (rules/roaming.gd)
var changes := 0 # how many walls have been broken, for whoever built something from the grid


func is_open(c: Vector2i) -> bool:
	if c.y < 0 or c.y >= grid.size():
		return false
	var row: Array = grid[c.y]
	return c.x >= 0 and c.x < row.size() and row[c.x] == 1


func is_cracked(c: Vector2i) -> bool:
	if c.y < 0 or c.y >= grid.size():
		return false
	var row: Array = grid[c.y]
	return c.x >= 0 and c.x < row.size() and row[c.x] == CRACKED


## A cracked wall gives way.
func break_wall(c: Vector2i) -> void:
	grid[c.y][c.x] = 1
	changes += 1


## The other end of the pad in this cell, or null.
func pad_partner(c: Vector2i):
	for t in teleports:
		if t.a == c:
			return t.b
		if t.b == c:
			return t.a
	return null


## The cells a monster may not stand in, as a set.
func reserved() -> Dictionary:
	var out := {}
	for t in teleports:
		out[t.a] = true
		out[t.b] = true
	for p in pickups:
		out[p.cell] = true
	if not merchant.is_empty():
		out[merchant.cell] = true
	if not quester.is_empty():
		out[quester.cell] = true
	return out


## Whether stepping into this cell would take you somewhere other than through it (a pad, a trader, someone asking), so a route goes round it.
func in_the_way(c: Vector2i) -> bool:
	return pad_partner(c) != null or merchant_at(c) or quester_at(c)


func quester_at(c: Vector2i) -> bool:
	return not quester.is_empty() and quester.cell == c


func merchant_at(c: Vector2i) -> bool:
	return not merchant.is_empty() and merchant.cell == c


## What lies in this cell, or "".
func pickup_at(c: Vector2i) -> String:
	for p in pickups:
		if p.cell == c:
			return p.item
	return ""


func remove_pickup(c: Vector2i) -> void:
	pickups = pickups.filter(func(p): return p.cell != c)


## Opens the chest in this cell if there is one: its gold, or 0.
func take_treasure(c: Vector2i) -> int:
	for i in treasure.size():
		if treasure[i].cell == c:
			return int(treasure.pop_at(i).gold)
	return 0


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
		"biome": biome,
		"treasure": treasure.map(func(t): return {"cell": [t.cell.x, t.cell.y], "gold": t.gold}),
		"teleports": teleports.map(func(t): return {"a": [t.a.x, t.a.y], "b": [t.b.x, t.b.y]}),
		"pickups": pickups.map(func(p): return {"cell": [p.cell.x, p.cell.y], "item": p.item}),
		"merchant": {} if merchant.is_empty() else {"cell": [merchant.cell.x, merchant.cell.y], "stock": merchant.stock.duplicate()},
		"quester": {} if quester.is_empty() else _quester_dict(),
		"steps": steps,
	}


func _quester_dict() -> Dictionary:
	var out := quester.duplicate()
	out.cell = [quester.cell.x, quester.cell.y]
	return out


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
	f.biome = str(d.get("biome", ""))
	f.treasure = d.get("treasure", []).map(func(t): return {"cell": _cell(t.cell), "gold": int(t.gold)})
	f.teleports = d.get("teleports", []).map(func(t): return {"a": _cell(t.a), "b": _cell(t.b)})
	f.pickups = d.get("pickups", []).map(func(p): return {"cell": _cell(p.cell), "item": str(p.item)})
	var trader: Dictionary = d.get("merchant", {})
	if not trader.is_empty():
		f.merchant = {"cell": _cell(trader.cell), "stock": trader.stock.map(func(id): return str(id))}
	f.steps = maxi(0, int(d.get("steps", 0)))
	var asking: Dictionary = d.get("quester", {})
	if not asking.is_empty():
		f.quester = asking.duplicate()
		f.quester.cell = _cell(asking.cell)
		f.quester.target = int(asking.get("target", -1))
		f.quester.want = str(asking.get("want", ""))
		f.quester.taken = bool(asking.get("taken", false))
	return f


static func _cell(v: Array) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1]))
