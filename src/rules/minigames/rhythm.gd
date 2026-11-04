## Rhythm: it stomps on the beat. A new stomp every other beat, shown two beats ahead, landing on the beat.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")


static func spawn(run, t: float, _rng: Rng, events: Array) -> void:
	var beat_ms := 600.0 / sqrt(run.intensity * run.pace)
	var b := floori((t - run.t0) / beat_ms)
	if b <= run.beat:
		return
	run.beat = b
	run.pulse = t
	events.append({"type": "beat"})
	events.append({"type": "sound", "name": "tick"})
	if b % 2 == 1:
		return
	var pattern: int = (b * 5 + run.foe_turn % 3) % Dodge.stomp_count()
	run.add_hazard(t, Dodge.stomp_cells(pattern, run.soul), beat_ms * 2.0, 240.0, "stomp", {"beat_hit": true})
