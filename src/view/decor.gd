## Things hung on the walls: torches, chains, banners, cracks, barred windows, skull niches. Which wall gets which is decided
## by a hash of its place and the floor's seed, so a wall is always decorated the same way. They are real shapes standing off
## the wall (mesh_kit.gd), black and outlined in the wall colour, dimming with distance like the walls' lines; a crack or an
## arch's edge is a strip drawn solid on the wall. Torch flames are a shader (shaders/flame.gdshader) in the accent colour, and
## each torch lights the wall round it (shaders/wire.gdshader). A cracked wall always shows a fissure, in the accent colour: it can be
## breakable only if it can be told apart from the cracks that are only cracks.
extends RefCounted

const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Materials = preload("res://src/view/materials.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")

const KINDS := ["torch", "torch", "chains", "banner", "crack", "window", "niche"]
const SHARE := 0.32 # about this share of wall faces carry something
const LIFT := 0.006 # flat strips sit this far off the wall so they don't flicker into it

## Which walls carry what: [{"cell": Vector2i, "side": int, "kind": String, "roll": float}], the same every time for a floor.
static func placements(floor_map) -> Array:
	var out := []
	for y in floor_map.size:
		for x in floor_map.size:
			var c := Vector2i(x, y)
			if not floor_map.is_open(c):
				continue
			for side in 4:
				if floor_map.is_open(c + FloorMap.DIRS[side]):
					continue
				if floor_map.is_cracked(c + FloorMap.DIRS[side]):
					out.append({"cell": c, "side": side, "kind": "fissure", "roll": 0.0})
					continue
				var roll := _hash(x, y, side, floor_map.seed_value)
				if roll[0] <= SHARE:
					out.append({"cell": c, "side": side, "kind": KINDS[int(roll[1] * KINDS.size()) % KINDS.size()], "roll": roll[0]})
	return out


## A node holding the decorations of `floor_map`: one mesh of shapes, one of flames. `torches` (an Array) gets
## {"pos": Vector3, "seed": float} per torch, for the caller to light the walls with.
static func build(floor_map, wall_color: Color, accent: Color, torches: Array) -> Node3D:
	var root := Node3D.new()
	var props := MeshKit.Builder.new()
	var flames := MeshKit.Builder.new()
	var half := Materials.CELL / 2.0
	for p in placements(floor_map):
		var face := _Face.new(DungeonMesh.center(p.cell), p.side, half)
		match p.kind:
			"torch":
				_torch(props, flames, torches, face, p.roll, wall_color)
			"chains":
				_chains(props, face, wall_color)
			"banner":
				_banner(props, face, wall_color)
			"crack":
				_crack(props, face, wall_color)
			"window":
				_window(props, face, wall_color)
			"niche":
				_niche(props, face, wall_color)
			"fissure":
				_fissure(props, face, accent)
	if not props.is_empty():
		var shapes := MeshInstance3D.new()
		shapes.name = "Props"
		shapes.mesh = props.commit()
		shapes.material_override = Materials.prop()
		shapes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(shapes)
	if not flames.is_empty():
		var fire := MeshInstance3D.new()
		fire.name = "Flames"
		fire.mesh = flames.commit()
		fire.material_override = Materials.flame(accent)
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.extra_cull_margin = 1.0 # the shader raises the quads off the point their vertices sit at
		root.add_child(fire)
	print_verbose("decor: %d triangles, %d torches" % [props.triangles(), torches.size()])
	return root


static func _torch(props: MeshKit.Builder, flames: MeshKit.Builder, torches: Array, face: _Face, roll: float, color: Color) -> void:
	var ink := MeshKit.color(color)
	var f := face.frame(0.5, 0.58)
	props.box(f * Transform3D(Basis(), Vector3(0, 0.02, 0.01)), Vector3(0.12, 0.16, 0.03), ink) # plate
	props.limb(f * Vector3(0, 0, 0.02), f * Vector3(0, 0.27, 0.15), 0.028, 0.038, ink, 8) # handle
	props.cylinder(f * Transform3D(Basis(), Vector3(0, 0.26, 0.15)), 0.05, 0.075, 0.07, ink, 10) # cup
	# the flame's quad: every corner at its foot, the UVs say which corner it is (shaders/flame.gdshader)
	var foot := f * Vector3(0, 0.32, 0.15)
	var seed_uv := Vector2(roll, 0)
	var i0 := flames.vertex(foot, Vector3.UP, Color.WHITE, Vector2(-1, 0), seed_uv)
	var i1 := flames.vertex(foot, Vector3.UP, Color.WHITE, Vector2(-1, 1), seed_uv)
	var i2 := flames.vertex(foot, Vector3.UP, Color.WHITE, Vector2(1, 1), seed_uv)
	var i3 := flames.vertex(foot, Vector3.UP, Color.WHITE, Vector2(1, 0), seed_uv)
	flames.tri_idx(i0, i1, i2)
	flames.tri_idx(i0, i2, i3)
	torches.append({"pos": f * Vector3(0, 0.45, 0.3), "seed": roll})


