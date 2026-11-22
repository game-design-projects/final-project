## How hard each attack is, and whether it is fair: a bot that reads every warning (and remembers the traps) plays each dodge over
## many seeds and intensities. It sees a hazard LATENCY_MS after it is drawn (a moving thing is drawn only `shows` before it lands),
## decides every DECIDE_MS, one step at a time, looking two steps ahead: about as fast as a person who knows the rule. Per attack
## and intensity it prints:
##   hits     mean hits per dodge for the quick bot (it knows every rule, so read them against each other)
##   slow     the same for a slower bot (SLOW_LATENCY_MS, SLOW_DECIDE_MS): closer to someone meeting the attack for the first time
##   clean    share of dodges with no hit
##   lit      mean share of open squares hurting at once
##   peak     the most open squares hurting at once, as a share
##   doomed   how often every square within two steps would hurt before the bot could get anywhere (should be 0)
##   blind    hazards on your square drawn less than REACT_MS before they hurt (should be 0)
##   quiet    the longest stretch with nothing warning or hurting, in ms (a long one is dead air)
## `only=a,b` limits it to those attacks, `seeds=N` sets how many (default 40), `csv=1` prints one CSV line per row, and
## `boss=1` plays it as a champion's attack: 6200 ms instead of 5400, at 1.2 times the intensity of a usual monster's at the
## same ask, so its rows print 1.2, 1.56 and 1.92 in `int` against a usual monster's 1.0, 1.3 and 1.6.
##
## `plan=timed` plays a bot that plans over time instead of two steps: it may stand still and step later, so a flare whose
## square stops hurting is not a wall it cannot cross, and each step is weighed in the slot it is taken in. `doomed` is then
## "the next two decisions leave no path that hurts nothing", the same local alarm as the two-step bot's, read with the
## timed bot's clock. Read a pattern the two-step bot finds hard with this bot: if it clears it, the pattern can be read by a
## player who waits, and the two-step `doomed` count is its own short sight, not a wall (#275).
##   godot --headless --path . -s res://tools/sim_dodge.gd -- nosave nosound [only=spit,bounce] [seeds=40] [boss=1] [plan=timed]
extends SceneTree

const Combat = preload("res://src/rules/combat.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const DodgeRun = preload("res://src/rules/dodge_run.gd")
const Flags = preload("res://src/utils/flags.gd")
const Rng = preload("res://src/utils/rng.gd")

const TICK_MS := 16.0
const DECIDE_MS := 160.0
const LATENCY_MS := 220.0 # how long after a warning is drawn the bot sees it
const SLOW_DECIDE_MS := 260.0
const SLOW_LATENCY_MS := 380.0
const REACT_MS := 300.0 # warning a person needs to see a square light and step off it
const INTENSITIES := [1.0, 1.3, 1.6]
const PLAN_SLOTS := 8 # how many decisions a plan=timed bot looks ahead, each one `decide` long
const TRAP_SLOTS := 2 # how many of them make a decision "doomed": no path over these hurts nothing
const MINI := ["gates", "stars", "dance"] # mini-games, not attacks: measured too, but the stars and pads heal


func _init() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray)
	var seeds := int(Flags.value("seeds")) if Flags.value("seeds") != "" else 40
	var only: Array = Array(Flags.value("only").split(",", false)) if Flags.value("only") != "" else []
	var genres: Array = DodgeRun.MINI_GAMES.keys()
	genres.sort()
	if not only.is_empty():
		genres = genres.filter(func(g): return only.has(g))
	var csv := Flags.value("csv") == "1"
	var boss := Flags.value("boss") == "1"
	var timed := Flags.value("plan") == "timed"
	if csv:
		print("genre,intensity,hits,slow,clean,lit,peak,doomed,blind,quiet")
	else:
		print("attack     | int  | hits | slow | clean | lit  | peak | doomed | blind | quiet ms")
		if timed:
			print("plan: timed (the bot may wait, then step; doomed is the next two decisions)")
	var failed := false
	for g in genres:
		for intensity in INTENSITIES:
			# a champion's dodge is denser than a usual monster's at the same ask: print the intensity the run really has
			var actual := _shown(Combat.dodge_intensity(_pressure(intensity), boss))
			var r := _measure(g, intensity, boss, seeds, LATENCY_MS, DECIDE_MS, timed)
			var slow: float = _measure(g, intensity, boss, seeds, SLOW_LATENCY_MS, SLOW_DECIDE_MS, timed).hits
			if csv:
				print("%s,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d" % [g, actual, r.hits, slow, r.clean, r.lit, r.peak, r.doomed, r.blind, r.quiet])
			else:
				print("%-10s | %4s | %4.2f | %4.2f | %4.0f%% | %3.0f%% | %3.0f%% | %6d | %5d | %d" % [g, actual, r.hits, slow, r.clean * 100.0, r.lit * 100.0, r.peak * 100.0, r.doomed, r.blind, r.quiet])
			if r.hazards == 0 and not MINI.has(g):
				print("  %s makes no hazards at all" % g)
				failed = true
	quit(1 if failed else 0)


