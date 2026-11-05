## What is kept between runs, whichever slot is played: the achievements earned, the embers, and the boons bought with them (the
## features achievements and legacy). One key each in the Store, so a damaged value counts as nothing, and `nosave` keeps it in memory.
extends RefCounted

const Achievements = preload("res://src/rules/achievements.gd")
const Legacy = preload("res://src/rules/legacy.gd")

const EARNED_KEY := "achievements"
const EMBERS_KEY := "embers"
const RANKS_KEY := "legacy_ranks"
const PAID_KEY := "legacy_paid" # run seed -> what that run has paid so far: a run left, loaded and left again pays only what is new


static func earned() -> Array:
	var v = Store.get_value(EARNED_KEY, [])
	return v.filter(func(id): return Achievements.known(str(id))) if v is Array else []


static func earn(id: String) -> void:
	var all := earned()
	if not all.has(id):
		all.append(id)
		Store.set_value(EARNED_KEY, all)


static func embers() -> int:
	var v = Store.get_value(EMBERS_KEY, 0)
	return maxi(0, int(v)) if v is float or v is int else 0


static func ranks() -> Dictionary:
	var v = Store.get_value(RANKS_KEY, {})
	var out := {}
	if v is Dictionary:
		for id in v:
			if Legacy.known(str(id)) and (v[id] is float or v[id] is int):
				out[str(id)] = clampi(int(v[id]), 0, Legacy.top_rank(str(id)))
	return out


## A run has ended, or been left for good, having earned `total` by now. What is new. A second end of the same run pays the difference.
static func pay(run_seed: int, total: int) -> int:
	var paid = Store.get_value(PAID_KEY, {})
	if not paid is Dictionary:
		paid = {}
	var key := str(run_seed)
	var new_embers := maxi(0, total - int(paid.get(key, 0)))
	paid[key] = maxi(total, int(paid.get(key, 0)))
	Store.set_value(PAID_KEY, paid)
	Store.set_value(EMBERS_KEY, embers() + new_embers)
	print("progress: run %s paid %d new embers, %d now" % [key, new_embers, embers()])
	return new_embers


## Buy the next rank of a boon. "bought", "poor" or "full".
static func buy(id: String) -> String:
	var all := ranks()
	var rank: int = all.get(id, 0)
	var cost := Legacy.next_cost(id, rank)
	if cost < 0:
		return "full"
	if embers() < cost:
		return "poor"
	all[id] = rank + 1
	Store.set_value(RANKS_KEY, all)
	Store.set_value(EMBERS_KEY, embers() - cost)
	print("progress: %s to rank %d for %d embers, %d left" % [id, rank + 1, cost, embers()])
	return "bought"
