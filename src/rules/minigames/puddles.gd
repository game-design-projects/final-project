## Puddles: drops of ooze fall, some beside you to herd you, and each puddle stays lit for a long while. They never take more
## than under half the box, and never wall you into a pocket of fewer than eight squares.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const EVERY_MS := 450.0
const PLUS_SHARE := 0.35
const HERD_SHARE := 0.5 # a drop beside the soul
const WARN_MS := 520.0
const HIT_MS := 2600.0 # a puddle stays
const MAX_SHARE := 0.45 # of the box lit by puddles at once
const MIN_ROOM := 8 # the soul's room that is neither warning nor hurting
const TRIES := 10
const STEPS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + EVERY_MS / (run.intensity * run.pace)
	var lit := {}
	for h in run.hazards:
		if h.kind == "goo":
			for k in h.cells:
				lit[k] = true
	var soul: Vector2i = run.soul
	var plus := rng.chance(PLUS_SHARE)
	var herd := rng.chance(HERD_SHARE)
	for attempt in TRIES:
		var centre: Vector2i
		if herd:
			var beside := []
			for d in STEPS:
				if Dodge.in_box(soul.x + d.x, soul.y + d.y):
					beside.append(soul + d)
			centre = rng.pick(beside)
		else:
			centre = Vector2i(rng.int_range(0, Dodge.COLS - 1), rng.int_range(0, Dodge.ROWS - 1))
		var cells := [Dodge.index(centre.x, centre.y)]
		if plus:
			for d in STEPS:
				if Dodge.in_box(centre.x + d.x, centre.y + d.y):
					cells.append(Dodge.index(centre.x + d.x, centre.y + d.y))
		var after := lit.duplicate()
		for k in cells:
			after[k] = true
		if float(after.size()) > MAX_SHARE * Dodge.COLS * Dodge.ROWS or _room(run, after) < MIN_ROOM:
			continue
		run.add_hazard(t, cells, WARN_MS, HIT_MS, "goo")
		print_verbose("puddles: %d squares at %s, %d lit in all" % [cells.size(), centre, after.size()])
		return
	print_verbose("puddles: no drop fits, skipped")


## How many squares the soul can walk to that are not lit (its own counts only if it is not lit).
static func _room(run, lit: Dictionary) -> int:
	var start := Dodge.index(run.soul.x, run.soul.y)
	var seen := {start: true}
	var todo: Array = [run.soul]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in STEPS:
			var n: Vector2i = c + d
			if not Dodge.in_box(n.x, n.y):
				continue
			var k := Dodge.index(n.x, n.y)
			if seen.has(k) or lit.has(k) or run.blocked.has(k):
				continue
			seen[k] = true
			todo.append(n)
	return seen.size() - (1 if lit.has(start) else 0)
