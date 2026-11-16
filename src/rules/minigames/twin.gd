## Twin: two lanterns circle opposite each other and flare in turn. Each flare burns every square not in the shadow of a pillar
## from that lantern, so you hide behind a pillar from one and move to hide from the other. The pillars are laid out afresh
## each time: the best of a few layouts, one where every flare leaves shadow and the next flare's shadow is never far.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const FLARE_MS := 900.0 # between one lantern's flare and the other's
const FIRST_MS := 300.0
const WARN_MS := 850.0
const HIT_MS := 300.0
const STEP_MS := 200.0 # a person tapping an arrow five times a second
const WARN_STRETCH := [1.0, 1.25, 1.5] # how much longer a flare may warn when its shade is far from you
const MIN_SHADE := 6 # squares in shadow at every flare
const TRIES := 12 # layouts drawn at random, then as many tried by moving one pillar of the best
const FALLBACK := [Vector2i(2, 2), Vector2i(4, 4), Vector2i(5, 1), Vector2i(1, 4)]
const SPOT := Vector2i(3, 3) # where the soul starts
const SAMPLES_PER_CELL := 1.5 # the layout check walks each ray at this many steps per cell (Dodge.in_shadow is finer)
const FAIL := 9999
const EVERYWHERE := true


static func begin(run, rng: Rng) -> void:
	run.lanterns = [Dodge.LANTERN_START_ANGLE, Dodge.LANTERN_START_ANGLE + PI]
	var step: float = FLARE_MS / (run.intensity * run.pace)
	var lanterns := [] # where the lantern of each flare is when it lands
	var t: float = run.t0 + FIRST_MS
	while t < run.end_t:
		lanterns.append(Dodge.lantern_at(t + WARN_MS / run.pace - run.t0, run.intensity, run.lanterns[lanterns.size() % 2]))
		t += step
	var best := _random_layout(rng)
	var best_score := _stuck(best, lanterns)
	for i in TRIES * 2:
		var tried := _random_layout(rng) if i < TRIES else _moved(best, rng)
		var score := _stuck(tried, lanterns)
		if score < best_score:
			best = tried
			best_score = score
	if best_score >= FAIL: # none leaves enough shadow at every flare
		best = {}
		for p in FALLBACK:
			best[Dodge.index(p.x, p.y)] = true
	run.blocked = best
	run.mem = {"flares": 0}
	print_verbose("twin: %d pillars, %d flares %.0f ms apart, %s places to hide a step too far" % [best.size(), lanterns.size(), step, best_score if best_score < FAIL else "all"])


static func _random_layout(rng: Rng) -> Dictionary:
	var out := {}
	var want := rng.int_range(4, 5)
	while out.size() < want:
		var k := rng.int_range(0, Dodge.COLS * Dodge.ROWS - 1)
		if k != Dodge.index(SPOT.x, SPOT.y): # the soul starts here
			out[k] = true
	return out


## `layout` with one of its pillars somewhere else.
static func _moved(layout: Dictionary, rng: Rng) -> Dictionary:
	var out := layout.duplicate()
	out.erase(rng.pick(out.keys()))
	while out.size() < layout.size():
		var k := rng.int_range(0, Dodge.COLS * Dodge.ROWS - 1)
		if k != Dodge.index(SPOT.x, SPOT.y):
			out[k] = true
	return out


## The squares in shadow from `lantern`. Like Dodge.in_shadow, but each ray is walked in fewer steps, as this is asked for many
## layouts; the flares themselves use Dodge.in_shadow.
static func _shaded(lantern: Vector2, pillars: Dictionary) -> Array:
	var out := []
	for r in Dodge.ROWS:
		for c in Dodge.COLS:
			var k := Dodge.index(c, r)
			if pillars.has(k):
				continue
			var target := Vector2(c + 0.5, r + 0.5)
			var steps := int(lantern.distance_to(target) * SAMPLES_PER_CELL)
			for i in range(1, steps):
				var p := lantern + (target - lantern) * (float(i) / steps)
				var pk := Dodge.index(floori(p.x), floori(p.y))
				if Dodge.in_box(floori(p.x), floori(p.y)) and pillars.has(pk):
					out.append(k)
					break
	return out


## How badly a layout does over a dodge's flares (`lanterns`: where each one lights from): FAIL if some flare leaves too little
## shadow, else the number of hiding places, over all the flares, with no hiding place from the next flare within two steps
## (the soul starts on SPOT, which counts as one). Fewer is better.
static func _stuck(pillars: Dictionary, lanterns: Array) -> int:
	var stuck := 0
	var prev := [Dodge.index(SPOT.x, SPOT.y)]
	for lantern in lanterns:
		var dark := _shaded(lantern, pillars)
		if dark.size() < MIN_SHADE:
			return FAIL
		var close := {}
		for k in dark:
			close[k] = true
		var reach := _within(close, 2, pillars)
		for k in prev:
			if not reach.has(k):
				stuck += 1
		prev = dark if not EVERYWHERE else _open(pillars)
	return stuck


## Every square within `steps` steps of the squares in `from`, walking round the pillars.
static func _within(from: Dictionary, steps: int, pillars: Dictionary) -> Dictionary:
	var seen := from.duplicate()
	var edge: Array = from.keys()
	for _i in steps:
		var next := []
		for k in edge:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var c: int = k % Dodge.COLS + d.x
				var r: int = k / Dodge.COLS + d.y
				var n := Dodge.index(c, r)
				if Dodge.in_box(c, r) and not pillars.has(n) and not seen.has(n):
					seen[n] = true
					next.append(n)
		edge = next
	return seen


static func _open(pillars: Dictionary) -> Array:
	var out := []
	for k in Dodge.COLS * Dodge.ROWS:
		if not pillars.has(k):
			out.append(k)
	return out


static func spawn(run, t: float, _rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + FLARE_MS / (run.intensity * run.pace)
	var n: int = run.mem.flares
	run.mem.flares += 1
	# a flare whose shade is further from you than you can walk before it lands waits longer, so the lantern moves on and the
	# shade with it; one that still can't be reached is left out
	for stretch in WARN_STRETCH:
		var warn: float = WARN_MS * stretch
		var lantern := Dodge.lantern_at(t + warn / run.pace - run.t0, run.intensity, run.lanterns[n % 2])
		var cells := []
		for r in Dodge.ROWS:
			for c in Dodge.COLS:
				var k := Dodge.index(c, r)
				if not run.blocked.has(k) and not Dodge.in_shadow(lantern, c, r, run.blocked):
					cells.append(k)
		if _steps_to_shade(run, cells) * STEP_MS <= warn / run.pace:
			run.add_hazard(t, cells, warn, HIT_MS, "light", {"lantern": lantern})
			return
	print_verbose("twin: flare %d left out, no shade within reach of %s" % [n, run.soul])


## How many steps from the soul to the nearest square these `lit` squares leave dark (FAIL when there is none).
static func _steps_to_shade(run, lit: Array) -> int:
	var dark := {}
	for k in Dodge.COLS * Dodge.ROWS:
		if not run.blocked.has(k) and not lit.has(k):
			dark[k] = true
	var dist := {run.soul: 0}
	var queue := [run.soul]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if dark.has(Dodge.index(c.x, c.y)):
			return dist[c]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if Dodge.in_box(nb.x, nb.y) and not run.blocked.has(Dodge.index(nb.x, nb.y)) and not dist.has(nb):
				dist[nb] = dist[c] + 1
				queue.append(nb)
	return FAIL
