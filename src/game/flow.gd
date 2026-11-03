## Runs a game: one state, one stage at a time, moves between stages checked against transitions.gd. Nothing here draws
## or plays a sound; the picture reads `state` and the sound listens to `event`. Time comes in from outside (`tick`), so
## a headless run can drive the whole game by calling `press` and `tick`.
##
## `press`, `tick` and `submit_text` may take time while a mind answers; callers can `await` them or ignore that, and
## input is dropped while one is still working (`busy`).
extends RefCounted

const Encounter = preload("res://src/game/encounter.gd")
const Events = preload("res://src/game/events.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const Flags = preload("res://src/utils/flags.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")
const Transitions = preload("res://src/game/transitions.gd")

const STAGES := {
	"explore": preload("res://src/game/stages/explore.gd"),
	"intro": preload("res://src/game/stages/intro.gd"),
	"menu": preload("res://src/game/stages/menu.gd"),
	"act": preload("res://src/game/stages/act.gd"),
	"talk": preload("res://src/game/stages/talk.gd"),
	"fightbar": preload("res://src/game/stages/fightbar.gd"),
	"wait": preload("res://src/game/stages/wait.gd"),
	"dodge": preload("res://src/game/stages/dodge.gd"),
	"result": preload("res://src/game/stages/result.gd"),
	"dead": preload("res://src/game/stages/dead.gd"),
	"end": preload("res://src/game/stages/end.gd"),
}

## Something happened that the picture or the sound should react to (see events.gd). Emit with `event()`, which checks
## the name and fields first.
signal happened(name: String, data: Dictionary)

var state # State
var rng
var mind
var encounter
## The game clock in ms, as last given to `tick`.
var clock := 0.0
var busy := false
## The personality slice (personality_slice.gd): while `slice_active`, the cut and the answer are drawn at `fixed_roll`,
## and `slice_next` names the monster that follows this fight.
var slice_active := false
var fixed_roll := -1.0
var slice_next := ""

var _stages := {}
var _since := 0.0 # clock when the current stage began


func _init(game_rng, game_mind) -> void:
	rng = game_rng
	mind = game_mind
	encounter = Encounter.new(self)
	for name in STAGES:
		_stages[name] = STAGES[name].new()
	state = State.new()


## A fresh run: a new floor, standing at its start.
func new_run() -> void:
	await _leave_current()
	end_slice()
	state = State.new()
	state.depth = maxi(1, int(Flags.value("floor", "1")))
	state.floor_map = FloorGen.generate(rng)
	state.cell = state.floor_map.start
	state.facing = state.floor_map.start_facing()
	state.visited = {state.cell: true}
	state.look()
	encounter.pending_notes = []
	encounter.pending_rows = []
	print("flow: new run, seed %d" % rng.seed_value)
	event("new_floor")
	await go("explore", {"lines": [State.sys_line(Texts.new_floor())]})


## Continue a saved state (from State.to_dict). False, and nothing changes, if it isn't one of ours.
func load_state(saved: Dictionary) -> bool:
	var loaded = State.from_dict(saved)
	if loaded == null:
		return false
	await _leave_current()
	end_slice()
	state = loaded
	encounter.pending_notes = []
	encounter.pending_rows = []
	print("flow: loaded a run (%s)" % state.summary())
	await go("explore", {"lines": [State.sys_line(Texts.welcome_back(state.summary()))]})
	return true


## Back to ordinary rolls (and no queued fight).
func end_slice() -> void:
	if slice_active:
		print("flow: personality slice over")
	slice_active = false
	fixed_roll = -1.0
	slice_next = ""


## Move to another stage. Moves the table doesn't allow are refused and reported.
func go(to: String, args := {}) -> void:
	var from: String = state.stage
	if not Transitions.allowed(from, to):
		push_error("flow: %s -> %s is not a move the game allows" % [from if from != "" else "start", to])
		return
	await _leave_current()
	state.stage = to
	_since = clock
	state.selected = 0
	print("flow: %s -> %s" % [from if from != "" else "start", to])
	event("stage", {"from": from, "to": to})
	await _stages[to].enter(self, args)


## Announce an event to whoever listens.
func event(name: String, data := {}) -> void:
	if Events.valid(name, data):
		happened.emit(name, data)


func press(key: String) -> void:
	if busy or state.stage == "":
		return
	busy = true
	await _stages[state.stage].handle(self, key)
	busy = false


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
