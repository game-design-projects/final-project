## Quake: a stomp lands near you on every third beat and its wave rings out from there, ring after ring, three squares wide.
## The whole wave shows two beats ahead, with the cracks it skips left dark: stand in a crack, or past the last ring.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const BEAT_MS := 560.0
const RING_MS := 170.0 # how long each ring takes to follow the last, and how long it hurts
const RINGS := 4 # Chebyshev radius 0 to 3
const WARN_BEATS := 2.0
const STEP_ONE := 0.85 # how often the crack is a step from the soul rather than two
const CRACKS_ONE := 1.3 # from this intensity there is one crack instead of two opposite ones
const DIRS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]


static func begin(run, _rng: Rng) -> void:
	run.mem = {"stomps": 0}
	print_verbose("quake: beat %.0f ms, rings every %.0f ms" % [BEAT_MS / sqrt(run.intensity * run.pace), RING_MS / (run.intensity * run.pace)])


## A direction for the crack: one with a crack square a step from the soul or, as often, two steps by a way that does not cross
## the epicentre, so there is always a way into a crack. Falls back to any direction.
static func _crack_dir(run, epi: Vector2i, soul: Vector2i, rng: Rng) -> Vector2i:
	var reach := 1 if rng.chance(STEP_ONE) else 2
	for r in range(reach, 3):
		var options := []
		for d in DIRS:
			var ends: Array = [epi + d] if run.intensity >= CRACKS_ONE else [epi + d, epi - d]
			for c in ends:
				if _walkable(epi, soul, c, r):
					options.append(d)
					break
		if not options.is_empty():
			return rng.pick(options)
	return rng.pick(DIRS)


## Whether the soul can get to `c` in exactly `steps` steps without stepping on the epicentre `epi` (or the box's edge).
static func _walkable(epi: Vector2i, soul: Vector2i, c: Vector2i, steps: int) -> bool:
	if not Dodge.in_box(c.x, c.y) or c == epi:
		return false
	var d := absi(c.x - soul.x) + absi(c.y - soul.y)
	if steps == 1:
		return d <= 1
	if d <= 1:
		return false
	for n in [soul + Vector2i(1, 0), soul + Vector2i(-1, 0), soul + Vector2i(0, 1), soul + Vector2i(0, -1)]:
		if Dodge.in_box(n.x, n.y) and n != epi and absi(c.x - n.x) + absi(c.y - n.y) <= 1:
			return true
	return false


static func spawn(run, t: float, rng: Rng, events: Array) -> void:
	var beat_ms := BEAT_MS / sqrt(run.intensity * run.pace)
	var b := floori((t - run.t0) / beat_ms)
	if b <= run.beat:
		return
	run.beat = b
	run.pulse = t
	events.append({"type": "beat"})
	events.append({"type": "sound", "name": "tick"})
	if b % 3 != 0:
		return
	var ring_ms: float = RING_MS / (run.intensity * run.pace)
	var soul: Vector2i = run.soul
	var epi := Vector2i(clampi(soul.x + rng.int_range(-1, 1), 0, Dodge.COLS - 1), clampi(soul.y + rng.int_range(-1, 1), 0, Dodge.ROWS - 1))
	# the cracks: rays from the epicentre whose squares never light
	var dir := _crack_dir(run, epi, soul, rng)
	var dark := {}
	for d in ([dir] if run.intensity >= CRACKS_ONE else [dir, -dir]):
		for j in range(1, Dodge.COLS):
			var c: Vector2i = epi + d * j
			if Dodge.in_box(c.x, c.y):
				dark[Dodge.index(c.x, c.y)] = true
	run.mem.stomps += 1
	print_verbose("quake: stomp %d at %s, crack %s, soul %s, t %d" % [run.mem.stomps, epi, dir, soul, t])
	var land := t + beat_ms * WARN_BEATS
	for k in RINGS:
		var cells := []
		for r in range(epi.y - k, epi.y + k + 1):
			for c in range(epi.x - k, epi.x + k + 1):
				if Dodge.in_box(c, r) and maxi(absi(c - epi.x), absi(r - epi.y)) == k and not dark.has(Dodge.index(c, r)):
					cells.append(Dodge.index(c, r))
		var extra := {"at": Dodge.index(epi.x, epi.y), "mark": "rock", "mark_warn": true} if k == 0 else {}
		run.add_hazard(t, cells, land + ring_ms * k - t, ring_ms, "stomp", extra)
