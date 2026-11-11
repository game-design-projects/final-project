## What a run can earn for good: deeds worth keeping, across runs. What each is called and says is in data/achievements.json; which
## moment earns it is here. No rolls and no state of its own: it looks at what just happened.
extends RefCounted

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")


static func table() -> Dictionary:
	return Content.table("achievements")


static func known(id: String) -> bool:
	return table().list.has(id)


static func ids() -> Array:
	return table().list.keys()


static func info(id: String) -> Dictionary:
	return table().list[id]


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
