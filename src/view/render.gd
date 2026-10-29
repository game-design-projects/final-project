## Wizardry-style wireframe view, automap, and title card. Lines on black, tinted per floor.
## Ported from crawler/public/render.js. `ctx` is a Canvas2D (`Canvas2D.new(self, Vector2(448, 288))` inside a
## `_draw()`); `ctx.size` plays the part of `ctx.canvas.width/height`.
##
## Points are Vector2 (the JS used [x, y] pairs); face coordinates, cells and edges stay plain Arrays.
## The map is the game's Dictionary: `grid` (rows of 0/1), `stairs` {x, y}, `n`, `palette` {name, wall, accent},
## `seed`, `boss` {x, y, defeated}. `seen` / `visited` are `{cell_key: true}` sets keyed `y * n + x`.
##
## The JS paints the corridor into an offscreen layer and copies it on every frame. Here the corridor is drawn
## straight into the view each frame (`draw_corridor`); what you see from a spot is still worked out once per spot.
extends RefCounted

const J = preload("res://src/core/js.gd")

const DIRS = [
	[0, -1],
	[1, 0],
	[0, 1],
	[-1, 0],
] # N E S W
const DIR_NAMES = ["N", "E", "S", "W"]

const INK = "#e8e8e8"
# Camera: the eye sits EYE cells behind the near edge of your cell (about a 44° field of view),
# and you see VIEW cells ahead. Size falls off as 1/distance, like a real corridor.
const EYE = 1.25
const VIEW = 6
const DEPTH = [
	EYE / (EYE + 0),
	EYE / (EYE + 1),
	EYE / (EYE + 2),
	EYE / (EYE + 3),
	EYE / (EYE + 4),
	EYE / (EYE + 5),
	EYE / (EYE + 6),
	EYE / (EYE + 7),
] # one entry per d in 0..VIEW+1


static func scale_at(z: float) -> float:
	return EYE / (EYE + z)


## World point -> canvas point. The cell you stand in fills the canvas (less a 4px border) at z = 0.
static func project(W: float, H: float, X: float, z: float, Y: float) -> Vector2:
	var s := scale_at(z)
	return Vector2(W / 2.0 + X * (W - 8.0) * s, H / 2.0 + Y * (H - 8.0) * s)


static func _frame(W: float, H: float, d: int) -> Dictionary:
	var f: float = DEPTH[d]
	var cx := W / 2.0
	var cy := H / 2.0
	var w := (W - 8.0) * f
	var h := (H - 8.0) * f
	return {"l": J.round_js(cx - w / 2.0), "r": J.round_js(cx + w / 2.0), "t": J.round_js(cy - h / 2.0), "b": J.round_js(cy + h / 2.0)}


static func _line(ctx, x1: float, y1: float, x2: float, y2: float) -> void:
	ctx.begin_path()
	ctx.move_to(x1 + 0.5, y1 + 0.5)
	ctx.line_to(x2 + 0.5, y2 + 0.5)
	ctx.stroke()


static func clear(ctx) -> void:
	ctx.fill_style = "#000"
	ctx.fill_rect(0, 0, ctx.size.x, ctx.size.y)


# Each floor gets its own colors: wall lines and an accent for torch flames and glows.
const PALETTES = [
	{"name": "BONE CRYPT", "wall": "#e8e2d0", "accent": "#ffb347"},
	{"name": "DROWNED HALLS", "wall": "#8fd3e8", "accent": "#7fffd4"},
	{"name": "BLOOD VAULT", "wall": "#e07a7a", "accent": "#ffcf5a"},
	{"name": "MOSS DEEP", "wall": "#9ed36b", "accent": "#ffe14a"},
	{"name": "ASH CHAMBERS", "wall": "#b9b0a4", "accent": "#ff6b3d"},
	{"name": "VIOLET CATACOMB", "wall": "#b79cf0", "accent": "#ff9de2"},
	{"name": "RUST TUNNELS", "wall": "#d39a6a", "accent": "#ffd27a"},
	{"name": "FROST WARRENS", "wall": "#cfe8ff", "accent": "#9ad0ff"},
]


# Stable pseudo-random number for a wall face, so its decoration never changes as you move or turn.
# The JS works in 32-bit integers (Math.imul, >>>); the low 32 bits of a 64-bit product are the same bits.
static func _hash(n: Array) -> float:
	var h := 2166136261
	for v in n:
		var x := (int(v) + 0x9e3779b9) & 0xFFFFFFFF
		h = (((h ^ x) & 0xFFFFFFFF) * 16777619) & 0xFFFFFFFF
	h ^= h >> 15
	return float(h & 0xFFFFFFFF) / 4294967296.0