## Two chains hanging from the top, link by link (one seen face on, the next edge on), each ending in a hook.
static func _chains(props: MeshKit.Builder, face: _Face, color: Color) -> void:
	var ink := MeshKit.color(color)
	for pair in [[0.38, 0.5], [0.6, 0.36]]:
		var u: float = pair[0]
		var length: float = pair[1]
		var v := 0.0
		var i := 0
		while v < length:
			var f := face.frame(u, v + 0.04, 0.05)
			var b := Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1, 1, 1.5)) if i % 2 == 0 else Basis(Vector3.FORWARD, PI / 2.0) * Basis.from_scale(Vector3(1.5, 1, 1))
			props.torus(f * Transform3D(b, Vector3.ZERO), 0.03, 0.055, ink, 8, 4)
			v += 0.06
			i += 1
		var hook := face.frame(u, length + 0.04, 0.05)
		props.limb(hook * Vector3(0, 0.02, 0), hook * Vector3(0.05, -0.1, 0.02), 0.014, 0.01, ink, 6)
		props.limb(hook * Vector3(0, 0.02, 0), hook * Vector3(-0.05, -0.1, 0.02), 0.014, 0.01, ink, 6)


## A cloth on a rod, with a notched hem and a mark on it.
static func _banner(props: MeshKit.Builder, face: _Face, color: Color) -> void:
	var ink := MeshKit.color(color)
	var rod := face.frame(0.5, 0.06, 0.08)
	props.limb(rod * Vector3(-0.42, 0, 0), rod * Vector3(0.42, 0, 0), 0.022, 0.022, ink, 8)
	for e in [-0.44, 0.44]:
		props.sphere(rod * Transform3D(Basis(), Vector3(e, 0, 0)), Vector3.ONE * 0.04, ink, 8, 4)
	var top := face.frame(0.5, 0.06, 0.06)
	var h := 0.5 * DungeonMesh.WALL_H
	props.box(top * Transform3D(Basis(), Vector3(0, -h / 2.0, 0)), Vector3(0.64, h, 0.025), ink)
	for e in [-0.24, 0.0, 0.24]:
		var tip := top * Vector3(e, -h - 0.12, 0.0)
		props.limb(top * Vector3(e - 0.08, -h, 0.0), tip, 0.012, 0.012, ink, 4)
		props.limb(tip, top * Vector3(e + 0.08, -h, 0.0), 0.012, 0.012, ink, 4)
	var mark := face.frame(0.5, 0.26, 0.085)
	props.torus(mark * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO), 0.1, 0.14, ink)
	props.box(mark, Vector3(0.03, 0.34, 0.02), ink)


## Strokes flat on the wall, drawn solid.
static func _crack(props: MeshKit.Builder, face: _Face, color: Color) -> void:
	var solid := MeshKit.color(color, true)
	_strip(props, face, [[0.3, 0.18], [0.38, 0.34], [0.34, 0.46], [0.46, 0.6], [0.42, 0.72], [0.52, 0.86]], 0.035, solid)
	_strip(props, face, [[0.38, 0.34], [0.48, 0.38]], 0.025, solid)
	_strip(props, face, [[0.46, 0.6], [0.58, 0.62]], 0.025, solid)


## A crack right across the wall, in the accent colour, branching: you can tell this one gives.
static func _fissure(props: MeshKit.Builder, face: _Face, accent: Color) -> void:
	var solid := MeshKit.color(accent, true)
	_strip(props, face, [[0.22, 0.04], [0.36, 0.2], [0.3, 0.36], [0.5, 0.5], [0.44, 0.68], [0.62, 0.82], [0.58, 0.97]], 0.05, solid)
	_strip(props, face, [[0.36, 0.2], [0.54, 0.26], [0.7, 0.2]], 0.035, solid)
	_strip(props, face, [[0.5, 0.5], [0.72, 0.54], [0.82, 0.68]], 0.035, solid)
	_strip(props, face, [[0.44, 0.68], [0.26, 0.74], [0.16, 0.9]], 0.035, solid)


