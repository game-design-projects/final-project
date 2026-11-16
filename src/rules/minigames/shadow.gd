## Shadow: the lantern circles the box and flares; every square burns but those in a pillar's shadow. A flare whose shadows are
## too far for you to reach in time waits a little longer (the lantern moves on, and its shadows with it).
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const WARN_MS := 900.0
const STEP_MS := 200.0 # a person tapping an arrow five times a second
const WARN_STRETCH := [1.0, 1.25, 1.5] # how much longer a flare may warn when its shadows are far from you


static func spawn(run, t: float, _rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + 1250.0 / (run.intensity * run.pace)
	for stretch in WARN_STRETCH:
		var warn: float = WARN_MS * stretch
		var lantern := Dodge.lantern_at(t + warn / run.pace - run.t0, run.intensity)
		var cells := []
		for r in Dodge.ROWS:
			for c in Dodge.COLS:
				var k := Dodge.index(c, r)
				if not run.blocked.has(k) and not Dodge.in_shadow(lantern, c, r, run.blocked):
					cells.append(k)
		var steps := Dodge.steps_to_clear(run.soul, cells, run.blocked)
		if steps >= 0 and steps * STEP_MS <= warn / run.pace:
			run.add_hazard(t, cells, warn, 300.0, "light", {"lantern": lantern})
			return
	print_verbose("shadow: a flare left out, no shadow within reach of %s" % run.soul)
