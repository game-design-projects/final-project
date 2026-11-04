## The shape of a run: how many floors it has, and what each one is like (who guards it, how tough its monsters are, how it is
## seeded). Pure numbers from data/floors.json. A floor's seed comes from the run's seed and where the floor sits, never from
## the generator the fights draw from, so `seed=N` makes the same floors however the fights went, and after a load too.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Rng = preload("res://src/utils/rng.gd")

const FLOOR_SEED_STEP := 7919 # a prime, so the floors' seeds don't line up with the seeds next to this run's


static func run_floors() -> int:
	return int(Content.table("floors").run_floors)


## Whether `depth` is the last floor of a run.
static func is_last(depth: int) -> bool:
	return depth >= run_floors()


## What generating this floor needs: {depth, champion: {name, hp}, hp_scale}.
static func plan(depth: int) -> Dictionary:
	var t := Content.table("floors")
	var champions: Array = t.champions
	return {
		"depth": depth,
		"champion": champions[clampi(depth - 1, 0, champions.size() - 1)],
		"hp_scale": 1.0 + float(t.hp_per_floor) * (depth - 1),
	}


## The seed of floor `depth` of the run seeded `run_seed`. `path` is which way down was taken (0 when there is one way).
static func floor_seed(run_seed: int, depth: int, path := 0) -> int:
	return Rng.offset(run_seed, depth * FLOOR_SEED_STEP + path)


## Why you are here, {title, banner, door, line}.
static func premise() -> Dictionary:
	return Content.table("floors").premise


## What a rest at the stairs gives back.
static func rest_heal() -> int:
	return int(Content.table("floors").rest_heal)
