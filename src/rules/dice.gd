## A die you can see: it tumbles through random faces, then slams onto the real number (~200ms in all).
## Frame maths and shapes are pure (tested in tests/rules/test_dice.gd); draw_die / DicePops paint wireframes
## through a Canvas2D context.
extends RefCounted

const J = preload("res://src/core/js.gd")

const DIE_TUMBLE_MS = 130 # flickering through random faces, spinning and growing toward the camera
const DIE_LAND_MS = 70 # the slam: scale punch + flash, number locked in
const DIE_ANIM_MS = DIE_TUMBLE_MS + DIE_LAND_MS # 200: the whole roll animation
const DIE_HOLD_MS = 550 # the result stays readable after it lands (longer on a natural 20 / 1)
const DIE_FADE_MS = 250
const FACE_MS = 26 # a new random face about every 26ms while tumbling

const RED = "#ff4a3a"
const _IDLE = {"show": false, "faceIdx": 0, "rot": 0.0, "hop": 0.0, "scale": 1.0, "flash": 0.0, "glow": 0.0, "shake": 0.0, "alpha": 0.0, "landed": false, "done": false}


## "crit" on a natural 20, "fumble" on a natural 1 (d20 only), else null.
static func die_tier(value, sides := 20):
	if sides != 20:
		return null
	return "crit" if value == 20 else ("fumble" if value == 1 else null)


static func _hold_for(tier) -> int:
	return DIE_HOLD_MS + (350 if tier != null else 0)


static func pop_life_ms(tier) -> int:
	return DIE_ANIM_MS + _hold_for(tier) + DIE_FADE_MS


## Faces to flicker through before the real number: random, never the same twice in a row, and the last
## flicker is never the final value (so the number visibly lands). faces[count - 1] is the final value.
## `count` null: the default (6). `rng`: a Callable returning [0, 1), default randf.
static func face_sequence(final, sides := 20, count = null, rng := Callable()) -> Array:
	var n: int = ceili(float(DIE_TUMBLE_MS) / FACE_MS) + 1 if count == null else int(count)
	var faces := []
	for i in n - 1:
		var f: int
		var tries := 0
		while true:
			f = 1 + floori((rng.call() if rng.is_valid() else randf()) * sides)
			var again := tries < 20
			tries += 1
			if not (again and sides > 2 and ((i > 0 and f == faces[i - 1]) or (i == n - 2 and f == final))):
				break
		faces.append(f)
	faces.append(final)
	return faces


static func _ease_out(p: float) -> float:
	return 1.0 - (1.0 - p) * (1.0 - p)


static func _frame(over: Dictionary) -> Dictionary:
	var f := _IDLE.duplicate()
	f.merge(over, true)
	return f


## What a die looks like `age` ms after it was thrown (negative: not thrown yet).
##   rot: radians; hop/scale: px offset and size multiplier; flash 0..1 white at the slam; glow 0..1 (nat 20);
##   shake: px of horizontal jitter (nat 1); faceIdx: index into face_sequence; landed: number is locked in.
static func die_frame(age: float, tier = null) -> Dictionary:
	if age < 0:
		return _frame({})
	var punch := 0.8 if tier == "crit" else (0.35 if tier == "fumble" else 0.5)
	var faces := ceili(float(DIE_TUMBLE_MS) / FACE_MS)
	if age < DIE_TUMBLE_MS:
		var p := age / DIE_TUMBLE_MS
		return _frame({
			"show": true,
			"alpha": 1.0,
			"faceIdx": mini(floori(age / FACE_MS), faces - 1),
			"rot": _ease_out(p) * 2.0 * TAU, # two turns, fast to slow, ending upright
			"hop": -sin(PI * p) * 8.0,
			"scale": 0.7 + (1.0 + punch - 0.7) * p * p, # thrown at the camera...
		})
	var total := pop_life_ms(tier)
	if age >= total:
		return _frame({"done": true})
	var q := minf(1.0, (age - DIE_TUMBLE_MS) / DIE_LAND_MS)
	var alpha := 1.0 if age < total - DIE_FADE_MS else (total - age) / DIE_FADE_MS
	var slam := age < DIE_ANIM_MS
	return _frame({
		"show": true,
		"alpha": alpha,
		"landed": true,
		"faceIdx": faces, # the final value
		# ...and slammed down onto the number, dipping a hair below 1 before it settles
		"scale": 1.0 + punch * pow(1.0 - q, 2.0) - 0.1 * sin(PI * q) if slam else 1.0,
		"flash": 1.0 - q if slam else 0.0,
		"glow": (1.0 if slam else 0.65 + 0.35 * sin(age / 80.0)) if tier == "crit" else 0.0,
		"shake": 4.0 * (1.0 - q) if tier == "fumble" and slam else 0.0,
	})


