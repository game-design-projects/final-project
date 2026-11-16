## Brood: the mother's babies crawl in from the edge and hop toward you, hurting the square they sit on. After six hops a baby
## pops, lighting its square and the four around it. Only the next hop shows, and no two babies take the same square.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const ENTER_MS := 800.0 # between new babies
const HOP_MS := 560.0
const MAX_ALIVE := 3
const MAX_ALIVE_FIERCE := 4
const FIERCE := 1.3
const HOPS := 6
const MIN_START := 3 # a baby enters at least this many cells (Chebyshev) from the soul
const POP_WARN_MS := 450.0
const POP_HIT_MS := 250.0
const LEAD_HOPS := 1.3 # how many hops ahead a square is planned, and drawn
const SHOWS_MIN_MS := 360.0 # a hop is planned this far ahead at least, so a person sees it in time
const NEIGHBOURS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func begin(run, _rng: Rng) -> void:
	run.mem = {"babies": [], "taken": []} # taken: {cell, from, to} squares a baby has claimed
	print_verbose("brood: up to %d babies, a hop every %.0f ms" % [MAX_ALIVE_FIERCE if run.intensity >= FIERCE else MAX_ALIVE, HOP_MS / (run.intensity * run.pace)])


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	var ip: float = run.intensity * run.pace
	var hop := HOP_MS / ip
	var lead := maxf(hop * LEAD_HOPS, SHOWS_MIN_MS) # how far ahead a hop is planned, and drawn
	var mem: Dictionary = run.mem
	mem.babies = mem.babies.filter(func(b): return t < b.gone)
	mem.taken = mem.taken.filter(func(k): return k.to > t)
	var limit := MAX_ALIVE_FIERCE if run.intensity >= FIERCE else MAX_ALIVE
	if t >= run.next_t and mem.babies.size() < limit:
		var baby := _enter(run, t, rng, lead, hop)
		if not baby.is_empty():
			mem.babies.append(baby)
			run.next_t = t + ENTER_MS / ip
	for baby in mem.babies:
		while not baby.done and baby.next - t <= lead:
			_hop(run, t, baby, rng, hop, lead)


## A baby on a free edge cell; its first square arrives `lead` from now.
static func _enter(run, t: float, rng: Rng, lead: float, hop: float) -> Dictionary:
	var edge := []
	for c in Dodge.COLS:
		for r in Dodge.ROWS:
			var on_edge: bool = c == 0 or r == 0 or c == Dodge.COLS - 1 or r == Dodge.ROWS - 1
			if on_edge and maxi(absi(c - run.soul.x), absi(r - run.soul.y)) >= MIN_START and _free(run, Vector2i(c, r), t + lead, hop):
				edge.append(Vector2i(c, r))
	if edge.is_empty():
		return {}
	var cell: Vector2i = rng.pick(edge)
	var baby := {"cell": cell, "next": t + lead, "hops": -1, "done": false, "gone": INF}
	print_verbose("brood: a baby enters at %s" % cell)
	_lay(run, t, baby, cell, hop, lead)
	return baby


static func _free(run, c: Vector2i, from: float, hop: float) -> bool:
	if not Dodge.in_box(c.x, c.y):
		return false
	var k := Dodge.index(c.x, c.y)
	for taken in run.mem.taken:
		if taken.cell == k and taken.from < from + hop and from < taken.to:
			return false
	return true


## Plans the baby's next square (toward the soul, or the pop after its last hop).
static func _hop(run, t: float, baby: Dictionary, rng: Rng, hop: float, lead: float) -> void:
	if baby.hops >= HOPS:
		_pop(run, t, baby)
		return
	var from: Vector2i = baby.cell
	var dist: int = absi(from.x - run.soul.x) + absi(from.y - run.soul.y)
	var best := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = from + d
		if Dodge.in_box(c.x, c.y) and absi(c.x - run.soul.x) + absi(c.y - run.soul.y) < dist and _free(run, c, baby.next, hop):
			best.append(c)
	var cell: Vector2i = rng.pick(best) if not best.is_empty() else from # no free way nearer: it waits a hop
	_lay(run, t, baby, cell, hop, lead)


static func _lay(run, t: float, baby: Dictionary, cell: Vector2i, hop: float, lead: float) -> void:
	var k := Dodge.index(cell.x, cell.y)
	var delay: float = baby.next - t
	var warn: float = delay * run.pace / run.WARN_BANDIT_SCALE if run.bandit_charm else delay * run.pace
	run.add_hazard(t, [k], warn, hop, "goo", {"at": k, "mark": "ball", "shows": lead})
	run.mem.taken.append({"cell": k, "from": baby.next, "to": baby.next + hop})
	baby.cell = cell
	baby.hops += 1
	baby.next += hop


## The baby sits out its last square, then pops: its square and the four around it.
static func _pop(run, t: float, baby: Dictionary) -> void:
	var cells := []
	for d in NEIGHBOURS:
		var c: Vector2i = baby.cell + d
		if Dodge.in_box(c.x, c.y):
			cells.append(Dodge.index(c.x, c.y))
	var start: float = baby.next - t # the last square's hop has already been laid, the pop warns from its end
	run.add_hazard(t + start, cells, POP_WARN_MS, POP_HIT_MS, "blast")
	var scale: float = run.WARN_BANDIT_SCALE if run.bandit_charm else 1.0
	baby.done = true
	baby.gone = t + start + POP_WARN_MS * scale / run.pace + POP_HIT_MS
	print_verbose("brood: a baby pops at %s" % baby.cell)
