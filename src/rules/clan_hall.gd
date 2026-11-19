## A clan's hall, where its teleporter leads (rules/envoys.gd): one room off the run's count, in the colours of the clan's home,
## with every kind of the clan standing either side of an aisle and its lord at the far end. Nobody here fights: walking into
## one of them gets a look, walking into the lord hears it out, and the stairs in the corner behind you go on down to the next
## floor of the run. Built from data/kinds.json and data/lords.json, so a new kind of a clan has its place here.
extends RefCounted

const Clans = preload("res://src/rules/clans.gd")
const Content = preload("res://src/rules/content.gd")
const Envoys = preload("res://src/rules/envoys.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Floors = preload("res://src/rules/floors.gd")
const Kinds = preload("res://src/rules/kinds.gd")
const Lords = preload("res://src/rules/lords.gd")
const Monster = preload("res://src/rules/monster.gd")
const Rng = preload("res://src/utils/rng.gd")

const SEED := 600 # its monsters' own draws (rules/envoys.gd has 500)


## The clan's kinds, the shallowest first: roster lines, each as its own floor makes it.
static func kinds_of(clan: String) -> Array:
	var species: Array = Content.table("clans").clans[clan].species
	var out := []
	for depth in range(1, Kinds.deepest() + 1):
		for line in Kinds.at_depth(depth):
			if species.has(str(line.species)):
				out.append(FloorGen.roster_line(line, Floors.plan(depth)))
	return out


## The lord as the hall holds it: an asker's figure with `lord` and its `title`.
static func lord_figure(clan: String, cell: Vector2i) -> Dictionary:
	var lord: Dictionary = Lords.table().lords[clan]
	return {"cell": cell, "clan": clan, "name": str(lord.name), "species": str(Envoys.entry(clan).species), "lord": true, "title": str(lord.title)}


## The hall, with everyone in it. `rng` names them and rolls their moods, as on any floor; `taken` is the run's names.
static func make(rng: Rng, clan: String, taken := {}):
	var lines := kinds_of(clan)
	var rows := int(ceil(lines.size() / 2.0))
	var inner_w := 3 # a stall, the aisle, a stall
	var inner_h := rows * 2 + 3 # the row you arrive in, a stall row and a gap for each pair, and the lord's
	var f := FloorMap.new()
	f.seed_value = rng.seed_value
	f.biome = str(Envoys.entry(clan).hall.biome)
	f.size = maxi(inner_h, inner_w + 2) + 2 # a floor is square; the +2 inside leaves a wall to cut the way out into
	var left := (f.size - inner_w) / 2
	var bottom := f.size - 2
	for y in f.size:
		var row := []
		for x in f.size:
			row.append(1 if x >= left and x < left + inner_w and y > bottom - inner_h and y <= bottom else 0)
		f.grid.append(row)
	f.start = Vector2i(left + 1, bottom)
	f.stairs = Vector2i(left - 1, bottom)
	f.grid[f.stairs.y][f.stairs.x] = 1
	var names: Dictionary = taken.duplicate()
	for i in lines.size():
		var cell := Vector2i(left + (0 if i % 2 == 0 else 2), bottom - 1 - (i / 2) * 2)
		f.monsters.append(Monster.make(rng, lines[i], cell, names))
	f.envoys = [lord_figure(clan, Vector2i(left + 1, bottom - inner_h + 1))]
	print("clan hall: %s, %dx%d, %d of its own and its lord" % [clan, f.size, f.size, f.monsters.size()])
	return f
