## Shadow: the lantern circles the box and flares; every square burns but those in a pillar's shadow.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")


static func spawn(run, t: float, _rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + 1250.0 / (run.intensity * run.pace)
	var warn := 900.0
	var lantern := Dodge.lantern_at(t + warn / run.pace - run.t0, run.intensity)
	var cells := []
	for r in Dodge.ROWS:
		for c in Dodge.COLS:
			var k := Dodge.index(c, r)
			if not run.blocked.has(k) and not Dodge.in_shadow(lantern, c, r, run.blocked):
				cells.append(k)
	run.add_hazard(t, cells, warn, 300.0, "light", {"lantern": lantern})
