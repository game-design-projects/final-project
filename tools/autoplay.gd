## Plays whole games with no window, to see that a run can be played from the start to the stairs without stalling.
## A simple autopilot presses keys (walks to the nearest monster or the stairs, picks menu entries at random, dodges at
## random) while the clock runs in 16 ms frames. Nothing is saved or shown; it prints one line per game.
##   godot --headless --path . -s res://tools/autoplay.gd                  seeds 1..5, the local mind
##   godot --headless --path . -s res://tools/autoplay.gd -- seed=7 mock    one seed, the seeded random mind
## Exit code 0 when every game reached the stairs, 1 otherwise.
extends SceneTree

const Dodge = preload("res://src/rules/dodge.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const Minds = preload("res://src/mind/minds.gd")
const Rng = preload("res://src/utils/rng.gd")

const FRAME_MS := 16.0
const MAX_FRAMES := 200000 # ~53 minutes of game time
const DEFAULT_SEEDS := [1, 2, 3, 4, 5]
const PHRASES := ["hello friend", "where are the stairs?", "I will pay 6 gold", "what does the champion do?", "asdf jkl", "you are strong and wise", "haha funny joke", "please stop, I mean no harm"]
const ARROWS := ["up", "down", "left", "right"]

var _autopilot: Rng
var _stage_counts := {}
var _event_counts := {}
var _retries := 0


func _init() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray)
	var seeds: Array = DEFAULT_SEEDS
	var flagged := Rng.flag_seed("playing the default seeds")
	if flagged >= 0:
		seeds = [flagged]
	var failed := 0
	for s in seeds:
		if not await _play(int(s)):
			failed += 1
	print("autoplay: %d of %d games reached the stairs" % [seeds.size() - failed, seeds.size()])
	quit(1 if failed > 0 else 0)


func _play(seed_value: int) -> bool:
	var rng := Rng.new(seed_value)
	_autopilot = Rng.new(Rng.offset(seed_value, 1000))
	var flow = Flow.new(rng, Minds.create(rng))
	_stage_counts = {}
	_event_counts = {}
	_retries = 0
	flow.happened.connect(func(name, _data): _event_counts[name] = _event_counts.get(name, 0) + 1)
	await flow.new_run()
	var t := 0.0
	var frames := 0
	var left := false
	flow.happened.connect(func(name, _data): if name == "leave": left = true)
	while frames < MAX_FRAMES and flow.state.stage != "end" and not left:
		t += FRAME_MS
		frames += 1
		await flow.tick(t)
		await _press_something(flow)
		_stage_counts[flow.state.stage] = _stage_counts.get(flow.state.stage, 0) + 1
	var done: bool = flow.state.stage == "end"
	print("autoplay: seed %d %s after %.0f s of game time · spared %d slain %d fled %d recruited %d · HP %d/%d · retries %d" % [
		seed_value, "reached the stairs" if done else "DID NOT FINISH (stage %s)" % flow.state.stage, t / 1000.0,
		flow.state.tally.spared, flow.state.tally.slain, flow.state.tally.fled, flow.state.tally.recruited,
		flow.state.hp, flow.state.max_hp, _retries])
	print_verbose("autoplay: stages %s" % [_stage_counts])
	print_verbose("autoplay: events %s" % [_event_counts])
	return done


func _press_something(flow) -> void:
	if flow.busy:
		return
	var s = flow.state
	match s.stage:
		"explore":
			await flow.press(_explore_key(s))
		"menu", "act":
			if _autopilot.chance(0.08):
				var pool := [1, 2, 3, 4] if s.stage == "menu" else range(1, s.menu.size() + 1)
				if s.stage == "menu" and s.foe.boss:
					pool = [1, 1, 2, 2, 3]
				await flow.press(str(_autopilot.pick(pool)))
		"talk":
			await flow.submit_text(_autopilot.pick(PHRASES))
		"fightbar":
			var progress: float = (flow.clock - s.bar.t0) / s.bar.dur if s.bar != null else 0.0
			if progress > 0.46 and progress < 0.54:
				await flow.press("confirm")
		"dodge":
			var key := _dodge_key(s, flow.clock)
			if key != "":
				await flow.press(key)
		"result":
			await flow.press("confirm")
		"dead":
			_retries += 1
			await flow.press("1" if _retries <= 4 else "2")


## Step to the neighbouring cell (or stay) that the fewest hazards light now or soon. Returns "" to stay put.
func _dodge_key(s, t: float) -> String:
	var run = s.dodge
	if run == null:
		return ""
	var best_key := ""
	var best_score := 1 << 30
	for option in [["", Vector2i.ZERO], ["up", Vector2i(0, -1)], ["down", Vector2i(0, 1)], ["left", Vector2i(-1, 0)], ["right", Vector2i(1, 0)]]:
		var c: Vector2i = run.soul + option[1]
		if not Dodge.in_box(c.x, c.y) or run.blocked.has(Dodge.index(c.x, c.y)):
			continue
		var score := 0 if option[0] == "" else 1
		for h in run.hazards:
			if h.cells.has(Dodge.index(c.x, c.y)) and h.end > t:
				score += 100 if t >= h.hit else (10 if h.hit < t + 900.0 else 1)
		if score < best_score:
			best_score = score
			best_key = option[0]
	return best_key


## Turn toward and walk to the nearest monster that's still around (for the first two fights), then the stairs.
func _explore_key(s) -> String:
	var goal: Vector2i = s.floor_map.stairs
	var best := 1 << 30
	var met: int = s.tally.spared + s.tally.slain + s.tally.fled
	for m in s.floor_map.monsters:
		if met < 2 and not m.is_gone() and not m.boss:
			var d := absi(m.cell.x - s.cell.x) + absi(m.cell.y - s.cell.y)
			if d < best:
				best = d
				goal = m.cell
	var step := _first_step(s.floor_map, s.cell, goal)
	if step < 0:
		return "up"
	if s.facing == step:
		return "up"
	return "right" if (step - s.facing + 4) % 4 <= 2 else "left"


## The heading of the first step on the shortest way from `from` to `to`, or -1 if there is none.
func _first_step(floor_map, from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return -1
	var queue: Array = [from]
	var first := {from: -1}
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for i in 4:
			var next: Vector2i = at + FloorMap.DIRS[i]
			if not (floor_map.is_open(next) or next == to) or first.has(next):
				continue
			first[next] = i if at == from else first[at]
			if next == to:
				return first[next]
			queue.append(next)
	return -1
