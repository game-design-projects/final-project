## Runs a game: one state, one stage at a time, moves between stages checked against transitions.gd. Nothing here draws
## or plays a sound; the picture reads `state` and the sound listens to `event`. Time comes in from outside (`tick`), so
## a headless run can drive the whole game by calling `press` and `tick`.
##
## `press`, `tick` and `submit_text` may take time while a mind answers; callers can `await` them or ignore that, and
## input is dropped while one is still working (`busy`).
extends RefCounted

const Coach = preload("res://src/game/coach.gd")
const Dice = preload("res://src/utils/dice.gd")
const Encounter = preload("res://src/game/encounter.gd")
const Events = preload("res://src/game/events.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const Flags = preload("res://src/utils/flags.gd")
const Floors = preload("res://src/rules/floors.gd")
const Items = preload("res://src/rules/items.gd")
const PersonalitySlice = preload("res://src/game/personality_slice.gd")
const Requests = preload("res://src/rules/requests.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")
const Transitions = preload("res://src/game/transitions.gd")

## The features the picture and the HUD show, which they read from the state (see State.views).
const VIEW_FEATURES := ["piece-icons", "mercy-link", "party-aid", "mood-cues", "clear-hp", "reveal", "chat", "boss-at-exit", "secrets", "items", "lurkers", "npcs", "roaming", "smooth-fight"]
const BANNER_MS := 3000.0
const WALK_HEAL_STEPS := 6
const FIGHT_STAGES := ["intro", "menu", "ask", "act", "items", "talk", "fightbar", "wait", "dodge", "dead"]
const AFTER_FIGHT_MS := 350.0 # how long keys do nothing once a fight is over
const STORY_BANNER_MS := 6000.0

const STAGES := {
	"explore": preload("res://src/game/stages/explore.gd"),
	"intro": preload("res://src/game/stages/intro.gd"),
	"menu": preload("res://src/game/stages/menu.gd"),
	"ask": preload("res://src/game/stages/ask.gd"),
	"act": preload("res://src/game/stages/act.gd"),
	"items": preload("res://src/game/stages/items.gd"),
	"trade": preload("res://src/game/stages/trade.gd"),
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
## Where the chances of an interaction are drawn (see dice.gd); the slice pins it.
var dice: Dice
var mind
var encounter
## The game clock in ms, as last given to `tick`.
var clock := 0.0
var busy := false
## The setting EASY DODGE, which the scene hands in: the game doesn't read settings itself.
var coach # the first-time tips
var easy_dodge := false
## The personality slice (personality_slice.gd): while `dice` is pinned, every chance of an interaction (the cut,
## the answer, a feeling, mercy, joining, an ally's verdict and starting loyalty) is drawn at it, and `slice_queue` holds
## the monsters still to fight. `slice_floor` marks the floor the slice was made on, which is never autosaved; a new floor
## or a load clears it.
var slice_queue: Array = []
var slice_floor := false

var _stages := {}
var _since := 0.0 # clock when the current stage began
var _keys_back_at := -1.0 # keys do nothing until the clock says this, once a fight is over
var _held_over := false # a key still held from the fight stays dropped until something is pressed afresh


func _init(game_rng, game_mind) -> void:
	rng = game_rng
	dice = Dice.new(game_rng)
	mind = game_mind
	encounter = Encounter.new(self)
	coach = Coach.new(self)
	for name in STAGES:
		_stages[name] = STAGES[name].new()
	state = State.new()


## Whether a feature is on for this game: the flag (flags.gd), and not on the personality slice, whose routes stay fixed so
## its sessions can be compared.
func feature(name: String) -> bool:
	return Flags.enabled(name) and not slice_floor and not PersonalitySlice.pending()


## A fresh run: a new floor, standing at its start.
func new_run() -> void:
	await _leave_current()
	_forget_slice()
	state = State.new()
	state.depth = maxi(1, int(Flags.value("floor", "1")))
	state.run_seed = rng.seed_value
	_apply_features()
	_make_floor()
	encounter.pending_notes = []
	encounter.pending_rows = []
	print("flow: new run, seed %d" % rng.seed_value)
	event("state_replaced", {"how": "new"})
	var lines := _arrival()
	if _telling_story():
		var premise: Dictionary = Floors.premise()
		lines = [State.sys_line(premise.line), lines[0]] # the log has room for two: why you are here says more than where
		announce(premise.title, premise.door if feature("last-door") else premise.banner, STORY_BANNER_MS)
	await go("explore", {"lines": lines})


## Take the stairs: the next floor of this run, keeping health, gold, allies and the tally, with a rest on the way down. `way` is
## which way down was chosen (Floors.paths), if there was a choice.
func next_floor(way := {}) -> void:
	await _leave_current()
	state.depth = mini(state.depth + 1, State.DEPTH_MAX)
	state.foe = null
	state.hp = mini(state.max_hp, state.hp + Floors.rest_heal() + int(way.get("rest", 0)))
	state.gold += int(way.get("gold", 0))
	_make_floor(way)
	encounter.pending_notes = []
	encounter.pending_rows = []
	print("flow: down to B%dF (%s)" % [state.depth, state.summary()])
	event("state_replaced", {"how": "floor"})
	var biome: Dictionary = Floors.biome_named(state.floor_map.biome)
	if not biome.is_empty():
		announce(biome.name, biome.line)
	await go("explore", {"lines": _arrival()})


## What the views read from the state rather than ask the flags, because the personality slice has them off.
func _apply_features() -> void:
	state.rotate_mini_games = feature("mini-games")
	state.floors_of = Floors.run_floors() if _telling_story() else 0
	for name in VIEW_FEATURES:
		state.views[name] = feature(name)


## The story needs a below to tell of.
func _telling_story() -> bool:
	return feature("story") and feature("real-floors")


## What the log says on arriving on this floor.
func _arrival() -> Array:
	var lines := []
	if _telling_story():
		lines.append(State.sys_line(Texts.floor_story(state.depth, Floors.run_floors(), Floors.plan(state.depth).champion)))
	else:
		lines.append(State.sys_line(Texts.new_floor(state.depth)))
	var biome: Dictionary = Floors.biome_named(state.floor_map.biome)
	if not biome.is_empty():
		lines.append(State.sys_line(biome.line))
	return lines


## The floor for `state.depth`, with the party at its start. Without real-floors it is the classic one, drawn from the game's
## generator as it always was, so old seeds make the same floor.
func _make_floor(way := {}) -> void:
	if feature("real-floors"):
		var floor_rng = Rng.new(Floors.floor_seed(state.run_seed, state.depth, int(way.get("path", 0))))
		var plan: Dictionary = Floors.plan(state.depth, way)
		plan.boss_at_exit = feature("boss-at-exit")
		if feature("map-gen"):
			plan.biome = Floors.biome(state.run_seed, state.depth)
		if feature("secrets"):
			plan.secrets = Floors.secrets(plan.get("biome", {}))
		plan.items = feature("items")
		plan.shop = feature("items") and feature("shop") and Items.shop_on(state.depth)
		plan.lurkers = feature("lurkers")
		plan.request = feature("npcs") and Requests.due(state.depth)
		state.floor_map = FloorGen.generate(floor_rng, plan)
	else:
		state.floor_map = FloorGen.generate(rng)
	state.palette_id = Floors.palette(state.floor_map.biome, state.floor_map.seed_value)
	state.cell = state.floor_map.start
	state.facing = state.floor_map.start_facing()
	state.quarter_turns = 0
	state.visited = {state.cell: true}
	state.seen = {}
	state.look()


## Continue a saved state (from State.to_dict). False, and nothing changes, if it isn't one of ours.
func load_state(saved: Dictionary) -> bool:
	var loaded = State.from_dict(saved)
	if loaded == null:
		return false
	await _leave_current()
	_forget_slice()
	state = loaded
	_apply_features()
	encounter.pending_notes = []
	encounter.pending_rows = []
	print("flow: loaded a run (%s)" % state.summary())
	event("state_replaced", {"how": "load"})
	await go("explore", {"lines": [State.sys_line(Texts.welcome_back(state.summary()))]})
	return true


## Whether the scene may write the AUTO save when the walk resumes: not on the slice's floor.
func autosave_allowed() -> bool:
	return not slice_floor


## A floor that replaces the current one (new run, loaded save) is an ordinary floor: no slice, no mark.
func _forget_slice() -> void:
	end_slice()
	slice_floor = false


## Back to ordinary rolls (and no queued fight).
func end_slice() -> void:
	if dice.is_pinned():
		print("flow: personality slice over")
	dice.unpin()
	slice_queue = []


## Move to another stage. Moves the table doesn't allow are refused and reported.
func go(to: String, args := {}) -> void:
	var from: String = state.stage
	if not Transitions.allowed(from, to):
		push_error("flow: %s -> %s is not a move the game allows" % [from if from != "" else "start", to])
		return
	await _leave_current()
	if to == "explore" and from in FIGHT_STAGES and feature("input-cooldown"):
		_keys_back_at = clock + AFTER_FIGHT_MS
		_held_over = true
	state.stage = to
	_since = clock
	state.selected = 0
	print("flow: %s -> %s" % [from if from != "" else "start", to])
	event("stage", {"from": from, "to": to})
	await _stages[to].enter(self, args)


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
	if busy or state.stage == "":
		return
	if _keys_dropped(held):
		print_verbose("flow: %s dropped, the fight has only just ended" % key)
		return
	busy = true
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
	if state.stage in ["", "talk"] or index < 0 or index >= state.menu.size() or index == state.selected:
		return
	state.selected = index
	print_verbose("flow: %s -> command %d picked by the pointer" % [state.stage, index])


## The player sent a line of text in the talk stage.
func submit_text(text: String) -> void:
	if busy or state.stage != "talk":
		return
	busy = true
	await _stages["talk"].submit(self, text)
	busy = false


func tick(t: float) -> void:
	clock = t
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
