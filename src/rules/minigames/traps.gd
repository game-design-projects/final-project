## Traps: squares around you light for a moment, then go dark, and spring a while later. Remember where they were. Never
## your own square, and never all of your neighbours at once, so there is always somewhere to stand.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const EVERY_MS := 1700.0
const COUNT := 7
const COUNT_HARD := 9 # from intensity 1.3
const NEAR := 3 # Chebyshev distance of "close to you"
const NEAR_SHARE := 0.7
const WARN_MS := 1100.0
const HIT_MS := 300.0
const SHOWN_MS := 450.0 # how long the traps show before they hide
const NEIGHBOURS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + EVERY_MS / (run.intensity * run.pace)
	var soul: Vector2i = run.soul
	var near := []
	var far := []
	for r in Dodge.ROWS:
		for c in Dodge.COLS:
			if c == soul.x and r == soul.y:
				continue
			(near if maxi(absi(c - soul.x), absi(r - soul.y)) <= NEAR else far).append(Dodge.index(c, r))
	rng.shuffle(near)
	rng.shuffle(far)
	var want := COUNT_HARD if run.intensity >= 1.3 else COUNT
	var cells := []
	while cells.size() < want and not (near.is_empty() and far.is_empty()):
		var from_near := rng.chance(NEAR_SHARE)
		if near.is_empty():
			from_near = false
		elif far.is_empty():
			from_near = true
		cells.append(near.pop_back() if from_near else far.pop_back())
	# never every neighbour of the soul at once: leave one open
	var around := []
	for d in NEIGHBOURS:
		if Dodge.in_box(soul.x + d.x, soul.y + d.y):
			around.append(Dodge.index(soul.x + d.x, soul.y + d.y))
	if not around.is_empty() and around.all(func(k): return cells.has(k)):
		cells.erase(rng.pick(around))
	run.add_hazard(t, cells, WARN_MS, HIT_MS, "chess", {"flash": SHOWN_MS})
	print_verbose("traps: %d traps set, shown %d ms, then hidden" % [cells.size(), SHOWN_MS])
