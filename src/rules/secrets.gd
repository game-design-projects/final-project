## What a floor hides, in passes over its finished layout: a chest behind a cracked wall, which breaks when you walk into it, and
## pairs of pads that carry you between a place near the start and a place far from it. A pad takes you away the moment you
## step on it, so one never stands where it would cut the floor in two. Everything is drawn from the floor's generator.
extends RefCounted

const FloorMap = preload("res://src/rules/floor_map.gd")
const Grid = preload("res://src/rules/maps/grid.gd")

const PAD_NEAR := [[0.1, 0.35], [0.03, 0.5]] # where the pads go, as shares of the walk from the start to the far end of the floor, and where if not there
const PAD_FAR := [[0.6, 0.9], [0.5, 0.98]]
const SAFE_TRIES := 40
const MIN_FROM_START := 3


## Closes off chests. `walk` is FloorGen's walk of the floor as it was.
static func hide_chests(rng, f, walk: Dictionary, hall: Vector2i, params: Dictionary) -> void:
	var gold: Array = params.get("gold", [5, 9])
	for _i in int(params.get("cracks", 0)):
		var spots := _dead_ends(f, walk, hall)
		if spots.is_empty():
			spots = _closets(f, walk, hall)
		if spots.is_empty():
			spots = _side_rooms(f, walk, hall)
		if spots.is_empty():
			print_verbose("secrets: no room for a chest")
			return
		var spot: Dictionary = rng.pick(spots)
		f.grid[spot.door.y][spot.door.x] = FloorMap.CRACKED
		f.grid[spot.room.y][spot.room.x] = 1
		f.treasure.append({"cell": spot.room, "gold": rng.int_range(int(gold[0]), int(gold[1]))})


## A corridor's dead end, whose last step becomes the wall: nobody would know the corridor went on.
static func _dead_ends(f, walk: Dictionary, hall: Vector2i) -> Array:
	var out := []
	for y in f.size:
		for x in f.size:
			var room := Vector2i(x, y)
			if not _quiet(f, walk, room, hall) or _open_sides(f, room).size() != 1:
				continue
			var door: Vector2i = _open_sides(f, room)[0]
			if not _quiet(f, walk, door, hall) or _open_sides(f, door).size() != 2:
				continue
			out.append({"door": door, "room": room})
	return out


## A floor with no such corridors: a dead end off a junction, where the junction's other ways don't need the cell walled up.
static func _side_rooms(f, walk: Dictionary, hall: Vector2i) -> Array:
	var out := []
	for y in f.size:
		for x in f.size:
			var room := Vector2i(x, y)
			if not _quiet(f, walk, room, hall) or _open_sides(f, room).size() != 1:
				continue
			var door: Vector2i = _open_sides(f, room)[0]
			if _quiet(f, walk, door, hall) and _reaches_all_without(f, [door, room]):
				out.append({"door": door, "room": room})
	return out


## Whether all the open floor but these cells can be walked to from the start without them.
static func _reaches_all_without(f, cells: Array) -> bool:
	var open := 0
	for row in f.grid:
		open += row.count(1)
	var reached := {f.start: true}
	var queue: Array = [f.start]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for d in FloorMap.DIRS:
			var next: Vector2i = at + d
			if f.is_open(next) and not reached.has(next) and not next in cells:
				reached[next] = true
				queue.append(next)
	return reached.size() == open - cells.size()


## A wall with solid rock behind it, to hollow out a one-cell room.
static func _closets(f, walk: Dictionary, hall: Vector2i) -> Array:
	var out := []
	for y in range(1, f.size - 1):
		for x in range(1, f.size - 1):
			var from := Vector2i(x, y)
			if not _quiet(f, walk, from, hall):
				continue
			for d in FloorMap.DIRS:
				var door: Vector2i = from + d
				var room: Vector2i = door + d
				if room.x < 1 or room.y < 1 or room.x > f.size - 2 or room.y > f.size - 2:
					continue
				if f.grid[door.y][door.x] != 0 or f.grid[room.y][room.x] != 0:
					continue
				if _open_sides(f, door).size() == 1 and _open_sides(f, room).is_empty():
					out.append({"door": door, "room": room})
	return out


static func _quiet(f, walk: Dictionary, c: Vector2i, hall: Vector2i) -> bool:
	return f.is_open(c) and c != f.start and walk.dist.has(c) and walk.dist[c] >= MIN_FROM_START and not Grid.in_hall(c, hall)


static func _open_sides(f, c: Vector2i) -> Array:
	var out := []
	for d in FloorMap.DIRS:
		if f.is_open(c + d):
			out.append(c + d)
	return out


## Sets out the pads. `walk` is FloorGen's walk of the floor with its stairs chosen.
static func place_pads(rng, f, walk: Dictionary, hall: Vector2i, params: Dictionary) -> void:
	var longest: int = walk.dist[walk.farthest]
	for _i in int(params.get("pads", 0)):
		var blocked := {}
		for t in f.teleports:
			blocked[t.a] = true
			blocked[t.b] = true
		var a: Variant = _pad_in(rng, f, walk, hall, PAD_NEAR, longest, blocked)
		if a == null:
			return
		blocked[a] = true
		var b: Variant = _pad_in(rng, f, walk, hall, PAD_FAR, longest, blocked)
		if b == null:
			return
		f.teleports.append({"a": a, "b": b})


## A spot for a pad in the first of these stretches of the walk that has one.
static func _pad_in(rng, f, walk: Dictionary, hall: Vector2i, shares: Array, longest: int, blocked: Dictionary) -> Variant:
	for share in shares:
		var spot: Variant = _pad_spot(rng, f, walk, hall, share, longest, blocked)
		if spot != null:
			return spot
	return null


## A cell in that stretch of the walk that no route needs, or null. A dead end if there is one.
static func _pad_spot(rng, f, walk: Dictionary, hall: Vector2i, share: Array, longest: int, blocked: Dictionary) -> Variant:
	var ends := []
	var others := []
	for c: Vector2i in walk.order:
		var d: float = float(walk.dist[c]) / maxi(1, longest)
		if d < share[0] or d > share[1] or c == f.stairs or c == f.start or Grid.in_hall(c, hall) or blocked.has(c) or _by_a_cracked_wall(f, c):
			continue
		if _open_sides(f, c).size() == 1:
			ends.append(c)
		else:
			others.append(c)
	for pool in [rng.shuffle(ends), rng.shuffle(others)]:
		for i in mini(pool.size(), SAFE_TRIES):
			if _leaves_floor_whole(f, walk, blocked, pool[i]):
				return pool[i]
	return null


## A pad here would carry you off before you could reach the wall.
static func _by_a_cracked_wall(f, c: Vector2i) -> bool:
	for d in FloorMap.DIRS:
		if f.is_cracked(c + d):
			return true
	return false


## Whether everything else on the floor can still be walked to with the pads in the way.
static func _leaves_floor_whole(f, walk: Dictionary, blocked: Dictionary, extra: Vector2i) -> bool:
	var reached := {f.start: true}
	var queue: Array = [f.start]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for d in FloorMap.DIRS:
			var next: Vector2i = at + d
			if f.is_open(next) and not reached.has(next) and next != extra and not blocked.has(next):
				reached[next] = true
				queue.append(next)
	return reached.size() == walk.order.size() - blocked.size() - 1
