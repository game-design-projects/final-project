## Slither: an adder crawls through the box, steering toward you but only seeing where you were two steps ago. Its head and its
## whole body hurt; the body stays lit for as long as the snake is long. When it traps itself it slides away and a new one comes.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const STEP_MS := 340.0 # how long the head takes over one cell
const LENGTH := 4
const LENGTH_FIERCE := 5
const FIERCE := 1.3
const CHASE := 0.5 # how often a step brings the head closer to the soul; else any legal step
const MIN_START := 3 # the head enters at least this many cells (Chebyshev) from the soul
const REENTER_MS := 600.0 # after the last head cell before a new snake's first
const SHOWS_STEPS := 2.0
const SHOWS_MIN_MS := 340.0
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func begin(run, _rng: Rng) -> void:
	var length := LENGTH_FIERCE if run.intensity >= FIERCE else LENGTH
	run.mem = {"snake": {}, "restart": run.t0 + 700.0, "length": length}
	print_verbose("slither: snake of %d, %.0f ms a step" % [length, STEP_MS / (run.intensity * run.pace)])


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	var step: float = STEP_MS / (run.intensity * run.pace)
	var shows := maxf(SHOWS_STEPS * step, SHOWS_MIN_MS)
	var mem: Dictionary = run.mem
	if mem.snake.is_empty():
		if mem.restart - t > shows:
			return
		mem.snake = _enter(run, rng, mem.restart)
	var snake: Dictionary = mem.snake
	while snake.next - t <= shows:
		var move := _next(run, snake, rng, mem.length)
		if move.is_empty():
			print_verbose("slither: the snake is stuck after %d cells and leaves" % snake.path.size())
			mem.restart = snake.next - step + REENTER_MS
			mem.snake = {}
			return
		_lay(run, t, snake, move, step, shows, mem.length)


## A new snake whose first head cell (on the edge) arrives at `at`.
static func _enter(run, rng: Rng, at: float) -> Dictionary:
	var edge := []
	for c in Dodge.COLS:
		for r in Dodge.ROWS:
			var on_edge: bool = c == 0 or r == 0 or c == Dodge.COLS - 1 or r == Dodge.ROWS - 1
			if on_edge and maxi(absi(c - run.soul.x), absi(r - run.soul.y)) >= MIN_START:
				edge.append(Vector2i(c, r))
	var cell: Vector2i = rng.pick(edge)
	var inward := []
	if cell.x == 0:
		inward.append(Vector2i(1, 0))
	if cell.x == Dodge.COLS - 1:
		inward.append(Vector2i(-1, 0))
	if cell.y == 0:
		inward.append(Vector2i(0, 1))
	if cell.y == Dodge.ROWS - 1:
		inward.append(Vector2i(0, -1))
	var dir: Vector2i = rng.pick(inward)
	print_verbose("slither: a snake enters at %s heading %s" % [cell, dir])
	return {"path": [], "dir": dir, "next": at, "first": cell}


## The head's next cell and direction, or {} when it has nowhere to go.
static func _next(run, snake: Dictionary, rng: Rng, length: int) -> Dictionary:
	var path: Array = snake.path
	if path.is_empty():
		return {"cell": snake.first, "dir": snake.dir}
	var head: Vector2i = path[-1]
	var body: Array = path.slice(maxi(0, path.size() - (length - 1)))
	var legal := []
	for d in DIRS:
		if d == -snake.dir:
			continue
		var c: Vector2i = head + d
		if Dodge.in_box(c.x, c.y) and not body.has(c):
			legal.append({"cell": c, "dir": d})
	if legal.is_empty():
		return {}
	if rng.chance(CHASE):
		var best := []
		var best_d := 1 << 20
		for m in legal:
			var dist: int = absi(m.cell.x - run.soul.x) + absi(m.cell.y - run.soul.y)
			if dist < best_d:
				best_d = dist
				best = [m]
			elif dist == best_d:
				best.append(m)
		if best_d < absi(head.x - run.soul.x) + absi(head.y - run.soul.y):
			return rng.pick(best)
	return rng.pick(legal)


static func _lay(run, t: float, snake: Dictionary, move: Dictionary, step: float, shows: float, length: int) -> void:
	var cell: Vector2i = move.cell
	var k := Dodge.index(cell.x, cell.y)
	var arrive: float = snake.next
	run.add_hazard(t, [k], _warn(run, arrive - t), step, "venom", {"at": k, "mark": "head", "dir": move.dir, "shows": shows})
	run.add_hazard(t, [k], _warn(run, arrive + step - t), (length - 1) * step, "venom", {"shows": shows + step})
	snake.path.append(cell)
	snake.dir = move.dir
	snake.next = arrive + step


static func _warn(run, delay: float) -> float:
	return delay * run.pace / run.WARN_BANDIT_SCALE if run.bandit_charm else delay * run.pace
