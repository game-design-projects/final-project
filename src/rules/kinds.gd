## The kinds of monster (data/kinds.json): five to a floor, and none on two floors. A kind belongs to a species, which keeps its
## clan, acts, tastes, words, voice and the charm it gives as a friend; the kind brings its own name, look, colour, health, attack
## and way of getting about. A champion has no kind: it is the Hoard's, and fights in every attack of its floor's kinds.
extends RefCounted

const Content = preload("res://src/rules/content.gd")


static func all() -> Dictionary:
	return Content.table("kinds").get("kinds", {})


static func has(id: String) -> bool:
	return all().has(id)


## One kind's entry, or an empty record.
static func info(id: String) -> Dictionary:
	return all().get(id, {})


## The deepest floor that has kinds of its own; a floor below it borrows that floor's.
static func deepest() -> int:
	var out := 1
	for id in all():
		out = maxi(out, int(all()[id].depth))
	return out


## The roster lines of floor `depth` ({kind, species, genre, hp}), in the file's order: one of each of its five kinds.
static func at_depth(depth: int) -> Array:
	var want := clampi(depth, 1, deepest())
	var out := []
	for id in all():
		if int(all()[id].depth) == want:
			out.append(line(id))
	return out


## A roster line for kind `id`.
static func line(id: String) -> Dictionary:
	var k := info(id)
	return {"kind": id, "species": str(k.species), "genre": str(k.genre), "hp": int(k.hp)}


## The kinds of `species` living at floor `depth` or above, the deepest first, as roster lines: a warren of one clan still meets
## the floor's own kind of it first, then the ones met higher up.
static func of_species(species: String, depth: int) -> Array:
	var out := []
	for id in all():
		var k: Dictionary = all()[id]
		if str(k.species) == species and int(k.depth) <= clampi(depth, 1, deepest()):
			out.append(line(id))
	out.sort_custom(func(a, b): return int(info(a.kind).depth) > int(info(b.kind).depth))
	return out


## What a champion of floor `depth` fights in: its floor's kinds' attacks, one a turn.
static func genres_at(depth: int) -> Array:
	return at_depth(depth).map(func(e): return e.genre)


## The kind a monster of `species` is when nothing says (a save from before kinds, the practice slime, meet=<species>).
static func base_of(species: String) -> String:
	return species if has(species) else ""


## What it is called: its kind's title, or its species' label for a monster without one.
static func title(m) -> String:
	var k := info(str(m.kind))
	return str(k.title) if not k.is_empty() else str(Content.species(m.species).get("label", m.species)).to_upper()


## Its colour, as "#rrggbb": its kind's, or its species'.
static func color_of(m) -> String:
	var k := info(str(m.kind))
	return str(k.color) if not k.is_empty() else str(Content.species(m.species).get("color", "#ffffff"))


## How it gets about when nothing else moves it, when its kind says (data/roaming.json's shape); {} leaves it to its species.
static func roam(m) -> Dictionary:
	return info(str(m.kind)).get("roam", {})


## One line about it for the cards: how it moves and fights.
static func note(m) -> String:
	return str(info(str(m.kind)).get("note", ""))
