## Deterministic five-encounter playtest in the real game. Uses ordinary combat, no pinned feelings or free rewards.
extends RefCounted

const Monster = preload("res://src/rules/monster.gd")
const Content = preload("res://src/rules/content.gd")
const Flags = preload("res://src/utils/flags.gd")

const CAST := [
	{"species": "bandit", "name": "PIP", "traits": ["jumpy", "greedy"], "fear": 50.0},
	{"species": "bandit", "name": "BRASS", "traits": ["proud", "surprisingly honest about being dishonest"], "fear": 10.0},
	{"species": "slime", "name": "MALLOW", "traits": ["lonely", "shy"], "fear": 30.0},
	{"species": "slime", "name": "QUIVER", "traits": ["easily startled", "shy"], "fear": 65.0},
	{"species": "dragon", "name": "CINDER", "traits": ["bored", "vain"], "fear": 0.0},
]

static func start(flow) -> void:
	var s = flow.state
	s.practice = false
	s.allies = []
	s.gold = 18
	s.max_hp = 40
	s.hp = 40
	s.banner = null
	flow.coach.enabled = false
	for i in CAST.size():
		var c: Dictionary = CAST[i]
		var m = Monster.given({"species": c.species, "genre": "chess" if c.species == "bandit" else "bullet", "hp": 45 if c.species == "dragon" else 38, "boss": i == CAST.size() - 1}, s.floor_map.monsters[i].cell, c.name, c.traits, {"friendliness": 20.0, "anger": 25.0, "fear": c.fear})
		m.mood = {"id": c.species, "goal": Content.table("moods")[c.species].goal}
		s.floor_map.monsters[i] = m
	flow.slice_queue = s.floor_map.monsters.slice(1, CAST.size()) # existing encounter chaining, without disabling features
	await flow.go("intro", {"foe": s.floor_map.monsters[0]})
	print("social-demo: PIP -> BRASS -> MALLOW -> QUIVER -> CINDER; 18 gold, 40 HP; feature %s" % flow.feature("initiated-dialogue"))

## Only this demo forces the first normal opportunity; ordinary runs keep data/social.json tuning.
static func tune(m) -> void:
	if Flags.on("social-demo") and not m.social.get("used", false):
		m.social.due = 2
