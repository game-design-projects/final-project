## Everything about the current run that the picture and the sound need to read: where you are, your health, who you are
## fighting, what the log says, which menu is open. The game's stages change it; the view only reads it.
extends RefCounted

const Ally = preload("res://src/game/ally.gd")
const Combat = preload("res://src/rules/combat.gd")
const Clans = preload("res://src/rules/clans.gd")
const Content = preload("res://src/rules/content.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Items = preload("res://src/rules/items.gd")
const Monster = preload("res://src/rules/monster.gd")
const Requests = preload("res://src/rules/requests.gd")
const Survival = preload("res://src/rules/survival.gd")
const Vision = preload("res://src/rules/vision.gd")

const DEPTH_MAX := 99
const CHAT_MAX := 60
const GRID_MAX := 64 # the biggest floor a save may describe (the biomes' largest is 31)

var stage := ""
var depth := 1 # which floor, B1F is 1
var run_seed := 0 # what this run's floors are made from (rules/floors.gd), so a printed seed replays them all
var steps := 0 # how far the party has walked this run
var chat: Array = [] # {who, text}: everything said this run, oldest first, up to CHAT_MAX
var _said: Array = [] # the lines last said, so one carried over isn't kept twice
var listening := false # a monster is taking in what you typed
var views := {} # the features the picture may show, as the flow worked them out (off on the personality slice)
var floors_of := 0 # how many floors the run has, for the header (0: it doesn't say)
var banner = null # a moment on the picture, {title, text, t0, ms} (see flow.announce)
var run_over := false # the run ended at the stairs: there is no floor below (always so without the feature real-floors)
var palette_id := 0 # which colours this run wears (Palette.for_run), picked from the seed and saved with the run

# the walk
var floor_map # FloorMap
var cell := Vector2i(1, 1)
var facing := 0
var quarter_turns := 0 # every quarter turn made, right +1 and left -1, adding up: the camera follows this, not `facing`, which is mod 4
var visited := {} # Vector2i -> true: cells you stood in
var in_sight := {} # Vector2i -> true: the cells the camera sees right now; worked out again by `look`
var seen := {} # Vector2i -> true: cells you saw from where you stood (rules/vision.gd), for the automap

# the party
var hp := Combat.START_HP
var max_hp := Combat.START_HP
var gold := Combat.START_GOLD
var allies: Array = [] # Ally
var tally := {"spared": 0, "slain": 0, "fled": 0, "recruited": 0, "left": 0}
var reputation := {} # clan -> how it thinks of you, -100..100 (rules/clans.gd)
var deeds: Array = [] # {clan, species, who, deed}: what you did to whom, oldest first
var items: Array = [] # item ids in the bag (rules/items.gd)
var sharpened := 0 # what a whetstone adds to your next strike that lands
var heavy_known := {} # species -> true, once a heavy strike has shown you how it takes one
var hunger := 0.0 # 0 fed .. rules/survival.gd's starving_at
var starved_steps := 0 # steps walked starving
var butchered: Array = [] # {species, name}: the friends who went into the bag
var meals := 0 # how many bowls you have fed the others
var found_out := false # one of them worked it out

# the fight
var foe # Monster, or null when not in a fight
var dodge # DodgeRun while the stage is "dodge"
var bar = null # {t0, dur} while the strike bar sweeps
var struggle := 0.0 # how much the player has been hit lately: the dodge eases off (rules/pace.gd)
var rotate_mini_games := false # every third attack is a mini-game (the feature mini-games)
var encounter_start := {} # snapshot (foe, purse, tally, party) taken when a fight begins, to try it again after dying; a retry starts at full HP

# what the screen shows
var lines: Array = [] # [{kind: "sys" | "say", who, text}]
var menu: Array = [] # [{label, sub, gold}]
var selected := 0
var hint := "" # the key hints for this stage
var mind_rows: Array = [] # what the mind answered last, [{id, label, answer}], for the debug panel and tooltips


func has_ally(species: String) -> bool:
	return allies.any(func(a): return a.species == species)


## Which charms are active, for the dodge: {"slime": true, ...}
func charms() -> Dictionary:
	var out := {}
	for a in allies:
		out[a.species] = true
	return out


## The attack `m` fights with on its current turn.
func genre_of(m) -> String:
	var enc := Content.table("encounter")
	return Dodge.genre_on_turn(m, enc.boss.genres, enc.mini_games if rotate_mini_games else [])


## Whether the views should show this feature.
func viewing(feature_name: String) -> bool:
	return views.get(feature_name, false)


func say(new_lines: Array) -> void:
	lines = new_lines
	for l in new_lines:
		if l.kind == "say" and l not in _said:
			add_chat(l.who, l.text)
	_said = new_lines


## Keep a line of talk for the chat card.
func add_chat(who: String, text: String) -> void:
	chat.append({"who": who, "text": text})
	if chat.size() > CHAT_MAX:
		chat = chat.slice(-CHAT_MAX)


static func sys_line(text: String) -> Dictionary:
	return {"kind": "sys", "who": "", "text": text}


static func speech(who: String, text: String) -> Dictionary:
	return {"kind": "say", "who": who, "text": text}


## Turn on the spot: 1 a quarter to the right, -1 to the left.
func turn(quarters: int) -> void:
	facing = posmod(facing + quarters, 4)
	quarter_turns += quarters
	look()


## Remember what you know from here (after a step or a turn): the cells straight ahead, and where a monster stands that is
## in front of you with nothing between (a little wider than the picture, which has its own field of view).
func look() -> void:
	var t0 := Time.get_ticks_usec()
	for c in Vision.ahead(floor_map, cell, facing):
		seen[c] = true
	in_sight = {}
	for c in Vision.sight(floor_map, cell, facing):
		seen[c] = true
		in_sight[c] = true
	spot()
	print_verbose("state: sight from %s took %d us, %d cells" % [cell, Time.get_ticks_usec() - t0, in_sight.size()])


## Note where the monsters in view are now, for the map.
func spot() -> void:
	for m in floor_map.monsters:
		if in_sight.has(m.cell):
			m.last_seen = m.cell


## "spared 1 · slain 0 · 8 gold", for the log when you come back to a save.
func summary() -> String:
	return "HP %d/%d · gold %d · spared %d · slain %d" % [hp, max_hp, gold, tally.spared, tally.slain]


func to_dict() -> Dictionary:
	var visited_cells := []
	for c in visited:
		visited_cells.append([c.x, c.y])
	var seen_cells := []
	for c in seen:
		seen_cells.append([c.x, c.y])
	return {
		"depth": depth, "runSeed": run_seed, "palette": palette_id, "floor": floor_map.to_dict(), "cell": [cell.x, cell.y], "facing": facing, "visited": visited_cells, "seen": seen_cells,
		"hp": hp, "maxHp": max_hp, "gold": gold, "tally": tally.duplicate(),
		"allies": allies.map(func(a): return a.to_dict()), "chat": chat.duplicate(),
		"reputation": reputation.duplicate(), "deeds": deeds.duplicate(),
		"items": items.duplicate(), "sharpened": sharpened, "heavyKnown": heavy_known.keys(),
		"hunger": hunger, "starvedSteps": starved_steps, "butchered": butchered.duplicate(true), "meals": meals, "foundOut": found_out,
	}


## A saved state, or null when `d` isn't one of ours or can't be played (nothing is changed then). A save is data from outside
## (a file, a copied slot), so every value is checked before it is used: a wrong kind of value refuses the save, a value out of
## range is brought back into it (the cell must be open, health stays within 1..max, loyalty within 0..100).
static func from_dict(d: Dictionary):
	var problem := _problem(d)
	if problem != "":
		push_warning("state: saved state refused, %s" % problem)
		return null
	var s = new()
	s.depth = clampi(_int(d.get("depth", 1)), 1, DEPTH_MAX)
	s.run_seed = maxi(0, _int(d.runSeed)) if _is_num(d.get("runSeed")) else s.floor_map_seed(d)
	s.floor_map = FloorMap.from_dict(d.floor, Monster)
	# a save from before palettes were saved wears the colours its floor's seed would pick
	s.palette_id = int(d.palette) if d.get("palette") is float or d.get("palette") is int else s.floor_map.seed_value
	s.cell = _cell(d.cell)
	s.facing = posmod(_int(d.facing), 4)
	for c in d.get("visited", []) if d.get("visited") is Array else []:
		if _is_cell(c) and s.floor_map.is_open(_cell(c)):
			s.visited[_cell(c)] = true
	for c in d.get("seen", []) if d.get("seen") is Array else []:
		if _is_cell(c) and s.floor_map.is_open(_cell(c)):
			s.seen[_cell(c)] = true
	s.look()
	s.max_hp = maxi(1, _int(d.maxHp))
	s.hp = clampi(_int(d.hp), 1, s.max_hp)
	s.gold = maxi(0, _int(d.gold))
	for k in s.tally:
		s.tally[k] = maxi(0, _int(d.tally.get(k, 0)))
	for c in d.get("chat", []) if d.get("chat") is Array else []:
		if c is Dictionary:
			s.add_chat(str(c.get("who", "")), str(c.get("text", "")))
	for clan in d.get("reputation", {}):
		if Clans.is_clan(str(clan)):
			s.reputation[str(clan)] = clampf(float(d.reputation[clan]), -Clans.STANDING_MAX, Clans.STANDING_MAX)
	for deed in d.get("deeds", []).slice(-Clans.DEEDS_MAX):
		if Clans.is_clan(str(deed.get("clan", ""))):
			s.deeds.append({"clan": str(deed.clan), "species": str(deed.get("species", "")), "who": str(deed.get("who", "")), "deed": str(deed.get("deed", ""))})
	for id in d.get("items", []) if d.get("items") is Array else []:
		if Items.known(str(id)):
			Items.carry(s, str(id))
	s.sharpened = maxi(0, _int(d.sharpened)) if _is_num(d.get("sharpened")) else 0
	for species in d.get("heavyKnown", []) if d.get("heavyKnown") is Array else []:
		if Combat.HEAVY_WEAK.has(str(species)):
			s.heavy_known[str(species)] = true
	s.hunger = clampf(float(d.hunger), 0.0, float(Survival.table().hunger.starving_at)) if _is_num(d.get("hunger")) else 0.0
	s.starved_steps = maxi(0, _int(d.starvedSteps)) if _is_num(d.get("starvedSteps")) else 0
	s.meals = maxi(0, _int(d.meals)) if _is_num(d.get("meals")) else 0
	s.found_out = d.get("foundOut") == true
	for b in d.get("butchered", []) if d.get("butchered") is Array else []:
		if b is Dictionary and b.get("species") is String and b.get("name") is String:
			s.butchered.append({"species": b.species, "name": b.name})
	for a in d.allies.slice(0, Combat.PARTY_MAX):
		var ally = Ally.from_dict(a)
		ally.loyalty = clampf(ally.loyalty, 0.0, 100.0)
		s.allies.append(ally)
	return s


## What a save from before `runSeed` was saved goes on from: its floor's own seed.
func floor_map_seed(d: Dictionary) -> int:
	return maxi(0, _int(d.floor.get("seed", 0))) if _is_num(d.floor.get("seed")) else 0


## Whether `d` is a state `from_dict` would read (the menu asks before it leaves for the game).
static func is_playable(d: Dictionary) -> bool:
	var problem := _problem(d)
	if problem != "":
		push_warning("state: not playable, %s" % problem)
	return problem == ""


## What is wrong with this saved state, or "" when it can be read.
static func _problem(d: Dictionary) -> String:
	for key in ["floor", "cell", "facing", "hp", "maxHp", "gold", "tally", "allies"]:
		if not d.has(key):
			return "it lacks '%s'" % key
	for key in ["facing", "hp", "maxHp", "gold"]:
		if not _is_num(d[key]):
			return "'%s' is not a number" % key
	if d.has("depth") and not _is_num(d.depth):
		return "'depth' is not a number"
	if d.has("runSeed") and not _is_num(d.runSeed):
		return "'runSeed' is not a number"
	if not d.tally is Dictionary or d.tally.values().any(func(v): return not _is_num(v)):
		return "'tally' is not a record of numbers"
	if not d.allies is Array:
		return "'allies' is not a list"
	for a in d.allies:
		if not a is Dictionary or not Content.table("species").has(str(a.get("species", ""))) or not _is_num(a.get("loyalty", 60.0)):
			return "an ally is not a known one"
	if d.has("reputation") and (not d.reputation is Dictionary or d.reputation.values().any(func(v): return not _is_num(v))):
		return "'reputation' is not a record of numbers"
	if d.has("deeds") and (not d.deeds is Array or d.deeds.any(func(v): return not v is Dictionary)):
		return "'deeds' is not a list of records"
	var problem := _floor_problem(d.floor)
	if problem != "":
		return problem
	if not _is_cell(d.cell) or not _open(d.floor, _cell(d.cell)):
		return "the party's cell is not an open cell of the floor"
	return ""


static func _floor_problem(f) -> String:
	if not f is Dictionary:
		return "'floor' is not a record"
	var size = f.get("size")
	if not _is_num(size) or _int(size) < 3 or _int(size) > GRID_MAX:
		return "the floor's size is not between 3 and %d" % GRID_MAX
	var grid = f.get("grid")
	if not grid is Array or grid.size() != _int(size):
		return "the floor's grid is not as tall as its size"
	for row in grid:
		if not row is Array or row.size() != _int(size) or row.any(func(v): return not _is_num(v)):
			return "a row of the floor's grid is not a row of numbers as wide as its size"
	for key in ["stairs", "start"]:
		if not _is_cell(f.get(key)) or not _open(f, _cell(f[key])):
			return "the floor's %s is not an open cell" % key
	if f.has("biome") and not f.biome is String:
		return "the floor's biome is not a word"
	if f.has("treasure"):
		if not f.treasure is Array or f.treasure.any(func(t): return not t is Dictionary or not _is_cell(t.get("cell")) or not _open(f, _cell(t.cell)) or not _is_num(t.get("gold"))):
			return "the floor's chests are not a list of open cells with gold"
	if f.has("teleports"):
		if not f.teleports is Array or f.teleports.any(func(t): return not t is Dictionary or not _is_cell(t.get("a")) or not _is_cell(t.get("b")) or not _open(f, _cell(t.a)) or not _open(f, _cell(t.b))):
			return "the floor's pads are not a list of pairs of open cells"
	if f.has("pickups"):
		if not f.pickups is Array or f.pickups.any(func(p): return not p is Dictionary or not _is_cell(p.get("cell")) or not _open(f, _cell(p.cell)) or not Items.known(str(p.get("item", "")))):
			return "the floor's items are not a list of open cells with known items"
	if f.has("merchant") and not f.merchant is Dictionary:
		return "the floor's trader is not a record"
	if f.has("merchant") and not f.merchant.is_empty():
		if not _is_cell(f.merchant.get("cell")) or not _open(f, _cell(f.merchant.cell)) or not f.merchant.get("stock") is Array or f.merchant.stock.any(func(id): return not Items.known(str(id))):
			return "the floor's trader is not on an open cell with known stock"
	if not f.get("monsters") is Array:
		return "the floor's monsters are not a list"
	for m in f.monsters:
		var problem := _monster_problem(m, f)
		if problem != "":
			return problem
	if f.has("steps") and not _is_num(f.steps):
		return "the floor's steps are not a number"
	if f.has("quester") and not f.quester is Dictionary:
		return "the floor's request is not a record"
	if f.has("quester") and not f.quester.is_empty():
		if not _is_cell(f.quester.get("cell")) or not _open(f, _cell(f.quester.cell)):
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
	if not _is_cell(m.get("cell")) or not _open(f, _cell(m.cell)):
		return "a monster is not on an open cell"
	for key in ["hp", "maxHp", "threshold", "turn"]:
		if m.has(key) and not _is_num(m[key]):
			return "a monster's '%s' is not a number" % key
	if m.has("meters") and (not m.meters is Dictionary or m.meters.values().any(func(v): return not _is_num(v))):
		return "a monster's meters are not a record of numbers"
	if m.has("checks") and not _is_num(m.checks):
		return "a monster's 'checks' is not a number"
	if m.has("tried") and not m.tried is Dictionary:
		return "a monster's 'tried' is not a record"
	if m.has("knownTraits") and not m.knownTraits is Array:
		return "a monster's 'knownTraits' is not a list"
	if m.has("heard") and (not m.heard is Dictionary or (m.heard.has("standing") and not _is_num(m.heard.standing))):
		return "what a monster heard is not a record"
	if m.has("traits") and (not m.traits is Array or m.traits.any(func(t): return not t is String)):
		return "a monster's traits are not a list of words"
	for key in ["purse", "hold", "leg"]:
		if m.has(key) and not _is_num(m[key]):
			return "a monster's '%s' is not a number" % key
	if m.has("patrol") and (not m.patrol is Array or m.patrol.size() not in [0, 2] or m.patrol.any(func(c): return not _is_cell(c) or not _open(f, _cell(c)))):
		return "a monster's beat is not two open cells"
	if m.has("lastSeen") and not _is_cell(m.lastSeen):
		return "where a monster was last seen is not a cell"
	if m.has("taste") and (not m.taste is Dictionary or m.taste.values().any(func(v): return not _is_num(v))):
		return "a monster's taste is not a record of numbers"
	return ""


static func _is_num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _is_cell(v) -> bool:
	return v is Array and v.size() == 2 and _is_num(v[0]) and _is_num(v[1])


static func _cell(v) -> Vector2i:
	return Vector2i(_int(v[0]), _int(v[1]))


## An int from a number a save held (as a float it may be far larger than an int holds).
static func _int(v) -> int:
	return clampi(int(clampf(float(v), -1e15, 1e15)), -1000000000000000, 1000000000000000)


static func _open(f: Dictionary, c: Vector2i) -> bool:
	var grid: Array = f.grid
	return c.y >= 0 and c.y < grid.size() and c.x >= 0 and c.x < grid[c.y].size() and _int(grid[c.y][c.x]) == 1
