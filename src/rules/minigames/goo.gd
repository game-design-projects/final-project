## Goo rain: blobs fall, some aimed at you; each splashes a small cross where its squares glow. A champion's goo comes down
## faster: the same splash lands on less warning, so its rain has to be read as it starts (#170).
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const CROSS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const WARN_MS := 820.0
const BOSS_WARN_MS := 700.0
const HIT_MS := 260.0
const EVERY_MS := 330.0


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + EVERY_MS / (run.intensity * run.pace)
	var aimed := rng.chance(0.4)
	var c: int = run.soul.x if aimed else rng.int_range(0, Dodge.COLS - 1)
	var r: int = run.soul.y if aimed else rng.int_range(0, Dodge.ROWS - 1)
	var cells := []
	for d in CROSS:
		if Dodge.in_box(c + d.x, r + d.y):
			cells.append(Dodge.index(c + d.x, r + d.y))
	run.add_hazard(t, cells, BOSS_WARN_MS if run.boss else WARN_MS, HIT_MS, "goo", {"at": Dodge.index(c, r)})
