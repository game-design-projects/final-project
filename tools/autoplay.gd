## Plays whole games with no window, to see that a run can be played from the start to the stairs without stalling.
## A simple autopilot presses keys (walks to the nearest monster or the stairs, picks menu entries at random, dodges at
## random) while the clock runs in 16 ms frames. Nothing is saved or shown; it prints one line per game.
##   godot --headless --path . -s res://tools/autoplay.gd                  seeds 1..5, the local mind
##   godot --headless --path . -s res://tools/autoplay.gd -- seed=7 mock    one seed, the seeded random mind
##   godot --headless --path . -s res://tools/autoplay.gd -- practice       each game starts on the practice floor
## Exit code 0 when every game reached the stairs, 1 otherwise.
extends SceneTree

const Dodge = preload("res://src/rules/dodge.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Flags = preload("res://src/utils/flags.gd")
const Items = preload("res://src/rules/items.gd")
const Survival = preload("res://src/rules/survival.gd")
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
var _met_floor := 1 # the floor the two fights are counted on
var _met_before := 0 # how many it had met before that floor
var _tried := {} # pacifist: ACT -> how far it moved the odds, for this foe
var _tried_foe = null
var _last_try := -1
var _mercy_before := 0.0


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
	_met_floor = 1
	_met_before = 0
	flow.happened.connect(func(name, _data): _event_counts[name] = _event_counts.get(name, 0) + 1)
	await flow.new_run(Flags.on("practice"))
	var t := 0.0
	var frames := 0
	var left := false
	flow.happened.connect(func(name, _data): if name == "leave": left = true)
	while frames < MAX_FRAMES and not (flow.state.stage == "end" and flow.state.run_over) and not left:
		t += FRAME_MS
		frames += 1
		await flow.tick(t)
		await _press_something(flow)
		_stage_counts[flow.state.stage] = _stage_counts.get(flow.state.stage, 0) + 1
	var done: bool = flow.state.stage == "end" and flow.state.run_over
	print("autoplay: seed %d %s after %.0f s of game time · spared %d slain %d fled %d recruited %d · HP %d/%d · retries %d" % [
		seed_value, "reached the last stairs on B%dF" % flow.state.depth if done else "DID NOT FINISH (stage %s)" % flow.state.stage, t / 1000.0,
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
		"intro", "wait":
			if s.hint == "ANY KEY CONTINUE":
				await flow.press("confirm")
		"explore":
			if Survival.stage_of(s.hunger) != "" and s.items.any(func(id): return str(Items.info(id).kind) == "food"):
				await flow.press("confirm")
			else:
				await flow.press(_explore_key(s))
		"camp":
			# food is listed first, then the party (to feed or butcher), and LEAVE last: it eats what there is, then gets up. Taking "1" with no
			# food left would ask to butcher a friend, answer NO, and ask again for as long as the game lasts.
			await flow.press("1" if str(s.menu[0].label).begins_with("EAT") else "cancel")
		"trade", "request":
			await flow.press("cancel")
		"menu", "act":
			if _autopilot.chance(0.08) and Flags.on("pacifist") and s.stage == "act":
				await flow.press(str(_kindest_act(flow)))
			elif _autopilot.chance(0.08):
				var pool := [1, 2, 3, 4] if s.stage == "menu" else range(1, s.menu.size() + 1)
				if s.stage == "menu" and s.foe.boss:
					pool = [1, 1, 2, 2, 3]
				if s.stage == "menu" and Flags.on("pacifist"):
					pool = [3] if s.menu[2].get("gold", false) else [2]
				await flow.press(str(_autopilot.pick(pool)))
		"social":
			# The peaceful pilot preserves recruitment; normal play samples real responses and Ignore.
			await flow.press("5" if Flags.on("pacifist") else str(_autopilot.pick([1, 2, 3, 5])))
		"skills":
			if _autopilot.chance(0.08): # skill-combat: any skill that can be used now, END TURN once none can
				var ready := range(1, s.menu.size()).filter(func(i): return not s.menu[i - 1].get("disabled", false))
				await flow.press(str(_autopilot.pick(ready) if not ready.is_empty() else s.menu.size()))
		"ask":
			await flow.press("1") # COME ALONG, or GO IN PEACE with a full party
		"end":
			# the shut door's first answer is TURN BACK: with nobody left to befriend that would go round for ever
			await flow.press("2" if s.menu[0].label == "TURN BACK" else "1")
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
		"dead":
			_retries += 1
			await flow.press("1") # a new run would lose the floors already walked


## What a player learns from the mercy gauge: try each ACT once, then keep to the one that moved the odds most (a key to press).
func _kindest_act(flow) -> int:
	var s = flow.state
	if _last_try >= 0:
		_tried[_last_try] = flow.encounter.known_mercy - _mercy_before
	if _tried_foe != s.foe:
		_tried_foe = s.foe
		_tried = {}
	_mercy_before = flow.encounter.known_mercy
	var options := []
	for i in range(1, s.menu.size() - 1): # past CHECK, and short of SAY SOMETHING
		if s.menu[i].sub == "": # a gold offer has a tip, and ends the fight with no friend
			options.append(i)
	var best: int = options[0]
	for i in options:
		if not _tried.has(i):
			_last_try = i
			return i + 1
		if _tried[i] > _tried[best]:
			best = i
	_last_try = best
	return best + 1


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
			if h.kind != "star" and h.cells.has(Dodge.index(c.x, c.y)) and h.end > t:
				score += 100 if t >= h.hit else (10 if h.hit < t + 900.0 else 1)
		if score < best_score:
			best_score = score
			best_key = option[0]
	return best_key


## Turn toward and walk to the nearest monster that's still around (for the first two fights), then the stairs.
func _explore_key(s) -> String:
	var goal: Vector2i = s.floor_map.stairs
	var best := 1 << 30
	var all_met: int = s.tally.spared + s.tally.slain + s.tally.fled
	if _met_floor != s.depth:
		_met_floor = s.depth
		_met_before = all_met
	var met: int = all_met - _met_before
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
			if not (floor_map.is_open(next) or next == to) or first.has(next) or (next != to and floor_map.in_the_way(next)):
				continue
			first[next] = i if at == from else first[at]
			if next == to:
				return first[next]
			queue.append(next)
	return -1