func _measure(genre: String, intensity: float, boss: bool, seeds: int, latency: float, decide: float, timed: bool) -> Dictionary:
	var hits := 0
	var clean := 0
	var lit_sum := 0.0
	var lit_n := 0
	var peak := 0.0
	var doomed := 0
	var blind := 0
	var quiet := 0.0
	var hazards := 0
	for i in seeds:
		var rng := Rng.new(1000 + i)
		var run = DodgeRun.start(genre, _pressure(intensity), boss, i % 3, 0.0, {}, 1.0, {})
		var t := 0.0
		var next_decide := 0.0
		var got := 0
		var last_busy := 0.0
		while not run.is_over(t):
			for e in run.update(t, rng):
				if e.type == "hurt":
					got += 1
			for h in run.hazards:
				if not h.has("_counted"):
					h._counted = true
					hazards += 1
				if not h.has("_drawn") and t >= _drawn_from(h):
					h._drawn = true
					if h.cells.has(Dodge.index(run.soul.x, run.soul.y)) and h.hit - t < REACT_MS and not DodgeRun.CATCHES.has(h.kind):
						blind += 1
			var open := 0
			var live := {}
			for k in Dodge.COLS * Dodge.ROWS:
				if not run.blocked.has(k):
					open += 1
			for h in run.hazards:
				if t >= h.hit and t < h.end and not DodgeRun.CATCHES.has(h.kind):
					for k in h.cells:
						live[k] = true
			var share := float(live.size()) / maxf(1.0, open)
			lit_sum += share
			lit_n += 1
			peak = maxf(peak, share)
			if not run.hazards.is_empty():
				quiet = maxf(quiet, t - last_busy)
				last_busy = t
			if t >= next_decide:
				next_decide = t + decide
				var plan := _plan_timed(run, t, latency, decide) if timed else _plan(run, t, latency, decide)
				if plan.doomed:
					doomed += 1
				if plan.step != Vector2i.ZERO:
					run.move(-plan.step.x if run.mirror else plan.step.x, -plan.step.y if run.mirror else plan.step.y)
			t += TICK_MS
		quiet = maxf(quiet, t - last_busy)
		hits += got
		if got == 0:
			clean += 1
	return {"hits": float(hits) / seeds, "clean": float(clean) / seeds, "lit": lit_sum / maxf(1.0, lit_n), "peak": peak, "doomed": doomed, "blind": blind, "quiet": int(quiet), "hazards": hazards}


## The pressure that gives a usual monster's dodge this intensity (Combat.dodge_intensity is 0.8 + 0.25 * pressure); at the
## same pressure a champion's run is a fifth denser, so the table prints the intensity the run got rather than the ask.
static func _pressure(intensity: float) -> float:
	return (intensity - 0.8) / 0.25


## An intensity as the table shows it: 1.2, 1.56, 1.0 (a champion's fall off the tenths).
static func _shown(intensity: float) -> String:
	var out: String = "%.2f" % intensity
	return out.trim_suffix("0") if out.ends_with("0") else out


