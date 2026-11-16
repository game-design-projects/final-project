## Spit: a glob is spat down a lane, one cell at a time, from the end farther from you. Often it is your own row or column; now and
## then two lanes side by side. Only the next few cells show. Two globs never cross your square close together.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const VOLLEY_MS := 900.0
const STEP_MS := 215.0 # how long a glob takes over one cell
const AIMED := 0.6 # how often a volley's first lane is the soul's own row or column
const DOUBLE := 0.35 # how often a volley fires two lanes side by side
const SHOWS_STEPS := 3.75
const SHOWS_MIN_MS := 340.0
const CLOSE_MS := 400.0 # two globs may not pass the soul's square this close together
const TRIES := 6


static func begin(run, _rng: Rng) -> void:
	run.mem = {"passes": []} # [cell, hit time] of every glob cell planned
	print_verbose("spit: a volley every %.0f ms, %.0f ms a cell" % [VOLLEY_MS / (run.intensity * run.pace), STEP_MS / (run.intensity * run.pace)])


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	var ip: float = run.intensity * run.pace
	run.next_t = t + VOLLEY_MS * (0.8 + 0.4 * rng.real()) / ip # a little give, so no two volleys are alike
	var step := STEP_MS / ip
	var shows := maxf(SHOWS_STEPS * step, SHOWS_MIN_MS)
	var passes: Array = run.mem.passes
	passes = passes.filter(func(p): return p[1] > t - CLOSE_MS)
	run.mem.passes = passes
	var lanes := []
	for attempt in TRIES:
		var lane := _lane(run, rng, attempt == 0 and rng.chance(AIMED) or attempt > 0 and rng.chance(AIMED * 0.5))
		if not _clashes(run, lane, t + shows, step, passes):
			lanes.append(lane)
			break
	if lanes.is_empty():
		run.next_t = t + 150.0
		return
	if rng.chance(DOUBLE):
		var first: Dictionary = lanes[0]
		for off in rng.shuffle([-2, -1, 1, 2]):
			var idx: int = first.index + off
			var limit: int = Dodge.ROWS if first.horizontal else Dodge.COLS
			if idx < 0 or idx >= limit:
				continue
			var second := _lane_at(run, first.horizontal, idx, rng)
			if not _clashes(run, second, t + shows, step, passes):
				lanes.append(second)
				break
	for lane in lanes:
		_fire(run, t, lane, step, shows, passes)
	print_verbose("spit: %d lane(s) %s" % [lanes.size(), lanes.map(func(l): return ("row %d" if l.horizontal else "col %d") % l.index)])


static func _lane(run, rng: Rng, aimed: bool) -> Dictionary:
	var horizontal := rng.chance(0.5)
	if aimed:
		return _lane_at(run, horizontal, run.soul.y if horizontal else run.soul.x, rng)
	return _lane_at(run, horizontal, rng.int_range(0, (Dodge.ROWS if horizontal else Dodge.COLS) - 1), rng)


## A lane starting from the end farther from the soul (along that lane).
static func _lane_at(run, horizontal: bool, index: int, rng: Rng) -> Dictionary:
	var along: int = run.soul.x if horizontal else run.soul.y
	var size := Dodge.COLS if horizontal else Dodge.ROWS
	var mid := floori((size - 1) / 2.0)
	var forward: bool = along > mid if along != mid else rng.chance(0.5) # heading + when the soul is on the far end
	var dir := Vector2i(1, 0) if horizontal else Vector2i(0, 1)
	return {"horizontal": horizontal, "index": index, "dir": dir if forward else -dir, "forward": forward, "size": size}


static func _cell(lane: Dictionary, k: int) -> Vector2i:
	var along: int = k if lane.forward else lane.size - 1 - k
	return Vector2i(along, lane.index) if lane.horizontal else Vector2i(lane.index, along)


## Whether the glob would pass the soul's cell within CLOSE_MS of another one planned.
static func _clashes(run, lane: Dictionary, first_hit: float, step: float, passes: Array) -> bool:
	for k in lane.size:
		var c := _cell(lane, k)
		if c != run.soul:
			continue
		var when: float = first_hit + k * step
		var here := Dodge.index(c.x, c.y)
		for p in passes:
			if p[0] == here and absf(p[1] - when) < CLOSE_MS:
				return true
	return false


static func _fire(run, t: float, lane: Dictionary, step: float, shows: float, passes: Array) -> void:
	for k in lane.size:
		var c := _cell(lane, k)
		var cell := Dodge.index(c.x, c.y)
		var delay: float = shows + k * step
		var warn: float = delay * run.pace / run.WARN_BANDIT_SCALE if run.bandit_charm else delay * run.pace
		run.add_hazard(t, [cell], warn, step, "goo", {"at": cell, "mark": "ball", "dir": lane.dir, "shows": shows})
		passes.append([cell, t + delay])
