## What carries over from one run to the next. A run that ends leaves embers, by what you did in it; between runs they buy boons
## in ranks, which every later run starts with. The numbers are in data/legacy.json. No rolls and nothing saved here: the scene keeps
## the embers and the ranks (menu/progress.gd) and hands the ranks to the flow.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Items = preload("res://src/rules/items.gd")


static func table() -> Dictionary:
	return Content.table("legacy")


static func line(id: String) -> String:
	return str(table().lines[id])


static func boons() -> Dictionary:
	return table().boons


static func known(id: String) -> bool:
	return boons().has(id)


## How many embers this run has earned so far. `depth` floors walked, and more if it `cleared` the last door.
static func earned(state, cleared: bool) -> int:
	var e: Dictionary = table().earn
	var t: Dictionary = state.tally
	var total := int(t.spared) * int(e.spared) + int(t.recruited) * int(e.recruited) + int(t.slain) * int(e.slain) + (int(state.depth) - 1) * int(e.floor)
	return total + (int(e.cleared) if cleared else 0)


static func top_rank(id: String) -> int:
	return boons()[id].cost.size()


## What the next rank of this boon costs, or -1 when it has none left.
static func next_cost(id: String, rank: int) -> int:
	var costs: Array = boons()[id].cost
	return int(costs[rank]) if rank >= 0 and rank < costs.size() else -1


## What the boon says it does at this rank (at least the first, so an unbought one says what it would do).
static func describe(id: String, rank: int) -> String:
	var b: Dictionary = boons()[id]
	var ranks := maxi(1, rank)
	var amount := ranks
	for key in ["max_hp", "gold", "sharpened"]:
		if b.has(key):
			amount = int(b[key]) * ranks
	return str(b.sub) % amount


## A new run starts with what the ranks give. `ranks` is boon id -> rank; what isn't a boon, or a rank past the top, doesn't count.
static func apply(state, ranks: Dictionary) -> void:
	for id in ranks:
		if not known(str(id)):
			push_warning("legacy: no boon '%s'" % id)
			continue
		var b: Dictionary = boons()[str(id)]
		var rank := clampi(int(ranks[id]), 0, top_rank(str(id)))
		state.max_hp += int(b.get("max_hp", 0)) * rank
		state.hp = state.max_hp
		state.gold += int(b.get("gold", 0)) * rank
		state.sharpened += int(b.get("sharpened", 0)) * rank
		if b.has("item"):
			for _i in rank:
				Items.carry(state, str(b.item))
	print("legacy: a run starts with %s (HP %d, gold %d, %d items)" % [ranks, state.max_hp, state.gold, state.items.size()])