# Wall decorations, sketched in (u, v) face coordinates: u across the face, v from top (0) to bottom (1).
const DECOR = ["torch", "torch", "chains", "banner", "crack", "window", "niche"]


# Strokes a polyline given in (u, v) face coordinates through the face mapper `P`
static func _poly(ctx, P: Callable, pts: Array, close := false) -> void:
	ctx.begin_path()
	for i in pts.size():
		var p: Vector2 = P.call(pts[i][0], pts[i][1])
		if i:
			ctx.line_to(p.x, p.y)
		else:
			ctx.move_to(p.x, p.y)
	if close:
		ctx.close_path()
	ctx.stroke()


static func _ring(ctx, P: Callable, cu: float, cv: float, ru: float, rv: float, n := 10) -> void:
	var pts := []
	for i in n:
		pts.append([cu + ru * cos(float(i) / n * 6.283), cv + rv * sin(float(i) / n * 6.283)])
	_poly(ctx, P, pts, true)


static func _decorate(ctx, P: Callable, kind: String, t: float, palette: Dictionary, rseed: float) -> void:
	ctx.save()
	if kind == "torch":
		var f := sin(t / 90.0 + rseed * 40.0) * 0.012 + sin(t / 37.0 + rseed * 17.0) * 0.008
		var g: Vector2 = P.call(0.5, 0.36)
		# Glow sized by the face's height where the torch hangs, which shrinks properly with distance
		var top: Vector2 = P.call(0.5, 0)
		var bottom: Vector2 = P.call(0.5, 1)
		var glow_r := maxf(6.0, absf(bottom.y - top.y) * 0.6)
		var glow = ctx.create_radial_gradient(g.x, g.y, 0, g.x, g.y, glow_r)
		glow.add_color_stop(0, str(palette.accent) + "55")
		glow.add_color_stop(1, str(palette.accent) + "00")
		ctx.fill_style = glow
		ctx.fill_rect(g.x - glow_r, g.y - glow_r, glow_r * 2.0, glow_r * 2.0)
		_poly(ctx, P, [[0.44, 0.58], [0.56, 0.58]]) # bracket
		_poly(ctx, P, [[0.5, 0.58], [0.5, 0.44]]) # handle
		ctx.stroke_style = palette.accent
		_poly(ctx, P, [[0.45, 0.44], [0.47 + f, 0.36], [0.5 - f, 0.26 + f], [0.53 + f, 0.36], [0.55, 0.44]], true) # flame
		_poly(ctx, P, [[0.49, 0.42], [0.5 + f, 0.35], [0.51, 0.42]])
	elif kind == "chains":
		for pair in [[0.38, 0.5], [0.6, 0.36]]:
			var u: float = pair[0]
			var length: float = pair[1]
			_poly(ctx, P, [[u, 0], [u, length]])
			var v := 0.06
			while v < length:
				_ring(ctx, P, u, v, 0.025, 0.03, 6)
				v += 0.08
			_poly(ctx, P, [[u - 0.04, length], [u, length + 0.06], [u + 0.04, length]]) # hook
	elif kind == "banner":
		_poly(ctx, P, [[0.3, 0.06], [0.7, 0.06]])
		_poly(ctx, P, [[0.34, 0.06], [0.34, 0.56], [0.42, 0.5], [0.5, 0.58], [0.58, 0.5], [0.66, 0.56], [0.66, 0.06]])
		_ring(ctx, P, 0.5, 0.26, 0.07, 0.08, 8)
		_poly(ctx, P, [[0.5, 0.18], [0.5, 0.34]])
	elif kind == "crack":
		_poly(ctx, P, [[0.3, 0.18], [0.38, 0.34], [0.34, 0.46], [0.46, 0.6], [0.42, 0.72], [0.52, 0.86]])
		_poly(ctx, P, [[0.38, 0.34], [0.48, 0.38]])
		_poly(ctx, P, [[0.46, 0.6], [0.58, 0.62]])
	elif kind == "window":
		_poly(ctx, P, [[0.36, 0.24], [0.64, 0.24], [0.64, 0.46], [0.36, 0.46]], true)
		for u in [0.43, 0.5, 0.57]:
			_poly(ctx, P, [[u, 0.24], [u, 0.46]])
	elif kind == "niche":
		_poly(ctx, P, [[0.36, 0.78], [0.36, 0.58], [0.42, 0.5], [0.5, 0.47], [0.58, 0.5], [0.64, 0.58], [0.64, 0.78]], true)
		_ring(ctx, P, 0.5, 0.64, 0.06, 0.06, 8) # skull
		ctx.fill_style = ctx.stroke_style
		for u in [0.48, 0.52]:
			var p: Vector2 = P.call(u, 0.63)
			ctx.fill_rect(p.x - 1.0, p.y - 1.0, 2, 2)
		_poly(ctx, P, [[0.47, 0.71], [0.53, 0.71]])
	ctx.restore()


