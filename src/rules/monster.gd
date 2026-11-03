## One monster: who it is, how it feels, what it likes. Made from a species in the content tables, with a random name,
## two random traits and a personal taste, so two slimes don't want the same thing.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Rng = preload("res://src/utils/rng.gd")

const METER_MAX := 100.0

var species := ""
var genre := "" # which attack style it fights in (a key of encounter.genres)
var boss := false
var name := ""
var cell := Vector2i.ZERO
var hp := 0
var max_hp := 0
## friendliness, anger, fear: 0..100
var meters := {"friendliness": 0.0, "anger": 0.0, "fear": 0.0}
var traits: Array = []
## Per intent (kindness, joke, gold, ...) how much this one monster likes it, on top of its species' leaning.
var taste := {}
var last_intent := ""
var spoke := false # it only hears one line per fight
var threshold := 0.0 # how friendly it must be before it will join
var turn := 0
var gone := "" # "", "spared" or "slain"


## `entry` is one line of the roster (species, genre, hp), or the boss. `cell` is where it stands.
static func make(rng: Rng, entry: Dictionary, cell: Vector2i):
	var m = new()
	var sp := Content.species(entry.species)
	var start: Dictionary = sp.start
	m.species = entry.species
	m.genre = entry.genre
	m.boss = entry.get("boss", false)
	m.cell = cell
	m.max_hp = int(entry.hp)
	m.hp = m.max_hp
	m.meters = {
		"friendliness": clampf(start.friendliness + rng.int_range(-10, 10), 0.0, METER_MAX),
		"anger": clampf(start.anger + rng.int_range(-5, 10), 0.0, METER_MAX),
		"fear": float(start.fear),
	}
	m.name = str(entry.get("name", "")) if m.boss else str(rng.pick(sp.names)).to_upper()
	m.threshold = float(sp.joinThreshold) + (5.0 if m.boss else 0.0)
	m.traits = _pick_traits(rng, m.species, sp)
	m._roll_taste(rng)
	print_verbose("monster: %s the %s %s, traits %s" % [m.name, m.species, "boss" if m.boss else "", m.traits])
	return m


## A monster whose personality is given instead of rolled (the playtest slice): the same species, genre and hp fields as
## `make`, and the taste its traits shift, without the random part. `entry` is a roster line, `meters` its starting feelings.
static func given(entry: Dictionary, cell: Vector2i, given_name: String, given_traits: Array, meters: Dictionary):
	var m = new()
	m.species = entry.species
	m.genre = entry.genre
	m.cell = cell
	m.max_hp = int(entry.hp)
	m.hp = m.max_hp
	m.meters = meters.duplicate()
	m.name = given_name
	m.threshold = float(Content.species(m.species).joinThreshold)
	m.traits = given_traits.duplicate()
	m._add_trait_shifts()
	return m


## Two traits, and at least one of them a trait that wants something (has a motive), so every monster has a personality
## the player can read.
static func _pick_traits(rng: Rng, species_id: String, sp: Dictionary) -> Array:
	var pool: Array = sp.traits.duplicate()
	if species_id == "bandit":
		pool.append("proud")
	rng.shuffle(pool)
	var chosen: Array = pool.slice(0, 2)
	var motives: Dictionary = Content.table("taste").motives
	for t in chosen:
		if motives.has(t):
			return chosen
	for t in pool:
		if motives.has(t):
			chosen[1] = t
			break
	return chosen


func _roll_taste(rng: Rng) -> void:
	var taste_table := Content.table("taste")
	for intent in taste_table.affinity[species]:
		taste[intent] = (rng.real() - 0.5) * 1.2
	_add_trait_shifts()


func _add_trait_shifts() -> void:
	var shifts: Dictionary = Content.table("taste").trait_shift
	for t in traits:
		var shift: Dictionary = shifts.get(t, {})
		for intent in shift:
			taste[intent] = float(taste.get(intent, 0.0)) + float(shift[intent])


## How much this monster likes a kind of words or deeds: its species' leaning plus its own taste. About -2..2.
func affinity(intent: String) -> float:
	return float(Content.table("taste").affinity[species].get(intent, 0.0)) + float(taste.get(intent, 0.0))


## What its traits do to `field` ("mercy", "join", "pressure") when the last thing done to it was `intent`.
func motive_shift(field: String, intent: String) -> float:
	var motives: Dictionary = Content.table("taste").motives
	var total := 0.0
	for t in traits:
		if motives.has(t):
			total += float(motives[t].get(field, {}).get(intent, 0.0))
	return total


func has_trait(trait_name: String) -> bool:
	return traits.has(trait_name)


## Visible behaviour that hints at its traits, without giving away the odds.
func clues() -> Array:
	var motives: Dictionary = Content.table("taste").motives
	var out := []
	for t in traits:
		if motives.has(t):
			out.append(motives[t].clue)
	return out


func hp_fraction() -> float:
	return float(hp) / max_hp if max_hp > 0 else 0.0


func is_gone() -> bool:
	return gone != ""


func to_dict() -> Dictionary:
	return {
		"species": species, "genre": genre, "boss": boss, "name": name, "cell": [cell.x, cell.y], "hp": hp, "maxHp": max_hp,
		"meters": meters.duplicate(), "traits": traits.duplicate(), "taste": taste.duplicate(), "lastIntent": last_intent,
		"spoke": spoke, "threshold": threshold, "turn": turn, "gone": gone,
	}


static func from_dict(d: Dictionary):
	var m = new()
	m.species = str(d.get("species", ""))
	m.genre = str(d.get("genre", ""))
	m.boss = bool(d.get("boss", false))
	m.name = str(d.get("name", ""))
	var c: Array = d.get("cell", [0, 0])
	m.cell = Vector2i(int(c[0]), int(c[1]))
	m.max_hp = int(d.get("maxHp", 0))
	m.hp = int(d.get("hp", m.max_hp))
	m.meters = {"friendliness": 0.0, "anger": 0.0, "fear": 0.0}
	for k in m.meters:
		m.meters[k] = float(d.get("meters", {}).get(k, 0.0))
	m.traits = d.get("traits", []).duplicate()
	m.taste = d.get("taste", {}).duplicate()
	m.last_intent = str(d.get("lastIntent", ""))
	m.spoke = bool(d.get("spoke", false))
	m.threshold = float(d.get("threshold", 0.0))
	m.turn = int(d.get("turn", 0))
	m.gone = str(d.get("gone", ""))
	return m
