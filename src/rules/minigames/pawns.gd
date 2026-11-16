## Pawns: a rank of pawns marches down the box one row a beat. Each one takes its own square and the two diagonals in front of
## it, shown a beat ahead. When a rank has gone, the next comes a beat later; when it is hard they alternate down and up.
## Every beat leaves at least two safe squares in each row the rank touches.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const BEAT_MS := 600.0
const COUNT := 4
const COUNT_HARD := 5 # from intensity 1.3
const MIN_SAFE := 2 # safe squares left in each row a rank touches
const HIT_BEATS := 0.45 # a rank hurts for this much of a beat, so there is a gap to step across between two
const GAP_BEATS := 0 # between one rank and the next
const BANDIT_SCALE := 1.3 # the bandit charm stretches every warning (dodge_run.gd); the warning is cut back so the rank still lands on the beat


static func begin(run, _rng: Rng) -> void:
	run.mem = {"row": -1, "cols": [], "dir": 1, "ranks": 0, "wait": 0}
	print_verbose("pawns: beat %d ms" % (BEAT_MS / sqrt(run.intensity * run.pace)))


static func spawn(run, t: float, rng: Rng, events: Array) -> void:
	var beat_ms := BEAT_MS / sqrt(run.intensity * run.pace)
	var b := floori((t - run.t0) / beat_ms)
	if b <= run.beat:
		return
	run.beat = b
	run.pulse = t
	events.append({"type": "beat"})
	events.append({"type": "sound", "name": "tick"})
	var mem: Dictionary = run.mem
	var hard: bool = run.intensity >= 1.3
	if mem.row < 0:
		if mem.wait > 0:
			mem.wait -= 1
			return
		# a new rank: down from the top, or (when hard, every other rank) up from the bottom
		mem.dir = -1 if hard and mem.ranks % 2 == 1 else 1
		mem.ranks += 1
		mem.row = 0 if mem.dir == 1 else Dodge.ROWS - 1
		mem.cols = _columns(rng, COUNT_HARD if hard else COUNT)
		print_verbose("pawns: rank %d goes %s on columns %s" % [mem.ranks, "down" if mem.dir == 1 else "up", mem.cols])
	var row: int = mem.row
	var dir: int = mem.dir
	# the squares one beat from now: the pawns' own and the two in front of each
	for c in mem.cols:
		var cells := [Dodge.index(c, row)]
		for side in [-1, 1]:
			if Dodge.in_box(c + side, row + dir):
				cells.append(Dodge.index(c + side, row + dir))
		run.add_hazard(t, cells, beat_ms * run.pace / (BANDIT_SCALE if run.bandit_charm else 1.0), beat_ms * HIT_BEATS, "chess", {"glyph": "P", "at": Dodge.index(c, row), "dir": Vector2i(0, dir)})
	mem.row += dir
	if mem.row < 0 or mem.row >= Dodge.ROWS:
		mem.row = -1
		mem.wait = GAP_BEATS


## `count` distinct columns for a rank, such that the two rows it touches keep MIN_SAFE safe squares each. A rank that also leaves a
## column open in the row ahead of it (not under a pawn or its diagonals) is taken when one turns up.
static func _columns(rng: Rng, count: int) -> Array:
	var best := []
	var best_free := -1
	for attempt in 40:
		var cols := range(Dodge.COLS)
		rng.shuffle(cols)
		cols = cols.slice(0, count)
		var free := _free(cols)
		if free > best_free and Dodge.COLS - _ahead(cols).size() >= MIN_SAFE:
			best = cols
			best_free = free
		if best_free >= 1:
			break
	if best.is_empty(): # never happens with 4 or 5 pawns of 7, but never leave a rank empty
		best = range(count)
	best.sort()
	return best


static func _ahead(cols: Array) -> Dictionary:
	var ahead := {}
	for c in cols:
		for side in [-1, 1]:
			if c + side >= 0 and c + side < Dodge.COLS:
				ahead[c + side] = true
	return ahead


## Columns that are neither a pawn's nor on a pawn's diagonal: a place to wait in the row ahead.
static func _free(cols: Array) -> int:
	var ahead := _ahead(cols)
	var n := 0
	for c in Dodge.COLS:
		if not cols.has(c) and not ahead.has(c):
			n += 1
	return n