## The bot's next step: the first step of the safest two-step path (staying put counts as a step), and whether every path hurts.
func _plan(run, t: float, latency: float, decide: float) -> Dictionary:
	var best := INF
	var best_step := Vector2i.ZERO
	var steps := [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for a in steps:
		var c1: Vector2i = run.soul + a
		if not _open(run, c1):
			continue
		var cost1 := _danger(run, c1, t, t + decide, latency)
		for b in steps:
			var c2: Vector2i = c1 + b
			if not _open(run, c2):
				continue
			var cost: float = cost1 * 2.0 + _danger(run, c2, t + decide, t + decide * 3.0, latency, t) + (0.01 if a != Vector2i.ZERO else 0.0) + (0.005 if b != Vector2i.ZERO else 0.0)
			if cost < best:
				best = cost
				best_step = a
	return {"step": best_step, "doomed": best >= 1.0}


## A bot that plans over time: the cheapest path over PLAN_SLOTS decisions, each weighed in the slot it is taken in, standing
## still allowed. A hazard that has stopped hurting before the bot would stand somewhere is not counted against it, which is
## what the two-step bot's single window cannot say. `doomed` stays a local alarm: the next TRAP_SLOTS decisions, not the
## whole plan, must have no path that hurts nothing.
func _plan_timed(run, t: float, latency: float, decide: float) -> Dictionary:
	var danger: Array = []
	for s in PLAN_SLOTS:
		danger.append(_slot_danger(run, t + s * decide, decide, latency, t))
	# best[s][k]: the cheapest way to the end of the plan, standing at k in slot s. Filled from the back.
	var best: Array = []
	best.resize(PLAN_SLOTS)
	var last := {}
	for k in _open_indices(run):
		last[k] = float(danger[PLAN_SLOTS - 1].get(k, 0))
	best[PLAN_SLOTS - 1] = last
	for s in range(PLAN_SLOTS - 2, -1, -1):
		var here := {}
		for k in _open_indices(run):
			var cheapest := INF
			for n in _neighbours(k):
				if not run.blocked.has(n) and best[s + 1].has(n):
					cheapest = minf(cheapest, float(best[s + 1][n]))
			if cheapest < INF:
				here[k] = float(danger[s].get(k, 0)) + cheapest
		best[s] = here
	var best_cost := INF
	var best_step := Vector2i.ZERO
	var best_trap := INF
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c1: Vector2i = run.soul + d
		if not _open(run, c1):
			continue
		var k1 := Dodge.index(c1.x, c1.y)
		var cost := float(danger[0].get(k1, 0)) + float(best[1][k1])
		if cost < best_cost:
			best_cost = cost
			best_step = d
		best_trap = minf(best_trap, _short_cost(run, danger, k1))
	return {"step": best_step, "doomed": best_trap >= 1.0}


## The cheapest path over TRAP_SLOTS decisions after standing at `start` in the first: what the local alarm reads.
func _short_cost(run, danger: Array, start: int) -> float:
	var cur := {start: float(danger[0].get(start, 0))}
	for s in range(1, TRAP_SLOTS):
		var nxt := {}
		for k in cur:
			for n in _neighbours(k):
				if run.blocked.has(n):
					continue
				var v: float = cur[k] + float(danger[s].get(n, 0))
				if not nxt.has(n) or v < nxt[n]:
					nxt[n] = v
		cur = nxt
	var best := INF
	for k in cur:
		best = minf(best, cur[k])
	return best


## Which squares a known hazard would hurt, and when, in the slot [from, from + width): {square: how many hazards}.
func _slot_danger(run, from: float, width: float, latency: float, now: float) -> Dictionary:
	var out := {}
	var to := minf(from + width, run.end_t)
	if from >= run.end_t:
		return out
	for h in run.hazards:
		if DodgeRun.CATCHES.has(h.kind) or now < _drawn_from(h) + latency:
			continue
		if h.hit >= run.end_t:
			continue # it lands after the dodge is over
		if h.hit < to and h.end > from:
			for k in h.cells:
				out[int(k)] = int(out.get(int(k), 0)) + 1
	return out


func _open_indices(run) -> Array:
	var out := []
	for k in Dodge.COLS * Dodge.ROWS:
		if not run.blocked.has(k):
			out.append(k)
	return out


## A square and its four neighbours, inside the box.
static func _neighbours(k: int) -> Array:
	var c: int = k % Dodge.COLS
	var r: int = k / Dodge.COLS
	var out := [k]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Dodge.in_box(c + d.x, r + d.y):
			out.append(Dodge.index(c + d.x, r + d.y))
	return out


func _open(run, c: Vector2i) -> bool:
	return Dodge.in_box(c.x, c.y) and not run.blocked.has(Dodge.index(c.x, c.y))


## How many hazards the bot knows of would hurt on cell `c` between `from` and `to` (it remembers a trap once seen).
## `now` is when the bot is looking (it can't see later warnings yet); by default `from`.
func _danger(run, c: Vector2i, from: float, to: float, latency: float, now := -1.0) -> float:
	var looking := from if now < 0.0 else now
	var k := Dodge.index(c.x, c.y)
	var out := 0.0
	for h in run.hazards:
		if DodgeRun.CATCHES.has(h.kind) or looking < _drawn_from(h) + latency:
			continue
		if h.cells.has(k) and h.hit < to and h.end > from:
			out += 1.0
	return out


## When a hazard first shows on the screen.
static func _drawn_from(h: Dictionary) -> float:
	return maxf(h.warn, h.hit - float(h.shows)) if h.has("shows") else h.warn
