## Game feel, kept apart from the rules: screen shake, hit-stop, the party's danger level, and the event bus
## that carries combat moments from the game's logic to whatever shows or sounds them (game.gd wires it).
## Everything here is pure or takes the clock as an argument, so it can be tested without a window.
extends RefCounted

const J = preload("res://src/core/js.gd")

# ---------------------------------------------------------------- the event bus
## Every event the presentation listens to, with the fields its payload must carry. emit() refuses an unknown
## event or a missing field, so a typo in game.gd fails loudly instead of silently skipping an effect.
const FX_EVENTS = {
	"party:hurt": ["dmg", "hp", "maxHp"], # an adventurer or ally took damage
	"party:down": [], # someone fell unconscious
	"enemy:hit": ["dmg", "maxHp", "crit"], # a monster took damage
	"enemy:kill": ["boss"], # a monster fell
	"view:step": ["dir"], # you moved: dir 1 forward, -1 back
	"view:turn": ["dir"], # you turned: dir -1 left, 1 right
	"view:bump": [], # you walked into a wall
	"combat:start": ["boss"],
	"combat:end": ["won"],
}


## `Juice.create_bus()` → a Bus. Listeners are Callables taking the payload Dictionary.
static func create_bus(catalog: Dictionary = FX_EVENTS) -> Bus:
	return Bus.new(catalog)


class Bus:
	extends RefCounted
	## Where a refused call is reported (the JS threw). Defaults to push_error; tests swap it to capture the text.
	var on_error: Callable = func(msg: String): push_error(msg)
	var _catalog: Dictionary
	var _subs := {} # event name -> Array of Callable (a set: the same Callable is added once)

	func _init(catalog: Dictionary = {}) -> void:
		_catalog = catalog

	## Subscribes; returns a Callable that unsubscribes. An unknown event is reported and the returned Callable does nothing.
	func on(name: String, fn: Callable) -> Callable:
		if not _catalog.has(name):
			on_error.call('fx: no such event "%s"' % name)
			return func(): pass
		if not _subs.has(name):
			_subs[name] = []
		var list: Array = _subs[name]
		if not list.has(fn):
			list.append(fn)
		return func(): list.erase(fn)

	## Delivers `payload` to the listeners. An unknown event or a missing field is reported and returned as
	## {"error": msg}; a success returns {}.
	func emit(name: String, payload := {}) -> Dictionary:
		if not _catalog.has(name):
			var msg := 'fx: no such event "%s"' % name
			on_error.call(msg)
			return {"error": msg}
		var missing := []
		for f in _catalog[name]:
			if not payload.has(f):
				missing.append(f)
		if not missing.is_empty():
			var msg := 'fx: "%s" needs %s' % [name, ", ".join(missing)]
			on_error.call(msg)
			return {"error": msg}
		for fn: Callable in (_subs.get(name, []) as Array).duplicate():
			# a broken effect never breaks the game: a listener whose object is gone is skipped
			if not fn.is_valid():
				print_verbose("fx: %s listener is gone, skipped" % name)
				continue
			fn.call(payload)
		return {}


# ---------------------------------------------------------------- screen shake
## Trauma-based shake: hits add trauma (0..1), it drains at a steady rate, and the offset grows with its square,
## so small hits barely nudge and big ones really rattle. The motion is smooth noise (sums of sines with odd
## frequencies), not a new random jump every frame. A kick can be dated in the future (`at`), to land with a die.
const SHAKE = {"maxPx": 10, "drainPerSec": 1.8}


class Shake:
	extends RefCounted
	var max_px
	var drain
	var seed
	var trauma := 0.0
	var last = null
	var pending: Array = []

	## opts: {maxPx, drainPerSec, seed}
	func _init(opts := {}) -> void:
		max_px = opts.get("maxPx", 10)
		drain = opts.get("drainPerSec", 1.8)
		seed = opts.get("seed", 0)

	## `at` (ms, optional) dates the kick in the future.
	func add(amount: float, at = null) -> void:
		if at != null and last != null and at > last:
			pending.append({"amount": amount, "at": at})
		else:
			trauma = minf(1.0, trauma + amount)

	## Advance to `now` (ms) and return the [dx, dy] offset in pixels.
	func offset(now: float) -> Array:
		if last != null:
			trauma = maxf(0.0, trauma - (drain * (now - last)) / 1000.0)
		last = now
		if not pending.is_empty():
			var due := pending.filter(func(p): return p.at <= now)
			pending = pending.filter(func(p): return p.at > now)
			for p in due:
				trauma = minf(1.0, trauma + p.amount)
		if trauma <= 0.0:
			return [0.0, 0.0]
		var k: float = max_px * trauma * trauma
		var s: float = now / 1000.0 + seed
		return [k * _noise(s, 41, 67, 103), k * _noise(s, 53, 79, 97)]

	static func _noise(s: float, a: float, b: float, c: float) -> float:
		return (sin(s * a) + sin(s * b) * 0.6 + sin(s * c) * 0.3) / 1.9


