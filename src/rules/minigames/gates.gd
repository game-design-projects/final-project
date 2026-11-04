## Walls: a wall flies in from the right, one column at a time, with a gap in it. Be at the gap when it reaches you. Only the
## wall's next column shows, so it reads as moving (view/overlay.gd).
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const STEP_MS := 300.0 # how long a wall takes over one column
const GAP := 3
const LEAD_MS := 500.0 # before a wall's first column arrives


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	var step: float = STEP_MS / (run.intensity * run.pace)
	run.next_t = t + step * (Dodge.COLS + 3)
	var gap := rng.int_range(0, Dodge.ROWS - GAP)
	for c in Dodge.COLS:
		var cells := []
		for r in Dodge.ROWS:
			if r < gap or r >= gap + GAP:
				cells.append(Dodge.index(Dodge.COLS - 1 - c, r))
		run.add_hazard(t, cells, (LEAD_MS + step * c) * run.pace, step, "wall", {"shows": step * 1.5})