# ---- shapes: unit-radius wireframes, y down. Closed outline polygon plus inner edges [x1, y1, x2, y2].
static func _ring(n: int, radius := 1.0, start := -90.0) -> Array:
	var out := []
	for k in n:
		var a := deg_to_rad(start + (360.0 / n) * k)
		out.append([cos(a) * radius, sin(a) * radius])
	return out


static func _seg(a: Array, b: Array) -> Array:
	return [a[0], a[1], b[0], b[1]]


static func _dist(a: Array, b: Array) -> float:
	return Vector2(a[0] - b[0], a[1] - b[1]).length()


## {outline: [[x, y]...], inner: [[x1, y1, x2, y2]...]}
static func die_shape(sides := 20) -> Dictionary:
	match sides:
		4:
			return {"outline": _ring(3), "inner": []}
		6:
			# a cube seen corner-on: hexagon with a Y inside
			var hex := _ring(6)
			return {"outline": hex, "inner": [1, 3, 5].map(func(i): return _seg([0, 0], hex[i]))}
		8:
			var o := _ring(4)
			return {"outline": o, "inner": [_seg(o[1], o[3]), _seg(o[0], o[2])]}
		10:
			var kite := [[0, -1], [0.85, -0.12], [0, 1], [-0.85, -0.12]]
			return {"outline": kite, "inner": [_seg(kite[0], kite[2]), _seg(kite[1], [0, 0.3]), _seg(kite[3], [0, 0.3])]}
		12:
			var o := _ring(5)
			var i := _ring(5, 0.5, 90.0)
			var edges := []
			for k in 5:
				edges.append(_seg(i[k], i[(k + 1) % 5]))
			for p in o:
				var best: Array = i[0]
				for q in i.slice(1):
					if _dist(q, p) < _dist(best, p):
						best = q
				edges.append(_seg(p, best))
			return {"outline": o, "inner": edges}
		20:
			# the classic d20 icon: hexagon, inner triangle, every hexagon corner tied to the triangle
			var hex := _ring(6)
			var tri := _ring(3, 0.52, 90.0) # points down
			var inner := []
			for k in 3:
				inner.append(_seg(tri[k], tri[(k + 1) % 3]))
			for h in hex:
				var order := [0, 1, 2]
				# nearest first; equal distances keep their order, as JS's stable sort does
				order.sort_custom(func(a, b):
					var da := _dist(tri[a], h)
					var db := _dist(tri[b], h)
					return a < b if da == db else da < db)
				inner.append(_seg(h, tri[order[0]]))
				if _dist(tri[order[1]], h) < 0.95:
					inner.append(_seg(h, tri[order[1]]))
			return {"outline": hex, "inner": inner}
	return {"outline": _ring(8), "inner": []}


# ---- drawing

static func _path(ctx, pts: Array) -> void:
	ctx.begin_path()
	for i in pts.size():
		if i:
			ctx.line_to(pts[i][0], pts[i][1])
		else:
			ctx.move_to(pts[i][0], pts[i][1])
	ctx.close_path()


