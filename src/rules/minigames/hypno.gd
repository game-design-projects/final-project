## Hypno: the controls are turned round (left goes right, up goes down) and goo lands where you stand, so you have to steer
## the wrong way out of it. Every fourth drop is your whole row or column.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const DROP_MS := 400.0
const WARN_MS := 650.0
const LINE_WARN_MS := 800.0
const HIT_MS := 250.0


static func begin(run, _rng: Rng) -> void:
	run.mirror = true
	run.mem = {"drops": 0}
	print_verbose("hypno: controls mirrored, a drop every %.0f ms" % (DROP_MS / (run.intensity * run.pace)))


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + DROP_MS / (run.intensity * run.pace)
	run.mem.drops += 1
	var soul: Vector2i = run.soul
	if run.mem.drops % 4 == 0:
		var cells := Dodge.row_cells(soul.y) if rng.chance(0.5) else Dodge.col_cells(soul.x)
		run.add_hazard(t, cells, LINE_WARN_MS, HIT_MS, "goo")
		return
	# a 2x2 blob with the soul in one of its four squares
	var left := clampi(soul.x - rng.int_range(0, 1), 0, Dodge.COLS - 2)
	var top := clampi(soul.y - rng.int_range(0, 1), 0, Dodge.ROWS - 2)
	var cells := []
	for dr in 2:
		for dc in 2:
			cells.append(Dodge.index(left + dc, top + dr))
	run.add_hazard(t, cells, WARN_MS, HIT_MS, "goo", {"at": Dodge.index(left, top)})
