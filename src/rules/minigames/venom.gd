## Venom: a ring of venom closes round you, two squares out, with one gap. Then the inside burns too. Slip out through the gap;
## the gap is two steps from you, on your row or column, when there is room.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const EVERY_MS := 1600.0
const RING_WARN_MS := 700.0
const RING_HIT_MS := 900.0
const INSIDE_WARN_MS := 1050.0
const INSIDE_HIT_MS := 300.0
const MIN_EVERY_MS := 1250.0 # a ring never follows the last faster than this, or there is no time to reach its gap
const RADIUS := 2
const AXES := [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + maxf(EVERY_MS / run.intensity, MIN_EVERY_MS) / run.pace
	var centre: Vector2i = run.soul
	var ring := []
	for r in range(centre.y - RADIUS, centre.y + RADIUS + 1):
		for c in range(centre.x - RADIUS, centre.x + RADIUS + 1):
			if maxi(absi(c - centre.x), absi(r - centre.y)) == RADIUS and Dodge.in_box(c, r):
				ring.append(Vector2i(c, r))
	var gap := _gap(centre, ring, rng)
	var cells := []
	for c in ring:
		if c != gap:
			cells.append(Dodge.index(c.x, c.y))
	var inside := []
	for r in range(centre.y - 1, centre.y + 2):
		for c in range(centre.x - 1, centre.x + 2):
			if Dodge.in_box(c, r):
				inside.append(Dodge.index(c, r))
	run.add_hazard(t, cells, RING_WARN_MS, RING_HIT_MS, "venom")
	run.add_hazard(t, inside, INSIDE_WARN_MS, INSIDE_HIT_MS, "venom")
	print_verbose("venom: ring round %s, %d squares, gap at %s" % [centre, cells.size(), gap])


## The gap: a square on the ring two steps from the centre in a straight line, with room beyond it (not facing a wall); else
## any such square; else any square on the ring.
static func _gap(centre: Vector2i, ring: Array, rng: Rng) -> Vector2i:
	var open := []
	var any := []
	for d in AXES:
		var c: Vector2i = centre + d
		if not Dodge.in_box(c.x, c.y):
			continue
		any.append(c)
		var beyond: Vector2i = c + d / 2
		if Dodge.in_box(beyond.x, beyond.y):
			open.append(c)
	if not open.is_empty():
		return rng.pick(open)
	if not any.is_empty():
		return rng.pick(any)
	return rng.pick(ring)
