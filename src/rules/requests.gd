## A monster with a request: not a fight but a favour, asked once a floor on some floors, and paid for when it is done. Fetch something
## from the floor, spare its kin, or get someone off the floor. Pure rules from data/npcs.json: the stage `request` does the talking.
## A request names its target by its place in the floor's list of monsters, which a retried fight leaves as it was.
extends RefCounted

const Clans = preload("res://src/rules/clans.gd")
const Content = preload("res://src/rules/content.gd")
const Items = preload("res://src/rules/items.gd")

const KINDS := ["fetch", "spare", "rid"]


static func table() -> Dictionary:
	return Content.table("npcs").requests


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
	q.name = _free_name(rng, f, q.species)
	q.taken = false
	if q.kind == "fetch":
		q.target = -1
		q.want = Items.gift_for(q.species)
	else:
		q.want = ""
	print("requests: %s the %s asks: %s %s" % [q.name, q.species, q.kind, q.want if q.kind == "fetch" else target.name])
	return true


## A name nobody on this floor has.
static func _free_name(rng, f, species: String) -> String:
	var taken: Array = f.monsters.map(func(m): return m.name)
	var free: Array = Content.species(species).names.map(func(n): return str(n).to_upper()).filter(func(n): return not taken.has(n))
	return str(rng.pick(free)) if not free.is_empty() else "THE OLD ONE"


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
	if q.kind == "fetch":
		s.items.erase(q.want)
	s.gold += int(t.gold)
	var before: int = s.hp
	s.hp = mini(s.max_hp, s.hp + int(t.heal))
	Clans.favour(s, q.species, float(t.standing))
	print("requests: %s is paid: %d gold, %d health" % [q.name, t.gold, s.hp - before])
	return {"gold": int(t.gold), "healed": s.hp - before}


## What a save holds: whether this is a request, from outside, that can be read. "" when it is.
static func problem(q: Dictionary, monsters: int) -> String:
	if not KINDS.has(str(q.get("kind", ""))):
		return "the floor's request is of no known kind"
	if not Content.table("species").has(str(q.get("species", ""))) or not q.get("name") is String:
		return "the floor's request comes from no known monster"
	if q.kind == "fetch":
		return "" if Items.known(str(q.get("want", ""))) else "the floor's request wants no known thing"
	var target = q.get("target")
	if not (target is int or target is float) or int(target) < 0 or int(target) >= monsters:
		return "the floor's request is about nobody on the floor"
	return ""
