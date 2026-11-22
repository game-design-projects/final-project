## The clans' askers (the feature clan-requests, the owner's design): one named monster of each clan, with two requests of its
## own (data/envoys.json). Two of them stand on every floor of a run, of two clans the run's seed picks, so each clan's asker is
## met on at least two floors. A request is taken from its asker and kept for the run: some are done at the asker (bring it a
## friend, hand over gold, say something to it the mind has to judge), the others wherever they happen (ask a dragon, win a
## fight with heavy strikes only, kill five snakes). Each one done pays a little and pleases the clan; the second done for a clan
## opens its teleporter, offered at the next stairs, to the hall where its lord stands among its own (rules/clan_hall.gd).
##
## What a run has of them is `state.errands` (id -> {taken, done, n}), `state.gates` (the clans whose teleporter is open) and
## `state.lords_met` (the lords seen in their halls). Pure rules: the stages `envoy` and `envoy_say` do the talking.
extends RefCounted

const Clans = preload("res://src/rules/clans.gd")
const Content = preload("res://src/rules/content.gd")
const Rng = preload("res://src/utils/rng.gd")

const SEED := 500 # the askers' own draws (rules/floors.gd has 100 and 200, the practice floor 300, the test room and a lord 400)
## Which two of the four clans (as the run's seed orders them) have their asker on a floor, floor by floor: each clan twice in
## the first four floors, and never the same two together twice running.
const PAIRS := [[0, 1], [2, 3], [0, 2], [1, 3], [0, 3], [1, 2]]
const KINDS := ["ask_dragon", "bring", "heavy_win", "say", "slay", "gold"]
const SAID_AT := ["say"] # the kinds typed to the asker itself
const GIVEN_AT := ["bring", "gold"] # the kinds handed over at the asker


static func table() -> Dictionary:
	return Content.table("envoys")


static func clans() -> Array:
	return table().clans.keys()


static func is_clan(clan: String) -> bool:
	return table().clans.has(clan)


## A clan's asker: {name, species, hall, lord_says, requests}.
static func entry(clan: String) -> Dictionary:
	return table().clans[clan]


## A clan's requests, each with its `clan` beside it.
static func requests_of(clan: String) -> Array:
	return entry(clan).requests.map(func(r): return _with_clan(r, clan))


## The request with this id (with its `clan`), or {}.
static func request(id: String) -> Dictionary:
	for clan in clans():
		for r in entry(clan).requests:
			if str(r.id) == id:
				return _with_clan(r, clan)
	return {}


static func _with_clan(r: Dictionary, clan: String) -> Dictionary:
	var out := r.duplicate()
	out.clan = clan
	return out


## The clans whose askers stand on floor `depth` of this run.
static func on_floor(run_seed: int, depth: int) -> Array:
	var order: Array = clans()
	Rng.new(Rng.offset(run_seed, SEED)).shuffle(order)
	var pair: Array = PAIRS[posmod(depth - 1, PAIRS.size())]
	return pair.slice(0, int(table().per_floor)).map(func(i): return str(order[i]))


## An asker as a floor holds it: {cell, clan, name, species}.
static func figure(clan: String, cell: Vector2i) -> Dictionary:
	return {"cell": cell, "clan": clan, "name": str(entry(clan).name), "species": str(entry(clan).species)}


# ---------------------------------------------------------------- what the run has of them

static func _log(s, id: String) -> Dictionary:
	if not s.errands.has(id):
		s.errands[id] = {"taken": false, "done": false, "n": 0}
	return s.errands[id]


static func is_taken(s, id: String) -> bool:
	return bool(s.errands.get(id, {}).get("taken", false))


static func is_done(s, id: String) -> bool:
	return bool(s.errands.get(id, {}).get("done", false))


## How far along a counted request is.
static func count(s, id: String) -> int:
	return int(s.errands.get(id, {}).get("n", 0))


## How many of a clan's requests are done.
static func done_for(s, clan: String) -> int:
	return requests_of(clan).filter(func(r): return is_done(s, str(r.id))).size()


## A clan's requests that are still to do.
static func open_for(s, clan: String) -> Array:
	return requests_of(clan).filter(func(r): return not is_done(s, str(r.id)))


## You said you would.
static func take(s, id: String) -> void:
	_log(s, id).taken = true
	print("envoys: %s taken" % id)


## The friend a `bring` request wants, if one walks with you: the first of that species. Or null.
static func friend_for(s, r: Dictionary):
	for a in s.allies:
		if str(a.species) == str(r.get("species", "")):
			return a
	return null


## How a request stands: "done", "new" (not taken), "ready" (it can be finished at the asker now: the friend is with you, the
## gold is in your purse, or it only wants words), or "waiting".
static func status(s, r: Dictionary) -> String:
	var id := str(r.id)
	if is_done(s, id):
		return "done"
	if not is_taken(s, id):
		return "new"
	match str(r.kind):
		"bring":
			return "ready" if friend_for(s, r) != null else "waiting"
		"gold":
			return "ready" if s.gold >= int(r.count) else "waiting"
		"say":
			return "ready"
	return "waiting"


## What the asker says about a request as it stands.
static func speak(s, r: Dictionary) -> String:
	match status(s, r):
		"new":
			return str(r.ask)
		"ready":
			var friend = friend_for(s, r)
			var words := str(r.get("ready", r.wait))
			return words % spoken(friend.name) if friend != null and words.contains("%s") else words
		"done":
			return str(r.done)
	var wait := str(r.wait)
	return wait % [count(s, str(r.id)), int(r.count)] if str(r.kind) == "slay" else wait


