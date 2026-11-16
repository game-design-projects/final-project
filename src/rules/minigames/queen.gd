## Queen: a queen lands on a square in line with you, a row, a column or a diagonal away, and takes every square she
## reaches. Later, one in three is followed by a second queen on another line.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const EVERY_MS := 950.0
const WARN_MS := 660.0
const HIT_MS := 300.0
const FOLLOW_MS := 450.0 # the second queen comes this long after the first
const FOLLOW_FROM := 1.3 # intensity
const NEAR_SAFE := 4 # squares within two steps of the soul that no queen, old or new, takes
const MAX_LIT := 33 # two queens together light no more squares than this


static func begin(run, _rng: Rng) -> void:
	run.mem = {"count": 0, "follow_at": -1.0, "first": []}
	print_verbose("queen: a queen every %d ms, a second one after %d ms from intensity %.1f" % [EVERY_MS / (run.intensity * run.pace), FOLLOW_MS, FOLLOW_FROM])


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	var mem: Dictionary = run.mem
	if mem.follow_at >= 0.0 and t >= mem.follow_at:
		mem.follow_at = -1.0
		var cells := _land(run, t, rng, mem.first)
		print_verbose("queen: second queen, %d squares" % cells.size())
	if t < run.next_t:
		return
	run.next_t = t + EVERY_MS / (run.intensity * run.pace)
	var cells := _land(run, t, rng, [])
	mem.count += 1
	if run.intensity >= FOLLOW_FROM and mem.count % 3 == 0:
		mem.follow_at = t + FOLLOW_MS
		mem.first = cells
	print_verbose("queen: queen number %d, %d squares" % [mem.count, cells.size()])


## Lands a queen in line with the soul, two or more squares away, leaving the soul NEAR_SAFE squares within two steps that no queen
## takes. With `taken` (the first queen's squares) she stands off those and the two together light at most MAX_LIT squares, or she
## does not come. Returns the squares she takes.
static func _land(run, t: float, rng: Rng, taken: Array) -> Array:
	var soul: Vector2i = run.soul
	var options := []
	for r in Dodge.ROWS:
		for c in Dodge.COLS:
			var dx := c - soul.x
			var dy := r - soul.y
			if maxi(absi(dx), absi(dy)) >= 2 and (dx == 0 or dy == 0 or absi(dx) == absi(dy)):
				options.append(Vector2i(c, r))
	rng.shuffle(options)
	var at := Vector2i.ZERO
	var cells := []
	var most := -1
	for o in options:
		var reach := _reach(o)
		if not taken.is_empty():
			if taken.has(Dodge.index(o.x, o.y)):
				continue
			var union := taken.duplicate()
			for c in reach:
				if not union.has(c):
					union.append(c)
			if union.size() > MAX_LIT:
				continue
		var safe := _near_safe(run, reach)
		if safe > most:
			most = safe
			at = o
			cells = reach
		if safe >= NEAR_SAFE:
			break
	if cells.is_empty() or (not taken.is_empty() and most < NEAR_SAFE):
		return []
	run.add_hazard(t, cells, WARN_MS, HIT_MS, "chess", {"glyph": "Q", "at": Dodge.index(at.x, at.y)})
	return cells


## Every square a queen on `at` takes, her own included.
static func _reach(at: Vector2i) -> Array:
	var cells: Array = Dodge.rook_cells(at)
	for k in Dodge.bishop_cells(at):
		if not cells.has(k):
			cells.append(k)
	var out := []
	for k in cells:
		if not out.has(k):
			out.append(k)
	return out


## How many squares within two steps of the soul stay clear of every queen still to land, `cells` (the new one) included.
static func _near_safe(run, cells: Array) -> int:
	var taken := {}
	for k in cells:
		taken[k] = true
	for h in run.hazards:
		if h.kind == "chess":
			for k in h.cells:
				taken[k] = true
	var n := 0
	for r in range(run.soul.y - 2, run.soul.y + 3):
		for c in range(run.soul.x - 2, run.soul.x + 3):
			if absi(c - run.soul.x) + absi(r - run.soul.y) <= 2 and Dodge.in_box(c, r) and not taken.has(Dodge.index(c, r)):
				n += 1
	return n
