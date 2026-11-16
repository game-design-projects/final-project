## Gaze: a beam through the middle of the box turns like a lighthouse, a step at a time, and now and then turns back. Each
## step is drawn a little before it lands, so the next square is always in view. Hotter, and a second beam turns with it.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const STEP_MS := 420.0 # one turn of the beam
const STEP_ANGLE := PI / 8.0 # 22.5 degrees
const BEAM_HALF := 0.55 # cells whose centre lies this near the line are lit
const LEAD_MS := 330.0 # a beam is drawn at least this long before it lands (the bot's REACT_MS is 300)
const TWO_BEAMS := 1.3 # from this intensity a second beam at right angles turns with the first
const CENTRE := Vector2i(3, 3)


static func begin(run, rng: Rng) -> void:
	run.mem = {"step": 0, "dir": 1 if rng.chance(0.5) else -1, "left": rng.int_range(6, 10), "start": rng.int_range(0, 7)}
	print_verbose("gaze: step %.0f ms, %s beams" % [STEP_MS / (run.intensity * run.pace), 2 if run.intensity >= TWO_BEAMS else 1])


## The cells whose centres lie within BEAM_HALF of the line through the middle of the box at `angle`.
static func beam_cells(angle: float) -> Array:
	var out := []
	var d := Vector2(cos(angle), sin(angle))
	for r in Dodge.ROWS:
		for c in Dodge.COLS:
			var off := Vector2(c - CENTRE.x, r - CENTRE.y)
			if absf(off.x * d.y - off.y * d.x) <= BEAM_HALF:
				out.append(Dodge.index(c, r))
	return out


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	var step: float = STEP_MS / (run.intensity * run.pace)
	run.next_t = t + step
	var m: Dictionary = run.mem
	if m.left <= 0:
		m.dir = -m.dir
		m.left = rng.int_range(6, 10)
	m.left -= 1
	m.step += m.dir
	var angle := float(m.start + m.step) * STEP_ANGLE
	var cells := beam_cells(angle)
	if run.intensity >= TWO_BEAMS:
		cells.append_array(beam_cells(angle + PI / 2.0))
	# drawn whole steps ahead (two at least), enough of them that the beam shows for LEAD_MS
	var lead := step * maxf(2.0, ceilf(LEAD_MS / step))
	run.add_hazard(t, cells, lead * run.pace, step, "beam", {"at": Dodge.index(CENTRE.x, CENTRE.y), "mark": "eye", "mark_warn": true, "shows": lead})
