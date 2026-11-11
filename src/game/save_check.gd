## Whether a saved state (State.to_dict, read back from a file or a copied slot) can be played, and the small readers State.from_dict
## uses on its values. A save is data from outside, so every value is checked before it is used: `problem` names the first thing
## wrong, or says "" when the save can be read.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Items = preload("res://src/rules/items.gd")
const Requests = preload("res://src/rules/requests.gd")

const GRID_MAX := 64 # the biggest floor a save may describe (the biomes' largest is 55)


## What is wrong with this saved state, or "" when it can be read.
static func problem(d: Dictionary) -> String:
	for key in ["floor", "cell", "facing", "hp", "maxHp", "gold", "tally", "allies"]:
		if not d.has(key):
			return "it lacks '%s'" % key
	for key in ["facing", "hp", "maxHp", "gold"]:
		if not is_num(d[key]):
			return "'%s' is not a number" % key
	if d.has("depth") and not is_num(d.depth):
		return "'depth' is not a number"
	if d.has("runSeed") and not is_num(d.runSeed):
		return "'runSeed' is not a number"
	if not d.tally is Dictionary or d.tally.values().any(func(v): return not is_num(v)):
		return "'tally' is not a record of numbers"
	if not d.allies is Array:
		return "'allies' is not a list"
	for a in d.allies:
		if not a is Dictionary or not Content.is_species(str(a.get("species", ""))) or not is_num(a.get("loyalty", 60.0)):
			return "an ally is not a known one"
	if d.has("reputation") and (not d.reputation is Dictionary or d.reputation.values().any(func(v): return not is_num(v))):
		return "'reputation' is not a record of numbers"
	if d.has("deeds") and (not d.deeds is Array or d.deeds.any(func(v): return not v is Dictionary)):
		return "'deeds' is not a list of records"
	var wrong := _floor_problem(d.floor)
	if wrong != "":
		return wrong
	if not is_cell(d.cell) or not is_open(d.floor, cell(d.cell)):
		return "the party's cell is not an open cell of the floor"
	return ""


static func _floor_problem(f) -> String:
	if not f is Dictionary:
		return "'floor' is not a record"
	var size = f.get("size")
	if not is_num(size) or to_int(size) < 3 or to_int(size) > GRID_MAX:
		return "the floor's size is not between 3 and %d" % GRID_MAX
	var grid = f.get("grid")
	if not grid is Array or grid.size() != to_int(size):
		return "the floor's grid is not as tall as its size"
	for row in grid:
		if not row is Array or row.size() != to_int(size) or row.any(func(v): return not is_num(v)):
			return "a row of the floor's grid is not a row of numbers as wide as its size"
	for key in ["stairs", "start"]:
		if not is_cell(f.get(key)) or not is_open(f, cell(f[key])):
			return "the floor's %s is not an open cell" % key
	if f.has("biome") and not f.biome is String:
		return "the floor's biome is not a word"
	if f.has("treasure"):
		if not f.treasure is Array or f.treasure.any(func(t): return not t is Dictionary or not is_cell(t.get("cell")) or not is_open(f, cell(t.cell)) or not is_num(t.get("gold"))):
			return "the floor's chests are not a list of open cells with gold"
	if f.has("teleports"):
		if not f.teleports is Array or f.teleports.any(func(t): return not t is Dictionary or not is_cell(t.get("a")) or not is_cell(t.get("b")) or not is_open(f, cell(t.a)) or not is_open(f, cell(t.b))):
			return "the floor's pads are not a list of pairs of open cells"
	if f.has("pickups"):
		if not f.pickups is Array or f.pickups.any(func(p): return not p is Dictionary or not is_cell(p.get("cell")) or not is_open(f, cell(p.cell)) or not Items.known(str(p.get("item", "")))):
			return "the floor's items are not a list of open cells with known items"
	if f.has("merchant") and not f.merchant is Dictionary:
		return "the floor's trader is not a record"
	if f.has("merchant") and not f.merchant.is_empty():
		if not is_cell(f.merchant.get("cell")) or not is_open(f, cell(f.merchant.cell)) or not f.merchant.get("stock") is Array or f.merchant.stock.any(func(id): return not Items.known(str(id))):
			return "the floor's trader is not on an open cell with known stock"
	if not f.get("monsters") is Array:
		return "the floor's monsters are not a list"
	for m in f.monsters:
		var wrong := _monster_problem(m, f)
		if wrong != "":
			return wrong
	if f.has("steps") and not is_num(f.steps):
		return "the floor's steps are not a number"
	if f.has("quester") and not f.quester is Dictionary:
		return "the floor's request is not a record"
	if f.has("quester") and not f.quester.is_empty():
		if not is_cell(f.quester.get("cell")) or not is_open(f, cell(f.quester.cell)):
			return "the floor's request is not on an open cell"
		return Requests.problem(f.quester, f.monsters.size())
	return ""


