## Everything about the current run that the picture and the sound need to read: where you are, your health, who you are
## fighting, what the log says, which menu is open. The game's stages change it; the view only reads it.
extends RefCounted

const Ally = preload("res://src/game/ally.gd")
const Combat = preload("res://src/rules/combat.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Monster = preload("res://src/rules/monster.gd")
const Vision = preload("res://src/rules/vision.gd")

var stage := ""
var depth := 1 # which floor, B1F is 1; it picks the colours

# the walk
var floor_map # FloorMap
var cell := Vector2i(1, 1)
var facing := 0
var quarter_turns := 0 # every quarter turn made, right +1 and left -1, adding up: the camera follows this, not `facing`, which is mod 4
var visited := {} # Vector2i -> true: cells you stood in
var seen := {} # Vector2i -> true: cells you saw down a corridor, for the automap

# the party
var hp := Combat.START_HP
var max_hp := Combat.START_HP
var gold := Combat.START_GOLD
var allies: Array = [] # Ally
var tally := {"spared": 0, "slain": 0, "fled": 0, "recruited": 0, "left": 0}

# the fight
var foe # Monster, or null when not in a fight
var dodge # DodgeRun while the stage is "dodge"
var bar = null # {t0, dur} while the strike bar sweeps
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


func say(new_lines: Array) -> void:
	lines = new_lines


static func sys_line(text: String) -> Dictionary:
	return {"kind": "sys", "who": "", "text": text}


static func speech(who: String, text: String) -> Dictionary:
	return {"kind": "say", "who": who, "text": text}


## Turn on the spot: 1 a quarter to the right, -1 to the left.
func turn(quarters: int) -> void:
	facing = posmod(facing + quarters, 4)
	quarter_turns += quarters
	look()


## Remember what you can see from here (after a step or a turn): the cells straight ahead, and where a monster stands that
## you can see, so the automap shows what the 3D view shows.
func look() -> void:
	for c in Vision.ahead(floor_map, cell, facing):
		seen[c] = true
	for m in Vision.monsters(floor_map, cell, facing):
		seen[m.cell] = true


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
		"depth": depth, "floor": floor_map.to_dict(), "cell": [cell.x, cell.y], "facing": facing, "visited": visited_cells, "seen": seen_cells,
		"hp": hp, "maxHp": max_hp, "gold": gold, "tally": tally.duplicate(),
		"allies": allies.map(func(a): return a.to_dict()),
	}


## A saved state, or null when `d` isn't one of ours (nothing is changed then).
static func from_dict(d: Dictionary):
	for key in ["floor", "cell", "facing", "hp", "maxHp", "gold", "tally", "allies"]:
		if not d.has(key):
			push_warning("state: saved state lacks '%s'" % key)
			return null
	var s = new()
	s.depth = maxi(1, int(d.get("depth", 1)))
	s.floor_map = FloorMap.from_dict(d.floor, Monster)
	s.cell = Vector2i(int(d.cell[0]), int(d.cell[1]))
	s.facing = posmod(int(d.facing), 4)
	for c in d.get("visited", []):
		s.visited[Vector2i(int(c[0]), int(c[1]))] = true
	for c in d.get("seen", []):
		s.seen[Vector2i(int(c[0]), int(c[1]))] = true
	s.look()
	s.hp = int(d.hp)
	s.max_hp = int(d.maxHp)
	s.gold = int(d.gold)
	for k in s.tally:
		s.tally[k] = int(d.tally.get(k, 0))
	s.allies = d.allies.map(func(a): return Ally.from_dict(a))
	return s
