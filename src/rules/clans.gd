## Who stands with whom, and what the run has done to them. Every kind of monster belongs to a clan (data/clans.json); what you
## do to one changes how its clan, less so the clans on its side, and a little the dragon's hoard, think of you. A monster hears
## of it when it meets you: it starts in a different mood, and says so. No rolls here: the same deeds always mean the same.
extends RefCounted

const Content = preload("res://src/rules/content.gd")

const STANDING_MAX := 100.0
const MOOD_MAX := 25.0 # how far a clan's opinion can move a monster's starting mood
const DEEDS_MAX := 40
const HEARD_SHOWN := 5 # how many deeds a monster repeats to the mind
const NEWS_AT := 1.0 # how far its clan's opinion must have moved for a monster to mention it


static func _table() -> Dictionary:
	return Content.table("clans")


## The clan of a kind of monster, or "".
static func of(species: String) -> String:
	var clans: Dictionary = _table().clans
	for id in clans:
		if clans[id].species.has(species):
			return id
	return ""


static func title(clan: String) -> String:
	return str(_table().clans[clan].name)


static func is_clan(clan: String) -> bool:
	return _table().clans.has(clan)


## The other clans on this clan's side.
static func side_of(clan: String) -> Array:
	var clans: Dictionary = _table().clans
	var side: String = clans[clan].side
	if side == "":
		return []
	return clans.keys().filter(func(c): return c != clan and clans[c].side == side)


## How much of what is done to `from` reaches `to`: all of it within a clan, some across a side, and what the clan hears of everything.
static func reach(from: String, to: String) -> float:
	if from == to:
		return 1.0
	if side_of(from).has(to):
		return float(_table().spill)
	return float(_table().clans[to].get("hears_all", 0.0))


## Write a deed into the run: "spared", "slain" or "recruited" against monster `m`.
static func record(state, m, deed: String) -> void:
	var from := of(m.species)
	if from == "":
		push_error("clans: %s has no clan" % m.species)
		return
	var worth: float = float(_table().deeds[deed]) * (float(_table().champion_weight) if m.boss else 1.0)
	for clan in _table().clans:
		var part: float = worth * reach(from, clan)
		if part != 0.0:
			state.reputation[clan] = clampf(float(state.reputation.get(clan, 0.0)) + part, -STANDING_MAX, STANDING_MAX)
	state.deeds.append({"clan": from, "species": m.species, "who": m.name, "deed": deed})
	if state.deeds.size() > DEEDS_MAX:
		state.deeds = state.deeds.slice(-DEEDS_MAX)
	print("clans: %s %s (%s), standing now %s" % [deed, m.name, from, state.reputation])


## How much a clan's opinion moves a monster's starting mood.
static func mood(standing: float) -> Dictionary:
	var shift: Dictionary = _table().mood
	return {
		"friendliness": clampf(standing * float(shift.friendliness), -MOOD_MAX, MOOD_MAX),
		"anger": clampf(standing * float(shift.anger), -MOOD_MAX, MOOD_MAX),
	}


## `m` meets you and hears what its clan has heard since it last did: its mood moves by the difference, and it remembers. Returns
## {clan, kind, deed, who, tone} for what it has to say (`kind` names its lines), or {} when there's no news for it.
static func hear(m, state) -> Dictionary:
	var clan := of(m.species)
	var standing: float = float(state.reputation.get(clan, 0.0))
	var before: float = float(m.heard.get("standing", 0.0))
	if clan == "" or absf(standing - before) < NEWS_AT:
		return {}
	var deed: Dictionary = _latest(state.deeds, clan)
	if deed.is_empty():
		return {}
	var now := mood(standing)
	var was := mood(before)
	for k in now:
		m.meters[k] = clampf(float(m.meters.get(k, 0.0)) + now[k] - was[k], 0.0, 100.0)
	m.heard = {"clan": clan, "standing": standing, "deed": deed.deed, "who": deed.who, "heard": _retell(state.deeds, clan)}
	var bad: bool = deed.deed == "slain"
	var news := {
		"clan": clan, "deed": deed.deed, "who": deed.who, "tone": "good" if standing > before else "bad",
		"kind": ("kin_" if deed.clan == clan else "side_") + ("slain" if bad else "spared"),
	}
	print("clans: %s heard %s %s; friendliness %.0f, anger %.0f" % [m.name, deed.deed, deed.who, m.meters.friendliness, m.meters.anger])
	return news


## The deed a clan talks about: its own last one if it has one, or else the last it heard of.
static func _latest(deeds: Array, clan: String) -> Dictionary:
	var heard := {}
	for i in range(deeds.size() - 1, -1, -1):
		var deed: Dictionary = deeds[i]
		if deed.clan == clan:
			return deed
		if heard.is_empty() and reach(deed.clan, clan) > 0.0:
			heard = deed
	return heard


## What a clan knows, in words a mind can read.
static func _retell(deeds: Array, clan: String) -> Array:
	var out := []
	for deed in deeds:
		if reach(deed.clan, clan) > 0.0:
			var whose := "one of its own" if deed.clan == clan else "of %s" % title(deed.clan)
			out.append("the player %s %s the %s, %s" % [deed.deed, deed.who, deed.species, whose])
	return out.slice(-HEARD_SHOWN)


## One line for the banner and the card: what was heard, and how the monster took it.
static func news(heard: Dictionary) -> String:
	var did: String = "killed" if heard.deed == "slain" else "spared"
	return "%s heard you %s %s. It starts %s." % [title(heard.clan), did, heard.who, "friendlier" if heard.tone == "good" else "angrier"]
