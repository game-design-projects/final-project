## How the halls feel about you. Nothing here is stored: it is read off what the run already keeps (who was spared, slain, left, eaten),
## so an old save has a warmth too and a retried fight takes its deeds back with it. Warm halls look at you; every cruelty turns
## something away, until the set is the cold wireframe it started as, and colder halls fight harder (`harder`, #291): their
## attacks come faster and hit harder, and mercy and friends come slower. Numbers and words are in data/warmth.json.
extends RefCounted

const Content = preload("res://src/rules/content.gd")


static func table() -> Dictionary:
	return Content.table("warmth")


## 0 (cold) .. 1 (beloved).
static func of(state) -> float:
	var t: Dictionary = table()
	var d: Dictionary = t.deeds
	var v: float = t.start
	v += float(d.spared) * state.tally.spared + float(d.recruited) * state.tally.recruited
	var kills: int = maxi(0, int(state.tally.slain) - int(state.tally.get("blessed", 0))) # a kill the party approved of is left out
	v += float(d.slain) * kills + float(d.left) * state.tally.left
	v += float(d.butchered) * state.butchered.size() + float(d.left_behind) * state.left_behind.size() + float(d.meals) * state.meals
	return clampf(v, 0.0, 1.0)


## The level a warmth falls in: 0 cold, 1 shut, 2 wary, 3 kind, 4 beloved.
static func level(value: float) -> int:
	var levels: Array = table().levels
	for i in range(levels.size() - 1, 0, -1):
		if value >= float(levels[i].from):
			return i
	return 0


static func level_id(i: int) -> String:
	return str(table().levels[i].id)


## What the log says when the level moved from `was` to `now`, "" when it says nothing.
static func line(was: int, now: int) -> String:
	if now == was:
		return ""
	return str(table().levels[now].up if now > was else table().levels[now].down)


const SOFT := {"intensity": 1.0, "damage": 0, "mercy": 1.0, "join": 1.0}


## What the halls' coldness does to every fight (#291): {intensity, damage, mercy, join}, all as they were in warm halls.
static func harder(state) -> Dictionary:
	var out := SOFT.duplicate()
	out.merge(table().levels[level(of(state))].get("harder", {}), true)
	return out


## What a level does, for the log when the halls turn: "" when it says nothing.
static func effect(i: int) -> String:
	return str(table().levels[i].get("effect", ""))