# ---------------------------------------------------------------- 3D corridor
# The view is a real perspective projection of the grid. World coordinates, relative to you:
#   X across (cells, 0 = the middle of your cell, + = right), z ahead (0 = the near edge of your cell),
#   Y down (-0.5 = ceiling, +0.5 = floor). The eye sits EYE cells behind z = 0.
# Walls are painted far to near as black-filled faces, so nearer walls hide what is behind them.

# The surrounding cells, relative to you: d steps ahead, k steps to the right.
static func _cell_at(x: int, y: int, dir: int, d: int, k: int) -> Array:
	var f: Array = DIRS[dir]
	var r: Array = DIRS[(dir + 1) % 4]
	return [x + f[0] * d + r[0] * k, y + f[1] * d + r[1] * k]


static func _is_open(grid: Array, cx: int, cy: int) -> bool:
	if cy < 0 or cy >= grid.size():
		return false
	var row = grid[cy]
	return cx >= 0 and cx < row.size() and row[cx] == 1


static func _is_open_at(grid: Array, c: Array) -> bool:
	return _is_open(grid, c[0], c[1])


# How many cells to each side can fall inside the view at the far end
const REACH = 4 # ceil(0.5 * (EYE + VIEW + 1) / EYE)
# Outer columns first, then inward: within one row, an inner wall may overlap an outer one, never the reverse
const COLUMNS = [-4, 4, -3, 3, -2, 2, -1, 1, 0]


## Every face to draw, in painting order (far to near). Pure: no canvas, so it can be tested.
## front: the wall cell's face toward you, at z = d. side: its face toward your column, from z = d to d + 1.
## `wall` is the wall cell and `from` the floor cell it is seen from (the pair keys its decoration).
static func corridor_faces(map: Dictionary, x: int, y: int, dir: int) -> Array:
	var grid: Array = map["grid"]
	var stairs: Dictionary = map["stairs"]
	var faces := []
	for d in range(VIEW, -1, -1):
		for k in COLUMNS:
			var here := _cell_at(x, y, dir, d, k)
			if _is_open_at(grid, here):
				if stairs["x"] == here[0] and stairs["y"] == here[1]:
					faces.append({"type": "stairs", "d": d, "k": k, "wall": here, "from": here})
				continue
			var inner: int = k + 1 if k < 0 else k - 1
			if k != 0:
				var beside := _cell_at(x, y, dir, d, inner)
				if _is_open_at(grid, beside):
					faces.append({"type": "side", "d": d, "k": k, "wall": here, "from": beside})
			if d > 0:
				var before := _cell_at(x, y, dir, d - 1, k)
				if _is_open_at(grid, before):
					faces.append({"type": "front", "d": d, "k": k, "wall": here, "from": before})
	return faces


## Floor cells you can actually see from here (for the automap): a ray from the eye must reach some
## part of the cell through open floor only, and the cell must be inside the view.
static func visible_cells(map: Dictionary, x: int, y: int, dir: int) -> Array:
	var grid: Array = map["grid"]
	var out := []
	for d in range(0, VIEW + 1):
		for k in range(-REACH, REACH + 1):
			var c := _cell_at(x, y, dir, d, k)
			if not _is_open_at(grid, c):
				continue
			if d == 0 and k == 0:
				out.append(c)
				continue
			var samples := [[k, d + 0.5], [k - 0.4, d + 0.1], [k + 0.4, d + 0.1], [k - 0.4, d + 0.9], [k + 0.4, d + 0.9]]
			for s in samples:
				if _sees(grid, x, y, dir, s[0], s[1]):
					out.append(c)
					break
	return out


static func _sees(grid: Array, x: int, y: int, dir: int, tx: float, tz: float) -> bool:
	if absf(tx) > (0.5 * (EYE + tz)) / EYE:
		return false # off the side of the screen
	var steps := ceili(tz / 0.08)
	for i in steps:
		var z := (tz * i) / steps
		var X := (tx * (EYE + z)) / (EYE + tz)
		if not _is_open_at(grid, _cell_at(x, y, dir, floori(z), J.round_js(X))):
			return false
	return true


