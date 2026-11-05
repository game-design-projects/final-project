## The shape of a run: how many floors it has, and what each one is like (who guards it, how tough its monsters are, how it is
## seeded). Pure numbers from data/floors.json. A floor's seed comes from the run's seed and where the floor sits, never from
## the generator the fights draw from, so `seed=N` makes the same floors however the fights went, and after a load too.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Rng = preload("res://src/utils/rng.gd")

const PATHS_OFFERED := 2
const PATH_SEED := 100 # the ways down are drawn from their own seed, not any floor's
const BIOME_SEED := 200 # the order of the biomes has its own seed too
const FLOOR_SEED_STEP := 7919 # a prime, so the floors' seeds don't line up with the seeds next to this run's


static func run_floors() -> int:
	return int(Content.table("floors").run_floors)


## Whether `depth` is the last floor of a run.
static func is_last(depth: int) -> bool:
	return depth >= run_floors()


## What generating this floor needs: {depth, champion: {name, hp}, hp_scale}, and what the way down changes (see `paths`): {count,
## only_species}.
static func plan(depth: int, way := {}) -> Dictionary:
	var t := Content.table("floors")
	var champions: Array = t.champions
	return {
		"depth": depth,
		"champion": champions[clampi(depth - 1, 0, champions.size() - 1)],
		"hp_scale": (1.0 + float(t.hp_per_floor) * (depth - 1)) * float(way.get("hp_scale", 1.0)),
		"count": int(way.get("count", -1)),
		"only_species": str(way.get("only_species", "")),
	}


## The biome of floor `depth` of this run, at the size it is that deep: the biomes in an order from the run's seed, round and round,
## so no two floors running are the same one.
static func biome(run_seed: int, depth: int) -> Dictionary:
	var order: Array = Content.table("biomes").biomes.duplicate()
	Rng.new(floor_seed(run_seed, 0, BIOME_SEED)).shuffle(order)
	return sized(order[posmod(depth - 1, order.size())], depth)


## A biome with the size it has at `depth`.
static func sized(entry: Dictionary, depth: int) -> Dictionary:
	var out := entry.duplicate()
	var sizes: Array = entry.sizes
	out.size = int(sizes[clampi(depth - 1, 0, sizes.size() - 1)])
	return out


## The biome with this id, or an empty record.
static func biome_named(id: String) -> Dictionary:
	for b in Content.table("biomes").biomes:
		if b.id == id:
			return b
	return {}


## Which colours a floor wears (Palette.for_run): one of its biome's, by its seed. With no biome, its seed alone picks.
static func palette(biome_id: String, seed_value: int) -> int:
	var entry := biome_named(biome_id)
	return seed_value if entry.is_empty() else int(entry.palettes[posmod(seed_value, entry.palettes.size())])


## What the log says when you find something hidden ("wall", "chest", "pad").
static func secret_line(kind: String) -> String:
	return Content.table("biomes").lines[kind]


## What a floor of this biome hides (an empty record: a floor with no biome).
static func secrets(of_biome := {}) -> Dictionary:
	return of_biome.get("secrets", Content.table("biomes").secrets)


## The seed of floor `depth` of the run seeded `run_seed`. `path` is which way down was taken (0 when there is one way).
static func floor_seed(run_seed: int, depth: int, path := 0) -> int:
	return Rng.offset(run_seed, depth * FLOOR_SEED_STEP + path)


## Why you are here, {title, banner, door, line}.
static func premise() -> Dictionary:
	return Content.table("floors").premise


## What beating or winning over a champion gives, {max_hp, heal}.
static func boss_reward() -> Dictionary:
	return Content.table("floors").boss_reward


## What backing away costs, {gold, anger}.
static func flee_cost() -> Dictionary:
	return Content.table("floors").flee_cost


## The fewest monsters a walk from the start to the stairs must go through, for measuring how much of a floor can be skipped.
static func fights_required(f) -> int:
	var blocked := {}
	for m in f.monsters:
		if not m.is_gone():
			blocked[m.cell] = true
	var cost := {f.start: 0}
	var queue: Array = [f.start]
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for dir in f.DIRS:
			var next: Vector2i = at + dir
			if not f.is_open(next):
				continue
			var step: int = cost[at] + (1 if blocked.has(next) else 0)
			if not cost.has(next) or step < cost[next]:
				cost[next] = step
				if blocked.has(next):
					queue.append(next)
				else:
					queue.insert(head, next) # a free step goes to the front, so the walk stays cheapest first
	return cost.get(f.stairs, -1)


## The two ways down from floor `depth` of this run, from its seed, so a printed seed offers the same ones. Each is what `plan`
## takes, with its `path`, which picks the floor's seed, and its label and sub for the menu. The way to the last floor is one stair.
## `traders` says whether a way with a trader may be offered (the features items and shop).
static func paths(run_seed: int, depth: int, traders := true) -> Array:
	if is_last(depth + 1):
		return []
	var rng := Rng.new(floor_seed(run_seed, depth, PATH_SEED))
	var kinds: Array = Content.table("floors").paths.filter(func(k): return traders or not k.get("shop", false))
	var out := []
	for i in PATHS_OFFERED:
		var kind: Dictionary = kinds.pop_at(rng.int_range(0, kinds.size() - 1)).duplicate()
		kind.path = i + 1
		if kind.get("territory", false):
			var roster: Array = Content.table("encounter").roster
			var entry: Dictionary = roster[rng.int_range(0, roster.size() - 1)]
			var word: String = str(Content.species(entry.species).label).to_lower()
			kind.only_species = entry.species
			kind.label = kind.label % word.to_upper()
			kind.sub = kind.sub % ("a " + word)
		out.append(kind)
	return out


## The gate that wants someone left at its chain (the feature toll).
static func toll() -> Dictionary:
	return Content.table("floors").toll


## What a rest at the stairs gives back.
static func rest_heal() -> int:
	return int(Content.table("floors").rest_heal)
