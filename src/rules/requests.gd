## A monster with a request: not a fight but a favour, asked once a floor on some floors, and paid for when it is done. Fetch something
## from the floor, spare its kin, or get someone off the floor. Pure rules from data/npcs.json: the stage `request` does the talking.
## A request names its target by its place in the floor's list of monsters, which a retried fight leaves as it was.
extends RefCounted

const Clans = preload("res://src/rules/clans.gd")
const Content = preload("res://src/rules/content.gd")
const Items = preload("res://src/rules/items.gd")
const Lords = preload("res://src/rules/lords.gd")

const KINDS := ["fetch", "spare", "rid"]


static func table() -> Dictionary:
	return Content.table("npcs").requests


## The floor's lord filling this asker, instead of a stray monster (`rules/lords.gd`): its kind is the lord's own, and the name
## and title are the data's, so the same floor always has the same lord. The draws come from the lord's own generator, so the
## floor's layout is what its seed always made. False when there is no floor spot or no target for the kind it asks.
static func fill_lord(rng, f, lord: Dictionary, plan: Dictionary) -> bool:
	var targets := []
	for i in f.monsters.size():
		if not f.monsters[i].boss and not f.monsters[i].lurking:
			targets.append(i)
	var kind: String = lord.kind
	if kind == "fetch" and not plan.get("items", false):
		kind = "rid" # nothing lies about for it to want
	if targets.is_empty():
		return false
	var q: Dictionary = f.quester
	q.lord = str(lord.clan)
	q.title = str(lord.title)
	q.name = str(lord.name)
	q.species = str(lord.species)
	q.kind = kind
	if kind == "fetch":
		q.target = -1
	elif kind == "spare": # its kin: the same species as the lord
		var kin := targets.filter(func(i): return f.monsters[i].species == str(lord.species))
		if kin.is_empty():
			return false
		q.target = int(rng.pick(kin))
	else:
		q.target = int(rng.pick(targets))
	q.taken = false
	q.want = Items.gift_for(q.species) if kind == "fetch" else ""
	print("lords: %s, %s, asks: %s %s" % [q.name, q.title, kind, q.want if kind == "fetch" else f.monsters[q.target].name])
	return true


## Whether this floor has someone asking.
static func due(depth: int) -> bool:
	return table().floors.has(float(depth))


## Who is asking and for what, for the floor once its monsters stand on it. False when there is nobody it could be about.
static func fill(rng, f, plan: Dictionary) -> bool:
	var targets := []
	for i in f.monsters.size():
		if not f.monsters[i].boss and not f.monsters[i].lurking:
			targets.append(i)
	var kinds: Array = KINDS.duplicate()
	if not plan.get("items", false):
		kinds.erase("fetch")
	if targets.is_empty():
		return false
	var q: Dictionary = f.quester
	q.kind = rng.pick(kinds)
	q.target = int(rng.pick(targets))
	var roster: Array = Content.table("encounter").roster
	var target = f.monsters[q.target]
	q.species = target.species if q.kind == "spare" else str(rng.pick(roster).species)
	q.name = _free_name(rng, f, q.species, plan.get("taken", {}))
	q.taken = false
	if q.kind == "fetch":
		q.target = -1
		q.want = Items.gift_for(q.species)
	else:
		q.want = ""
	print("requests: %s the %s asks: %s %s" % [q.name, q.species, q.kind, q.want if q.kind == "fetch" else target.name])
	return true


## A name nobody on this floor has, nor anyone met earlier in the run (`taken` is the run's names, upper case -> true: the one
## asking is a monster of the run like the others, and a later floor keeps off its name through State.names_met). The recorded
## names come first and the spare ones once those are used up, as a monster's do (Monster._fresh_name).
static func _free_name(rng, f, species: String, taken: Dictionary) -> String:
	var here: Array = f.monsters.map(func(m): return str(m.name).to_upper())
	var sp: Dictionary = Content.species(species)
	var free: Array = _free_names(sp.names, here, taken)
	if free.is_empty():
		free = _free_names(sp.get("spare_names", []), here, taken)
	return str(rng.pick(free)) if not free.is_empty() else "THE OLD ONE"


## The names off `names` that neither this floor's monsters (`here`) nor the run (`taken`) have had.
static func _free_names(names: Array, here: Array, taken: Dictionary) -> Array:
	return names.map(func(n): return str(n).to_upper()).filter(func(n): return not here.has(n) and not taken.has(n))


## What it is about, as the words say it: the thing wanted, or who.
static func subject(q: Dictionary, f) -> String:
	return Items.label(q.want) if q.kind == "fetch" else f.monsters[q.target].name


## How it stands: "new" (not asked yet), "waiting", "ready" (done, to be paid for) or "failed".
static func status(q: Dictionary, s) -> String:
	if q.kind == "fetch":
		if s.items.has(q.want):
			return "ready"
	else:
		var target = s.floor_map.monsters[q.target]
		if q.kind == "spare" and target.gone == "slain":
			return "failed"
		if target.is_gone():
			return "ready"
	return "waiting" if q.taken else "new"


## What it says, for this status.
static func speak(q: Dictionary, s) -> String:
	var kind: Dictionary = table().kinds[q.kind]
	var words: String = {"new": kind.ask, "waiting": kind.wait, "ready": kind.ready, "failed": kind.get("failed", "")}[status(q, s)]
	return words % subject(q, s.floor_map)


## Paid: what was asked for leaves the bag, the gold and health come, and its clan hears. Returns {gold, healed}.
static func settle(q: Dictionary, s) -> Dictionary:
	var t := table()
	var gold: int = int(t.gold)
	var heal: int = int(t.heal)
	var standing: float = float(t.standing)
	var lord := str(q.get("lord", ""))
	if lord != "": # a lord pays more, and the run remembers it was met (rules/lords.gd)
		var pays := Lords.pays()
		gold = int(pays.gold)
		heal = int(pays.heal)
		standing = float(pays.standing)
		if not s.lords_met.has(lord):
			s.lords_met.append(lord)
	if q.kind == "fetch":
		s.items.erase(q.want)
	s.gold += gold
	var before: int = s.hp
	s.hp = mini(s.max_hp, s.hp + heal)
	Clans.favour(s, q.species, standing)
	print("requests: %s is paid: %d gold, %d health%s" % [q.name, gold, s.hp - before, ", a lord's favour" if lord != "" else ""])
	return {"gold": gold, "healed": s.hp - before}


## What a save holds: whether this is a request, from outside, that can be read. "" when it is.
static func problem(q: Dictionary, monsters: int) -> String:
	if not KINDS.has(str(q.get("kind", ""))):
		return "the floor's request is of no known kind"
	if not Content.is_monster(str(q.get("species", ""))) or not q.get("name") is String:
		return "the floor's request comes from no known monster"
	if q.kind == "fetch":
		return "" if Items.known(str(q.get("want", ""))) else "the floor's request wants no known thing"
	var target = q.get("target")
	if not (target is int or target is float) or int(target) < 0 or int(target) >= monsters:
		return "the floor's request is about nobody on the floor"
	return ""
