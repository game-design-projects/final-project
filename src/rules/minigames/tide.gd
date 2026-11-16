## Tide: every so often a wave floods the whole box but for one island, which shows from the start. Get to the island. Each
## island is near the last, never the same place twice running, and gets smaller as it gets hotter.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const WAVE_MS := 1500.0
const WARN_MS := 750.0
const HIT_MS := 350.0
const SMALL := 1.3 # from this intensity the island is 2x2 instead of 3x3


static func begin(run, _rng: Rng) -> void:
	var size := 2 if run.intensity >= SMALL else 3
	run.mem = {"size": size, "at": Vector2i(-1, -1)}
	print_verbose("tide: %dx%d islands, a wave every %.0f ms" % [size, size, WAVE_MS / (run.intensity * run.pace)])


## Where the next island's top left corner goes: 1-2 steps from the soul (so it has to move), and after the first one within
## two squares of the last, never the same place. The soul stands in the last island when this is asked.
static func _next_island(run, rng: Rng) -> Vector2i:
	var size: int = run.mem.size
	var top_max := Dodge.COLS - size
	var last: Vector2i = run.mem.at
	var soul: Vector2i = run.soul
	var near := []
	var any := []
	for r in range(0, top_max + 1):
		for c in range(0, top_max + 1):
			var here := Vector2i(c, r)
			if here == last or (last.x >= 0 and maxi(absi(c - last.x), absi(r - last.y)) > 2):
				continue
			any.append(here)
			var dx := maxi(c - soul.x, soul.x - (c + size - 1))
			var dy := maxi(r - soul.y, soul.y - (r + size - 1))
			var steps := maxi(dx, 0) + maxi(dy, 0) # steps from the soul to the island's nearest square
			if steps >= 1 and steps <= 2:
				near.append(here)
	if not near.is_empty():
		return rng.pick(near)
	return rng.pick(any)


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + WAVE_MS / (run.intensity * run.pace)
	var size: int = run.mem.size
	var island := _next_island(run, rng)
	run.mem.at = island
	var cells := []
	for r in Dodge.ROWS:
		for c in Dodge.COLS:
			if c < island.x or c >= island.x + size or r < island.y or r >= island.y + size:
				cells.append(Dodge.index(c, r))
	run.add_hazard(t, cells, WARN_MS, HIT_MS, "goo")
