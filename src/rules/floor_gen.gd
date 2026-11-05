## Makes a floor in passes: a layout from the biome's generator (rules/maps), checked and carved again if it won't do; the secrets;
## the stairs at the far end; and the monsters spread along the way from near to far. Every draw comes from the floor's generator, so
## the same seed makes the same floor. With no biome it is the classic maze, drawing the numbers it always drew.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Grid = preload("res://src/rules/maps/grid.gd")
const Monster = preload("res://src/rules/monster.gd")
const Rng = preload("res://src/utils/rng.gd")
const Secrets = preload("res://src/rules/secrets.gd")

## A biome names one of these (data/biomes.json); each is a file of its own in rules/maps, with `carve(rng, size, params)`.
const GENERATORS := {
	"halls": preload("res://src/rules/maps/halls.gd"),
	"chunks": preload("res://src/rules/maps/chunks.gd"),
	"caves": preload("res://src/rules/maps/caves.gd"),
}
const SIZE := 13 # the classic floor
const HALL_RADIUS := Grid.HALL_RADIUS
const SHORTCUT_TRIES := 12
const CARVE_TRIES := 100 # a layout that won't do is carved again, from the same generator, so a seed still makes one floor
const EXTRA_MONSTER_CELLS := 3 # a floor this much wider than the classic one has one more monster
const MIN_MONSTER_DISTANCE := 3 # steps from the start before the first monster may stand
const MONSTER_SPACING := 2 # no two monsters within this many cells of each other (Manhattan)


## `plan` (rules/floors.gd) says how deep the floor is, who guards it, its biome and its secrets; without one it is the classic first
## floor.
static func generate(rng: Rng, plan := {}):
	var t0 := Time.get_ticks_usec()
	var f := FloorMap.new()
	f.seed_value = rng.seed_value
	var biome: Dictionary = plan.get("biome", {})
	f.biome = str(biome.get("id", ""))
	var hall := _lay_out(f, rng, biome)
	var walk := _walk_from(f, f.start, hall)
	var secrets: Dictionary = plan.get("secrets", {})
	if not secrets.is_empty():
		Secrets.hide_chests(rng, f, walk, hall, secrets)
		walk = _walk_from(f, f.start, hall)
	f.stairs = walk.farthest
	if not secrets.is_empty():
		Secrets.place_pads(rng, f, walk, hall, secrets)
	f.monsters = _place_monsters(rng, walk, hall, plan, f.pads())
	print("floor: seed %d, %s %dx%d, stairs at %s, %d monsters, %d chests, %d pads, in %d ms" % [rng.seed_value, f.biome if f.biome != "" else "classic", f.size, f.size, f.stairs, f.monsters.size(), f.treasure.size(), f.teleports.size() * 2, (Time.get_ticks_usec() - t0) / 1000])
	return f


## Gives the floor its grid, start and size, and returns where its hall is.
static func _lay_out(f, rng: Rng, biome: Dictionary) -> Vector2i:
	if biome.is_empty():
		return _use(f, GENERATORS.halls.carve(rng, SIZE, {"shortcuts": SHORTCUT_TRIES}))
	var size := int(biome.size)
	for i in CARVE_TRIES:
		var hall := _use(f, GENERATORS[biome.generator].carve(rng, size, biome.params))
		if _will_do(f, hall, biome):
			if i > 0:
				print("floor: %s took %d tries" % [biome.id, i + 1])
			return hall
	push_warning("floor: %s made nothing usable in %d tries; plain halls instead" % [biome.id, CARVE_TRIES])
	return _use(f, GENERATORS.halls.carve(rng, size | 1, {"shortcuts": SHORTCUT_TRIES}))


static func _use(f, layout: Dictionary) -> Vector2i:
	f.grid = layout.grid
	f.size = layout.grid.size()
	f.start = layout.start
	return layout.hall


## All the floor in one piece, enough of it, and the stairs a good walk from the start.
static func _will_do(f, hall: Vector2i, biome: Dictionary) -> bool:
	if not f.is_open(f.start) or not f.is_open(hall):
		return false
	var open := 0
	for row in f.grid:
		open += row.count(1)
	var walk := _walk_from(f, f.start, hall)
	return walk.order.size() == open and float(open) / (f.size * f.size) >= float(biome.params.get("min_open", 0.0)) and walk.dist[walk.farthest] >= f.size


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
				if not Grid.in_hall(next, hall) and dist[next] > dist[farthest]:
					farthest = next
	return {"dist": dist, "order": order, "farthest": farthest}


## Roster monsters spread out nearest first, evenly through the candidate cells; the champion stands in the hall.
static func _place_monsters(rng: Rng, walk: Dictionary, hall: Vector2i, plan: Dictionary, reserved: Dictionary) -> Array:
	var enc := Content.table("encounter")
	var candidates := []
	for i in walk.order.size():
		var c: Vector2i = walk.order[i]
		var d: int = walk.dist[c]
		if d >= MIN_MONSTER_DISTANCE and not Grid.in_hall(c, hall) and c != walk.farthest and not reserved.has(c):
			candidates.append({"cell": c, "dist": d, "order": i})
	candidates.sort_custom(func(a, b): return a.dist < b.dist or (a.dist == b.dist and a.order < b.order))
	var monsters := []
	var used: Array = []
	var roster: Array = _roster_for(enc.roster, plan, rng)
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


## Who lives on this floor: the whole roster, more on a bigger floor (the biome says of what), or what the way down left of it.
static func _roster_for(roster: Array, plan: Dictionary, rng: Rng) -> Array:
	var out := roster
	var biome: Dictionary = plan.get("biome", {})
	if not biome.is_empty():
		out = roster.duplicate()
		for _i in maxi(0, (int(biome.size) - SIZE) / EXTRA_MONSTER_CELLS):
			out.append(_one_of(roster, biome.get("weights", {}), rng))
	if str(plan.get("only_species", "")) != "":
		var kind: Array = roster.filter(func(e): return e.species == plan.only_species)
		out = out.map(func(_e): return kind[0])
	if int(plan.get("count", -1)) > 0:
		var scale := float(biome.get("size", SIZE)) / SIZE
		out = out.slice(0, ceili(int(plan.count) * scale))
	return out


## A roster line, the biome's favourites more often.
static func _one_of(roster: Array, weights: Dictionary, rng: Rng) -> Dictionary:
	var total := 0.0
	for e in roster:
		total += float(weights.get(e.species, 1))
	var roll := rng.real() * total
	for e in roster:
		roll -= float(weights.get(e.species, 1))
		if roll < 0.0:
			return e
	return roster[-1]


## A roster line with the floor's toughness.
static func _at_depth(entry: Dictionary, plan: Dictionary) -> Dictionary:
	var out := entry.duplicate()
	out.hp = roundi(float(entry.hp) * float(plan.get("hp_scale", 1.0)))
	return out