## One die at (x, y), radius r, already framed by die_frame. `face` is the number to print.
## opts: {x, y, r = 16, sides = 20, face, frame, ink = "#e8e8e8", hot = "#ffd27a", tier = null, label = "", dim = false, seed = 0}
static func draw_die(ctx, opts: Dictionary) -> void:
	var frame: Dictionary = opts.frame
	if not frame.show:
		return
	var x: float = opts.x
	var y: float = opts.y
	var r: float = J.nz(opts.get("r"), 16)
	var ink = J.nz(opts.get("ink"), "#e8e8e8")
	var hot = J.nz(opts.get("hot"), "#ffd27a")
	var tier = opts.get("tier")
	var label: String = J.nz(opts.get("label"), "")
	var dim: bool = J.truthy(opts.get("dim"))
	var shape := die_shape(J.nz(opts.get("sides"), 20))
	var outline: Array = shape.outline
	var inner: Array = shape.inner
	var line = hot if tier == "crit" else (RED if tier == "fumble" and frame.landed else ink)
	var jitter: float = sin(J.nz(opts.get("seed"), 0) + frame.shake * 40.0) * frame.shake if frame.shake else 0.0
	var dimmed: bool = dim and frame.landed
	var k: float = r * frame.scale * (0.8 if dimmed else 1.0)
	var alpha: float = frame.alpha * (0.4 if dimmed else 1.0)
	ctx.save()
	ctx.global_alpha = alpha
	ctx.translate(J.round_js(x + jitter), J.round_js(y + frame.hop))
	ctx.rotate(frame.rot)
	ctx.scale(k, k)
	if frame.glow:
		ctx.shadow_color = hot
		ctx.shadow_blur = 14.0 * frame.glow
	_path(ctx, outline)
	ctx.fill_style = "rgba(0,0,0,0.88)"
	ctx.fill()
	ctx.line_join = "round"
	ctx.line_width = 2.0 / k
	ctx.stroke_style = line
	ctx.stroke()
	ctx.shadow_blur = 0.0
	ctx.line_width = 1.0 / k
	ctx.global_alpha *= 0.5
	ctx.begin_path()
	for e in inner:
		ctx.move_to(e[0], e[1])
		ctx.line_to(e[2], e[3])
	ctx.stroke()
	ctx.global_alpha = alpha
	if frame.flash > 0:
		_path(ctx, outline)
		ctx.fill_style = hot if tier == "crit" else "#ffffff"
		ctx.global_alpha *= 0.7 * frame.flash
		ctx.fill()
		ctx.global_alpha = alpha
	# the number (counter-scaled so the font stays crisp)
	ctx.scale(1.0 / k, 1.0 / k)
	var shown := J.num(opts.get("face"))
	ctx.font = "%dpx \"Press Start 2P\", monospace" % J.round_js(r * (0.62 if shown.length() > 1 else 0.78))
	ctx.text_align = "center"
	ctx.text_baseline = "middle"
	ctx.fill_style = "#000"
	ctx.fill_text(shown, 1.5, J.round_js(r * 0.05) + 1.5)
	ctx.fill_style = "#000" if frame.landed and frame.flash > 0.5 else (line if frame.landed and tier != null else "#ffffff")
	ctx.fill_text(shown, 0, J.round_js(r * 0.05))
	ctx.scale(k, k)
	if frame.landed and tier == "fumble":
		# a crack through the die
		ctx.stroke_style = RED
		ctx.line_width = 1.6 / k
		ctx.begin_path()
		var crack := [[-0.25, -0.95], [0.1, -0.4], [-0.2, 0.05], [0.22, 0.5], [0, 0.98]]
		for i in crack.size():
			if i:
				ctx.line_to(crack[i][0], crack[i][1])
			else:
				ctx.move_to(crack[i][0], crack[i][1])
		ctx.stroke()
	if frame.landed and tier == "crit":
		# rays burst out of the die as it lands
		var grow: float = 1.25 + 0.5 * (frame.flash if frame.flash else 0.2)
		ctx.stroke_style = hot
		ctx.line_width = 1.5 / k
		ctx.begin_path()
		for i in 8:
			var a := (i / 8.0) * TAU + PI / 8.0
			ctx.move_to(cos(a) * 1.25, sin(a) * 1.25)
			ctx.line_to(cos(a) * grow * 1.35, sin(a) * grow * 1.35)
		ctx.stroke()
	ctx.restore()
	if label != "" and frame.landed:
		ctx.save()
		ctx.global_alpha = frame.alpha * (0.4 if dim else 1.0)
		ctx.font = "7px \"Press Start 2P\", monospace"
		ctx.text_align = "center"
		ctx.fill_style = "#000"
		ctx.fill_text(label, J.round_js(x) + 1, J.round_js(y + r + 12) + 1)
		ctx.fill_style = line
		ctx.fill_text(label, J.round_js(x), J.round_js(y + r + 12))
		ctx.restore()


