## Bombs: every other beat a bomb is set down near you. It ticks three beats (the number on it counts down), then blows in a plus
## along its row and column, two squares each way (three when it is hard).
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const BEAT_MS := 440.0
const EVERY_BEATS := 1
const FUSE_BEATS := 3
const HIT_MS := 300.0
const REACH := 2
const REACH_HARD := 3 # from intensity 1.3
const NEAREST := 1 # Manhattan distance from the soul
const FARTHEST := 3
const LINED_UP_SHARE := 0.6 # a bomb on your row or column, so its blast crosses you
const COUNT := 1 # bombs set down each time
const COUNT_HARD := 1 # from intensity 1.3
const TRIES := 6
const NEAR_SAFE := 2 # squares within two steps of the soul that no bomb (old or new) takes
const ARMS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func spawn(run, t: float, rng: Rng, events: Array) -> void:
	var beat_ms := BEAT_MS / sqrt(run.intensity * run.pace)
	var b := floori((t - run.t0) / beat_ms)
	if b <= run.beat:
		return
	run.beat = b
	run.pulse = t
	events.append({"type": "beat"})
	events.append({"type": "sound", "name": "tick"})
	if b % EVERY_BEATS != 0:
		return
	for n in (COUNT_HARD if run.intensity >= 1.3 else COUNT):
		_set_down(run, t, rng)


static func _set_down(run, t: float, rng: Rng) -> void:
	var beat_ms := BEAT_MS / sqrt(run.intensity * run.pace)
	var taken := {}
	for h in run.hazards:
		if h.kind == "blast" and h.has("at"):
			taken[h.at] = true
	var soul: Vector2i = run.soul
	var options := []
	for r in Dodge.ROWS:
		for c in Dodge.COLS:
			var d := absi(c - soul.x) + absi(r - soul.y)
			var k := Dodge.index(c, r)
			if d >= NEAREST and d <= FARTHEST and not taken.has(k) and not run.blocked.has(k):
				options.append(Vector2i(c, r))
	if options.is_empty():
		return
	var lined := options.filter(func(o): return o.x == soul.x or o.y == soul.y)
	var reach := REACH_HARD if run.intensity >= 1.3 else REACH
	var at := Vector2i.ZERO
	var cells := []
	for attempt in TRIES:
		at = rng.pick(lined if not lined.is_empty() and rng.chance(LINED_UP_SHARE) else options)
		cells = _plus(at, reach)
		if _near_safe(run, cells) >= NEAR_SAFE:
			break
		print_verbose("bombs: bomb at %s would leave no way out, trying another" % at)
	if _near_safe(run, cells) < NEAR_SAFE:
		return
	var before: int = run.hazards.size()
	run.add_hazard(t, cells, FUSE_BEATS * beat_ms * run.pace, HIT_MS, "blast", {"at": Dodge.index(at.x, at.y), "mark": "bomb", "mark_warn": true})
	if run.hazards.size() == before:
		return # a frightened sapper's bomb may never come (DodgeRun mood)
	var h: Dictionary = run.hazards.back()
	h["beat"] = (h.hit - h.warn) / FUSE_BEATS # so it reads 3, 2, 1 even when the pace stretches the fuse
	print_verbose("bombs: bomb at %s, reach %d, %d squares, beat %d ms" % [at, reach, cells.size(), h.beat])


static func _plus(at: Vector2i, reach: int) -> Array:
	var cells := [Dodge.index(at.x, at.y)]
	for d in ARMS:
		for step in range(1, reach + 1):
			var c: Vector2i = at + d * step
			if Dodge.in_box(c.x, c.y):
				cells.append(Dodge.index(c.x, c.y))
	return cells


## How many open squares within two steps of the soul stay clear of every bomb still to blow, `cells` (the new one) included.
static func _near_safe(run, cells: Array) -> int:
	var taken := {}
	for k in cells:
		taken[k] = true
	for h in run.hazards:
		if h.kind == "blast":
			for k in h.cells:
				taken[k] = true
	var n := 0
	for r in range(run.soul.y - 2, run.soul.y + 3):
		for c in range(run.soul.x - 2, run.soul.x + 3):
			if absi(c - run.soul.x) + absi(r - run.soul.y) <= 2 and Dodge.in_box(c, r):
				var k := Dodge.index(c, r)
				if not taken.has(k) and not run.blocked.has(k):
					n += 1
	return n
