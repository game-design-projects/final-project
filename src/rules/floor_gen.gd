## Makes a floor in passes: a layout from the biome's generator (rules/maps), checked and carved again if it won't do; the secrets;
## the stairs at the far end; and the monsters spread along the way from near to far. Every draw comes from the floor's generator, so
## the same seed makes the same floor. With no biome it is the classic maze, drawing the numbers it always drew.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Grid = preload("res://src/rules/maps/grid.gd")
const Items = preload("res://src/rules/items.gd")
const Lords = preload("res://src/rules/lords.gd")
const Kinds = preload("res://src/rules/kinds.gd")
const Monster = preload("res://src/rules/monster.gd")
const Requests = preload("res://src/rules/requests.gd")
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
const LORD_SEED := 400 # a lord's own draws, apart from the floor's: the layout stays what the floor's seed always made
const LORE_SEED := 300 # the writing is placed from a generator of its own, so the rest of a floor is what that seed always made


## `plan` (rules/floors.gd) says how deep the floor is, who guards it, its biome and its secrets; without one it is the classic first
## floor.
static func generate(rng: Rng, plan := {}):
	var t0 := Time.get_ticks_usec()
	plan = plan.duplicate()
	plan.taken = (plan.get("names_taken", {}) as Dictionary).duplicate() # the names met this run, and this floor's as they are given
	var f := FloorMap.new()
	f.seed_value = rng.seed_value
	f.hp_scale = float(plan.get("hp_scale", 1.0))
	var biome: Dictionary = plan.get("biome", {})
	f.biome = str(biome.get("id", ""))
	var hall := _lay_out(f, rng, biome)
	var walk := _walk_from(f, f.start, hall)
	var secrets: Dictionary = (plan.get("secrets", {}) as Dictionary).duplicate() # a copy: the vault is this floor's, and the biome's numbers stay as they are
	if bool(plan.get("vault", false)):
		secrets.vault = true
	if not secrets.is_empty():
		Secrets.hide_chests(rng, f, walk, hall, secrets)
		walk = _walk_from(f, f.start, hall)
	f.stairs = walk.farthest
	if not secrets.is_empty():
		Secrets.place_pads(rng, f, walk, hall, secrets)
	if plan.get("shop", false):
		var cell: Variant = Secrets.place_trader(rng, f, walk, hall)
		if cell != null:
			f.merchant = {"cell": cell, "stock": Items.stock(rng, plan)}
	var lord: Dictionary = {}
	if plan.get("lords", false) or plan.get("lords_return", false): # at home here, or back where its biome comes round again
		lord = Lords.due(str(f.biome), int(f.seed_value), plan.get("lords_done", []), plan.get("lords_sworn", []), bool(plan.get("lords_return", false)), plan.get("lords_standing", {}))
	if plan.get("request", false):
		var cell: Variant = Secrets.place_trader(rng, f, walk, hall)
		if cell != null:
			f.quester = {"cell": cell} # the draw is made whether or not a lord takes the asker's part, so the floor keeps its seed
	var stirs := {}
	if plan.get("lurkers", false) and int(plan.get("count", -1)) <= 0: # a quiet way down is quiet
		var numbers: Dictionary = Content.table("npcs").lurkers
		for cell in Secrets.place_lurkers(rng, f, walk, hall, rng.int_range(int(numbers.count[0]), int(numbers.count[1]))):
			stirs[cell] = true
	if plan.get("items", false):
		for item in Items.floor_finds(rng, plan):
			var cell: Variant = Secrets.quiet_spot(rng, f, walk, hall, stirs)
			if cell != null:
				f.pickups.append({"cell": cell, "item": item})
	var reserved: Dictionary = f.reserved()
	reserved.merge(stirs)
	f.monsters = _place_monsters(rng, walk, hall, plan, reserved)
	_add_lurkers(rng, f, stirs.keys(), plan)
	if not lord.is_empty(): # after the monsters stand: on a floor that already had someone asking, the lord is that one
		_place_lord(f, walk, hall, lord)
	if not f.quester.is_empty():
		_finish_request(rng, f, walk, hall, plan, stirs)
	if plan.get("lore", false):
		_write_on_a_wall(f, walk, hall)
	print("floor: seed %d, %s %dx%d, stairs at %s, %d monsters, %d chests, %d pads, %d items%s%s%s, in %d ms" % [rng.seed_value, f.biome if f.biome != "" else "classic", f.size, f.size, f.stairs, f.monsters.size(), f.treasure.size(), f.teleports.size() * 2, f.pickups.size(), ", a trader" if not f.merchant.is_empty() else "", ", someone asking" if not f.quester.is_empty() else "", ", writing at %s" % f.lore.cell if not f.lore.is_empty() else "", (Time.get_ticks_usec() - t0) / 1000])
	return f