## The scale bump for anything that "lands" (the Roll of Fate name): 1 + strength at the slam, settling to 1 in 200ms.
static func land_punch(age: float, strength := 0.45) -> float:
	return 1.0 + strength * pow(1.0 - age / DIE_ANIM_MS, 2.0) if age >= 0 and age < DIE_ANIM_MS else 1.0


## Dice currently on screen. Each pop is one roll: a single d20, or two for advantage / disadvantage.
class DicePops:
	extends RefCounted
	const Dice = preload("res://src/rules/dice.gd")
	var max: int
	var pops: Array = []
	## Number of pops on screen.
	var size: int:
		get:
			return pops.size()

	func _init(max_count := 10) -> void:
		max = max_count

	## opts: {x, y, rolls: every die thrown, kept: the one that counts (default rolls[0]), sides = 20, label: small
	## text under the die (e.g. "=21"), now = J.now_ms(), rng: Callable returning [0, 1)}. Returns the new pop.
	func add(opts: Dictionary) -> Dictionary:
		var x: float = opts.x
		var y: float = opts.y
		var rolls: Array = opts.rolls
		var kept = opts.get("kept", rolls[0])
		var sides: int = opts.get("sides", 20)
		var now: float = opts.get("now", J.now_ms())
		var rng: Callable = opts.get("rng", Callable())
		# Rolls at the same target sit side by side (a round of attacks shows all its dice at once);
		# if there is no room left, the previous result is pushed out.
		var near := pops.filter(func(p): return absf(p.y - y) < 28)
		var free = null
		for dx in [0, 52, -52, 104, -104]:
			if x + dx > 20 and x + dx < 428 and not near.any(func(p): return absf(p.x - (x + dx)) < 48):
				free = dx
				break
		if free != null:
			x += free
		else:
			for p in near:
				if absf(p.x - x) < 48:
					p.t0 = minf(p.t0, now - (DIE_ANIM_MS + Dice._hold_for(p.tier)))
		var tier = Dice.die_tier(kept, sides)
		var kept_idx := maxi(0, rolls.find(kept))
		var dice := []
		for i in rolls.size():
			dice.append({"final": rolls[i], "faces": Dice.face_sequence(rolls[i], sides, null, rng), "kept": i == kept_idx})
		var pop := {"x": x, "y": y, "sides": sides, "label": J.nz(opts.get("label"), ""), "t0": now, "tier": tier, "kept": kept, "dice": dice}
		pops.append(pop)
		while pops.size() > max:
			pops.pop_front()
		return pop

	## Paints every live pop at time `t` (ms) and drops the expired ones. opts: {ink, hot} (CSS colors).
	func draw(ctx, t: float, opts := {}) -> void:
		pops = pops.filter(func(p): return t - p.t0 < Dice.pop_life_ms(p.tier))
		for p in pops:
			var age: float = t - p.t0
			var two: bool = p.dice.size() > 1
			for i in p.dice.size():
				var die: Dictionary = p.dice[i]
				var tier = p.tier if die.kept else Dice.die_tier(die.final, p.sides)
				var frame := Dice.die_frame(age, p.tier if die.kept else null)
				var faces: Array = die.faces
				Dice.draw_die(ctx, {
					"x": p.x + ((19 if i else -19) if two else 0),
					"y": p.y,
					"r": 14 if two else 17,
					"sides": p.sides,
					"face": die.final if frame.landed else faces[mini(frame.faceIdx, faces.size() - 2)],
					"frame": frame,
					"ink": opts.get("ink"),
					"hot": opts.get("hot"),
					"tier": tier if die.kept else null,
					"label": p.label if die.kept else "",
					"dim": two and not die.kept,
					"seed": p.t0 + i,
				})
