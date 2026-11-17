## What you know of a floor without having seen it: late on, the rest of its layout is handed to you, so the last stretch of a
## long floor isn't a search for the stairs. Two ways there (data/floors.json's `chart`): a monster that is out of the way may have
## been carrying a map of the floor, the likelier the more of it you have seen, and at a set share seen your own instinct fills in
## the rest. Either way only the layout and the stairs are learnt: monsters, chests, pads and the champion still show when seen,
## and what lies behind a cracked wall or at the far end of a pad stays a secret (only what can be walked to from the start counts).
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Rng = preload("res://src/utils/rng.gd")

const ROLL_STEP := 7919 # what tells one monster's roll from the next one's on the same floor


static func table() -> Dictionary:
	return Content.table("floors").chart


## The cells that can be walked to from the floor's start, as a set: the floor as far as a map of it goes.
static func reach(floor_map) -> Dictionary:
	var out := {floor_map.start: true}
	var queue: Array = [floor_map.start]
	var at := 0
	while at < queue.size():
		var c: Vector2i = queue[at]
		at += 1
		for d in FloorMap.DIRS:
			var n: Vector2i = c + d
			if floor_map.is_open(n) and not out.has(n):
				out[n] = true
				queue.append(n)
	return out


## How much of the floor you have seen, 0..1, counting only what can be walked to from the start.
static func share(s) -> float:
	var cells: Dictionary = s.reach()
	if cells.is_empty():
		return 0.0
	var n := 0
	for c in cells:
		if s.seen.has(c):
			n += 1
	return float(n) / cells.size()


## Whether there is anything left for a map to tell: not on the practice floor, not twice on one floor, and not when all is seen.
static func open(s) -> bool:
	return s.floor_map != null and not s.practice and s.charted.is_empty() and share(s) < 1.0


## Whether your instinct fills in the rest now.
static func instinct_due(s) -> bool:
	return open(s) and share(s) >= float(table().instinct_at)


## The chance that a monster just out of the way was carrying the floor's map: from `start` with nothing seen up to `full` at the
## share where instinct would do it anyway.
static func drop_chance(s) -> float:
	if not open(s):
		return 0.0
	var t: Dictionary = table()
	var along := clampf(share(s) / float(t.instinct_at), 0.0, 1.0)
	return lerpf(float(t.drop.start), float(t.drop.full), along)


## Whether `m`, now out of the way, was carrying the map. The roll is the monster's own, from the floor's seed and its place among
## the floor's monsters, so a fight tried again rolls the same and no other draw of the run moves.
static func drops(s, m) -> bool:
	if m == null or m.boss or not m.is_gone():
		return false
	var p := drop_chance(s)
	if p <= 0.0:
		return false
	var index: int = s.floor_map.monsters.find(m)
	return Rng.new(Rng.offset(int(s.floor_map.seed_value), ROLL_STEP * (index + 1))).chance(p)


## Learn the rest of the layout: every cell that can be walked to and isn't seen yet is charted. Returns how many that was.
static func reveal(s) -> int:
	var n := 0
	for c in s.reach():
		if not s.seen.has(c) and not s.charted.has(c):
			s.charted[c] = true
			n += 1
	return n


## Whether the map shows this cell's floor: seen, or charted.
static func known(s, c: Vector2i) -> bool:
	return s.seen.has(c) or s.charted.has(c)
