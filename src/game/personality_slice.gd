## A reproducible two-bandit encounter for the personality playtest (flag `personality-slice`, with `seed=N`). ROOK deals
## straight and VEX is jumpy, so the same fair-cut offer is taken by one and refused by the other at the fixed roll. While
## it is on, the monsters think with the local rules, the flow draws every interaction chance (cut, answer, feeling, mercy,
## joining, ally verdicts) at `fixed_roll`, and the floor is never autosaved. The slice ends after the second fight, on
## fleeing, on a new floor, on a load, or on leaving.
extends RefCounted

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Flags = preload("res://src/utils/flags.gd")
const Monster = preload("res://src/rules/monster.gd")
const Rng = preload("res://src/utils/rng.gd")

const DEFAULT_SEED := 7042
const GOLD := Combat.CUT_COST * 2 # enough to hear the same offer twice, even if the first one takes it
const ROLL := 0.5
const METERS := {"friendliness": 78.0, "anger": 12.0, "fear": 15.0}
const FOES := [
	{"name": "ROOK", "trait": "surprisingly honest about being dishonest"},
	{"name": "VEX", "trait": "jumpy"},
]

static var _started := false # the flag starts one slice per launch, so MAIN MENU from inside it shows the real menu


## Arm the flag again (for tests that start several slices in one process).
static func reset() -> void:
	_started = false


## The flag is on and its slice hasn't begun yet.
static func pending() -> bool:
	return Flags.on("personality-slice") and not _started


## The seed of the slice: `seed=N` (0 or more), or the one the playtest document names.
static func seed_value() -> int:
	var seed := Rng.flag_seed("using %d instead" % DEFAULT_SEED)
	return seed if seed >= 0 else DEFAULT_SEED


## The roster's own bandit, so the slice's bandits are built like the floor's.
static func bandit() -> Dictionary:
	for entry in Content.table("encounter").roster:
		if entry.species == "bandit":
			return entry
	push_error("slice: the roster has no bandit")
	return {}


## Turn the first two monsters of the fresh run into ROOK and VEX and start the fight with ROOK.
static func start(flow) -> void:
	_started = true
	var s = flow.state
	s.gold = GOLD
	flow.fixed_roll = ROLL
	flow.slice_floor = true
	var monsters: Array = s.floor_map.monsters
	for i in FOES.size():
		monsters[i] = Monster.given(bandit(), monsters[i].cell, FOES[i].name, [FOES[i].trait], METERS)
	flow.slice_queue = [monsters[1]]
	print("slice: seed %d, %s then %s, %d gold" % [flow.rng.seed_value, FOES[0].name, FOES[1].name, s.gold])
	await flow.go("intro", {"foe": monsters[0]})
