## Crossfire: a lookout fires volleys of bolts, a row's worth one time and a column's the next. Each bolt is aimed at where you
## stand when its warning starts, so keep moving; the arrow shows the side it comes from.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const VOLLEY_MS := 1300.0
const GAP_MS := 280.0 # between the bolts of a volley
const BOLTS := 3
const BOLTS_FIERCE := 4
const FIERCE := 1.3
const WARN_MS := 600.0
const HIT_MS := 200.0


static func begin(run, _rng: Rng) -> void:
	run.mem = {"n": 0, "queue": []} # queue: {at, horizontal} bolts still to aim
	print_verbose("crossfire: a volley of %d every %.0f ms" % [BOLTS_FIERCE if run.intensity >= FIERCE else BOLTS, VOLLEY_MS / (run.intensity * run.pace)])


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	var ip: float = run.intensity * run.pace
	if t >= run.next_t:
		run.next_t = t + VOLLEY_MS * _jitter(rng) / ip
		var horizontal: bool = run.mem.n % 2 == 0
		run.mem.n += 1
		var lanes := [] # the lanes this volley has lit so far
		var at := t
		for k in (BOLTS_FIERCE if run.intensity >= FIERCE else BOLTS):
			run.mem.queue.append({"at": at, "horizontal": horizontal, "lanes": lanes})
			at += GAP_MS * _jitter(rng) / ip
	var queue: Array = run.mem.queue
	while not queue.is_empty() and t >= queue[0].at:
		_fire(run, t, queue.pop_front(), rng)


static func _fire(run, t: float, bolt: Dictionary, rng: Rng) -> void:
	var horizontal: bool = bolt.horizontal
	var lane: int = run.soul.y if horizontal else run.soul.x
	var lit: Array = bolt.lanes
	# a bolt beside one still to land would catch you stepping out of it, so it is held back (the same lane again is harmless)
	if not lit.has(lane) and (lit.has(lane - 1) or lit.has(lane + 1)):
		return
	lit.append(lane)
	var from_start := rng.chance(0.5) # enters from the left (or top) edge, else the right (or bottom)
	var cells: Array = Dodge.row_cells(lane) if horizontal else Dodge.col_cells(lane)
	var edge := Vector2i(0 if from_start else Dodge.COLS - 1, lane) if horizontal else Vector2i(lane, 0 if from_start else Dodge.ROWS - 1)
	var dir := Vector2i(1 if from_start else -1, 0) if horizontal else Vector2i(0, 1 if from_start else -1)
	run.add_hazard(t, cells, WARN_MS, HIT_MS, "bolt", {"at": Dodge.index(edge.x, edge.y), "mark": "arrow", "dir": dir, "mark_warn": true})
	print_verbose("crossfire: a bolt on %s %d from %s" % ["row" if horizontal else "col", lane, edge])


## A little give in the timing (0.8 to 1.2 times), so no two volleys are the same.
static func _jitter(rng: Rng) -> float:
	return 0.8 + 0.4 * rng.real()
