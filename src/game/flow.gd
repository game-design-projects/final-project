## Runs a game: one state, one stage at a time, moves between stages checked against transitions.gd. Nothing here draws
## or plays a sound; the picture reads `state` and the sound listens to `event`. Time comes in from outside (`tick`), so
## a headless run can drive the whole game by calling `press` and `tick`.
##
## `press`, `tick` and `submit_text` may take time while a mind answers; callers can `await` them or ignore that, and
## input is dropped while one is still working (`busy`).
extends RefCounted

const Ally = preload("res://src/game/ally.gd")
const Clans = preload("res://src/rules/clans.gd")
const Coach = preload("res://src/game/coach.gd")
const Content = preload("res://src/rules/content.gd")
const Trophies = preload("res://src/game/trophies.gd")
const Dice = preload("res://src/utils/dice.gd")
const Encounter = preload("res://src/game/encounter.gd")
const Events = preload("res://src/game/events.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const Flags = preload("res://src/utils/flags.gd")
const Floors = preload("res://src/rules/floors.gd")
const Items = preload("res://src/rules/items.gd")
const Legacy = preload("res://src/rules/legacy.gd")
const Practice = preload("res://src/rules/practice.gd")
const Requests = preload("res://src/rules/requests.gd")
const Rng = preload("res://src/utils/rng.gd")
const Skills = preload("res://src/rules/skills.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")
const Survival = preload("res://src/rules/survival.gd")
const Transitions = preload("res://src/game/transitions.gd")
const Vision = preload("res://src/rules/vision.gd")
const Warmth = preload("res://src/rules/warmth.gd")

## The features the picture and the HUD show, which they read from the state (see State.views).
const VIEW_FEATURES := ["dungeon-reveal", "roaming", "wick"]
const BANNER_MS := 3000.0
const WICK_LOYALTY := 75.0
const DOOR_THEN_WICK_MS := 3000.0 # the words about the door, with a friend on her way
const WICK_BANNER_MS := 4500.0
const WARMTH_TITLE := "THE HALLS"
const WALK_HEAL_STEPS := 6
const AFTER_FIGHT_MS := 350.0 # how long keys do nothing once a fight is over
const DIALOGUE_BUFFER_MS := 300.0
const STORY_BANNER_MS := 6000.0
const PRACTICE_SEEN := "practice" # its id among the tips seen

const STAGES := {
	"social": preload("res://src/game/stages/social.gd"),
	"explore": preload("res://src/game/stages/explore.gd"),
	"intro": preload("res://src/game/stages/intro.gd"),
	"menu": preload("res://src/game/stages/menu.gd"),
	"ask": preload("res://src/game/stages/ask.gd"),
	"act": preload("res://src/game/stages/act.gd"),
	"items": preload("res://src/game/stages/items.gd"),
	"skills": preload("res://src/game/stages/skills.gd"),
	"trade": preload("res://src/game/stages/trade.gd"),
	"camp": preload("res://src/game/stages/camp.gd"),
	"request": preload("res://src/game/stages/request.gd"),
	"talk": preload("res://src/game/stages/talk.gd"),
	"fightbar": preload("res://src/game/stages/fightbar.gd"),
	"wait": preload("res://src/game/stages/wait.gd"),
	"dodge": preload("res://src/game/stages/dodge.gd"),
	"dead": preload("res://src/game/stages/dead.gd"),
	"end": preload("res://src/game/stages/end.gd"),
}

## Something happened that the picture or the sound should react to (see events.gd). Emit with `event()`, which checks
## the name and fields first.
signal happened(name: String, data: Dictionary)

var state # State
var rng
## Where the chances of an interaction are drawn (see dice.gd); a test may pin it.
var dice: Dice
var mind
var encounter
## The game clock in ms, as last given to `tick`.
var clock := 0.0
var busy := false
## The setting EASY DODGE, which the scene hands in: the game doesn't read settings itself.
var coach # the first-time tips
var trophies # the achievements
## The boons bought between runs (boon id -> rank), which the scene hands in: the game doesn't read what is kept itself.
var legacy_ranks := {}
var easy_dodge := false
## The monsters still to fight, back to back, with no walk between (the social-demo playtest). A new floor, a load or fleeing
## clears it.
var fight_queue: Array = []

var _stages := {}
var _since := 0.0 # clock when the current stage began
var _wick_comes := false # a new run: she is on her way, and her words wait for the ones up now
var film_seen := false # the opening film (menu/intro_cg.gd) showed her to the end: she needn't hop in again, and her words follow it
var _teach_walk := false # on the practice floor: Wick says how to walk once her welcome is gone
var _keys_back_at := -1.0 # keys do nothing until the clock says this, once a fight is over
var repeating := false # the key being handled is one repeating by itself, not one just pressed
var _held_over := false # a key still held from the fight stays dropped until something is pressed afresh


func _init(game_rng, game_mind) -> void:
	rng = game_rng
	dice = Dice.new(game_rng)
	mind = game_mind
	encounter = Encounter.new(self)
	coach = Coach.new(self)
	trophies = Trophies.new(self)
	for name in STAGES:
		_stages[name] = STAGES[name].new()
	state = State.new()


## Whether a feature is on for this game (flags.gd).
func feature(name: String) -> bool:
	return Flags.enabled(name)


## A fresh run: a new floor, standing at its start. With `practice` (the scene asks for it until it has been played once) and
## the tips on, the run starts on the practice floor above B1F (rules/practice.gd).
func new_run(practice := false) -> void:
	await _leave_current()
	fight_queue = []
	state = State.new()
	state.depth = maxi(1, int(Flags.value("floor", "1")))
	state.run_seed = rng.seed_value
	state.practice = practice and practice_allowed()
	if state.practice:
		coach.seen[PRACTICE_SEEN] = true
		event("coach", {"id": PRACTICE_SEEN}) # the scene remembers it with the tips, so SHOW THE TIPS AGAIN brings it back
	_apply_features()
	if feature("legacy"):
		Legacy.apply(state, legacy_ranks)
	if feature("wick"):
		_meet_wick()
	_make_floor()
	encounter.pending_notes = []
	encounter.pending_rows = []
	print("flow: new run, seed %d%s" % [rng.seed_value, ", on the practice floor" if state.practice else ""])
	event("state_replaced", {"how": "new"})
	var lines := _arrival()
	var premise: Dictionary = Floors.premise()
	lines = [State.sys_line(premise.line), lines[0]] # the log has room for two: why you are here says more than where
	announce(premise.title, premise.door if feature("last-door") else premise.banner, DOOR_THEN_WICK_MS if feature("wick") else STORY_BANNER_MS)
	if feature("wick"):
		_wick_comes = true
		_teach_walk = state.practice
	await go("explore", {"lines": lines})


## Whether a run may start on the practice floor: it needs floors to go down to and the tips to teach it, and a run told to start
## deeper (`floor=N`) or to meet a given species (`meet=`) skips it.
func practice_allowed() -> bool:
	if Flags.on("notips"):
		return false
	if Flags.value("floor") != "" or Flags.value("meet") != "" or Flags.on("social-demo"):
		print("flow: no practice floor, the flags ask for another start")
		return false
	return true


## She reaches you as the words about the door fade: alone, and then not.
func _wick_arrives() -> void:
	if not _wick_comes or banner_up() or not state.has_ally("witch"):
		return
	_wick_comes = false
	var friend: Dictionary = Floors.friend()
	announce(friend.title, friend.line_film if film_seen else friend.line, WICK_BANNER_MS)
	film_seen = false
	state.say(state.lines.slice(-1) + [State.sys_line(friend.joined)]) # the log has room for two


## On the practice floor she is the one who teaches: first how to walk, as soon as her welcome is gone (the tips after it come from
## coach.gd, in her voice).
func _wick_teaches() -> void:
	if not _teach_walk or banner_up() or _wick_comes:
		return
	_teach_walk = false
	if state.practice:
		coach.say("walk")


## Your first friend: she is in the party from the first moment, and leaves the way any of them does.
func _meet_wick() -> void:
	var wick: Dictionary = Content.table("friends").witch
	state.allies.append(Ally.make("witch", str(wick.name), WICK_LOYALTY))
	print("flow: Wick joins, loyalty %.0f" % WICK_LOYALTY)


## Take the stairs: the next floor of this run, keeping health, gold, allies and the tally, with a rest on the way down. `way` is
## which way down was chosen (Floors.paths), if there was a choice.
func next_floor(way := {}) -> void:
	await _leave_current()
	if state.practice: # its stairs lead to B1F, and the run starts there whole
		state.practice = false
		state.hp = state.max_hp
	else:
		state.depth = mini(state.depth + 1, State.DEPTH_MAX)
	state.foe = null
	state.hp = mini(state.max_hp, state.hp + Floors.rest_heal() + int(way.get("rest", 0)))
	state.gold += int(way.get("gold", 0))
	Survival.rest(state)
	_make_floor(way)
	encounter.pending_notes = []
	encounter.pending_rows = []
	print("flow: down to B%dF (%s)" % [state.depth, state.summary()])
	event("state_replaced", {"how": "floor"})
	var biome: Dictionary = Floors.biome_named(state.floor_map.biome)
	if not biome.is_empty():
		announce(biome.name, biome.line)
	if Floors.is_last(state.depth):
		event("reached_last")
	await go("explore", {"lines": _arrival()})


## This run is over for good: at the last stairs, or given up after a fall. What it earned in all (0 without the feature legacy). The scene
## pays it; a run left and loaded again pays only what is new.
func close_run(cleared: bool) -> int:
	if not feature("legacy"):
		return 0
	var embers := Legacy.earned(state, cleared)
	print("flow: run closed, %d embers" % embers)
	event("run_closed", {"embers": embers})
	return embers


## What the views read from the state rather than ask the flags.
func _apply_features() -> void:
	state.rotate_mini_games = true
	state.floors_of = Floors.run_floors()
	for name in VIEW_FEATURES:
		state.views[name] = feature(name)
	if feature("skill-combat") and state.skills.is_empty(): # a new run, or a save from before: the starting skills
		state.skills = Skills.start()


## What the log says on arriving on this floor.
func _arrival() -> Array:
	if state.practice:
		return [State.sys_line(Practice.line("line"))]
	var lines := [State.sys_line(Texts.floor_story(state.depth, Floors.run_floors(), Floors.plan(state.depth).champion))]
	var biome: Dictionary = Floors.biome_named(state.floor_map.biome)
	if not biome.is_empty():
		lines.append(State.sys_line(biome.line))
	var senders := elites_from(state.floor_map)
	if not senders.is_empty():
		lines.append(State.sys_line(str(Clans.elite().arrival) % " and ".join(senders.map(func(c): return Clans.title(c)))))
	return lines


## The clans that sent elites to this floor, in the order their elites stand.
static func elites_from(floor_map) -> Array:
	var out := []
	for m in floor_map.monsters:
		var clan := Clans.of(m.species)
		if m.elite and not out.has(clan):
			out.append(clan)
	return out


## The clans furious with you send their elites to a floor made now: its monsters of their kinds (never the champion) are
## tougher and hit harder. A floor made earlier keeps who it had, and so does a save.
func _send_elites() -> void:
	var scale := float(Clans.elite().hp_scale)
	for m in state.floor_map.monsters:
		if not m.boss and Clans.sends_elites(state, m.species):
			m.become_elite(scale)
	var senders := elites_from(state.floor_map)
	if not senders.is_empty():
		print("flow: B%dF has %d elites, sent by %s" % [state.depth, state.floor_map.monsters.filter(func(m): return m.elite).size(), ", ".join(senders)])


## The floor for `state.depth`, with the party at its start.
func _make_floor(way := {}) -> void:
	if state.practice:
		state.floor_map = Practice.make(Rng.new(Floors.floor_seed(state.run_seed, 0, Practice.SEED)))
	else:
		var floor_rng = Rng.new(Floors.floor_seed(state.run_seed, state.depth, int(way.get("path", 0))))
		var plan: Dictionary = Floors.plan(state.depth, way)
		plan.boss_at_exit = true
		plan.biome = Floors.biome(state.run_seed, state.depth)
		plan.secrets = Floors.secrets(plan.get("biome", {}))
		plan.items = true
		plan.food = true
		plan.shop = Items.shop_on(state.depth) or way.get("shop", false)
		plan.lurkers = true
		plan.request = Requests.due(state.depth)
		state.floor_map = FloorGen.generate(floor_rng, plan)
		_send_elites()
	state.palette_id = Floors.palette(state.floor_map.biome, state.floor_map.seed_value)
	state.cell = state.floor_map.start
	state.facing = state.floor_map.start_facing()
	state.quarter_turns = 0
	state.visited = {state.cell: true}
	state.seen = {}
	state.look()


## Continue a saved state (from State.to_dict). False, and nothing changes, if it isn't one of ours.
func load_state(saved: Dictionary) -> bool:
	_wick_comes = false
	var loaded = State.from_dict(saved)
	if loaded == null:
		return false
	await _leave_current()
	fight_queue = []
	state = loaded
	_apply_features()
	encounter.pending_notes = []
	encounter.pending_rows = []
	print("flow: loaded a run (%s)" % state.summary())
	event("state_replaced", {"how": "load"})
	await go("explore", {"lines": [State.sys_line(Texts.welcome_back(state.summary()))]})
	return true


## Whether the scene may write the AUTO save when the walk resumes: not in the social-demo playtest.
func autosave_allowed() -> bool:
	return not Flags.on("social-demo")


## Move to another stage. Moves the table doesn't allow are refused and reported.
func go(to: String, args := {}) -> void:
	var from: String = state.stage
	if not Transitions.allowed(from, to):
		push_error("flow: %s -> %s is not a move the game allows" % [from if from != "" else "start", to])
		return
	await _leave_current()
	if to == "explore" and from in Transitions.FIGHT:
		_keys_back_at = clock + AFTER_FIGHT_MS
		_held_over = true
	state.stage = to
	_since = clock
	state.selected = 0
	print("flow: %s -> %s" % [from if from != "" else "start", to])
	event("stage", {"from": from, "to": to})
	await _stages[to].enter(self, args)
	if to == "explore":
		_note_warmth()


## The halls have changed their mind about you: say so on the way back from whatever did it.
func _note_warmth() -> void:
	var now := Warmth.level(Warmth.of(state))
	var was: int = state.warmth_level
	state.warmth_level = now
	if was < 0 or was == now:
		return
	print("flow: warmth %s -> %s (%.2f)" % [Warmth.level_id(was), Warmth.level_id(now), Warmth.of(state)])
	event("warmth", {"from": was, "to": now})
	var said := Warmth.line(was, now)
	if said != "" and not banner_up():
		announce(WARMTH_TITLE, said)


## Put a moment worth stopping for on the picture: a banner that fades by itself.
func announce(title: String, text: String, ms := BANNER_MS) -> void:
	state.banner = {"title": title, "text": text, "t0": clock, "ms": ms}
	print("flow: banner %s: %s" % [title, text])


## Whether a banner is showing now.
func banner_up() -> bool:
	return state.banner != null and clock - state.banner.t0 < state.banner.ms


## Announce an event to whoever listens.
func event(name: String, data := {}) -> void:
	if Events.valid(name, data):
		happened.emit(name, data)


## `held` says it is a key repeating by itself, not one just pressed.
func press(key: String, held := false) -> void:
	if busy:
		if not held and state.stage == "intro" and state.hint == "ANY KEY CONTINUE":
			_stages["intro"].queue_continue()
		return
	if state.stage == "":
		return
	if _keys_dropped(held):
		print_verbose("flow: %s dropped, the fight has only just ended" % key)
		return
	busy = true
	repeating = held
	await _stages[state.stage].handle(self, key)
	busy = false


func _keys_dropped(held: bool) -> bool:
	if clock < _keys_back_at or (held and _held_over):
		return true
	if not held:
		_held_over = false
	return false


## Run `action` (a Callable that may await stage changes) the way a key press runs: once any press or tick still working has
## finished, and with input held off until it is done. For callers that move the game from outside a press (the first fight a
## testing flag asks for, a loaded save): a tick arriving while a mind is still answering would otherwise run the stage's own
## tick in the middle of its `enter`.
func exclusive(action: Callable) -> void:
	while busy:
		await Engine.get_main_loop().process_frame
	busy = true
	await action.call()
	busy = false


## The pointer is over command `index` of the menu: it becomes the picked one, as if the arrows had moved there. Nothing
## else happens, so hovering never does anything the player didn't ask for.
func select(index: int) -> void:
	if state.stage in ["", "talk"] or index < 0 or index >= state.menu.size() or index == state.selected or state.menu[index].get("disabled", false):
		return
	state.selected = index
	print_verbose("flow: %s -> command %d picked by the pointer" % [state.stage, index])


## The player sent a line of text in the talk stage.
func submit_text(text: String) -> void:
	if busy or state.stage not in ["talk", "social"]:
		return
	busy = true
	await _stages[state.stage].submit(self, text)
	busy = false


func tick(t: float) -> void:
	clock = t
	_wick_arrives()
	_wick_teaches()
	if busy or state.stage == "":
		return
	busy = true
	await _stages[state.stage].tick(self, t)
	busy = false


## How long the current stage has been going, in ms.
func stage_ms() -> float:
	return clock - _since


func _leave_current() -> void:
	if state.stage != "":
		_stages[state.stage].leave(self)