## How much trauma each moment adds. Party damage scales with how much of the victim's health it took.
static func trauma_for(name: String, p := {}) -> float:
	var dmg := float(p.get("dmg", 0))
	var share := minf(1.0, dmg / maxf(1.0, float(p.get("maxHp", 0))))
	match name:
		"party:hurt":
			return 0.28 + 0.5 * share
		"party:down":
			return 0.55
		"enemy:hit":
			return 0.4 if J.truthy(p.get("crit")) else 0.12 + 0.18 * share
		"enemy:kill":
			return 0.75 if J.truthy(p.get("boss")) else 0.3
		"view:bump":
			return 0.16
	return 0.0


# ---------------------------------------------------------------- hit-stop
## A big hit freezes the monsters' animation for a few frames, so the blow reads. clock(now) is the
## animation time: it stands still during a freeze and then carries on without jumping ahead.
const HITSTOP_MS = {"crit": 90, "kill": 70, "bossKill": 160, "down": 110}


class HitStop:
	extends RefCounted
	var lost := 0.0 # ms the clock has stood still in total
	var from := 0.0
	var until := 0.0

	func freeze(now: float, ms: float) -> void:
		if now >= until:
			settle(now)
			from = now
		until = maxf(until, now + ms)

	func settle(now: float) -> void:
		if until > from and now >= until:
			lost += until - from
			from = until

	func clock(now: float) -> float:
		if now < until and now >= from:
			return from - lost
		settle(now)
		return now - lost


# ---------------------------------------------------------------- danger
## How close the party is to falling, 0 (fine) to 1 (about to wipe): from the share of health left among the
## living, and from anyone lying unconscious and rolling death saves. Drives the music's low-pass, the
## heartbeat and the red edge of the view.
static func danger_of(party: Array) -> float:
	var living := party.filter(func(m): return not J.truthy(m.get("dead")))
	if living.is_empty():
		return 1.0
	var hp := 0.0
	var max_hp := 0.0
	var dying := 0
	for m in living:
		hp += maxf(0.0, float(m.get("hp", 0)))
		max_hp += float(m.get("maxHp", 0))
		if J.truthy(m.get("down")) and not J.truthy(m.get("stable")):
			dying += 1
	var frac := hp / max_hp if max_hp != 0.0 else 0.0
	var from_health := minf(1.0, maxf(0.0, (0.5 - frac) / 0.35)) # 0 at half health, 1 at 15%
	var from_dying := minf(1.0, 0.6 + 0.2 * (dying - 1)) if dying > 0 else 0.0
	return maxf(from_health, from_dying)


## Ease a value toward its target, frame-rate independent: `half_life` ms to close half the gap.
static func approach(value: float, target: float, dt_ms: float, half_life := 250.0) -> float:
	return target + (value - target) * pow(0.5, dt_ms / half_life)


# ---------------------------------------------------------------- view transitions
## Moving and turning ease between the old view and the new one: a step dollies (the old frame grows past you
## as it fades), a turn pans. Returns how to draw the old frame at time `now`, or null once it is done.
const TRANSITION_MS = {"step": 150, "turn": 170, "bump": 140}


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


## tr: {kind, dir, t0} or null. Returns {kind, scale, alpha, shift, p} or null.
static func transition_at(tr, now: float):
	if tr == null:
		return null
	var p: float = (now - float(tr.t0)) / float(TRANSITION_MS[tr.kind])
	if p >= 1.0 or p < 0.0:
		return null
	var e := _ease_out(p)
	if tr.kind == "step":
		return {"kind": "step", "scale": 1.0 + 0.45 * e if tr.dir > 0 else 1.0 - 0.3 * e, "alpha": 1.0 - e, "shift": 0.0, "p": p}
	if tr.kind == "turn":
		return {"kind": "turn", "scale": 1.0, "alpha": 1.0, "shift": -tr.dir * e, "p": p} # shift in view widths
	# bump: the view lunges a little toward the wall and springs back
	return {"kind": "bump", "scale": 1.0 + 0.06 * sin(PI * p), "alpha": 0.0, "shift": 0.0, "p": p}
