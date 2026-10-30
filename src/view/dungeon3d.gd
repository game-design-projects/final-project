## The floor as a 3D set, for the cel-shaded view (Stage3D): walls, floor and ceiling from the map's grid, the
## stairs down as a stairwell cut into the floor, and the same wall decorations the wireframe view drew (torches,
## chains, banners, cracks, barred windows, skull niches), placed by Render's hash so a wall looks the same in both.
## Pure: `build(map)` returns meshes and the torches' positions, no nodes, so it can be tested without a window.
##
## World coordinates: one cell is CELL units wide, cell (x, y) is centered on ((x + 0.5) * CELL, 0, (y + 0.5) *
## CELL), so map +x is world +X and map +y (south) is world +Z; the floor is at Y = 0 and the ceiling at WALL_H.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Render = preload("res://src/view/render.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")

const CELL := 2.0
const WALL_H := 2.2
## How dark a wall's edge is inked where the wall runs on into the next cell (1 at a real corner)
const SEAM_INK := 0.3
## The stairwell: the hole's half width (in cells, as the wireframe drew it) and how deep it goes
const STAIRS_HALF := 0.38
const STAIRS_DEPTH := 1.5
const STAIRS_STEPS := 5
const STAIRS_DROP := 0.2 # each step down

const METAL := "#6f7280"
const WOOD := "#7a5234"
const BONE := "#e6dcc2"
const HOLLOW := "#07060b" # the dark inside a window, a niche, a crack


static func cell_center(x: float, y: float) -> Vector3:
	return Vector3((x + 0.5) * CELL, 0.0, (y + 0.5) * CELL)


## A map direction (0..3 = N E S W) as a world vector
static func dir_vec(d: int) -> Vector3:
	var v: Array = Render.DIRS[posmod(d, 4)]
	return Vector3(v[0], 0, v[1])


static func _open(grid: Array, x: int, y: int) -> bool:
	return Render._is_open(grid, x, y)


## How dark the ink is on one side edge of the wall face that floor cell (x, y) sees in direction s: `side` -1 is
## the face's left edge as you face it, 1 its right. Faint where the wall carries straight on, full at a corner.
static func edge_ink(grid: Array, x: int, y: int, s: int, side: int) -> float:
	var along: Array = Render.DIRS[posmod(s + side, 4)]
	var ahead: Array = Render.DIRS[s]
	var nx: int = x + along[0]
	var ny: int = y + along[1]
	if _open(grid, nx, ny) and not _open(grid, nx + ahead[0], ny + ahead[1]):
		return SEAM_INK
	return 1.0


## Every wall face: the floor cell it is seen from, the direction it faces away from that cell, and the wall cell.
## In grid order (row by row, then N E S W), which keeps the meshes the same from one build to the next.
static func wall_faces(map: Dictionary) -> Array:
	var grid: Array = map["grid"]
	var out := []
	for y in grid.size():
		for x in grid[y].size():
			if grid[y][x] != 1:
				continue
			for s in 4:
				var d: Array = Render.DIRS[s]
				if not _open(grid, x + d[0], y + d[1]):
					out.append({"from": [x, y], "s": s, "wall": [x + d[0], y + d[1]]})
	return out


## The face's corners in the world: top left, top right, bottom right, bottom left as you face it
static func face_corners(face: Dictionary) -> Array:
	var c := cell_center(face["from"][0], face["from"][1])
	var f := dir_vec(face["s"])
	var r := dir_vec(face["s"] + 1)
	var mid := c + f * (CELL / 2.0)
	var up := Vector3(0, WALL_H, 0)
	return [mid - r * (CELL / 2.0) + up, mid + r * (CELL / 2.0) + up, mid + r * (CELL / 2.0), mid - r * (CELL / 2.0)]