## A dark hole in a frame, with a sill and three bars.
static func _window(props: MeshKit.Builder, face: _Face, color: Color) -> void:
	var ink := MeshKit.color(color)
	_patch(props, face, [[0.36, 0.24], [0.64, 0.24], [0.64, 0.46], [0.36, 0.46]])
	var mid := face.frame(0.5, 0.35, 0.03)
	var w := 0.28 * Materials.CELL
	var hh := 0.11 * DungeonMesh.WALL_H
	props.box(mid * Transform3D(Basis(), Vector3(0, hh + 0.035, 0)), Vector3(w * 2.0 + 0.14, 0.07, 0.07), ink)
	props.box(mid * Transform3D(Basis(), Vector3(0, -hh - 0.04, 0.02)), Vector3(w * 2.0 + 0.2, 0.08, 0.11), ink) # sill
	props.box(mid * Transform3D(Basis(), Vector3(-w - 0.035, 0, 0)), Vector3(0.07, hh * 2.0, 0.07), ink)
	props.box(mid * Transform3D(Basis(), Vector3(w + 0.035, 0, 0)), Vector3(0.07, hh * 2.0, 0.07), ink)
	for u in [0.43, 0.5, 0.57]:
		props.cylinder(face.frame(u, 0.46, 0.02), 0.016, 0.016, hh * 2.0, ink, 6)


## A dark arch with a ledge, and a skull on the ledge.
static func _niche(props: MeshKit.Builder, face: _Face, color: Color) -> void:
	var ink := MeshKit.color(color)
	var solid := MeshKit.color(color, true)
	var arch := [[0.36, 0.78], [0.36, 0.58], [0.42, 0.5], [0.5, 0.47], [0.58, 0.5], [0.64, 0.58], [0.64, 0.78]]
	_patch(props, face, [[0.5, 0.64]] + arch + [[0.36, 0.78]])
	_strip(props, face, arch, 0.035, solid, 0.008)
	props.box(face.frame(0.5, 0.78, 0.06), Vector3(0.62, 0.05, 0.14), ink)
	var skull := face.frame(0.5, 0.66, 0.1)
	props.sphere(skull, Vector3(0.1, 0.095, 0.1), ink, 12, 6)
	props.box(skull * Transform3D(Basis(), Vector3(0, -0.085, 0.02)), Vector3(0.1, 0.05, 0.08), ink) # jaw
	for e in [-0.04, 0.04]:
		props.sphere(skull * Transform3D(Basis(), Vector3(e, 0.0, 0.082)), Vector3(0.026, 0.03, 0.02), solid, 8, 4)
	props.sphere(skull * Transform3D(Basis(), Vector3(0, -0.04, 0.092)), Vector3(0.012, 0.016, 0.01), solid, 6, 3)


# A strip along a polyline given in face coordinates, flat on the wall.
static func _strip(props: MeshKit.Builder, face: _Face, pts: Array, width: float, col: Color, out := LIFT) -> void:
	for i in range(pts.size() - 1):
		var a := face.frame(pts[i][0], pts[i][1], out).origin
		var b := face.frame(pts[i + 1][0], pts[i + 1][1], out).origin
		var side := face.inward.cross((b - a).normalized()) * (width / 2.0)
		props.quad(a + side, b + side, b - side, a - side, col)


# A flat black polygon on the wall (a fan from its first point), the dark inside of a window or a niche.
static func _patch(props: MeshKit.Builder, face: _Face, pts: Array, out := LIFT * 0.75) -> void:
	var p := pts.map(func(q): return face.frame(q[0], q[1], out).origin)
	for i in range(1, p.size() - 1):
		props.tri(p[0], p[i], p[i + 1], Color.BLACK)


## Two numbers in 0..1 from a wall's place: whether it is decorated, and with what.
static func _hash(x: int, y: int, side: int, seed_value: int) -> Array:
	var h := (x * 73856093) ^ (y * 19349663) ^ (side * 83492791) ^ (seed_value * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	var a := float(h & 0xFFFF) / 65536.0
	var b := float((h >> 16) & 0xFFFF) / 65536.0
	return [a, b]


## A wall face seen from inside its cell: where (u, v) on it is in the world.
class _Face:
	extends RefCounted
	var a: Vector3 # u = 0, on the floor
	var across: Vector3 # a to the u = 1 end
	var inward: Vector3 # which way is into the cell, for lifting off the wall

	func _init(mid: Vector3, side: int, half: float) -> void:
		var b: Vector3
		match side:
			0: a = mid + Vector3(-half, 0, -half); b = mid + Vector3(half, 0, -half)
			1: a = mid + Vector3(half, 0, -half); b = mid + Vector3(half, 0, half)
			2: a = mid + Vector3(half, 0, half); b = mid + Vector3(-half, 0, half)
			_: a = mid + Vector3(-half, 0, half); b = mid + Vector3(-half, 0, -half)
		across = b - a
		inward = -Vector3(FloorMap.DIRS[side].x, 0, FloorMap.DIRS[side].y)

	## A frame on the face at (u, v), `out` off the wall: +X along the wall as you face it, +Y up, +Z out into the cell.
	func frame(u: float, v: float, out := 0.0) -> Transform3D:
		var at := a + across * u + Vector3(0, DungeonMesh.WALL_H * (1.0 - v), 0) + inward * out
		return Transform3D(Basis(across.normalized(), Vector3.UP, inward), at)