static func _monster_problem(m, f: Dictionary) -> String:
	if not m is Dictionary:
		return "a monster is not a record"
	if not Content.table("species").has(str(m.get("species", ""))):
		return "a monster is of no known species"
	if not Content.table("encounter").genres.has(str(m.get("genre", ""))):
		return "a monster fights in no known genre"
	if not is_cell(m.get("cell")) or not is_open(f, cell(m.cell)):
		return "a monster is not on an open cell"
	for key in ["hp", "maxHp", "threshold", "turn"]:
		if m.has(key) and not is_num(m[key]):
			return "a monster's '%s' is not a number" % key
	if m.has("meters") and (not m.meters is Dictionary or m.meters.values().any(func(v): return not is_num(v))):
		return "a monster's meters are not a record of numbers"
	for key in ["mood", "social"]:
		if m.has(key) and not m[key] is Dictionary:
			return "a monster's %s is not a record" % key
	if m.has("social"):
		var social: Dictionary = m.social
		for key in ["used", "promise", "betrayed", "pending", "was_low", "words_asked"]:
			if social.has(key) and not social[key] is bool:
				return "social %s is not a boolean" % key
		if social.has("history") and (not social.history is Array or social.history.any(func(v): return not v is Dictionary)):
			return "social history is not a list of records"
		for key in ["rounds", "due", "checked", "seed", "pressure", "soft_turns", "opening", "trial"]:
			if social.has(key) and not is_num(social[key]):
				return "social %s is not a number" % key
	if m.has("checks") and not is_num(m.checks):
		return "a monster's 'checks' is not a number"
	if m.has("tried") and not m.tried is Dictionary:
		return "a monster's 'tried' is not a record"
	if m.has("knownTraits") and not m.knownTraits is Array:
		return "a monster's 'knownTraits' is not a list"
	if m.has("heard") and (not m.heard is Dictionary or (m.heard.has("standing") and not is_num(m.heard.standing))):
		return "what a monster heard is not a record"
	if m.has("traits") and (not m.traits is Array or m.traits.any(func(t): return not t is String)):
		return "a monster's traits are not a list of words"
	for key in ["purse", "hold", "leg"]:
		if m.has(key) and not is_num(m[key]):
			return "a monster's '%s' is not a number" % key
	if m.has("patrol") and (not m.patrol is Array or m.patrol.size() not in [0, 2] or m.patrol.any(func(c): return not is_cell(c) or not is_open(f, cell(c)))):
		return "a monster's beat is not two open cells"
	if m.has("lastSeen") and not is_cell(m.lastSeen):
		return "where a monster was last seen is not a cell"
	if m.has("taste") and (not m.taste is Dictionary or m.taste.values().any(func(v): return not is_num(v))):
		return "a monster's taste is not a record of numbers"
	return ""


static func is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func is_cell(v) -> bool:
	return v is Array and v.size() == 2 and is_num(v[0]) and is_num(v[1])


static func cell(v) -> Vector2i:
	return Vector2i(to_int(v[0]), to_int(v[1]))


## An int from a number a save held (as a float it may be far larger than an int holds).
static func to_int(v) -> int:
	return clampi(int(clampf(float(v), -1e15, 1e15)), -1000000000000000, 1000000000000000)


static func is_open(f: Dictionary, c: Vector2i) -> bool:
	var grid: Array = f.grid
	return c.y >= 0 and c.y < grid.size() and c.x >= 0 and c.x < grid[c.y].size() and to_int(grid[c.y][c.x]) == 1
