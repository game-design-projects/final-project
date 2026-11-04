## Stars: they fall to be caught, each healing a little (dodge_run.gd sees to the catch); a red splash now and then keeps you moving.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const EVERY_MS := 620.0
const SPLASH_ODDS := 0.5


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + EVERY_MS / (run.intensity * run.pace)
	var at := Vector2i(rng.int_range(0, Dodge.COLS - 1), rng.int_range(0, Dodge.ROWS - 1))
	run.add_hazard(t, [Dodge.index(at.x, at.y)], 900.0, 420.0, "star", {"at": Dodge.index(at.x, at.y)})
	if rng.chance(SPLASH_ODDS):
		_splash(run, t, rng)


static func _splash(run, t: float, rng: Rng) -> void:
	var c := rng.int_range(1, Dodge.COLS - 2)
	var r := rng.int_range(1, Dodge.ROWS - 2)
	var cells := []
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		cells.append(Dodge.index(c + d.x, r + d.y))
	run.add_hazard(t, cells, 950.0, 260.0, "goo", {"at": Dodge.index(c, r)})
