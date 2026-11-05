## Going hungry, and what you can do about it. Walking wears on you: past a line the walk stops healing you, and past another each
## few steps costs health, though never the last of it. Food fixes that. So does a friend: a butchered ally is roasts for the bag, to
## eat, to sell to a trader who won't ask, or to feed to the others, who like you better for it as long as they don't work out why.
## Whoever works it out walks out and tells the rest, and the victim's clan hears. The numbers are in data/survival.json.
extends RefCounted

const Allies = preload("res://src/rules/allies.gd")
const Clans = preload("res://src/rules/clans.gd")
const Content = preload("res://src/rules/content.gd")
const Dice = preload("res://src/utils/dice.gd")
const Items = preload("res://src/rules/items.gd")
const Odds = preload("res://src/rules/odds.gd")

const ROAST := "roast"
const RATION := "ration"


static func table() -> Dictionary:
	return Content.table("survival")


static func line(id: String) -> String:
	return str(table().lines[id])


## "" (fed), "hungry" or "starving": what the hunger means now.
static func stage_of(hunger: float) -> String:
	var h: Dictionary = table().hunger
	if hunger >= float(h.starving_at):
		return "starving"
	return "hungry" if hunger >= float(h.hungry_at) else ""


## One step's worth. What it says: {"crossed": the stage it just got to, or "", "hurt": health it cost}.
static func walk(state) -> Dictionary:
	var h: Dictionary = table().hunger
	var was := stage_of(state.hunger)
	state.hunger = minf(state.hunger + float(h.per_step), float(h.starving_at))
	var now := stage_of(state.hunger)
	var hurt := 0
	if now == "starving":
		state.starved_steps += 1
		if state.starved_steps % int(h.starve_every) == 0 and state.hp > 1:
			state.hp -= 1
			hurt = 1
	return {"crossed": now if now != was else "", "hurt": hurt}


## Going down a floor is a rest with what is in your pockets.
static func rest(state) -> void:
	state.hunger = maxf(0.0, state.hunger + float(table().hunger.per_floor))


## Whether the walk still heals you.
static func heals(state) -> bool:
	return stage_of(state.hunger) == ""


## Food out of the bag, at slot `index`, eaten. How much health it gave back.
static func eat(state, index: int) -> int:
	var item: Dictionary = Items.info(state.items[index])
	state.items.remove_at(index)
	state.hunger = maxf(0.0, state.hunger - float(item.food))
	var healed: int = mini(state.max_hp - state.hp, int(item.get("amount", 0)))
	state.hp += healed
	print("survival: ate, hunger %.0f, healed %d" % [state.hunger, healed])
	return healed


## How likely this ally is to work it out, by what it is and how many bowls it has had.
static func notice_odds(ally, first: float = 0.0) -> float:
	var b: Dictionary = table().butcher
	return clampf(float(b.notice.get(ally.species, 0.1)) + first + float(b.notice_per_meal) * ally.meals, 0.0, 1.0)


## `ally` becomes roasts. Anyone left may have seen. {"made": how many fitted in the bag, "witnesses": allies who saw and left, "told": allies told}.
static func butcher(state, ally, dice: Dice) -> Dictionary:
	var b: Dictionary = table().butcher
	state.allies.erase(ally)
	state.butchered.append({"species": ally.species, "name": ally.name})
	var made := 0
	for _i in int(b.roasts):
		if Items.carry(state, ROAST):
			made += 1
	var out := {"made": made, "witnesses": [], "told": []}
	Clans.favour(state, ally.species, float(b.clan_worth) * 0.5) # a monster that went off with you and never came back is talked about
	for other in state.allies.duplicate():
		if other in out.witnesses or not state.allies.has(other):
			continue
		if Odds.succeeds(dice, notice_odds(other, float(b.notice_at_butcher))):
			var heard := find_out(state, other, ally)
			out.witnesses.append(other)
			for t in heard:
				if not out.told.has(t):
					out.told.append(t)
	print("survival: butchered %s, %d roasts, %d saw it" % [ally.name, made, out.witnesses.size()])
	return out


## A roast from the bag to this ally: it is happier, and it may work out what it just ate. {"found_out": bool, "told": allies told}.
static func feed(state, ally, dice: Dice) -> Dictionary:
	var index: int = state.items.find(ROAST)
	if index < 0:
		push_warning("survival: no roast to feed %s" % ally.name)
		return {"found_out": false, "told": []}
	state.items.remove_at(index)
	state.meals += 1
	ally.meals += 1
	ally.loyalty = clampf(ally.loyalty + float(table().butcher.feed_loyalty), 0.0, 100.0)
	var knows := Odds.succeeds(dice, notice_odds(ally))
	var told := find_out(state, ally, state.butchered[-1] if not state.butchered.is_empty() else null) if knows else []
	print("survival: fed %s, loyalty %.0f, %s" % [ally.name, ally.loyalty, "it knows" if knows else "it suspects nothing"])
	return {"found_out": knows, "told": told}


## This ally has worked it out: it leaves, the others hear and trust you less, and the clan of whoever went into the pot hears too.
## Who was told.
static func find_out(state, ally, victim) -> Array:
	var b: Dictionary = table().butcher
	state.allies.erase(ally)
	state.tally.left += 1
	state.found_out = true
	if victim != null:
		Clans.favour(state, str(victim.species), float(b.clan_worth))
	for other in state.allies:
		other.loyalty = clampf(other.loyalty + float(b.told_loyalty), 0.0, 100.0)
	print("survival: %s found out and left, %d told" % [ally.name, state.allies.size()])
	return state.allies.duplicate()


## What a trader gives for this item, or 0 when it won't buy it.
static func sell_price(id: String) -> int:
	return int(Items.info(id).get("sell", 0))


## A last line for the summary at the end of a run, or "".
static func ending_note(state) -> String:
	if state.found_out:
		return line("known")
	return line("kept") if state.meals > 0 else ""
