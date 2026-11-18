## What a run can earn for good: deeds worth keeping, across runs. What each is called and says is in data/achievements.json,
## with the group it is shown in, its badge (view/badges.gd) and whether it is a secret until earned; which moment earns it is
## here, and so is the board the panel shows. No rolls and no state of its own: it looks at what just happened.
extends RefCounted

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Lore = preload("res://src/rules/lore.gd")


static func table() -> Dictionary:
	return Content.table("achievements")


static func known(id: String) -> bool:
	return table().list.has(id)


static func ids() -> Array:
	return table().list.keys()


static func info(id: String) -> Dictionary:
	return table().list[id]


## Whether it keeps its name and line to itself until it is earned.
static func secret(id: String) -> bool:
	return bool(info(id).get("secret", false))


## How far along a counted one is, as [so far, of], or [] for one earned in a single moment. `facts` is what is known across
## runs: {"lore": how many pieces of writing have been read}.
static func progress(id: String, facts: Dictionary) -> Array:
	if id == "lore_all":
		return [mini(int(facts.get("lore", 0)), Lore.total()), Lore.total()]
	return []


## One of them as it is shown: {id, group, color, icon, label, text, earned, at, hidden, progress}. An earned one says what
## was done (`text`), one still to earn says what to do (`how`), and a secret not yet earned says neither. `at` is when it
## was earned, in Unix seconds, or 0 when that was never kept.
static func card(id: String, earned_at: Dictionary, facts := {}) -> Dictionary:
	var i := info(id)
	var earned := earned_at.has(id)
	var hidden := secret(id) and not earned
	var veil: Dictionary = table().secret
	return {
		"id": id, "group": str(i.group), "color": str(table().groups[i.group].color),
		"icon": "secret" if hidden else str(i.icon),
		"label": str(veil.label if hidden else i.label),
		"text": str(veil.text) if hidden else str(i.text if earned else i.get("how", i.text)),
		"earned": earned, "at": int(earned_at.get(id, 0)), "hidden": hidden,
		"progress": [] if earned else progress(id, facts),
	}


## Everything there is to earn, as the panel shows it: the groups in their order, each {id, label, color, got, cards}.
static func board(earned_at: Dictionary, facts := {}) -> Array:
	var out := []
	for g in table().groups:
		var cards := []
		for id in ids():
			if str(info(id).group) == g:
				cards.append(card(id, earned_at, facts))
		var group: Dictionary = table().groups[g]
		out.append({"id": g, "label": str(group.label), "color": str(group.color), "got": cards.filter(func(c): return c.earned).size(), "cards": cards})
	return out


## The ones this event earns, whether or not they were earned before. `state` is the run as it stands.
static func earned_by(event: String, data: Dictionary, state) -> Array:
	var out := []
	match event:
		"spared":
			out.append("words")
		"recruited":
			out.append("friend")
			if state.party_size() >= Combat.PARTY_MAX:
				out.append("party")
			if state.foe != null and state.foe.boss:
				out.append("champion_won")
		"lord_joined": # a sworn lord comes along unspared, so it fills the table but is nobody's "friend" card
			if state.party_size() >= Combat.PARTY_MAX:
				out.append("party")
		"slain":
			if data.boss:
				out.append("champion_slain")
		"found":
			if data.what == "chest":
				out.append("chest")
			elif data.what == "lore":
				out.append("lore")
				if int(data.get("read", 0)) >= int(data.get("total", 0)) and int(data.get("total", 0)) > 0:
					out.append("lore_all")
		"strike":
			if not state.heavy_known.is_empty():
				out.append("heavy")
		"reached_last":
			out.append("deep")
		"butchered":
			out.append("roast")
		"found_out":
			out.append("came_out")
		"run_ended":
			out.append_array(_of_the_end(data, state))
	return out


static func _of_the_end(data: Dictionary, state) -> Array:
	if data.how == "lonely":
		return ["lonely"]
	var out := ["door"] if data.how == "cleared" and not state.allies.is_empty() else []
	var t: Dictionary = state.tally
	if t.spared + t.slain == 0:
		out.append("ghost")
	elif t.slain == 0:
		out.append("quiet")
	elif t.spared == 0:
		out.append("blood")
	if state.meals > 0 and not state.found_out:
		out.append("nobody_asked")
	return out
