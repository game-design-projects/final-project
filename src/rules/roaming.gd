## Monsters walk when you do: each step you take gives every monster a turn, one at a time, and turning or bumping a wall gives none,
## so you can always stop and look. What it does comes from who it is (data/roaming.json), and how it feels can override that: an
## angry one or one whose clan you wronged hunts you, a frightened one backs away, a friendly one comes close and stops short.
##
## A move is never drawn from `Dice` or the game's generator: those aren't saved, and in the slice `Dice` gives one fixed number, so
## it would shift the fights and change after a load. It is worked out from the floor's seed, the monster's place in the list and the
## floor's saved count of steps (AGENTS.md has this as the one exception).
extends RefCounted

const Clans = preload("res://src/rules/clans.gd")
const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

const FAR := 1 << 30 # not within reach


static func table() -> Dictionary:
	return Content.table("roaming")


## Everybody takes a turn. `options` are {revenge, boss_chase}, what the flags say. Returns {caught, noticed, moved}: the monster that
## walked into you (the rest stay put), or null, those that have just started hunting you, and those that moved.
static func turn(state, options := {}) -> Dictionary:
	var f = state.floor_map
	f.steps += 1
	var barred := _barred(f)
	var to_you := _field(f, state.cell, barred)
	var out := {"caught": null, "noticed": [], "moved": []}
	for i in f.monsters.size():
		var m = f.monsters[i]
		if m.is_gone() or m.lurking:
			continue
		if m.hold > 0:
			m.hold -= 1
			m.hunting = false
			continue
		var intent := _intent(m, f, to_you, state, options)
		if intent == "hunt" and not m.hunting:
			out.noticed.append(m)
			print("roaming: %s starts hunting you from %s" % [m.name, m.cell])
		m.hunting = intent == "hunt"
		var next: Variant = _next(m, i, f, intent, to_you, barred, state.cell)
		if next == null:
			continue
		if next == state.cell:
			if intent == "come":
				continue
			out.caught = m
			print("roaming: %s walks into you at %s" % [m.name, m.cell])
			return out
		print_verbose("roaming: %s %s %s -> %s" % [m.name, intent, m.cell, next])
		m.cell = next
		out.moved.append(m)
	return out


## After a fight you backed out of: it holds still for a few steps, or the same fight would start again on your next one.
static func hold(m) -> void:
	m.hold = int(table().flee_hold)


## What it means to do this turn: "hunt", "away", "come", "drift", "patrol" or "still".
static func _intent(m, f, to_you: Dictionary, state, options: Dictionary) -> String:
	var t := table()
	var near: int = to_you.get(m.cell, FAR)
	if m.boss:
		var seen: bool = m.hunting or state.seen.has(m.cell)
		return "hunt" if options.get("boss_chase", false) and m.cell != f.stairs and seen else "still"
	if m.meters.fear >= float(t.afraid_at) and near <= int(t.afraid_sense):
		return "away"
	if options.get("revenge", false) and near <= int(t.revenge_sense) and float(state.reputation.get(Clans.of(m.species), 0.0)) <= float(t.revenge_at):
		return "hunt"
	if m.meters.anger >= float(t.angry_at) and near <= int(t.angry_sense):
		return "hunt"
	if m.meters.friendliness >= float(t.friendly_at) and near <= int(t.friendly_sense):
		return "come"
	var way: Dictionary = t.species.get(m.species, {"kind": "still"})
	match str(way.kind):
		"drift":
			return "drift" if f.steps % int(way.every) == 0 else "still"
		"patrol":
			return "patrol"
		"stalk":
			var reach: int = int(way.sense) + (int(way.keeps_on) if m.hunting else 0)
			return "hunt" if near <= reach else "still"
	return "still"


## The cell it moves to, or null to stay. It may be yours.
static func _next(m, index: int, f, intent: String, to_you: Dictionary, barred: Dictionary, you: Vector2i) -> Variant:
	match intent:
		"hunt", "come":
			return _downhill(m, f, to_you, barred, you)
		"away":
			var best: Variant = null
			var far: int = to_you.get(m.cell, -1)
			for d in FloorMap.DIRS:
				var c: Vector2i = m.cell + d
				if _free(f, c, barred) and c != you and to_you.get(c, -1) > far:
					far = to_you[c]
					best = c
			return best
		"drift":
			var ways := []
			for d in FloorMap.DIRS:
				if _free(f, m.cell + d, barred):
					ways.append(m.cell + d)
			return ways[_roll(f, index, ways.size())] if not ways.is_empty() else null
		"patrol":
			return _patrol(m, index, f, barred, you)
	return null


## One step closer on this field, if the way isn't taken.
static func _downhill(m, f, field: Dictionary, barred: Dictionary, you: Vector2i) -> Variant:
	var here: int = field.get(m.cell, FAR)
	for d in FloorMap.DIRS:
		var c: Vector2i = m.cell + d
		if field.get(c, FAR) < here and (c == you or _free(f, c, barred)):
			return c
	return null


## Up and down its beat, between where it started and somewhere far off. Finding someone in the way, it turns back.
static func _patrol(m, index: int, f, barred: Dictionary, you: Vector2i) -> Variant:
	if m.patrol.is_empty():
		m.patrol = [m.cell, _far_end(m, index, f, barred)]
		m.leg = 1
	if m.cell == m.patrol[m.leg]:
		m.leg = 1 - m.leg
	var next: Variant = _downhill(m, f, _field(f, m.patrol[m.leg], barred), barred, you)
	if next == null:
		m.leg = 1 - m.leg
	return next


static func _far_end(m, index: int, f, barred: Dictionary) -> Vector2i:
	var field := _field(f, m.cell, barred)
	var farthest := 0
	for c in field:
		farthest = maxi(farthest, mini(field[c], int(table().patrol_reach)))
	var ends := []
	for c in field:
		if field[c] == farthest:
			ends.append(c)
	return ends[_roll(f, index, ends.size())]


## Whether a monster may step here: floor it may stand on, with nobody on it.
static func _free(f, c: Vector2i, barred: Dictionary) -> bool:
	return f.is_open(c) and not barred.has(c) and f.monster_at(c) == null


## Where no monster goes: pads, things lying about, the trader, whoever is asking, chests and the stairs.
static func _barred(f) -> Dictionary:
	var out: Dictionary = f.reserved()
	out[f.stairs] = true
	for t in f.treasure:
		out[t.cell] = true
	return out


## How many steps every cell a monster can walk is from `from`.
static func _field(f, from: Vector2i, barred: Dictionary) -> Dictionary:
	var out := {from: 0}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for d in FloorMap.DIRS:
			var c: Vector2i = at + d
			if f.is_open(c) and not barred.has(c) and not out.has(c):
				out[c] = out[at] + 1
				queue.append(c)
	return out


## A whole number below `n` for this monster on this step of this floor.
static func _roll(f, index: int, n: int) -> int:
	var x: int = f.seed_value + index * 2654435761 + f.steps * 40503
	x = (x ^ (x >> 15)) * 2862933555777941757
	return posmod(x ^ (x >> 27), n)
