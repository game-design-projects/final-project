## A clan's lord at home in its biome: who it is, what it asks, and where it is met. The design is the owner's (#77): the Crew
## keeps the old halls, the Old Stone the undercroft, and the Burrow and the Coil the wet caves, where they are the heaviest
## weights of `data/biomes.json`; the Hoard keeps its champions. Everything here is data (`data/lords.json`) and a rule about
## which floor a lord is due on.
extends RefCounted

const Content = preload("res://src/rules/content.gd")


static func table() -> Dictionary:
	return Content.table("lords")


## The clans at home in a biome.
static func homes(biome: String) -> Array:
	return table().homes.get(biome, [])


## The lord due on this floor, or {}. On the run's first floor of a biome it is a lord there the run has not met (in a biome with
## two of them, the one the floor's seed picks); where the biome comes back it is the lord met there, asking its second and last
## favour, unless its clan is already sworn. `second` says which of the two it is.
static func due(biome: String, seed_value: int, met: Array = [], sworn: Array = [], returning := false) -> Dictionary:
	var here: Array = homes(biome)
	if returning:
		var again: Array = here.filter(func(c): return met.has(str(c)) and not sworn.has(str(c)))
		if again.is_empty():
			return {}
		return _entry(str(again[0]), true)
	var fresh: Array = here.filter(func(c): return not met.has(str(c)) and not sworn.has(str(c)))
	if fresh.is_empty():
		return {}
	var clan: String = str(fresh[0]) if fresh.size() == 1 else str(fresh[posmod(seed_value, fresh.size())])
	return _entry(clan, false)


## A lord's entry, as the rest of the game reads it.
static func _entry(clan: String, second: bool) -> Dictionary:
	var entry: Dictionary = table().lords[clan]
	var species: String = str(Content.table("clans").clans[clan].species[0])
	return {"clan": clan, "species": species, "name": str(entry.name), "title": str(entry.title), "kind": str(entry.kind), "second": second}


## What a lord pays: more than a stray asker does (`data/lords.json` `pays`).
static func pays() -> Dictionary:
	return table().pays


## What swearing the clan looks like: the banner of the second favour paid (`data/lords.json` `pact`).
static func pact() -> Dictionary:
	return table().pact

