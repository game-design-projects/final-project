## Things you carry: what they do, what a floor leaves lying about and what a trader stocks. Pure rules from data/items.json; the
## stages say what happened. A gift is a new way to win a monster over: the kind it loves does most of what a few kind words would.
extends RefCounted

const Content = preload("res://src/rules/content.gd")


static func table() -> Dictionary:
	return Content.table("items")


static func info(id: String) -> Dictionary:
	return table().items.get(id, {})


static func known(id: String) -> bool:
	return table().items.has(id)


static func line(kind: String) -> String:
	return table().lines[kind]


static func label(id: String) -> String:
	return str(info(id).get("label", id))


## Into the bag, if it has room.
static func carry(state, id: String) -> bool:
	if state.items.size() >= int(table().carry):
		return false
	state.items.append(id)
	return true


## Whether this floor has a trader.
static func shop_on(depth: int) -> bool:
	return table().shop_floors.has(float(depth))


## What lies about on a floor: the weighted draw, favouring the gift for whoever lives there. A kind's own territory always has its gift.
static func floor_finds(rng, plan: Dictionary) -> Array:
	var out := []
	var only := str(plan.get("only_species", ""))
	if only != "":
		out.append(gift_for(only))
	var favours: Dictionary = plan.get("biome", {}).get("weights", {})
	while out.size() < int(table().pickups_per_floor):
		out.append(_draw(rng, favours, out))
	return out


## What a trader has on the shelf, none of it twice.
static func stock(rng, plan: Dictionary) -> Array:
	var out := []
	while out.size() < int(table().stock):
		out.append(_draw(rng, plan.get("biome", {}).get("weights", {}), out))
	return out


## The gift this species loves, or "".
static func gift_for(species: String) -> String:
	for id in table().items:
		if str(info(id).get("loves", "")) == species:
			return id
	return ""


## A gift given. Its meters move before the mind is asked how it feels, so the odds it shows are the odds after. True when it loved it.
static func give(m, id: String) -> bool:
	var g: Dictionary = table().gift
	var loved: bool = str(info(id).get("loves", "")) == m.species
	m.meters.friendliness = clampf(m.meters.friendliness + float(g.loved_friendliness if loved else g.other_friendliness), 0.0, 100.0)
	if loved:
		m.meters.anger = clampf(m.meters.anger - float(g.loved_calm), 0.0, 100.0)
	print("items: %s given to %s, %s: friendliness %.0f, anger %.0f" % [id, m.name, "loved" if loved else "shrugged at", m.meters.friendliness, m.meters.anger])
	return loved


static func _draw(rng, favours: Dictionary, already: Array) -> String:
	var pool := []
	var total := 0.0
	for id in table().items:
		if id in already:
			continue
		var w := _weight(id, favours)
		pool.append([id, w])
		total += w
	var roll: float = rng.real() * total
	for entry in pool:
		roll -= entry[1]
		if roll < 0.0:
			return entry[0]
	return pool[-1][0]


static func _weight(id: String, favours: Dictionary) -> float:
	var w := float(info(id).weight)
	var loves := str(info(id).get("loves", ""))
	return w * float(favours.get(loves, 1.0)) if loves != "" else w
