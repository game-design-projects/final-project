## Everything about the current run that the picture and the sound need to read: where you are, your health, who you are
## fighting, what the log says, which menu is open. The game's stages change it; the view only reads it.
extends RefCounted

const Ally = preload("res://src/game/ally.gd")
const Chart = preload("res://src/rules/chart.gd")
const Combat = preload("res://src/rules/combat.gd")
const Clans = preload("res://src/rules/clans.gd")
const Content = preload("res://src/rules/content.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Items = preload("res://src/rules/items.gd")
const Keepsakes = preload("res://src/rules/keepsakes.gd")
const Monster = preload("res://src/rules/monster.gd")
const SaveCheck = preload("res://src/game/save_check.gd")
const Skills = preload("res://src/rules/skills.gd")
const Survival = preload("res://src/rules/survival.gd")
const Vision = preload("res://src/rules/vision.gd")

const DEPTH_MAX := 99
const CHAT_MAX := 60

var stage := ""
var depth := 1 # which floor, B1F is 1
var practice := false # on the practice floor above B1F; depth stays 1 until its stairs
var testing := false # in the test room (rules/test_room.gd): nothing here is kept, saved or counted, and `depth` is the floor of whoever is being fought; never saved
var run_seed := 0 # what this run's floors are made from (rules/floors.gd), so a printed seed replays them all
var steps := 0 # how far the party has walked this run
var chat: Array = [] # {who, text}: everything said this run, oldest first, up to CHAT_MAX
var _said: Array = [] # the lines last said, so one carried over isn't kept twice
var listening := false # a monster is taking in what you typed
var views := {} # the features the picture may show, as the flow worked them out
var floors_of := 0 # how many floors the run has, for the header (0: it doesn't say)
var banner = null # a moment on the picture, {title, text, t0, ms} (see flow.announce)
var run_over := false # the run ended at the stairs: there is no floor below
var palette_id := 0 # which colours this run wears (Palette.for_run), picked from the seed and saved with the run

# the walk
var floor_map # FloorMap
var cell := Vector2i(1, 1)
var facing := 0
var quarter_turns := 0 # every quarter turn made, right +1 and left -1, adding up: the camera follows this, not `facing`, which is mod 4
var visited := {} # Vector2i -> true: cells you stood in
var in_sight := {} # Vector2i -> true: the cells the camera sees right now; worked out again by `look`
var seen := {} # Vector2i -> true: cells you saw from where you stood (rules/vision.gd), for the automap
var lords_met: Array = [] # the clans whose lord was paid a favour this run (rules/lords.gd)
var lords_sworn: Array = [] # and those sworn to you by its second favour
var lords_warren: Array = [] # a sworn lord that had no place in the party opens its clan's warren on the next stairs
var charted := {} # Vector2i -> true: cells not seen yet whose layout a map or your instinct told you (rules/chart.gd)
var _reach := {} # the cells that can be walked to from the floor's start, kept until the floor or its walls change
var _reach_key := []

# the party
var hp := Combat.START_HP
var max_hp := Combat.START_HP
var gold := Combat.START_GOLD
var allies: Array = [] # Ally
var tally := {"spared": 0, "slain": 0, "fled": 0, "recruited": 0, "left": 0}
var reputation := {} # clan -> how it thinks of you, -100..100 (rules/clans.gd)
var deeds: Array = [] # {clan, species, who, deed}: what you did to whom, oldest first
var questers_met: Array = [] # the names of the ones who asked a favour and were heard: kept after their floor, as deeds keep the ones fought
var items: Array = [] # item ids in the bag (rules/items.gd)
var sharpened := 0 # what a whetstone adds to your next strike that lands
var heavy_known := {} # species -> true, once a heavy strike has shown you how it takes one
var vignette := "" # what the walk has stopped at, for the picture to show (view/vignette.gd): set by the stage, "" on the walk; never saved
var keepsakes: Array = [] # the keepsakes taken from champions this run, in the order taken (rules/keepsakes.gd, the feature keepsakes)
var skills: Array = [] # the skills held (rules/skills.gd): given by the feature skill-combat, kept in a save made with it
var hunger := 0.0 # 0 fed .. rules/survival.gd's starving_at
var starved_steps := 0 # steps walked starving
var butchered: Array = [] # {species, name}: the friends who went into the bag
var meals := 0 # how many bowls you have fed the others
var left_behind: Array = [] # the names of the friends left at a gate's chain
var found_out := false # one of them worked it out
var warmth_level := -1 # the level of warmth last noted on the walk (rules/warmth.gd), -1 until then; worked out again on a load, not saved

# the fight
var foe # Monster, or null when not in a fight
var dodge # DodgeRun while the stage is "dodge"
var bar = null # {t0, dur} while the strike bar sweeps
var skill_fight = null # this fight's energy, cooldowns, block and bruises (Skills.new_fight), with the feature skill-combat; null without it
var nerve := 0 # what holding your ground in the dodge box has earned this fight, 0..Combat.NERVE_MAX: the next strike that lands or SPARE spends it (the feature nerve)
var second_wind_used := false # the keepsake second wind has kept you standing once this fight
var keepsake_due := "" # the name of a champion just put out of the way, until the fight's end offers its keepsakes
var struggle := 0.0 # how much the player has been hit lately: the dodge eases off (rules/pace.gd)
var rotate_mini_games := false # every third attack is a mini-game (the flow turns it on; a test may leave it off)
var social_offer := {} # only the social stage owns this popup
var social_typing := false
var social_note := ""
var social_heard := {} # the typed line the popup is previewing: {text, choice (an index into the menu, or -1 for plain words), words}
var recent_social := "" # last species to offer, to space repeated topics
var encounter_start := {} # snapshot (foe, purse, tally, party) taken when a fight begins, to try it again after dying; a retry starts at full HP

# what the screen shows
var lines: Array = [] # [{kind: "sys" | "say", who, text}]
var menu: Array = [] # [{label, sub, gold}]
var selected := 0
var hint := "" # the key hints for this stage
var mind_rows: Array = [] # what the mind answered last, [{id, label, answer}], for the debug panel and tooltips


## How many of the party count against its limit: a friend who isn't a monster takes nobody's place.
func party_size() -> int:
	return allies.filter(func(a): return not Content.table("friends").has(a.species)).size()


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


## The cells that can be walked to from the floor's start, as a set (rules/chart.gd): worked out once, and again when a wall breaks.
func reach() -> Dictionary:
	var key := [floor_map, floor_map.changes]
	if key != _reach_key:
		var t0 := Time.get_ticks_usec()
		_reach = Chart.reach(floor_map)
		_reach_key = key
		print_verbose("state: %d cells can be walked to, worked out in %d us" % [_reach.size(), Time.get_ticks_usec() - t0])
	return _reach


## Note where the monsters in view are now, for the map.
func spot() -> void:
	for m in floor_map.monsters:
		if in_sight.has(m.cell):
			m.last_seen = m.cell


## "spared 1 · slain 0 · 8 gold", for the log when you come back to a save.
func summary() -> String:
	return "HP %d/%d · gold %d · spared %d · slain %d" % [hp, max_hp, gold, tally.spared, tally.slain]


## The names of the monsters met this run as far as it remembers them (upper case -> true): the floor you are on (or leaving),
## the one asking on it, the ones asking on the floors before it, the ones the clans talk about, the party and the friends you
## lost. A new floor gives its monsters other names.
func names_met() -> Dictionary:
	var out := {}
	if floor_map != null:
		for m in floor_map.monsters:
			out[str(m.name).to_upper()] = true
		if not floor_map.quester.is_empty(): # the one asking is a monster of the run too, named from the same pools
			out[str(floor_map.quester.get("name", "")).to_upper()] = true
	for n in questers_met: # and the ones heard asking on the floors before
		out[str(n).to_upper()] = true
	for d in deeds:
		out[str(d.who).to_upper()] = true
	for a in allies:
		out[str(a.name).to_upper()] = true
	for b in butchered:
		out[str(b.get("name", "")).to_upper()] = true
	for n in left_behind:
		out[str(n).to_upper()] = true
	out.erase("")
	return out


func to_dict() -> Dictionary:
	var visited_cells := []
	for c in visited:
		visited_cells.append([c.x, c.y])
	var seen_cells := []
	for c in seen:
		seen_cells.append([c.x, c.y])
	var out := {
		"depth": depth, "runSeed": run_seed, "palette": palette_id, "floor": floor_map.to_dict(), "cell": [cell.x, cell.y], "facing": facing, "visited": visited_cells, "seen": seen_cells,
		"recentSocial": recent_social, "hp": hp, "maxHp": max_hp, "gold": gold, "tally": tally.duplicate(),
		"allies": allies.map(func(a): return a.to_dict()), "chat": chat.duplicate(),
		"reputation": reputation.duplicate(), "deeds": deeds.duplicate(),
		"items": items.duplicate(), "sharpened": sharpened, "heavyKnown": heavy_known.keys(),
		"hunger": hunger, "starvedSteps": starved_steps, "butchered": butchered.duplicate(true), "leftBehind": left_behind.duplicate(), "meals": meals, "foundOut": found_out,
	}
	if practice:
		out.practice = true # only then, so a save from any other floor reads as it always did
	if not skills.is_empty(): # a save made without skill-combat stays as it was
		out.skills = skills.duplicate()
	if not keepsakes.is_empty(): # and so does one with no keepsake taken
		out.keepsakes = keepsakes.duplicate()
	if not questers_met.is_empty(): # and one whose run has heard nobody asking
		out.questersMet = questers_met.duplicate()
	if not charted.is_empty(): # and one whose floor has no map of it yet
		out.charted = charted.keys().map(func(c): return [c.x, c.y])
	if not lords_met.is_empty():
		out.lordsMet = lords_met.duplicate()
	if not lords_sworn.is_empty():
		out.lordsSworn = lords_sworn.duplicate()
	if not lords_warren.is_empty():
		out.lordsWarren = lords_warren.duplicate()
	return out


## A saved state, or null when `d` isn't one of ours or can't be played (nothing is changed then). A save is data from outside
## (a file, a copied slot), so every value is checked before it is used: a wrong kind of value refuses the save, a value out of
## range is brought back into it (the cell must be open, health stays within 1..max, loyalty within 0..100).
static func from_dict(d: Dictionary):
	var problem := SaveCheck.problem(d)
	if problem != "":
		push_warning("state: saved state refused, %s" % problem)
		return null
	var s = new()
	s.depth = clampi(SaveCheck.to_int(d.get("depth", 1)), 1, DEPTH_MAX)
	s.practice = d.get("practice") == true
	s.run_seed = maxi(0, SaveCheck.to_int(d.runSeed)) if SaveCheck.is_num(d.get("runSeed")) else s.floor_map_seed(d)
	s.floor_map = FloorMap.from_dict(d.floor, Monster)
	# a save from before palettes were saved wears the colours its floor's seed would pick
	s.palette_id = int(d.palette) if d.get("palette") is float or d.get("palette") is int else s.floor_map.seed_value
	s.cell = SaveCheck.cell(d.cell)
	s.facing = posmod(SaveCheck.to_int(d.facing), 4)
	for c in d.get("visited", []) if d.get("visited") is Array else []:
		if SaveCheck.is_cell(c) and s.floor_map.is_open(SaveCheck.cell(c)):
			s.visited[SaveCheck.cell(c)] = true
	for c in d.get("seen", []) if d.get("seen") is Array else []:
		if SaveCheck.is_cell(c) and s.floor_map.is_open(SaveCheck.cell(c)):
			s.seen[SaveCheck.cell(c)] = true
	for clan in d.get("lordsMet", []) if d.get("lordsMet") is Array else []:
		if Clans.is_clan(str(clan)) and not s.lords_met.has(str(clan)):
			s.lords_met.append(str(clan))
	for clan in d.get("lordsSworn", []) if d.get("lordsSworn") is Array else []:
		if Clans.is_clan(str(clan)) and not s.lords_sworn.has(str(clan)):
			s.lords_sworn.append(str(clan))
	for clan in d.get("lordsWarren", []) if d.get("lordsWarren") is Array else []:
		if Clans.is_clan(str(clan)) and not s.lords_warren.has(str(clan)):
			s.lords_warren.append(str(clan))
	for c in d.get("charted", []) if d.get("charted") is Array else []:
		if SaveCheck.is_cell(c) and s.floor_map.is_open(SaveCheck.cell(c)):
			s.charted[SaveCheck.cell(c)] = true
	s.look()
	s.max_hp = maxi(1, SaveCheck.to_int(d.maxHp))
	s.hp = clampi(SaveCheck.to_int(d.hp), 1, s.max_hp)
	s.gold = maxi(0, SaveCheck.to_int(d.gold))
	s.recent_social = str(d.get("recentSocial", ""))
	for k in s.tally:
		s.tally[k] = maxi(0, SaveCheck.to_int(d.tally.get(k, 0)))
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
	s.sharpened = maxi(0, SaveCheck.to_int(d.sharpened)) if SaveCheck.is_num(d.get("sharpened")) else 0
	for id in d.get("skills", []) if d.get("skills") is Array else []:
		Skills.learn(s.skills, str(id))
	for id in d.get("keepsakes", []) if d.get("keepsakes") is Array else []:
		if id is String and Keepsakes.known(id) and not s.keepsakes.has(id): # what the ember heart gave is in maxHp already
			s.keepsakes.append(id)
	for species in d.get("heavyKnown", []) if d.get("heavyKnown") is Array else []:
		if Content.is_monster(str(species)):
			s.heavy_known[str(species)] = true
	s.hunger = clampf(float(d.hunger), 0.0, float(Survival.table().hunger.starving_at)) if SaveCheck.is_num(d.get("hunger")) else 0.0
	s.starved_steps = maxi(0, SaveCheck.to_int(d.starvedSteps)) if SaveCheck.is_num(d.get("starvedSteps")) else 0
	s.meals = maxi(0, SaveCheck.to_int(d.meals)) if SaveCheck.is_num(d.get("meals")) else 0
	s.found_out = d.get("foundOut") == true
	for who in d.get("leftBehind", []) if d.get("leftBehind") is Array else []:
		if who is String:
			s.left_behind.append(who)
	for who in d.get("questersMet", []) if d.get("questersMet") is Array else []:
		if who is String and who != "":
			s.questers_met.append(who)
	for b in d.get("butchered", []) if d.get("butchered") is Array else []:
		if b is Dictionary and b.get("species") is String and b.get("name") is String:
			s.butchered.append({"species": b.species, "name": b.name})
	for a in d.allies:
		var ally = Ally.from_dict(a)
		ally.loyalty = clampf(ally.loyalty, 0.0, 100.0)
		s.allies.append(ally)
		if s.party_size() > Combat.PARTY_MAX: # a friend who isn't a monster (data/friends.json) doesn't count
			s.allies.pop_back()
	return s


## What a save from before `runSeed` was saved goes on from: its floor's own seed.
func floor_map_seed(d: Dictionary) -> int:
	return maxi(0, SaveCheck.to_int(d.floor.get("seed", 0))) if SaveCheck.is_num(d.floor.get("seed")) else 0


## Whether `d` is a state `from_dict` would read (the menu asks before it leaves for the game).
static func is_playable(d: Dictionary) -> bool:
	var problem := SaveCheck.problem(d)
	if problem != "":
		push_warning("state: not playable, %s" % problem)
	return problem == ""
