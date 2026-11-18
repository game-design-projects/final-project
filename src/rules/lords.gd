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


## The lord due on this floor, or {}: a lord at home in this biome that the run has not met yet (in a biome with two of them,
## the one the floor's seed picks among those).
static func due(biome: String, seed_value: int, met: Array = []) -> Dictionary:
	var here: Array = homes(biome).filter(func(c): return not met.has(str(c)))
	if here.is_empty():
		return {}
	var clan: String = str(here[0]) if here.size() == 1 else str(here[posmod(seed_value, here.size())])
	var entry: Dictionary = table().lords[clan]
	var species: String = str(Content.table("clans").clans[clan].species[0])
	return {"clan": clan, "species": species, "name": str(entry.name), "title": str(entry.title), "kind": str(entry.kind)}


## What a lord pays: more than a stray asker does (`data/lords.json` `pays`).
static func pays() -> Dictionary:
	return table().pays

