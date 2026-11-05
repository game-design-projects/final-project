## Dance: a pad of light moves a step on every beat, with the next one shown a beat ahead. On it when the beat lands, you heal a
## little (dodge_run.gd sees to it); every fourth beat something stomps as well, so you can't only watch your feet.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Rng = preload("res://src/utils/rng.gd")

const BEAT_MS := 640.0
const ON_THE_BEAT_MS := 220.0 # how long a pad stays good after its beat
const STOMP_EVERY := 4


static func spawn(run, t: float, rng: Rng, events: Array) -> void:
	var beat_ms := BEAT_MS / sqrt(run.intensity * run.pace)
	var b := floori((t - run.t0) / beat_ms)
	if b <= run.beat:
		return
	run.beat = b
	run.pulse = t
	events.append({"type": "beat"})
	events.append({"type": "sound", "name": "tick"})
	run.pad = _next_pad(run.pad, rng)
	var at := Dodge.index(run.pad.x, run.pad.y)
	run.add_hazard(t, [at], beat_ms * run.pace, ON_THE_BEAT_MS, "pad", {"at": at}) # (add_hazard undoes the pace: it stays a beat)
	if b % STOMP_EVERY == STOMP_EVERY - 1:
		var pattern: int = (b * 5 + run.foe_turn % 3) % Dodge.stomp_count()
		var cells: Array = Dodge.stomp_cells(pattern, run.soul).filter(func(k): return k != at)
		run.add_hazard(t, cells, beat_ms * 2.0, 240.0, "stomp", {"beat_hit": true})


## One step on from where the pad was, inside the box.
static func _next_pad(from: Vector2i, rng: Rng) -> Vector2i:
	var ways := []
	for d in FloorMap.DIRS:
		if Dodge.in_box(from.x + d.x, from.y + d.y):
			ways.append(from + d)
	return rng.pick(ways)
