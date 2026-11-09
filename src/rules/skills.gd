## The skills of the feature skill-combat, in place of the strike bar: each costs energy, some cool down for a turn or more, and
## none asks for timing. A fight keeps its own record (`new_fight`): the energy left this turn, what is cooling down, the block
## that soaks up the next hits, and how bruised the foe is. Numbers and words are in data/skills.json. Nothing here draws or asks
## a mind; stages/skills.gd plays them.
extends RefCounted

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")


static func table() -> Dictionary:
	return Content.table("skills")


static func info(id: String) -> Dictionary:
	return table().skills.get(id, {})


static func known(id: String) -> bool:
	return table().skills.has(id)


## The energy every turn starts with.
static func energy_per_turn() -> int:
	return int(table().energy)


## How many skills you can hold.
static func slots() -> int:
	return int(table().slots)


## What a run starts holding.
static func start() -> Array:
	return table().start.duplicate()


## Add a skill to what is held, if there is a free slot and it isn't held already. True when it was added.
static func learn(held: Array, id: String) -> bool:
	if not known(id) or held.has(id) or held.size() >= slots():
		return false
	held.append(id)
	return true


static func label(id: String) -> String:
	return str(info(id).label)


static func line(id: String) -> String:
	return str(table().lines[id])


## A fight's record, at the start of its first turn.
static func new_fight() -> Dictionary:
	return {"energy": energy_per_turn(), "cooldowns": {}, "block": 0, "bruised": 0, "used": 0, "hits": 0, "dealt": 0, "turn_over": false}


## A new turn of yours: the energy comes back, the block from the last one is gone, and every cooldown is a turn shorter.
static func start_turn(f: Dictionary) -> void:
	f.energy = energy_per_turn()
	f.block = 0
	f.used = 0
	f.hits = 0
	f.dealt = 0
	f.turn_over = false
	for id in f.cooldowns.keys():
		f.cooldowns[id] = int(f.cooldowns[id]) - 1
		if f.cooldowns[id] <= 0:
			f.cooldowns.erase(id)


## Turns until it can be used again: 0 when it is ready (or still could be, this turn).
static func cooling(f: Dictionary, id: String) -> int:
	return int(f.cooldowns.get(id, 0))


static func usable(f: Dictionary, id: String) -> bool:
	return known(id) and cooling(f, id) == 0 and int(info(id).cost) <= int(f.energy)


## Whether anything held can still be used this turn.
static func any_usable(f: Dictionary, held: Array) -> bool:
	return held.any(func(id): return usable(f, id))


## What the menu says under it: its cost and what it does, or why it can't be used now.
static func sub(f: Dictionary, id: String) -> String:
	var s := info(id)
	var cost := "%d ENERGY" % int(s.cost)
	if cooling(f, id) > 0:
		return "%s · ready in %d turn%s" % [cost, cooling(f, id), "" if cooling(f, id) == 1 else "s"]
	if int(s.cost) > int(f.energy):
		return "%s · not enough energy left" % cost
	var cd := int(s.get("cooldown", 0))
	return "%s · %s%s" % [cost, str(s.text), " · cools down %d turn%s" % [cd, "" if cd == 1 else "s"] if cd > 0 else ""]


## What an attack skill does to this foe: its damage (scaled for a champion), plus how bruised the foe is, plus `bonus` (allies, a
## whetstone, the dragon's charm). 0 for a skill that doesn't attack.
static func damage(f: Dictionary, id: String, boss: bool, bonus := 0) -> int:
	var base := float(info(id).get("damage", 0))
	if base <= 0.0:
		return 0
	return roundi(base * (Combat.BOSS_DAMAGE_SCALE if boss else 1.0)) + int(f.bruised) + bonus


## Use it: spend its energy, start its cooldown, add its block and bruise (after its own damage, which `damage` gives).
## What it did: {damage, block, bruise}. Nothing happens, and {} comes back, if it can't be used now.
static func use(f: Dictionary, id: String, boss: bool, bonus := 0) -> Dictionary:
	if not usable(f, id):
		return {}
	var s := info(id)
	var out := {"damage": damage(f, id, boss, bonus), "block": int(s.get("block", 0)), "bruise": int(s.get("bruise", 0))}
	f.energy = int(f.energy) - int(s.cost)
	if int(s.get("cooldown", 0)) > 0:
		f.cooldowns[id] = int(s.cooldown) + 1 # it counts down at the start of each turn, the one after this included
	f.block = int(f.block) + out.block
	f.bruised = int(f.bruised) + out.bruise
	f.used = int(f.used) + 1
	if out.damage > 0:
		f.hits = int(f.hits) + 1
		f.dealt = int(f.dealt) + out.damage
	return out


## A hit in the dodge box against the block: what still gets through. The block goes down by what it soaked.
static func soak(f: Dictionary, damage_in: int) -> int:
	var soaked := mini(int(f.block), damage_in)
	f.block = int(f.block) - soaked
	return damage_in - soaked
