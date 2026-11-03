## A reproducible two-bandit encounter for the personality playtest (flag `personality-slice`, with `seed=N`). ROOK deals
## straight and VEX is jumpy, so the same fair-cut offer is taken by one and refused by the other at the fixed roll. While
## it is on, the flow draws the cut and the answer at `fixed_roll`, nothing is autosaved, and a retry keeps the HP the
## fight began with. It ends after the second fight, on fleeing, on a new floor, on a load, or on leaving.
extends RefCounted

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Flags = preload("res://src/utils/flags.gd")

const DEFAULT_SEED := 7042
const GOLD := 12 # enough to hear the same 6-gold offer twice, even if the first one takes it
const ROLL := 0.5
const FOES := [
	{"name": "ROOK", "trait": "surprisingly honest about being dishonest"},
	{"name": "VEX", "trait": "jumpy"},
]


static func wanted() -> bool:
	return Flags.on("personality-slice")


## The seed of the slice: `seed=N`, or the one the playtest document names.
static func seed_value() -> int:
	return int(Flags.value("seed", str(DEFAULT_SEED)))


## Turn the first two monsters of the fresh run into ROOK and VEX and start the fight with ROOK.
static func start(flow) -> void:
	var s = flow.state
	s.gold = GOLD
	flow.fixed_roll = ROLL
	flow.slice_active = true
	var shifts: Dictionary = Content.table("taste").trait_shift
	for i in FOES.size():
		var m = s.floor_map.monsters[i]
		m.species = "bandit"
		m.genre = "chess"
		m.name = FOES[i].name
		m.max_hp = 24
		m.hp = 24
		m.threshold = float(Content.species("bandit").joinThreshold)
		m.traits = [FOES[i].trait]
		m.taste = {}
		for intent in shifts.get(FOES[i].trait, {}):
			m.taste[intent] = float(shifts[FOES[i].trait][intent])
		m.meters = {"friendliness": 78.0, "anger": 12.0, "fear": 15.0}
		m.last_intent = ""
	flow.slice_next = FOES[1].name
	print("slice: seed %d, %s then %s, %d gold" % [flow.rng.seed_value, FOES[0].name, FOES[1].name, s.gold])
	await flow.go("intro", {"foe": s.floor_map.monsters[0]})
