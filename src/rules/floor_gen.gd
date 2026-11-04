## Makes a floor: a maze carved by random walk, a few shortcuts, the champion's hall in the middle, the stairs at the far
## end, and the roster's monsters spread along the way from near to far. The same seed makes the same floor.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Monster = preload("res://src/rules/monster.gd")
const Rng = preload("res://src/utils/rng.gd")

const SIZE := 13 # odd, so the carved cells land on odd coordinates and walls on even ones
const HALL_RADIUS := 2 # the hall is 5x5
const SHORTCUT_TRIES := 12
const MIN_MONSTER_DISTANCE := 3 # steps from the start before the first monster may stand
const MONSTER_SPACING := 2 # no two monsters within this many cells of each other (Manhattan)


## `plan` (rules/floors.gd) says how deep the floor is and who guards it; without one it is the classic first floor.
static func generate(rng: Rng, plan := {}):
	var f := FloorMap.new()
	f.size = SIZE
	f.seed_value = rng.seed_value
	f.grid = _carve(rng)
	var mid := floori(SIZE / 2.0)
	var hall := Vector2i(mid, mid)
	_open_hall(f.grid, hall)
	var walk := _walk_from(f, f.start, hall)
	f.stairs = walk.farthest
	f.monsters = _place_monsters(rng, walk, hall, plan)
	print("floor: seed %d, stairs at %s, %d monsters" % [rng.seed_value, f.stairs, f.monsters.size()])
	return f


## Random-walk maze (depth-first), then a few walls knocked out between two open cells so it isn't a pure tree.
static func _carve(rng: Rng) -> Array:
	var grid := []
	for _y in SIZE:
		var row := []
		row.resize(SIZE)
		row.fill(0)
		grid.append(row)
	var stack: Array = [Vector2i(1, 1)]
	grid[1][1] = 1
	while not stack.is_empty():
		var at: Vector2i = stack[-1]
		var options := []
		for d in FloorMap.DIRS:
			var far: Vector2i = at + d * 2
			if far.x > 0 and far.y > 0 and far.x < SIZE - 1 and far.y < SIZE - 1 and grid[far.y][far.x] == 0:
				options.append([at + d, far])
		if options.is_empty():
			stack.pop_back()
			continue
		var pick: Array = rng.pick(options)
		grid[pick[0].y][pick[0].x] = 1
		grid[pick[1].y][pick[1].x] = 1
		stack.append(pick[1])
	for _i in SHORTCUT_TRIES:
		var c := Vector2i(rng.int_range(1, SIZE - 2), rng.int_range(1, SIZE - 2))
		if grid[c.y][c.x] == 1:
			continue
		var across_x: bool = grid[c.y][c.x - 1] == 1 and grid[c.y][c.x + 1] == 1
		var across_y: bool = grid[c.y - 1][c.x] == 1 and grid[c.y + 1][c.x] == 1
		if across_x or across_y:
			grid[c.y][c.x] = 1
	return grid


static func _open_hall(grid: Array, hall: Vector2i) -> void:
	for y in range(hall.y - HALL_RADIUS, hall.y + HALL_RADIUS + 1):
		for x in range(hall.x - HALL_RADIUS, hall.x + HALL_RADIUS + 1):
			grid[y][x] = 1


static func _in_hall(c: Vector2i, hall: Vector2i) -> bool:
	return absi(c.x - hall.x) <= HALL_RADIUS and absi(c.y - hall.y) <= HALL_RADIUS


## Breadth-first from `from`: `order` is the cells in discovery order, `dist` the steps to each, `farthest` the
## farthest cell outside the hall (where the stairs go).
static func _walk_from(f, from: Vector2i, hall: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var order: Array = [from]
	var farthest := from
	var head := 0
	while head < order.size():
		var cur: Vector2i = order[head]
		head += 1
		for d in FloorMap.DIRS:
			var next: Vector2i = cur + d
			if f.is_open(next) and not dist.has(next):
				dist[next] = dist[cur] + 1
				order.append(next)
				if not _in_hall(next, hall) and dist[next] > dist[farthest]:
					farthest = next
	return {"dist": dist, "order": order, "farthest": farthest}


## Roster monsters spread out nearest first, evenly through the candidate cells; the champion stands in the hall.
static func _place_monsters(rng: Rng, walk: Dictionary, hall: Vector2i, plan: Dictionary) -> Array:
	var enc := Content.table("encounter")
	var candidates := []
	for i in walk.order.size():
		var c: Vector2i = walk.order[i]
		var d: int = walk.dist[c]
		if d >= MIN_MONSTER_DISTANCE and not _in_hall(c, hall) and c != walk.farthest:
			candidates.append({"cell": c, "dist": d, "order": i})
	candidates.sort_custom(func(a, b): return a.dist < b.dist or (a.dist == b.dist and a.order < b.order))
	var monsters := []
	var used: Array = []
	var roster: Array = _roster_for(enc.roster, plan)
	for i in roster.size():
		var target := floori(float(i + 1) / (roster.size() + 1) * candidates.size())
		var spot: Vector2i = candidates[target % candidates.size()].cell
		for j in candidates.size():
			var c: Vector2i = candidates[(target + j) % candidates.size()].cell
			if used.all(func(u): return absi(u.x - c.x) + absi(u.y - c.y) > MONSTER_SPACING):
				spot = c
				break
		used.append(spot)
		monsters.append(Monster.make(rng, _at_depth(roster[i], plan), spot))
	var boss: Dictionary = enc.boss
	var champion: Dictionary = plan.get("champion", boss)
	var post: Vector2i = walk.farthest if plan.get("boss_at_exit", false) else hall
	monsters.append(Monster.make(rng, {"species": boss.species, "genre": boss.genres[0], "hp": champion.hp, "name": champion.name, "boss": true}, post))
	return monsters


## Who lives on this floor: the whole roster, or what the way down left of it.
static func _roster_for(roster: Array, plan: Dictionary) -> Array:
	var out := roster
	if str(plan.get("only_species", "")) != "":
		var kind: Array = roster.filter(func(e): return e.species == plan.only_species)
		out = roster.map(func(_e): return kind[0])
	if int(plan.get("count", -1)) > 0:
		out = out.slice(0, int(plan.count))
	return out


## A roster line with the floor's toughness.
static func _at_depth(entry: Dictionary, plan: Dictionary) -> Dictionary:
	var out := entry.duplicate()
	out.hp = roundi(float(entry.hp) * float(plan.get("hp_scale", 1.0)))
	return out
