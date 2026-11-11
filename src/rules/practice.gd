## The practice floor before B1F (the feature tutorial-floor): one corridor drawn by hand in data/floors.json, so it is the
## same every time. You learn to walk and turn, pick something up, meet one small shy slime, and find the stairs. No champion
## guards it. The slime is the guided first fight of the old 2D tips, redone here: it starts near enough to friendly that a
## kind ACT or two makes SPARE likely, and a tip says so; nothing is locked. `#` is wall, `.` open, `S` the start, `I` the item, `M` the monster, `>` the stairs.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Monster = preload("res://src/rules/monster.gd")
const Rng = preload("res://src/utils/rng.gd")

const SEED := 300 # its slime is drawn from a seed of its own (rules/floors.gd has 100 and 200)


static func table() -> Dictionary:
	return Content.table("floors").practice


## The floor, with its item. `rng` only names the slime and rolls its mood, as any monster's.
static func make(rng: Rng):
	var t := table()
	var f := FloorMap.new()
	f.seed_value = rng.seed_value
	var layout: Array = t.layout
	f.size = layout.size()
	for y in layout.size():
		var row := []
		var line: String = layout[y]
		for x in line.length():
			var c := Vector2i(x, y)
			row.append(0 if line[x] == "#" else 1)
			match line[x]:
				"S":
					f.start = c
				">":
					f.stairs = c
				"I":
					f.pickups.append({"cell": c, "item": str(t.item)})
				"M":
					var m = Monster.make(rng, t.foe, c)
					for meter in t.meters: # shy, not hostile: the first fight is the one to learn sparing on
						m.meters[meter] = float(t.meters[meter])
					f.monsters.append(m)
		f.grid.append(row)
	return f


static func line(key: String) -> String:
	return str(table()[key])
