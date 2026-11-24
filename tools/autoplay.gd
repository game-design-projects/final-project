## Plays whole games with no window, to see that a run can be played from the start to the stairs without stalling.
## A simple autopilot presses keys (takes the floor's favour and finishes it, walks to the monster it chose for the first two
## fights, keeping it until it is gone, then the stairs; takes SPARE for the kin a spare favour names and picks the rest of the
## menu at random, dodges at random) while the clock runs in 16 ms frames. With `clan-requests` (the default) it also takes the
## clans' askers' requests and does them (#259): it says the line an asker wants, fights a favour's fight the way it asks
## (no light strike for a heavy_win, a spare for a friend to bring, the dragon asked, the kind to slay struck), hands over the
## friend or the gold, takes an open teleporter at the stairs and hears the lord out in its hall.
## Nothing is saved or shown; it prints one line per game.
##   godot --headless --path . -s res://tools/autoplay.gd                  seeds 1..5, the local mind
##   godot --headless --path . -s res://tools/autoplay.gd -- seed=7 mock    one seed, the seeded random mind
##   godot --headless --path . -s res://tools/autoplay.gd -- practice       each game starts on the practice floor
## Exit code 0 when every game reached the stairs, 1 otherwise.
extends SceneTree

const Clans = preload("res://src/rules/clans.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const Envoys = preload("res://src/rules/envoys.gd")
const Fault = preload("res://src/utils/fault.gd")
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
## What it types to an asker or a dragon, by what the request listens for (mind/words.gd `sounds_like`): a hiss long enough,
## flat words that repeat and end on a full stop, a question about liking slimes.
const ERRAND_FRAMES := 3600 # about a minute of the fight menu being up: a favour's fight is then played as a usual one, so a foe that will not be won its way cannot hold the game
const SAYS := {"hiss": "hisssssssss", "monotone": "the stone is still and the stone is grey.", "likes_slimes": "do dragons like slimes?"}

var _autopilot: Rng
var _stage_counts := {}
var _event_counts := {}
var _retries := 0
var _met_floor := 1 # the floor the two fights are counted on
var _goal_monster = null # the monster this floor's walk is committed to; null walks to the stairs
var _met_before := 0 # how many it had met before that floor
var _tried := {} # pacifist: ACT -> how far it moved the odds, for this foe
var _fled := {} # fight-only: this game's monsters it has already fled from once, so it fights rather than fleeing for ever
var _attack_menus := 0 # fight-only: the fight menus this game took, printed so the roads test can see the road ran
var _tried_foe = null
var _envoy_seen := {} # "depth|hall|clan" -> how its requests stood the last time it stood at that asker, so it goes back only when that changed
var _errand_foe = null # the foe a favour's fight is being played against, and how many frames its fight menu has been up
var _errand_frames := 0
var _says := "" # what the request it just took or is finishing at the asker listens for (envoy_say types it)
var _last_try := -1
var _mercy_before := 0.0


func _init() -> void:
	Fault.watch()
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave"])) # its games never reach the player's saves or store
	var seeds: Array = DEFAULT_SEEDS
	var flagged := Rng.flag_seed("playing the default seeds")
	if flagged >= 0:
		seeds = [flagged]
	var failed := 0
	for s in seeds:
		if not await _play(int(s)):
			failed += 1
	print("autoplay: %d of %d games reached the stairs" % [seeds.size() - failed, seeds.size()])
	# a debug build fails fast: a game that reached the stairs over a script error in any part of the game is not a pass
	var tripped := Fault.script_errors()
	if tripped > 0:
		print("autoplay: FAIL %d script error(s) while playing, the first at %s" % [tripped, Fault.first_script_error()])
	quit(1 if failed > 0 or tripped > 0 else 0)


func _play(seed_value: int) -> bool:
	var rng := Rng.new(seed_value)
	_autopilot = Rng.new(Rng.offset(seed_value, 1000))
	var flow = Flow.new(rng, Minds.create(rng))
	_stage_counts = {}
	_event_counts = {}
	_retries = 0
	_met_floor = 1
	_met_before = 0
	_goal_monster = null
	_fled = {} # once per game: a name fled in one game says nothing about the next one's monsters
	_attack_menus = 0
	_envoy_seen = {}
	_says = ""
	_errand_foe = null
	_errand_frames = 0
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
	print("autoplay: seed %d %s after %.0f s of game time · spared %d slain %d fled %d recruited %d · HP %d/%d · LVL %d · lords %d sworn %d · retries %d" % [
		seed_value, "reached the last stairs on B%dF" % flow.state.depth if done else "DID NOT FINISH (stage %s)" % flow.state.stage, t / 1000.0,
		flow.state.tally.spared, flow.state.tally.slain, flow.state.tally.fled, flow.state.tally.recruited,
		flow.state.hp, flow.state.max_hp, flow.state.level(), flow.state.lords_met.size(), flow.state.lords_sworn.size(), _retries])
	if Flags.on("fight-only"):
		print("autoplay: attack-only seed %d took the fight menu %d times" % [seed_value, _attack_menus])
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
		"trade":
			await flow.press("cancel")
		"envoy":
			await flow.press(_envoy_key(flow))
		"envoy_say":
			if SAYS.has(_says):
				print("autoplay: says \"%s\" to the asker" % SAYS[_says])
				await flow.submit_text(SAYS[_says])
			else:
				await flow.press("cancel")
		"request":
			# the first choice accepts the favour (or hands it over, or leaves when it has failed), so a whole game now asks,
			# does and is paid: the request and the lords' favours were only ever asked and dropped before
			await flow.press("1")
		"keepsake":
			await flow.press(str(_autopilot.int_range(1, s.menu.size())))
		"menu", "act":
			# the attack-only road (`fight-only`): the bar, HEAVY when it is on offer, and FLEE at a quarter of the health,
			# which is what a player who never talks but wants to live would do. It says nothing and spares nobody (#163)
			if Flags.on("fight-only") and s.stage == "menu":
				_attack_menus += 1
				var heavy_at := _menu_key(s, "HEAVY")
				if float(s.hp) / float(s.max_hp) < 0.25 and not s.foe.boss and not _fled.has(s.foe.name):
					_fled[s.foe.name] = true # once per monster: a hunter that follows step for step would be fled from for ever
					await flow.press("4")
				elif heavy_at > 0 and _autopilot.chance(0.25):
					await flow.press(str(heavy_at))
				else:
					await flow.press("1")
				return
			# a monster a favour named to be spared is worth more alive: take SPARE whenever it is on offer, so that favour is
			# finished the way it asks (the pilot used to kill it and fail the request)
			var spare_at := _spare_index(s) if s.stage == "menu" else 0
			var errand := _errand_fight(flow)
			if spare_at > 0:
				await flow.press(str(spare_at))
			elif errand == "ask":
				# a request sent it to ask this dragon something: ACT, then SAY SOMETHING (the act menu's last row)
				await flow.press("2" if s.stage == "menu" else str(s.menu.size()))
			elif errand == "strike" and s.stage == "act":
				await flow.press("cancel") # back to the fight menu, to strike
			elif errand == "strike" and _autopilot.chance(0.08):
				await flow.press("1")
			elif errand == "still" and _autopilot.chance(0.08):
				# no light strike in this fight: ACT until SPARE is likely, then SPARE (the peaceful pilot's way)
				if s.stage == "act":
					await flow.press(str(_kindest_act(flow)))
				else:
					await flow.press(str(_peaceful_menu_key(s)))
			elif errand != "":
				pass # a favour's fight waits its turn rather than taking a random row
			elif _autopilot.chance(0.08) and Flags.on("pacifist") and s.stage == "act":
				await flow.press(str(_kindest_act(flow)))
			elif _autopilot.chance(0.08):
				var pool := [1, 2, 3, 4] if s.stage == "menu" else range(1, s.menu.size() + 1)
				if s.stage == "menu" and s.foe.boss:
					pool = [1, 1, 2, 2, 3]
				if s.stage == "menu" and Flags.on("pacifist"):
					pool = [_peaceful_menu_key(s)]
				await flow.press(str(_autopilot.pick(pool)))
		"social":
			# The peaceful pilot preserves recruitment; normal play samples real responses and Ignore.
			await flow.press("5" if Flags.on("pacifist") or _errand_fight(flow) == "still" else str(_autopilot.pick([1, 2, 3, 5])))
		"skills":
			if _autopilot.chance(0.08): # skill-combat: any skill that can be used now, END TURN once none can
				var ready := range(1, s.menu.size()).filter(func(i): return not s.menu[i - 1].get("disabled", false))
				await flow.press(str(_autopilot.pick(ready) if not ready.is_empty() else s.menu.size()))
		"ask":
			await flow.press("1") # COME ALONG, or GO IN PEACE with a full party
		"end":
			# the shut door's first answer is TURN BACK: with nobody left to befriend that would go round for ever
			await flow.press("2" if s.menu[0].label == "TURN BACK" else str(_hall_way(s)))
		"talk":
			var asked: Dictionary = Envoys.to_ask(s, s.foe) if flow.feature("clan-requests") and s.foe != null else {}
			await flow.submit_text(str(SAYS.get(str(asked.get("sounds", "")), _autopilot.pick(PHRASES))))
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
	if run.mirror: # the box says MIRRORED: press the other way to go this way
		return {"up": "down", "down": "up", "left": "right", "right": "left"}.get(best_key, best_key)
	return best_key


## Turn toward and walk to the nearest monster that's still around (for the first two fights), then the stairs. The
## monster is kept for the floor once chosen: picking the nearest every step made two monsters in opposite directions
## alternate, each step making the other the nearer one, so the walk stood still (seeds 313, 357, 362, 415, 451, 454).
func _explore_key(s) -> String:
	var all_met: int = s.tally.spared + s.tally.slain + s.tally.fled
	if _met_floor != s.depth:
		_met_floor = s.depth
		_met_before = all_met
		_goal_monster = null
	var met: int = all_met - _met_before
	if met >= 2 or (_goal_monster != null and _goal_monster.is_gone()):
		_goal_monster = null # the stairs: two monsters met on this floor, or the one walked to is gone
	if met < 2 and _goal_monster == null and s.visiting == "": # in a clan's hall nobody fights: walking into one only gets a line
		var best := 1 << 30
		for m in s.floor_map.monsters:
			if not m.is_gone() and not m.boss:
				var d := absi(m.cell.x - s.cell.x) + absi(m.cell.y - s.cell.y)
				if d < best:
					best = d
					_goal_monster = m
	# a favour it took: go and finish it (the thing it wants, or the monster it named), so the paid path is played too
	var quest := _envoy_goal(s)
	if quest == Vector2i(-1, -1):
		quest = _quest_goal(s)
	var goal: Vector2i = quest if quest != Vector2i(-1, -1) else (s.floor_map.stairs if _goal_monster == null else _goal_monster.cell)
	var step := _first_step(s.floor_map, s.cell, goal)
	if step < 0 and _goal_monster != null: # walled off from it: the stairs are the floor's one sure way on
		_goal_monster = null
		step = _first_step(s.floor_map, s.cell, s.floor_map.stairs)
	if step < 0:
		return "up"
	if s.facing == step:
		return "up"
	return "right" if (step - s.facing + 4) % 4 <= 2 else "left"


## The key that picks a menu row by its label, or 0 when the menu does not have it (or has it greyed out).
func _menu_key(s, label: String) -> int:
	for n in s.menu.size():
		if str(s.menu[n].label) == label and not s.menu[n].get("disabled", false):
			return n + 1
	return 0


## A fight without a strike: take SPARE when it is usable and the odds are good, otherwise ACT.
func _peaceful_menu_key(s) -> int:
	var spare := _menu_key(s, "SPARE")
	return spare if spare > 0 and s.menu[spare - 1].get("gold", false) else _menu_key(s, "ACT")


## The menu number of SPARE when this foe is the kin a favour wants spared and SPARE can be taken, else 0.
func _spare_index(s) -> int:
	var q: Dictionary = s.floor_map.quester
	if q.is_empty() or not q.get("taken", false) or str(q.get("kind", "")) != "spare" or s.foe == null:
		return 0
	var i := int(q.get("target", -1))
	if i < 0 or i >= s.floor_map.monsters.size() or s.floor_map.monsters[i] != s.foe:
		return 0
	for n in s.menu.size():
		if str(s.menu[n].label) == "SPARE" and not s.menu[n].get("disabled", false):
			return n + 1
	return 0


## Where to go for the favour it has taken, or (-1, -1) when there is none to do here.
func _quest_goal(s) -> Vector2i:
	var q: Dictionary = s.floor_map.quester
	if q.is_empty():
		return Vector2i(-1, -1)
	if not q.get("taken", false):
		# it has not been asked on this floor yet: walk up to it, and the request stage accepts on the first key. The name being
		# known from an earlier floor does not count — a lord met on B1 asks its second favour when its biome comes back, and the
		# pilot used to skip it there, so the pact was never reached in a played game
		return q.cell
	if str(q.kind) == "fetch":
		if s.items.has(str(q.want)):
			return q.cell # in the bag already: bring it back
		for p in s.floor_map.pickups:
			if str(p.item) == str(q.want):
				return p.cell
		return Vector2i(-1, -1)
	var i := int(q.get("target", -1))
	if i < 0 or i >= s.floor_map.monsters.size():
		return Vector2i(-1, -1)
	var m = s.floor_map.monsters[i]
	if m.is_gone():
		return q.cell # the one it named is off the floor: the asker is who pays, not the empty cell
	return m.cell


## Where a clan's asker on this floor has something for it to do (a request to take, a friend or the gold to hand over, a line
## to say), or its lord in its hall has not been heard out: that cell, or (-1, -1). An asker it has stood at is gone back to only
## once how its requests stand has changed since, so a request it cannot finish yet does not hold the walk at its feet.
func _envoy_goal(s) -> Vector2i:
	if not Flags.enabled("clan-requests"):
		return Vector2i(-1, -1)
	for e in s.floor_map.envoys:
		if e.get("lord", false):
			if not s.lords_met.has(str(e.clan)):
				return e.cell
			continue
		var stands := _envoy_stands(s, str(e.clan))
		if (stands.contains("new") or stands.contains("ready")) and _envoy_seen.get(_envoy_key_of(s, str(e.clan)), "") != stands:
			return e.cell
	return Vector2i(-1, -1)


func _envoy_key_of(s, clan: String) -> String:
	return "%d|%s|%s" % [s.depth, s.visiting, clan]


## How a clan's open requests stand, in the asker's menu order: "new,ready,waiting".
func _envoy_stands(s, clan: String) -> String:
	return ",".join(Envoys.open_for(s, clan).map(func(r): return Envoys.status(s, r)))


## At a clan's asker: the first row that takes a request, says its line or hands its friend or gold over, or Esc when there is
## none. The lord in its hall: the first row, which hears it out to the end and then leaves.
func _envoy_key(flow) -> String:
	var s = flow.state
	var who: Dictionary = s.floor_map.envoy_at(s.cell + FloorMap.DIRS[s.facing])
	if who.is_empty() or who.get("lord", false):
		return "1"
	var clan := str(who.clan)
	_envoy_seen[_envoy_key_of(s, clan)] = _envoy_stands(s, clan)
	var open := Envoys.open_for(s, clan) # the stage lists these, each request a row, in this order (stages/envoy.gd)
	for i in open.size():
		var now := Envoys.status(s, open[i])
		if now == "new" or now == "ready":
			_says = str(open[i].get("sounds", ""))
			print("autoplay: at %s, %s %s" % [who.name, "takes" if now == "new" else "finishes", open[i].id])
			return str(i + 1)
	return "cancel"


## How the request it has taken wants this fight played: "ask" (say the dragon its question), "still" (no light strike: a
## heavy_win, or a friend of the kind a bring wants), "strike" (the kind a slay counts), or "" for none. An enraged foe takes
## no mercy, so it is never fought still; the peaceful road never strikes; and a fight whose menu has been up for ERRAND_FRAMES
## frames is played as a usual one.
func _errand_fight(flow) -> String:
	var s = flow.state
	var m = s.foe
	if m == null or not flow.feature("clan-requests") or Flags.on("fight-only"):
		return ""
	if _errand_foe != m:
		_errand_foe = m
		_errand_frames = 0
	if s.stage == "menu":
		_errand_frames += 1
	if _errand_frames > ERRAND_FRAMES:
		return ""
	if not m.spoke and not Envoys.to_ask(s, m).is_empty():
		return "ask"
	for clan in Envoys.clans():
		for r in Envoys.open_for(s, str(clan)):
			if not Envoys.is_taken(s, str(r.id)):
				continue
			match str(r.kind):
				"heavy_win":
					if int(m.strikes.get("light", 0)) == 0 and not Clans.enraged(s, m):
						return "still"
				"bring":
					if str(m.species) == str(r.species) and Envoys.friend_for(s, r) == null and not Clans.enraged(s, m):
						return "still"
				"slay":
					if str(m.species) == str(r.species) and not Flags.on("pacifist"):
						return "strike"
	return ""


## The stairs' row to take: an open teleporter to a clan's hall when there is one, else the first way down.
func _hall_way(s) -> int:
	for clan in Envoys.ways(s):
		var label := str(Envoys.way(str(clan)).label)
		for n in s.menu.size():
			if str(s.menu[n].label) == label:
				print("autoplay: takes %s" % label)
				return n + 1
	return 1


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
