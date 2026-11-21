## The test room: one hall that holds every monster there is, for trying each of them out. They stand in rows with an aisle
## either side of each: the kinds of B1F nearest the start, each deeper floor's behind them, then one elite of every clan
## (data/floors.json's `test_room.elites` says of which kind), and the champions at the far end. Each is made as its own floor
## would make it (its health at that floor's toughness, a champion with its floor's attacks), nobody walks about, and the stairs
## in the corner behind you are the way out. The flow puts the room and the party back as they were after every fight
## (game/flow.gd), so one fight never colours the next. The hall is built from data/kinds.json, so a new kind has its place here
## without anyone drawing it in.
extends RefCounted

const Clans = preload("res://src/rules/clans.gd")
const Content = preload("res://src/rules/content.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Floors = preload("res://src/rules/floors.gd")
const Kinds = preload("res://src/rules/kinds.gd")
const Lords = preload("res://src/rules/lords.gd")
const Requests = preload("res://src/rules/requests.gd")
const Monster = preload("res://src/rules/monster.gd")
const Rng = preload("res://src/utils/rng.gd")

const SEED := 400 # its monsters are drawn from a seed of their own (rules/floors.gd has 100 and 200, the practice floor 300)


static func table() -> Dictionary:
	return Content.table("floors").test_room


## Who stands in each row, the nearest first: [{depth, lines: [roster line, with `elite` on an elite's]}]. A floor's kinds in
## the file's order, then the elites, then the champions in the order of their floors.
static func rows() -> Array:
	var out := []
	for depth in range(1, Kinds.deepest() + 1):
		out.append(Kinds.at_depth(depth).map(func(line): return FloorGen.roster_line(line, Floors.plan(depth))))
	var elites := []
	for id in table().elites:
		if not Kinds.has(str(id)):
			push_error("test room: no kind '%s' to make an elite of" % id)
			continue
		var line: Dictionary = FloorGen.roster_line(Kinds.line(str(id)), Floors.plan(int(Kinds.info(str(id)).depth)))
		line.elite = true
		elites.append(line)
	out.append(elites)
	out.append(range(1, Floors.run_floors() + 1).map(func(depth): return FloorGen.champion_line(Floors.plan(depth))))
	return out


## How many monsters the room holds.
static func count() -> int:
	var n := 0
	for row in rows():
		n += row.size()
	return n


## The room, with everyone in it. `rng` names them and rolls their moods and traits, as on any floor.
static func make(rng: Rng):
	var t0 := Time.get_ticks_usec()
	var all := rows()
	var cols := 0
	for row in all:
		cols = maxi(cols, row.size())
	var inner_w := cols * 2 + 1 # an aisle, then a stall and an aisle for each
	var inner_h := all.size() * 2 + 1
	var f := FloorMap.new()
	f.seed_value = rng.seed_value
	f.size = maxi(inner_h, inner_w + 2) + 2 # a floor is square; the +2 inside leaves a wall to cut the way out into
	var left := (f.size - inner_w) / 2
	var bottom := f.size - 2 # the row the party starts in
	for y in f.size:
		var row := []
		for x in f.size:
			row.append(1 if x >= left and x < left + inner_w and y > bottom - inner_h and y <= bottom else 0)
		f.grid.append(row)
	f.start = Vector2i(left + (cols / 2) * 2, bottom) # the foot of the middle aisle, so the rows run away on both sides
	f.stairs = Vector2i(left - 1, bottom)
	f.grid[f.stairs.y][f.stairs.x] = 1
	var taken := {}
	for r in all.size():
		var row: Array = all[r]
		for c in row.size():
			var m = Monster.make(rng, row[c], Vector2i(left + 1 + c * 2, bottom - 1 - r * 2), taken)
			if row[c].get("elite", false):
				m.become_elite(float(Clans.elite().hp_scale))
			f.monsters.append(m)
	# a clan's lord asking its favour, on the aisle beside the start: the walk's other half, so a playtest can try a favour
	# (and the request stage that carries it) without reaching the floor of a run that has one. The room puts every monster back
	# after a fight, so a rid's target would be standing again before the favour could be reported and a spare's never leaves at
	# all: a fetch is the one favour the room can pay, and the lord asks for the thing that lies beside it.
	var lord: Dictionary = Lords.due("halls", f.seed_value, [], [], false, {})
	var asker_at := f.start + Vector2i(2, 0)
	if not lord.is_empty() and f.is_open(asker_at):
		lord.kind = "fetch" # the room can pay no other favour (see above)
		f.quester = {"cell": asker_at}
		if Requests.fill_lord(Rng.new(f.seed_value), f, lord, {"items": true}):
			var lying_at := f.start - Vector2i(2, 0) # the aisle on the other side of the start, where it can be walked to; nothing else lies in the room
			if str(f.quester.want) != "" and f.is_open(lying_at):
				f.pickups.append({"cell": lying_at, "item": str(f.quester.want)})
			else:
				f.quester = {} # nowhere for the thing to lie: a favour that could not be paid is no favour to show
		else:
			f.quester = {}
	print("test room: %dx%d, %d monsters in %d rows, in %d ms" % [f.size, f.size, f.monsters.size(), all.size(), (Time.get_ticks_usec() - t0) / 1000])
	return f


## The floor a monster is from: its kind's, or for a champion the floor it guards. Its fight runs at that floor's pace.
static func depth_of(m) -> int:
	if m.boss:
		var champions: Array = Content.table("floors").champions
		for i in champions.size():
			if str(champions[i].name) == m.name:
				return i + 1
		return Floors.run_floors()
	return int(Kinds.info(str(m.kind)).get("depth", 1))


## One line about who this is, for the log: its name, what it is, where it is from, how it fights and its health.
static func describe(m) -> String:
	var t := table()
	if m.boss:
		return str(t.champion) % [m.name, depth_of(m), m.max_hp]
	var genre := str(Content.table("encounter").genres[m.genre].name)
	return str(t.elite if m.elite else t.kind) % [m.name, Kinds.title(m), depth_of(m), genre, m.max_hp]


## What the log says standing at `cell` and facing `facing`: who is right in front of you, or failing that who stands at your
## sides, or "" with nobody near.
static func ahead(floor_map, cell: Vector2i, facing: int) -> String:
	var front = floor_map.monster_at(cell + FloorMap.DIRS[facing])
	if front != null:
		return describe(front)
	var left = floor_map.monster_at(cell + FloorMap.DIRS[(facing + 3) % 4])
	var right = floor_map.monster_at(cell + FloorMap.DIRS[(facing + 1) % 4])
	if left == null and right == null:
		return ""
	var t := table()
	return str(t.beside) % [_short(left, t), _short(right, t)]


static func _short(m, t: Dictionary) -> String:
	if m == null:
		return str(t.nobody)
	return m.name if m.boss else "%s%s" % ["ELITE " if m.elite else "", Kinds.title(m)]
