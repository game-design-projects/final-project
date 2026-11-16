## Bounce: a gumdrop ricochets round the box one diagonal step at a time, and where it hits a wall it squashes and lights its two
## neighbours along that wall. A second gumdrop joins after a couple of seconds (at once when it is fierce). Each ball's path is
## planned a few steps ahead and only the next two steps show (view/overlay.gd).
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const STEP_MS := 260.0 # how long a gumdrop takes over one cell
const SECOND_MS := 2200.0 # when the second one joins, unless the attack is fierce
const FIERCE := 1.3
const MIN_START := 3 # a gumdrop starts at least this many cells (Chebyshev) from the soul
const SHOWS_STEPS := 2.0
const SHOWS_MIN_MS := 340.0 # a person needs this long to see a square and step off it
const PLAN_STEPS := 3.0 # each path is planned at least this far ahead


static func begin(run, _rng: Rng) -> void:
	var launches := [run.t0, run.t0 if run.intensity >= FIERCE else run.t0 + SECOND_MS]
	run.mem = {"balls": [], "launches": launches}
	print_verbose("bounce: %d gumdrops, the second at +%d ms, step %.0f ms" % [launches.size(), int(launches[1] - run.t0), STEP_MS / (run.intensity * run.pace)])


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	var step: float = STEP_MS / (run.intensity * run.pace)
	var shows := maxf(SHOWS_STEPS * step, SHOWS_MIN_MS)
	var launches: Array = run.mem.launches
	while not launches.is_empty() and t >= launches[0]:
		launches.remove_at(0)
		run.mem.balls.append(_launch(run, t, rng, shows))
	for ball in run.mem.balls:
		while ball.due <= t + PLAN_STEPS * step:
			_plan(run, t, ball, step, shows)


static func _launch(run, t: float, rng: Rng, shows: float) -> Dictionary:
	var edge := []
	for c in Dodge.COLS:
		for r in Dodge.ROWS:
			var on_edge: bool = c == 0 or r == 0 or c == Dodge.COLS - 1 or r == Dodge.ROWS - 1
			if on_edge and maxi(absi(c - run.soul.x), absi(r - run.soul.y)) >= MIN_START:
				edge.append(Vector2i(c, r))
	var cell: Vector2i = rng.pick(edge)
	var vel := Vector2i(_inward(cell.x, Dodge.COLS, rng), _inward(cell.y, Dodge.ROWS, rng))
	print_verbose("bounce: a gumdrop enters at %s heading %s" % [cell, vel])
	return {"cell": cell, "vel": vel, "due": t + shows}


## +1 or -1 along one axis: away from the wall it stands on, else either way.
static func _inward(v: int, size: int, rng: Rng) -> int:
	if v == 0:
		return 1
	if v == size - 1:
		return -1
	return 1 if rng.chance(0.5) else -1


## Adds the hazard for the ball's next cell (and, on a wall, its squashed neighbours), then moves the plan on one step.
static func _plan(run, t: float, ball: Dictionary, step: float, shows: float) -> void:
	var cell: Vector2i = ball.cell
	var vel: Vector2i = ball.vel
	var cells := [Dodge.index(cell.x, cell.y)]
	var hit_x := not Dodge.in_box(cell.x + vel.x, cell.y)
	var hit_y := not Dodge.in_box(cell.x, cell.y + vel.y)
	var squash := []
	if hit_x:
		squash.append_array([Vector2i(cell.x, cell.y - 1), Vector2i(cell.x, cell.y + 1)])
	if hit_y:
		squash.append_array([Vector2i(cell.x - 1, cell.y), Vector2i(cell.x + 1, cell.y)])
	for s in squash:
		if Dodge.in_box(s.x, s.y):
			cells.append(Dodge.index(s.x, s.y))
	var warn: float = (ball.due - t) * run.pace / run.WARN_BANDIT_SCALE if run.bandit_charm else (ball.due - t) * run.pace
	run.add_hazard(t, cells, warn, step, "goo", {"at": cells[0], "mark": "ball", "shows": shows})
	if hit_x:
		vel.x = -vel.x
	if hit_y:
		vel.y = -vel.y
	ball.vel = vel
	ball.cell = cell + vel
	ball.due += step