## A NAME as it is said out loud: Name. The stages have it too (a friend handed over is named in the asker's line), so it is
## not private to this file.
static func spoken(a_name: String) -> String:
	return a_name.left(1) + a_name.substr(1).to_lower()


## Whether a game played with the fight menu as it stands can do this request at all: one that wants a fight won with HEAVY
## strikes needs a menu that offers HEAVY, which the feature `heavy-strike` gives it and the `skill-combat` experiment takes away
## (rules and stages don't read each other's flags, so the caller says whether the menu has it). A request the menu can't do is
## never offered: an asker that keeps asking for what you cannot give holds its teleporter shut for good.
static func can_do(r: Dictionary, heavy: bool) -> bool:
	return str(r.kind) != "heavy_win" or heavy


## A request is done: it pays, its clan hears, and the second one done for a clan opens its teleporter. Returns {gold, healed,
## opened}: `opened` is the clan whose way is now open, or "". {} when it was done already.
static func finish(s, id: String) -> Dictionary:
	var r := request(id)
	if r.is_empty() or is_done(s, id):
		return {}
	var log := _log(s, id)
	log.taken = true
	log.done = true
	var pays: Dictionary = table().pays
	var before: int = s.hp
	s.gold += int(pays.gold)
	s.hp = mini(s.max_hp, s.hp + int(pays.heal))
	Clans.favour(s, str(entry(r.clan).species), float(pays.standing))
	var opened := ""
	if done_for(s, r.clan) >= int(table().need) and not s.gates.has(r.clan) and not s.lords_met.has(r.clan):
		s.gates.append(r.clan)
		opened = r.clan
	print("envoys: %s done: %d gold, %d health%s" % [id, int(pays.gold), s.hp - before, ", and %s's teleporter is open" % opened if opened != "" else ""])
	return {"gold": int(pays.gold), "healed": s.hp - before, "opened": opened}


# ---------------------------------------------------------------- what happens away from the asker

## A monster was killed: the taken requests that count its kind count it. Returns the ids this finishes (to be `finish`ed).
static func slain(s, m) -> Array:
	var out := []
	for clan in clans():
		for r in entry(clan).requests:
			var id := str(r.id)
			if str(r.kind) != "slay" or str(r.species) != str(m.species) or not is_taken(s, id) or is_done(s, id):
				continue
			var log := _log(s, id)
			log.n = int(log.n) + 1
			print("envoys: %s, %d of %d" % [id, log.n, int(r.count)])
			if int(log.n) >= int(r.count):
				out.append(id)
	return out


## A foe fell: the taken heavy_win requests are done if every strike of yours in that fight was a heavy one (and one landed).
static func felled(s, m) -> Array:
	var out := []
	if int(m.strikes.get("heavy", 0)) <= 0 or int(m.strikes.get("light", 0)) > 0:
		return out
	for clan in clans():
		for r in entry(clan).requests:
			if str(r.kind) == "heavy_win" and is_taken(s, str(r.id)) and not is_done(s, str(r.id)):
				out.append(str(r.id))
	return out


## The taken request that wants something said to this monster in a fight (ask_dragon, to a dragon), or {}.
static func to_ask(s, m) -> Dictionary:
	if str(m.species) != "dragon":
		return {}
	for clan in clans():
		for r in entry(clan).requests:
			if str(r.kind) == "ask_dragon" and is_taken(s, str(r.id)) and not is_done(s, str(r.id)):
				return _with_clan(r, clan)
	return {}


## Whether what the mind made of the words (0..1, Mind.sounds_like) is enough.
static func passes(score: float) -> bool:
	return score >= float(table().pass_at)


# ---------------------------------------------------------------- the teleporter and the hall

## The clans whose teleporter is open, to be offered at the stairs.
static func ways(s) -> Array:
	return s.gates.filter(func(clan): return is_clan(str(clan)))


## The stairs' line for a clan's teleporter: {label, sub, hall}.
static func way(clan: String) -> Dictionary:
	var lines: Dictionary = table().lines
	var hall := str(entry(clan).hall.name)
	return {"label": str(lines.way_label) % Clans.title(clan).to_upper(), "sub": str(lines.way_sub) % hall, "hall": clan}


## The lord was heard out in its hall: it pays, its clan stands with you, and the run remembers. Returns {gold, healed}.
static func meet_lord(s, clan: String) -> Dictionary:
	if s.lords_met.has(clan):
		return {}
	s.lords_met.append(clan)
	var pays: Dictionary = table().hall.pays
	var before: int = s.hp
	s.gold += int(pays.gold)
	s.hp = mini(s.max_hp, s.hp + int(pays.heal))
	Clans.favour(s, str(entry(clan).species), float(pays.standing))
	print("envoys: the lord of %s was heard out: %d gold, %d health" % [clan, int(pays.gold), s.hp - before])
	return {"gold": int(pays.gold), "healed": s.hp - before}


# ---------------------------------------------------------------- saves

## What a save may hold as `errands`: the known ids only, each {taken, done, n}. Anything else is dropped.
static func from_saved(saved) -> Dictionary:
	var out := {}
	if not saved is Dictionary:
		return out
	for id in saved:
		var entry_saved = saved[id]
		if request(str(id)).is_empty() or not entry_saved is Dictionary:
			continue
		var n = entry_saved.get("n", 0)
		out[str(id)] = {"taken": entry_saved.get("taken") == true, "done": entry_saved.get("done") == true, "n": clampi(int(n) if (n is float or n is int) else 0, 0, 999)}
	return out
