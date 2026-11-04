## Goo rain: blobs fall, some aimed at you; each splashes a small cross where its squares glow.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + 330.0 / (run.intensity * run.pace)
	var aimed := rng.chance(0.4)
	var c: int = run.soul.x if aimed else rng.int_range(0, Dodge.COLS - 1)
	var r: int = run.soul.y if aimed else rng.int_range(0, Dodge.ROWS - 1)
	var cells := []
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Dodge.in_box(c + d.x, r + d.y):
			cells.append(Dodge.index(c + d.x, r + d.y))
	run.add_hazard(t, cells, 820.0, 260.0, "goo", {"at": Dodge.index(c, r)})