## The floor's lord (rules/lords.gd) in its biome: its place drawn from a generator of its own, so the floor's own draws, and
## so its layout, are what the seed always made. A lord is due here (#166), so its place is not given up for want of the
## usual stretch of the walk: `Secrets.place_lord` falls back on any cell it may stand on that leaves a way through the floor
## whole, and a floor that somehow has none says so rather than quietly losing the run's second favour, the pact and the warren.
static func _place_lord(f, walk: Dictionary, hall: Vector2i, lord: Dictionary) -> void:
	if f.quester.is_empty(): # no one was asking here: a place of its own, from the lord's generator, after the monsters stand
		var lrng := Rng.new(Rng.offset(int(f.seed_value), LORD_SEED))
		var stood := {}
		for m in f.monsters: # they are here already, and `reserved()` does not know them
			stood[m.cell] = true
		var cell: Variant = Secrets.place_lord(lrng, f, walk, hall, stood)
		if cell == null:
			print("floor: no place for %s, the lord of %s" % [lord.name, lord.clan])
			return
		f.quester = {"cell": cell}
	f.quester["lord"] = lord # the asker is the lord; `_finish_request` fills it with the lord's own favour


## The writing (rules/lore.gd), on a wall nobody stands in front of. Which piece it is is decided when it is read.
static func _write_on_a_wall(f, walk: Dictionary, hall: Vector2i) -> void:
	var keep_off := {}
	for m in f.monsters:
		keep_off[m.cell] = true
	var spot: Variant = Secrets.lore_spot(Rng.new(Rng.offset(f.seed_value, LORE_SEED)), f, walk, hall, keep_off)
	if spot == null:
		print("floor: no wall for the writing")
		return
	f.lore = {"cell": spot.cell, "side": int(spot.side), "read": false}


## Whoever stirs in these cells: a monster like the floor's others, with a purse. The champion stays the last of the list.
static func _add_lurkers(rng: Rng, f, cells: Array, plan: Dictionary) -> void:
	var numbers: Dictionary = Content.table("npcs").lurkers
	var roster: Array = _kinds_here(plan)
	var champion = f.monsters.pop_back()
	for c: Vector2i in cells:
		var m = Monster.make(rng, roster_line(_one_of(roster, plan.get("biome", {}).get("weights", {}), rng), plan), c, plan.taken)
		m.lurking = true
		m.purse = rng.int_range(int(numbers.purse[0]), int(numbers.purse[1]))
		f.monsters.append(m)
	f.monsters.append(champion)


## Who asks, and what it asks for; what's fetched lies on this floor. Nobody asks when there is nothing to ask about. A thing
## the floor already has is asked for where it lies, and nothing is put down for it; only a floor with nothing lying about
## has its kind's gift placed, as it always did.
static func _finish_request(rng: Rng, f, walk: Dictionary, hall: Vector2i, plan: Dictionary, stirs: Dictionary) -> void:
	var draws = rng # what places what's fetched: the floor's own draws, or a lord's (rules/lords.gd)
	if f.quester.has("lord"): # a lord asks its own favour, on its own draws
		var lord: Dictionary = f.quester.lord
		f.quester.erase("lord")
		draws = Rng.new(Rng.offset(int(f.seed_value), LORD_SEED))
		if not Requests.fill_lord(draws, f, lord, plan):
			f.quester = {}
			return
	elif not Requests.fill(rng, f, plan):
		f.quester = {}
		return
	if f.quester.kind != "fetch":
		return
	if f.pickups.any(func(p): return str(p.item) == str(f.quester.want)):
		return # the ask is a thing already lying here: it is not put down a second time (requests.gd: want_for)
	var taken := stirs.duplicate()
	for m in f.monsters:
		taken[m.cell] = true
	var cell: Variant = Secrets.quiet_spot(draws, f, walk, hall, taken)
	if cell == null: # no quiet spot at all: the thing still gets a place that leaves the way through whole, so the favour can be finished
		cell = Secrets.place_lord(draws, f, walk, hall, taken)
	if cell == null:
		f.quester = {}
		return
	f.pickups.append({"cell": cell, "item": f.quester.want})


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