## A face's (u, v) -> screen mapper, perspective-correct: u runs left to right as you see the face,
## v from its top (0) to its bottom (1). A Callable: `P.call(u, v) -> Vector2`.
static func face_mapper(W: float, H: float, face: Dictionary) -> Callable:
	var d: int = face["d"]
	var k: int = face["k"]
	if face["type"] == "front":
		return func(u: float, v: float) -> Vector2: return project(W, H, k - 0.5 + u, d, v - 0.5)
	var X: float = k + 0.5 if k < 0 else k - 0.5
	# A wall on your left reads near-to-far left to right; one on your right, far-to-near
	if k < 0:
		return func(u: float, v: float) -> Vector2: return project(W, H, X, d + u, v - 0.5)
	return func(u: float, v: float) -> Vector2: return project(W, H, X, d + 1.0 - u, v - 0.5)


# Lines fade with distance, like torchlight that doesn't reach far
static func _fog(z: float) -> float:
	return maxf(0.15, minf(1.0, 1.15 - z * 0.16))


static func _alpha(hex: String, a: float) -> String:
	return hex + ("%02x" % J.round_js(a * 255.0))


# The path of a polygon given as points, on the context (closed)
static func _trace(ctx, pts: Array) -> void:
	ctx.begin_path()
	for i in pts.size():
		var p: Vector2 = pts[i]
		if i:
			ctx.line_to(p.x, p.y)
		else:
			ctx.move_to(p.x, p.y)
	ctx.close_path()


static func _outline(P: Callable) -> Array:
	return [P.call(0, 0), P.call(1, 0), P.call(1, 1), P.call(0, 1)]


# Fills the face black over what is behind it, then draws its edges
static func _paint_face(ctx, pts: Array, face: Dictionary, palette: Dictionary) -> void:
	_trace(ctx, pts)
	ctx.fill_style = "#000"
	ctx.fill()
	if face["type"] == "front":
		ctx.stroke_style = _alpha(palette.wall, _fog(face["d"]))
	else:
		# A side wall spans a whole cell of depth, so its lines fade along it
		var left: bool = face["k"] < 0
		var zl: float = face["d"] if left else face["d"] + 1.0
		var zr: float = face["d"] + 1.0 if left else face["d"]
		var g = ctx.create_linear_gradient(pts[0].x, 0, pts[1].x, 0)
		g.add_color_stop(0, _alpha(palette.wall, _fog(zl)))
		g.add_color_stop(1, _alpha(palette.wall, _fog(zr)))
		ctx.stroke_style = g
	ctx.line_width = 1.5 if face["d"] >= 3 else 2.0
	ctx.stroke()


# Stairs down: a hole in the floor, steps dropping away inside it.
static func _paint_stairs(ctx, W: float, H: float, face: Dictionary, palette: Dictionary) -> void:
	var d: int = face["d"]
	var k: int = face["k"]
	var x0 := k - 0.38
	var x1 := k + 0.38
	var z0 := d + 0.08
	var z1 := d + 0.92
	var rim := [project(W, H, x0, z0, 0.5), project(W, H, x1, z0, 0.5), project(W, H, x1, z1, 0.5), project(W, H, x0, z1, 0.5)]
	ctx.save()
	ctx.stroke_style = _alpha(palette.wall, _fog(d + 0.5))
	ctx.line_width = 1.0 if d >= 3 else 1.5
	_trace(ctx, rim)
	ctx.fill_style = "#000"
	ctx.fill()
	ctx.stroke()
	ctx.clip()
	# Each step a little lower and a little narrower than the one before, so the hole reads as going down.
	# Steps in the accent color: from the floor at a grazing angle the hole is thin, and it has to stand out.
	ctx.stroke_style = _alpha(palette.accent, _fog(d + 0.5))
	for i in range(1, 5):
		var z := z1 - (i / 5.0) * (z1 - z0)
		var inset := i * 0.02
		var a := project(W, H, x0 + inset, z, 0.5 + i * 0.012)
		var b := project(W, H, x1 - inset, z, 0.5 + i * 0.012)
		_line(ctx, a.x, a.y, b.x, b.y)
	ctx.restore()