## A frame on a wall face at (u, v) (the wireframe's face coordinates: u across as you face it, v from the top
## down): +X along the wall, +Y up, +Z out of the wall into the corridor
static func face_frame(face: Dictionary, u: float, v: float, out := 0.0) -> Transform3D:
	var corners := face_corners(face)
	var r := dir_vec(face["s"] + 1)
	var back := -dir_vec(face["s"])
	var p: Vector3 = corners[0] + r * (CELL * u) + Vector3(0, -WALL_H * v, 0) + back * out
	return Transform3D(Basis(r, Vector3.UP, back), p)


## {walls, floor, ceiling, props, flames: ArrayMesh or null, torches: [{pos: Vector3, seed}], faces: count}
static func build(map: Dictionary) -> Dictionary:
	var grid: Array = map["grid"]
	var stairs: Dictionary = map.get("stairs", {"x": -1, "y": -1})
	var palette: Dictionary = J.nz(map.get("palette"), Render.PALETTES[0])
	var walls := MeshKit.Builder.new()
	var floor_b := MeshKit.Builder.new()
	var ceil_b := MeshKit.Builder.new()
	var props := MeshKit.Builder.new()
	var flames := MeshKit.Builder.new()
	var torches := []
	var faces := wall_faces(map)
	for face in faces:
		var fx: int = face["from"][0]
		var fy: int = face["from"][1]
		var c := face_corners(face)
		var seed := Render._hash([face["wall"][0], face["wall"][1], fx, fy, 3])
		var ink := Vector2(edge_ink(grid, fx, fy, face["s"], -1), edge_ink(grid, fx, fy, face["s"], 1))
		walls.quad(c[0], c[1], c[2], c[3], Color(seed, 0, 0, 1), ink)
		var dec = Render._decor_for(map, face["wall"], face["from"])
		if dec != null:
			_decorate(props, flames, torches, face, dec["kind"], dec["seed"], palette)
	for y in grid.size():
		for x in grid[y].size():
			if grid[y][x] != 1:
				continue
			var x0: float = x * CELL
			var z0: float = y * CELL
			var cell := Vector2(x, y)
			if int(stairs.get("x", -1)) == x and int(stairs.get("y", -1)) == y:
				_stairwell(floor_b, props, x, y, palette)
			else:
				floor_b.quad(Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0), Vector3(x0 + CELL, 0, z0 + CELL), Vector3(x0, 0, z0 + CELL), Color(1, 0, 0, 1), cell)
			ceil_b.quad(Vector3(x0, WALL_H, z0), Vector3(x0, WALL_H, z0 + CELL), Vector3(x0 + CELL, WALL_H, z0 + CELL), Vector3(x0 + CELL, WALL_H, z0), Color(1, 0, 0, 1), cell,
				[Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
	return {
		"walls": walls.commit(),
		"floor": floor_b.commit(),
		"ceiling": ceil_b.commit(),
		"props": props.commit(),
		"flames": flames.commit(),
		"torches": torches,
		"faces": faces.size(),
	}


# ---------------------------------------------------------------- the stairs down

## The stairs' cell: the floor around a square hole, the hole's walls, steps going down into the dark (in the
## floor's accent color, so the hole stands out the way the wireframe's accent steps did) and a lit rim.
static func _stairwell(floor_b, props, x: int, y: int, palette: Dictionary) -> void:
	var x0 := x * CELL
	var z0 := y * CELL
	var hw := STAIRS_HALF * CELL
	var c := cell_center(x, y)
	var hx0 := c.x - hw
	var hx1 := c.x + hw
	var hz0 := c.z - hw
	var hz1 := c.z + hw
	var cell := Vector2(x, y)
	var uv := func(px: float, pz: float) -> Vector2: return Vector2((px - x0) / CELL, (pz - z0) / CELL)
	# The floor around the hole: four strips, their stones lined up with the rest of the floor
	for r in [[x0, z0, x0 + CELL, hz0], [x0, hz1, x0 + CELL, z0 + CELL], [x0, hz0, hx0, hz1], [hx1, hz0, x0 + CELL, hz1]]:
		floor_b.quad(Vector3(r[0], 0, r[1]), Vector3(r[2], 0, r[1]), Vector3(r[2], 0, r[3]), Vector3(r[0], 0, r[3]), Color(1, 0, 0, 1), cell,
			[uv.call(r[0], r[1]), uv.call(r[2], r[1]), uv.call(r[2], r[3]), uv.call(r[0], r[3])])
	var dark := MeshKit.lin("#1a1820")
	var depth := STAIRS_DEPTH
	# The hole's four walls, facing in
	props.quad(Vector3(hx0, 0, hz0), Vector3(hx1, 0, hz0), Vector3(hx1, -depth, hz0), Vector3(hx0, -depth, hz0), dark) # north, faces south
	props.quad(Vector3(hx1, 0, hz1), Vector3(hx0, 0, hz1), Vector3(hx0, -depth, hz1), Vector3(hx1, -depth, hz1), dark)
	props.quad(Vector3(hx0, 0, hz1), Vector3(hx0, 0, hz0), Vector3(hx0, -depth, hz0), Vector3(hx0, -depth, hz1), dark)
	props.quad(Vector3(hx1, 0, hz0), Vector3(hx1, 0, hz1), Vector3(hx1, -depth, hz1), Vector3(hx1, -depth, hz0), dark)
	props.quad(Vector3(hx0, -depth, hz0), Vector3(hx1, -depth, hz0), Vector3(hx1, -depth, hz1), Vector3(hx0, -depth, hz1), MeshKit.lin(HOLLOW, true))
	# Steps going down all round, a square funnel narrowing into the dark: from whichever side you come up to it, the
	# far side's steps face you. Each ring is a frame of four boxes, lower and darker than the one outside it.
	var accent := MeshKit.lin(palette.accent)
	var w := hw / (STAIRS_STEPS + 1)
	for i in STAIRS_STEPS:
		var top := -(i + 1) * STAIRS_DROP
		var o := hw - i * w
		var n := o - w
		var h := depth + top
		var yc := (top - depth) / 2.0
		var col := MeshKit.shade(accent, 0.95 - 0.16 * i)
		props.box(Transform3D(Basis(), Vector3(c.x, yc, c.z - (o + n) / 2.0)), Vector3(2.0 * o, h, w), col) # north
		props.box(Transform3D(Basis(), Vector3(c.x, yc, c.z + (o + n) / 2.0)), Vector3(2.0 * o, h, w), col) # south
		props.box(Transform3D(Basis(), Vector3(c.x - (o + n) / 2.0, yc, c.z)), Vector3(w, h, 2.0 * n), col) # west
		props.box(Transform3D(Basis(), Vector3(c.x + (o + n) / 2.0, yc, c.z)), Vector3(w, h, 2.0 * n), col) # east
	# The rim, lit in the accent color
	var rim := MeshKit.lin(palette.accent, true)
	var rw := 0.05
	for r in [[hx0 - rw, hz0 - rw, hx1 + rw, hz0], [hx0 - rw, hz1, hx1 + rw, hz1 + rw], [hx0 - rw, hz0, hx0, hz1], [hx1, hz0, hx1 + rw, hz1]]:
		props.quad(Vector3(r[0], 0.006, r[1]), Vector3(r[2], 0.006, r[1]), Vector3(r[2], 0.006, r[3]), Vector3(r[0], 0.006, r[3]), rim)


# ---------------------------------------------------------------- wall decorations

# A strip along a polyline given in face coordinates, flat on the wall (cracks, a niche's edge)
static func _strip(props, face: Dictionary, pts: Array, width: float, col: Color, out := 0.004) -> void:
	for i in range(pts.size() - 1):
		var a := face_frame(face, pts[i][0], pts[i][1], out).origin
		var b := face_frame(face, pts[i + 1][0], pts[i + 1][1], out).origin
		var along := (b - a).normalized()
		var n := face_frame(face, 0, 0).basis.z
		var side := n.cross(along) * (width / 2.0)
		props.quad(a + side, b + side, b - side, a - side, col)


# A flat polygon on the wall (a fan from its first point), for the dark inside of a window or a niche
static func _patch(props, face: Dictionary, pts: Array, col: Color, out := 0.003) -> void:
	var p := []
	for q in pts:
		p.append(face_frame(face, q[0], q[1], out).origin)
	for i in range(1, p.size() - 1):
		props.tri(p[0], p[i], p[i + 1], col)


static func _decorate(props, flames, torches: Array, face: Dictionary, kind: String, rseed: float, palette: Dictionary) -> void:
	var metal := MeshKit.lin(METAL)
	var hollow := MeshKit.lin(HOLLOW, true)
	match kind:
		"torch":
			var f := face_frame(face, 0.5, 0.58)
			props.box(f * Transform3D(Basis(), Vector3(0, 0.02, 0.01)), Vector3(0.12, 0.16, 0.03), metal) # plate
			props.limb(f * Vector3(0, 0, 0.02), f * Vector3(0, 0.27, 0.15), 0.028, 0.038, MeshKit.lin(WOOD), 8) # handle
			props.cylinder(f * Transform3D(Basis(), Vector3(0, 0.26, 0.15)), 0.05, 0.075, 0.07, metal, 10) # cup
			var foot := f * Vector3(0, 0.32, 0.15)
			var col := Color(1, 1, 1, 1)
			var s := Vector2(rseed, 0)
			var i0: int = flames.vertex(foot, Vector3.UP, col, Vector2(-1, 0), s)
			var i1: int = flames.vertex(foot, Vector3.UP, col, Vector2(-1, 1), s)
			var i2: int = flames.vertex(foot, Vector3.UP, col, Vector2(1, 1), s)
			var i3: int = flames.vertex(foot, Vector3.UP, col, Vector2(1, 0), s)
			flames.tri_idx(i0, i1, i2)
			flames.tri_idx(i0, i2, i3)
			torches.append({"pos": f * Vector3(0, 0.45, 0.3), "seed": rseed})
		"chains":
			for pair in [[0.38, 0.5], [0.6, 0.36]]:
				var u: float = pair[0]
				var length: float = pair[1]
				var v := 0.0
				var i := 0
				while v < length:
					var f := face_frame(face, u, v + 0.04, 0.05)
					# Links alternate: one seen face on, the next edge on
					var b := Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1, 1, 1.5)) if i % 2 == 0 else Basis(Vector3.FORWARD, PI / 2.0) * Basis.from_scale(Vector3(1.5, 1, 1))
					props.torus(f * Transform3D(b, Vector3.ZERO), 0.03, 0.055, metal, Vector2.ZERO, 8, 4)
					v += 0.06
					i += 1
				var hook := face_frame(face, u, length + 0.04, 0.05)
				props.limb(hook * Vector3(0, 0.02, 0), hook * Vector3(0.05, -0.1, 0.02), 0.014, 0.01, metal, 6)
				props.limb(hook * Vector3(0, 0.02, 0), hook * Vector3(-0.05, -0.1, 0.02), 0.014, 0.01, metal, 6)
		"banner":
			var cloth := MeshKit.shade(MeshKit.lin(palette.accent), 0.5)
			var rod := face_frame(face, 0.5, 0.06, 0.08)
			props.limb(rod * Vector3(-0.42, 0, 0), rod * Vector3(0.42, 0, 0), 0.022, 0.022, MeshKit.lin(WOOD), 8)
			for e in [-0.44, 0.44]:
				props.sphere(rod * Transform3D(Basis(), Vector3(e, 0, 0)), Vector3.ONE * 0.04, metal, 8, 4)
			var top := face_frame(face, 0.5, 0.06, 0.06)
			var h := 0.5 * WALL_H
			props.box(top * Transform3D(Basis(), Vector3(0, -h / 2.0, 0)), Vector3(0.64, h, 0.025), cloth)
			# The tails of the notched hem
			for e in [-0.24, 0.0, 0.24]:
				var tip := top * Vector3(e, -h - 0.12, 0.0)
				props.tri(top * Vector3(e - 0.08, -h, 0.014), top * Vector3(e + 0.08, -h, 0.014), tip, cloth)
			var emblem := MeshKit.lin("#e8c060")
			var mark := face_frame(face, 0.5, 0.26, 0.085)
			props.torus(mark * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO), 0.1, 0.14, emblem)
			props.box(mark, Vector3(0.03, 0.34, 0.02), emblem)
		"crack":
			_strip(props, face, [[0.3, 0.18], [0.38, 0.34], [0.34, 0.46], [0.46, 0.6], [0.42, 0.72], [0.52, 0.86]], 0.035, hollow)
			_strip(props, face, [[0.38, 0.34], [0.48, 0.38]], 0.025, hollow)
			_strip(props, face, [[0.46, 0.6], [0.58, 0.62]], 0.025, hollow)
		"window":
			_patch(props, face, [[0.36, 0.24], [0.64, 0.24], [0.64, 0.46], [0.36, 0.46]], hollow)
			var stone := MeshKit.shade(MeshKit.lin(palette.wall), 0.55)
			var mid := face_frame(face, 0.5, 0.35, 0.03)
			var w := 0.28 * CELL
			var hh := 0.11 * WALL_H
			props.box(mid * Transform3D(Basis(), Vector3(0, hh + 0.035, 0)), Vector3(w * 2.0 + 0.14, 0.07, 0.07), stone)
			props.box(mid * Transform3D(Basis(), Vector3(0, -hh - 0.04, 0.02)), Vector3(w * 2.0 + 0.2, 0.08, 0.11), stone) # sill
			props.box(mid * Transform3D(Basis(), Vector3(-w - 0.035, 0, 0)), Vector3(0.07, hh * 2.0, 0.07), stone)
			props.box(mid * Transform3D(Basis(), Vector3(w + 0.035, 0, 0)), Vector3(0.07, hh * 2.0, 0.07), stone)
			for u in [0.43, 0.5, 0.57]:
				var bar := face_frame(face, u, 0.46, 0.02)
				props.cylinder(bar, 0.016, 0.016, hh * 2.0, metal, 6)
		"niche":
			var arch := [[0.36, 0.78], [0.36, 0.58], [0.42, 0.5], [0.5, 0.47], [0.58, 0.5], [0.64, 0.58], [0.64, 0.78]]
			_patch(props, face, [[0.5, 0.64]] + arch + [[0.36, 0.78]], hollow)
			_strip(props, face, arch, 0.05, MeshKit.shade(MeshKit.lin(palette.wall), 0.6), 0.008)
			var ledge := face_frame(face, 0.5, 0.78, 0.06)
			props.box(ledge, Vector3(0.62, 0.05, 0.14), MeshKit.shade(MeshKit.lin(palette.wall), 0.6))
			var bone := MeshKit.lin(BONE)
			var skull := face_frame(face, 0.5, 0.66, 0.1)
			props.sphere(skull, Vector3(0.1, 0.095, 0.1), bone, 12, 6)
			props.box(skull * Transform3D(Basis(), Vector3(0, -0.085, 0.02)), Vector3(0.1, 0.05, 0.08), bone) # jaw
			for e in [-0.04, 0.04]:
				props.sphere(skull * Transform3D(Basis(), Vector3(e, 0.0, 0.082)), Vector3(0.026, 0.03, 0.02), hollow, 8, 4)
			props.sphere(skull * Transform3D(Basis(), Vector3(0, -0.04, 0.092)), Vector3(0.012, 0.016, 0.01), hollow, 6, 3)