## Roster monsters spread out nearest first, evenly through the candidate cells; the champion stands on the stairs, or in the
## hall when the plan keeps it there (no `boss_at_exit`).
static func _place_monsters(rng: Rng, walk: Dictionary, hall: Vector2i, plan: Dictionary, reserved: Dictionary) -> Array:
	var candidates := []
	for i in walk.order.size():
		var c: Vector2i = walk.order[i]
		var d: int = walk.dist[c]
		if d >= MIN_MONSTER_DISTANCE and not Grid.in_hall(c, hall) and c != walk.farthest and not reserved.has(c):
			candidates.append({"cell": c, "dist": d, "order": i})
	candidates.sort_custom(func(a, b): return a.dist < b.dist or (a.dist == b.dist and a.order < b.order))
	var monsters := []
	var used: Array = []
	var roster: Array = _roster_for(_kinds_here(plan), plan, rng)
	for i in roster.size():
		var target := floori(float(i + 1) / (roster.size() + 1) * candidates.size())
		var spot: Vector2i = candidates[target % candidates.size()].cell
		for j in candidates.size():
			var c: Vector2i = candidates[(target + j) % candidates.size()].cell
			if used.all(func(u): return absi(u.x - c.x) + absi(u.y - c.y) > MONSTER_SPACING):
				spot = c
				break
		used.append(spot)
		monsters.append(Monster.make(rng, roster_line(roster[i], plan), spot, plan.taken))
	var post: Vector2i = walk.farthest if plan.get("boss_at_exit", false) else hall
	monsters.append(Monster.make(rng, champion_line(plan), post))
	return monsters


## The roster line of the champion of the plan's floor: the Hoard's, with its floor's name and health, fighting in every attack
## of its floor's kinds.
static func champion_line(plan: Dictionary) -> Dictionary:
	var boss: Dictionary = Content.table("encounter").boss
	var champion: Dictionary = plan.get("champion", boss)
	var genres: Array = Kinds.genres_at(int(plan.get("depth", 1)))
	if genres.is_empty():
		genres = boss.genres
	return {"species": boss.species, "genre": genres[0], "genres": genres, "hp": champion.hp, "name": champion.name, "boss": true}


## The roster lines that live on this floor: its depth's five kinds (rules/kinds.gd), or down a warren every kind of that clan met so
## far, the floor's own first.
static func _kinds_here(plan: Dictionary) -> Array:
	var depth := int(plan.get("depth", 1))
	var only := str(plan.get("only_species", ""))
	var out: Array = Kinds.of_species(only, depth) if only != "" else Kinds.at_depth(depth)
	if out.is_empty():
		push_error("floor: no kinds of monster for depth %d%s" % [depth, " (%s)" % only if only != "" else ""])
		out = Content.table("encounter").roster
	return out


## Who lives on this floor: one of each of its kinds, more on a bigger floor (the biome says of which clans), or fewer down a quiet
## way. A warren's roster is already all one clan.
static func _roster_for(roster: Array, plan: Dictionary, rng: Rng) -> Array:
	var out := roster
	if str(plan.get("only_species", "")) != "": # as many as a floor has kinds, round the clan's
		out = range(Kinds.at_depth(int(plan.get("depth", 1))).size()).map(func(i): return roster[i % roster.size()])
	var biome: Dictionary = plan.get("biome", {})
	if not biome.is_empty():
		out = out.duplicate()
		for _i in maxi(0, (int(biome.size) - SIZE) / EXTRA_MONSTER_CELLS):
			out.append(_one_of(roster, biome.get("weights", {}), rng))
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
static func roster_line(entry: Dictionary, plan: Dictionary) -> Dictionary:
	var out := entry.duplicate()
	out.hp = roundi(float(entry.hp) * float(plan.get("hp_scale", 1.0)))
	return out
