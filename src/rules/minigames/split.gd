## Split: a big blob lands on a 3x3 around you; when it lands it throws four small globs outward, diagonally one time and
## straight the next, one cell at a time until they leave the box.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const BLOB_MS := 1500.0 # between blobs
const WARN_MS := 850.0
const HIT_MS := 250.0
const BREATH_MS := 250.0 # least pause between one blob's hit and the next blob's warning
const MAX_ESCAPE := 2 # steps the soul may need to get out of the blob
const STEP_MS := 150.0 # how long a small glob takes over one cell
const SHOWS_STEPS := 2.0
const SHOWS_MIN_MS := 340.0
const ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func begin(run, _rng: Rng) -> void:
	run.mem = {"n": 0}
	print_verbose("split: a blob every %.0f ms, globs %.0f ms a cell" % [BLOB_MS / (run.intensity * run.pace), STEP_MS / (run.intensity * run.pace)])


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	var ip: float = run.intensity * run.pace
	var land: float = WARN_MS * (run.WARN_BANDIT_SCALE if run.bandit_charm else 1.0) / run.pace # when it lands, from now
	run.next_t = t + maxf(BLOB_MS / ip, land + HIT_MS + BREATH_MS) # never two blobs warning at once
	var step := STEP_MS / ip
	var shows := maxf(SHOWS_STEPS * step, SHOWS_MIN_MS)
	var at := _centre(run, rng)
	var cx := at.x
	var cy := at.y
	var blob := []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			blob.append(Dodge.index(cx + dx, cy + dy))
	var centre := Dodge.index(cx, cy)
	run.add_hazard(t, blob, WARN_MS, HIT_MS, "goo", {"at": centre, "mark": "ball", "mark_warn": true})
	var dirs: Array = ORTHO if run.mem.n % 2 == 1 else Dodge.BISHOP_DIRS
	run.mem.n += 1
	for d in dirs:
		var k := 2
		while Dodge.in_box(cx + d.x * k, cy + d.y * k):
			var cell := Dodge.index(cx + d.x * k, cy + d.y * k)
			var delay: float = land + (k - 1) * step
			run.add_hazard(t, [cell], delay * run.pace / (run.WARN_BANDIT_SCALE if run.bandit_charm else 1.0), step, "goo", {"at": cell, "mark": "ball", "dir": d, "shows": shows})
			k += 1
	print_verbose("split: a blob on %s, then %s globs" % [Vector2i(cx, cy), "straight" if dirs == ORTHO else "diagonal"])


## Where the next blob lands: within one cell of the soul, and so that the soul is one step from the edge of it (two where the
## box's edge leaves no better); failing that, the nearest centre that lets it get out in two.
static func _centre(run, rng: Rng) -> Vector2i:
	for limit in range(1, MAX_ESCAPE + 1):
		var near := []
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var c := Vector2i(clampi(run.soul.x + dx, 1, Dodge.COLS - 2), clampi(run.soul.y + dy, 1, Dodge.ROWS - 2))
				if _escape(run.soul, c) <= limit:
					near.append(c)
		if not near.is_empty():
			return rng.pick(near)
	var best := []
	var best_d := 99
	for x in range(1, Dodge.COLS - 1):
		for y in range(1, Dodge.ROWS - 1):
			var c := Vector2i(x, y)
			var d := maxi(absi(x - run.soul.x), absi(y - run.soul.y))
			if _escape(run.soul, c) <= MAX_ESCAPE and d <= best_d:
				if d < best_d:
					best = []
				best_d = d
				best.append(c)
	return rng.pick(best)


## How many steps the soul needs to be outside a blob's 3x3 (0 when it already is).
static func _escape(soul: Vector2i, centre: Vector2i) -> int:
	if maxi(absi(soul.x - centre.x), absi(soul.y - centre.y)) > 1:
		return 0
	var best := 99
	for x in Dodge.COLS:
		for y in Dodge.ROWS:
			if maxi(absi(x - centre.x), absi(y - centre.y)) > 1:
				best = mini(best, absi(x - soul.x) + absi(y - soul.y))
	return best
