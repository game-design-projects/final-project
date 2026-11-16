## Crush: a press closes two opposite walls in, a pair of lines at a time, until only the middle line is left, then stamps
## that line too but for a gap. The gap shows early. The next press closes from the other two sides.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const BEAT_MS := 500.0
const STAMP_MS := 300.0
const PRESS_BEATS := 5 # the press runs four beats, the fifth is its rest
const START_BEAT := 1
const ONE_CELL_GAP := 1.3 # from this intensity the gap is one square, not two


static func begin(run, _rng: Rng) -> void:
	run.mem = {"press": 0, "gap": 0}
	print_verbose("crush: beat %.0f ms, press every %d beats" % [BEAT_MS / sqrt(run.intensity * run.pace), PRESS_BEATS])


## The lines of the press: `wall(d)` is the two lines at depth `d`, from the sides (columns when `cols`).
static func _wall(cols: bool, d: int) -> Array:
	var out := []
	for k in [d, Dodge.COLS - 1 - d]:
		out.append_array(Dodge.col_cells(k) if cols else Dodge.row_cells(k))
	return out


static func spawn(run, t: float, rng: Rng, events: Array) -> void:
	var beat_ms := BEAT_MS / sqrt(run.intensity * run.pace)
	var b := floori((t - run.t0) / beat_ms)
	while run.beat < b:
		run.beat += 1
		var n: int = run.beat
		if n == b:
			run.pulse = t
			events.append({"type": "beat"})
			events.append({"type": "sound", "name": "tick"})
		_on_beat(run, t, n, beat_ms, rng)


## What beat `n` of the run sets going. `t` is now, and beat `n` falls at t0 + n * beat_ms.
static func _on_beat(run, t: float, n: int, beat_ms: float, rng: Rng) -> void:
	if n < START_BEAT or (n - START_BEAT) % PRESS_BEATS > 2:
		return
	var local := (n - START_BEAT) % PRESS_BEATS
	var press := (n - START_BEAT) / PRESS_BEATS
	var cols := press % 2 == 0
	var start_ms: float = run.t0 + float(n - local) * beat_ms # the press began here
	var stamp_ms := start_ms + beat_ms * 4.0 # the middle line lands
	var release := stamp_ms + STAMP_MS
	# the wall at depth `local` closes one beat after it is drawn and stays lit until the press ends
	var land: float = run.t0 + float(n + 1) * beat_ms
	run.add_hazard(t, _wall(cols, local), (land - t) * run.pace, release - land, "wall")
	if local != 2:
		return
	# the stamp is drawn two beats ahead; the gap goes within a step of the soul, along the line
	var size := 1 if run.intensity >= ONE_CELL_GAP else 2
	var along: int = run.soul.y if cols else run.soul.x
	var first := clampi(along + rng.int_range(-2 - (size - 1), 2), 0, Dodge.COLS - size)
	var cells := []
	for k in Dodge.COLS:
		if k < first or k >= first + size:
			cells.append(Dodge.index(3, k) if cols else Dodge.index(k, 3))
	run.mem.gap = first
	print_verbose("crush: press %d (%s), gap at %d" % [press, "columns" if cols else "rows", first])
	run.add_hazard(t, cells, stamp_ms - t, STAMP_MS, "stomp")
