## Golem: it brings its fists down on the beat. One lands where you stood two beats ago, the other where you stood a beat
## later, then a sweep takes two rows, and it rests a beat. Each is shown two beats before it lands.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const BEAT_MS := 700.0
const WARN_BEATS := 2.0
const HIT_MS := 260.0


static func begin(run, _rng: Rng) -> void:
	run.mem = {}
	print_verbose("golem: beat %.0f ms" % (BEAT_MS / sqrt(run.intensity * run.pace)))


## A fist: the 3x3 around `centre`, which is kept far enough in for the fist to fit.
static func _fist(centre: Vector2i) -> Array:
	var c := clampi(centre.x, 1, Dodge.COLS - 2)
	var r := clampi(centre.y, 1, Dodge.ROWS - 2)
	var cells := []
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			cells.append(Dodge.index(c + dc, r + dr))
	return [Dodge.index(c, r), cells]


static func spawn(run, t: float, rng: Rng, events: Array) -> void:
	var beat_ms := BEAT_MS / sqrt(run.intensity * run.pace)
	var b := floori((t - run.t0) / beat_ms)
	if b <= run.beat:
		return
	run.beat = b
	run.pulse = t
	events.append({"type": "beat"})
	events.append({"type": "sound", "name": "tick"})
	var warn := beat_ms * WARN_BEATS
	match b % 4:
		0, 1:
			var fist := _fist(run.soul)
			run.add_hazard(t, fist[1], warn, HIT_MS, "stomp", {"at": fist[0], "mark": "fist", "mark_warn": true})
		2:
			var top: int = run.soul.y if rng.chance(0.5) else run.soul.y - 1
			top = clampi(top, 0, Dodge.ROWS - 2)
			run.add_hazard(t, Dodge.row_cells(top) + Dodge.row_cells(top + 1), warn, HIT_MS, "stomp")
