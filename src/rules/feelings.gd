## What a feeling does to a monster. A mind picks how the monster feels about what the player just did; code owns what
## each feeling changes, so every word and deed has a visible consequence.
extends RefCounted

const Content = preload("res://src/rules/content.gd")

const WARM_UP := {"friendliness": 2.5, "anger": -1.0}


static func all() -> Dictionary:
	return Content.table("emotions").feelings


static func get_feeling(id: String) -> Dictionary:
	var f: Dictionary = all().get(id, {})
	if f.is_empty():
		push_error("feelings: no feeling '%s'" % id)
	return f


## Moves the monster's friendliness, anger and fear by the feeling, plus whatever its own traits add for the last
## thing done to it. Meters stay in 0..100. Returns the feeling's entry (label, tone, effect) for the caller to show.
static func apply(m, id: String) -> Dictionary:
	var feeling := get_feeling(id)
	_shift(m, feeling.get("meters", {}))
	var motives: Dictionary = Content.table("taste").motives
	for t in m.traits:
		if motives.has(t):
			_shift(m, motives[t].meters.get(m.last_intent, {}))
	print_verbose("feelings: %s feels %s -> %s" % [m.name, id, m.meters])
	return feeling


## Patience pays: a monster you kept talking to warms up a little however the words landed, unless they landed badly. So every
## monster can be won over in the end, and the odds never stall.
static func warm_up(m, feeling: Dictionary) -> void:
	if feeling.get("tone", "") != "bad":
		_shift(m, WARM_UP)


static func _shift(m, shift: Dictionary) -> void:
	for k in shift:
		m.meters[k] = clampf(float(m.meters.get(k, 0.0)) + float(shift[k]), 0.0, 100.0)


## Does this feeling make the monster skip its attack this round?
static func pacifies(id: String) -> bool:
	var cond: String = get_feeling(id).get("cond", "")
	return cond != "" and Content.table("emotions").pacifying.has(cond)
