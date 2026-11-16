## Roll: boulders two cells wide roll across the box, one column (or, when fierce, row) at a time, each from the side the last
## one did not. Half are lined up with you. There is always a free lane: boulders on screen never cover every row or column.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const SPAWN_MS := 1100.0
const STEP_MS := 200.0 # how long a boulder takes over one cell
const AIMED := 0.5 # how often a boulder covers the soul's row (or column)
const FIERCE := 1.3 # from here every other boulder rolls down or up instead
const SHOWS_STEPS := 4.2
const SHOWS_MIN_MS := 340.0
const WIDTH := 2
const TRIES := 6


static func begin(run, _rng: Rng) -> void:
	run.mem = {"n": 0, "active": [], "flip": [false, false]} # active: {vertical, lane, until}
	print_verbose("roll: a boulder every %.0f ms, %.0f ms a cell" % [SPAWN_MS / (run.intensity * run.pace), STEP_MS / (run.intensity * run.pace)])


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	var ip: float = run.intensity * run.pace
	run.next_t = t + SPAWN_MS / ip
	var step := STEP_MS / ip
	var shows := maxf(SHOWS_STEPS * step, SHOWS_MIN_MS)
	var mem: Dictionary = run.mem
	var active: Array = mem.active.filter(func(a): return a.until > t)
	mem.active = active
	var vertical: bool = run.intensity >= FIERCE and mem.n % 2 == 1
	var lanes := _lanes_in_use(active, vertical)
	var size := Dodge.COLS if vertical else Dodge.ROWS
	var soul_lane: int = run.soul.x if vertical else run.soul.y
	var lane := -1
	for attempt in TRIES:
		var cand: int = clampi(soul_lane - rng.int_range(0, WIDTH - 1), 0, size - WIDTH) if attempt == 0 and rng.chance(AIMED) else rng.int_range(0, size - WIDTH)
		var covered := lanes.duplicate()
		for w in WIDTH:
			covered[cand + w] = true
		if covered.size() < size:
			lane = cand
			break
	if lane < 0:
		run.next_t = t + 200.0
		return
	mem.n += 1
	var which := 1 if vertical else 0
	mem.flip[which] = not mem.flip[which]
	var forward: bool = mem.flip[which]
	mem.active.append({"vertical": vertical, "lane": lane, "until": t + shows + size * step})
	for k in size:
		var along := k if forward else size - 1 - k
		var cells := []
		for w in WIDTH:
			cells.append(Dodge.index(lane + w, along) if vertical else Dodge.index(along, lane + w))
		var delay: float = shows + k * step
		var warn: float = delay * run.pace / run.WARN_BANDIT_SCALE if run.bandit_charm else delay * run.pace
		run.add_hazard(t, cells, warn, step, "rock", {"at": cells[0], "mark": "rock", "shows": shows})
	print_verbose("roll: a boulder on %s %d-%d rolls %s" % ["cols" if vertical else "rows", lane, lane + WIDTH - 1, "forward" if forward else "back"])


## The rows (or columns) boulders still on screen cover, as a dictionary used as a set.
static func _lanes_in_use(active: Array, vertical: bool) -> Dictionary:
	var out := {}
	for a in active:
		if a.vertical == vertical:
			for w in WIDTH:
				out[a.lane + w] = true
	return out