# A decoration, if this wall face (wall cell seen from floor cell) has one: {kind, seed} or null
static func _decor_for(map: Dictionary, wall: Array, from: Array) -> Variant:
	var map_seed = J.nz(map.get("seed"), 0)
	var r := _hash([wall[0], wall[1], from[0], from[1], map_seed])
	if r < 0.32:
		return {"kind": DECOR[floori(_hash([wall[1], wall[0], map_seed, 7]) * DECOR.size())], "seed": r}
	return null


# The corridor only changes when you move or turn; in between only torch flames move, and they flicker at
# FLAME_FPS. The JS caches the painted view per flame frame in an offscreen layer; here every frame repaints, and
# this stays as the key a cache would use (and the flame quantisation below).
const FLAME_FPS = 24

# What you see from a spot is worked out once: the cache holds the last map and position
static var _cache_map = null
static var _cache_pos := ""
static var _cache_view := {}


## The layer's cache key at time t: where you stand, and the flame frame only if a flame is in sight
static func layer_key(pos: String, torches: bool, t: float) -> String:
	return "%s|%s" % [pos, str(floori(t * FLAME_FPS / 1000.0)) if torches else "-"]


## What you see from (x, y) facing dir, worked out once per position: faces in painting order, their
## decorations, whether a torch is among them, and the floor cells in view (for the automap).
static func corridor_view(map: Dictionary, x: int, y: int, dir: int) -> Dictionary:
	var faces := corridor_faces(map, x, y, dir)
	var decor := []
	var torches := false
	for f in faces:
		if f["type"] == "stairs":
			decor.append(null)
			continue
		var dec = _decor_for(map, f["wall"], f["from"])
		decor.append(dec)
		if dec != null and dec["kind"] == "torch":
			torches = true
	return {"faces": faces, "decor": decor, "torches": torches, "cells": visible_cells(map, x, y, dir)}


static func _paint_corridor(ctx, map: Dictionary, view: Dictionary, t: float) -> void:
	var W: float = ctx.size.x
	var H: float = ctx.size.y
	var palette: Dictionary = J.nz(map.get("palette"), PALETTES[0])
	clear(ctx)
	ctx.save()
	ctx.begin_path()
	ctx.rect(4, 4, W - 8, H - 8)
	ctx.clip()
	var faces: Array = view["faces"]
	var decor: Array = view["decor"]
	for i in faces.size():
		var face: Dictionary = faces[i]
		if face["type"] == "stairs":
			_paint_stairs(ctx, W, H, face, palette)
			continue
		var P := face_mapper(W, H, face)
		var pts := _outline(P)
		_paint_face(ctx, pts, face, palette)
		var dec = decor[i]
		if dec == null:
			continue
		# Decorations go on with their wall, so nearer walls still cover them, and stay inside it (a torch's glow
		# must not leak around the corner of the wall that hides it)
		ctx.save()
		_trace(ctx, pts)
		ctx.clip()
		ctx.stroke_style = palette.wall
		ctx.global_alpha = _fog(face["d"] + (0.5 if face["type"] == "side" else 0.0))
		ctx.line_width = 1.0 if face["d"] >= 2 else 1.5
		_decorate(ctx, P, dec["kind"], t, palette, dec["seed"])
		ctx.restore()
	ctx.restore()
	# The clip above only cuts a line's centerline, so a stroke along the edge of the view sticks out by half its
	# width: black the 4px border out again, as the pixel clip of a browser canvas would have
	ctx.fill_style = "#000"
	ctx.fill_rect(0, 0, W, 4)
	ctx.fill_rect(0, H - 4, W, 4)
	ctx.fill_rect(0, 4, 4, H - 8)
	ctx.fill_rect(W - 4, 4, 4, H - 8)
	ctx.stroke_style = palette.wall
	ctx.line_width = 2
	ctx.stroke_rect(4.5, 4.5, W - 8, H - 8)


## Draws the view from (x,y) facing dir. Returns the floor cells you can see (for the automap), as [x, y] pairs.
## `t` (ms) animates torch flames.
static func draw_corridor(ctx, map: Dictionary, x: int, y: int, dir: int, t := 0.0) -> Array:
	var pos := "%d,%d,%d,%dx%d" % [x, y, dir, int(ctx.size.x), int(ctx.size.y)]
	if not is_same(_cache_map, map) or _cache_pos != pos:
		_cache_view = corridor_view(map, x, y, dir)
		_cache_map = map
		_cache_pos = pos
	var flame_t := floorf(t * FLAME_FPS / 1000.0) * 1000.0 / FLAME_FPS
	_paint_corridor(ctx, map, _cache_view, flame_t)
	return _cache_view["cells"]


## The walls you have seen, as edges of seen floor cells: [x, y, side] with side 0..3 = N E S W.
## In the view walls are faces with no thickness, so the map draws them as lines, not as blocks
## (a block would look the same as unexplored dark).
static func wall_edges(map: Dictionary, seen) -> Array:
	var grid: Array = map["grid"]
	var w: int = grid[0].size()
	var edges := []
	for key in seen:
		var k := int(key)
		var cx := k % w
		var cy := floori(float(k) / w)
		for side in 4:
			var dxy: Array = DIRS[side]
			if not _is_open(grid, cx + dxy[0], cy + dxy[1]):
				edges.append([cx, cy, side])
	return edges


static func draw_map(ctx, map: Dictionary, seen, visited, x: int, y: int, dir: int) -> void:
	var grid: Array = map["grid"]
	var n := grid.size()
	var s := floori(ctx.size.x / n)
	clear(ctx)
	for cy in n:
		for cx in n:
			var k := cy * n + cx
			if not seen.has(k):
				continue
			ctx.fill_style = "#5a5a5a" if visited.has(k) else "#262626"
			ctx.fill_rect(cx * s, cy * s, s, s)
	# Walls: a bright line along each side of seen floor that faces one, in the floor's wall color
	var palette: Dictionary = J.nz(map.get("palette"), PALETTES[0])
	ctx.fill_style = palette.wall
	for e in wall_edges(map, seen):
		var ex: int = e[0] * s
		var ey: int = e[1] * s
		match e[2]:
			0:
				ctx.fill_rect(ex, ey, s, 1)
			1:
				ctx.fill_rect(ex + s - 1, ey, 1, s)
			2:
				ctx.fill_rect(ex, ey + s - 1, s, 1)
			_:
				ctx.fill_rect(ex, ey, 1, s)
	var stairs: Dictionary = map["stairs"]
	var sk: int = int(stairs["y"]) * n + int(stairs["x"])
	if seen.has(sk):
		ctx.fill_style = INK
		ctx.fill_rect(stairs["x"] * s + 1, stairs["y"] * s + 1, s - 2, s - 2)
		ctx.fill_style = "#000"
		ctx.fill_rect(stairs["x"] * s + 2, stairs["y"] * s + 2, s - 4, s - 4)
	# The floor's red champion, marked from the start so you can choose to hunt it
	var boss = map.get("boss")
	if boss != null and not J.truthy(boss.get("defeated", false)):
		ctx.fill_style = "#ff2a2a"
		ctx.fill_rect(boss["x"] * s, boss["y"] * s, s, s)
	# You: a small arrow
	var px := x * s + s / 2.0
	var py := y * s + s / 2.0
	var dxy: Array = DIRS[dir]
	var dx: float = dxy[0]
	var dy: float = dxy[1]
	ctx.fill_style = "#fff"
	ctx.begin_path()
	ctx.move_to(px + dx * s * 0.6, py + dy * s * 0.6)
	ctx.line_to(px - dx * s * 0.4 - dy * s * 0.4, py - dy * s * 0.4 + dx * s * 0.4)
	ctx.line_to(px - dx * s * 0.4 + dy * s * 0.4, py - dy * s * 0.4 - dx * s * 0.4)
	ctx.close_path()
	ctx.fill()


static func draw_title(ctx, t: float, prompt := "PRESS ANY KEY") -> void:
	var W: float = ctx.size.x
	var H: float = ctx.size.y
	clear(ctx)
	ctx.stroke_style = INK
	ctx.line_width = 2
	# A receding corridor behind the title
	for d in 5:
		var f := _frame(W, H, d)
		ctx.stroke_rect(f.l + 0.5, f.t + 0.5, f.r - f.l, f.b - f.t)
	ctx.fill_style = "#000"
	ctx.fill_rect(W * 0.12, H * 0.3, W * 0.76, H * 0.42)
	ctx.stroke_rect(W * 0.12 + 0.5, H * 0.3 + 0.5, W * 0.76, H * 0.42)
	ctx.fill_style = INK
	ctx.text_align = "center"
	ctx.font = "28px \"Press Start 2P\", monospace"
	ctx.fill_text("DONJON", W / 2.0, H * 0.45)
	ctx.font = "9px \"Press Start 2P\", monospace"
	if floori(t / 600.0) % 2 == 0:
		ctx.fill_text(prompt, W / 2.0, H * 0.65)
	ctx.text_align = "left"
