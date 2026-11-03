## Things hung on the walls: torches (with a glow), chains, banners, cracks, barred windows, skull niches. Which wall gets which is
## decided by a hash of its place and the floor's seed, so a wall is always decorated the same way. They are drawn as thin
## lines on the wall faces, in the wall colour (torch flames in the accent colour), plus a soft glow sprite for each torch.
extends RefCounted

const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Materials = preload("res://src/view/materials.gd")

const KINDS := ["torch", "torch", "chains", "banner", "crack", "window", "niche"]
const SHARE := 0.22 # about this share of wall faces carry something
const LIFT := 0.012 # lines sit this far off the wall so they don't flicker into it

## Each kind is a list of strokes; a stroke is [closed?, "accent"|"wall", u, v, u, v, ...] in the face's own coordinates:
## u across the face (0..1), v from the top (0) to the floor (1).
const STROKES := {
	"torch": [
		[false, "wall", 0.44, 0.58, 0.56, 0.58], # bracket
		[false, "wall", 0.5, 0.58, 0.5, 0.44], # handle
		[true, "accent", 0.45, 0.44, 0.47, 0.36, 0.5, 0.26, 0.53, 0.36, 0.55, 0.44], # flame
		[false, "accent", 0.49, 0.42, 0.5, 0.35, 0.51, 0.42],
	],
	"banner": [
		[false, "wall", 0.3, 0.06, 0.7, 0.06],
		[false, "wall", 0.34, 0.06, 0.34, 0.56, 0.42, 0.5, 0.5, 0.58, 0.58, 0.5, 0.66, 0.56, 0.66, 0.06],
		[false, "wall", 0.5, 0.18, 0.5, 0.34],
	],
	"crack": [
		[false, "wall", 0.3, 0.18, 0.38, 0.34, 0.34, 0.46, 0.46, 0.6, 0.42, 0.72, 0.52, 0.86],
		[false, "wall", 0.38, 0.34, 0.48, 0.38],
		[false, "wall", 0.46, 0.6, 0.58, 0.62],
	],
	"window": [
		[true, "wall", 0.36, 0.24, 0.64, 0.24, 0.64, 0.46, 0.36, 0.46],
		[false, "wall", 0.43, 0.24, 0.43, 0.46],
		[false, "wall", 0.5, 0.24, 0.5, 0.46],
		[false, "wall", 0.57, 0.24, 0.57, 0.46],
	],
	"niche": [
		[true, "wall", 0.36, 0.78, 0.36, 0.58, 0.42, 0.5, 0.5, 0.47, 0.58, 0.5, 0.64, 0.58, 0.64, 0.78],
		[false, "wall", 0.47, 0.71, 0.53, 0.71],
	],
}


## Which walls carry what: [{"cell": Vector2i, "side": int, "kind": String}], the same every time for a floor.
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
				var roll := _hash(x, y, side, floor_map.seed_value)
				if roll[0] <= SHARE:
					out.append({"cell": c, "side": side, "kind": KINDS[int(roll[1] * KINDS.size()) % KINDS.size()]})
	return out


## A node holding the decorations of `floor_map`. `torch_glows` (an Array) gets one MeshInstance3D per torch for the caller to
## flicker.
static func build(floor_map, wall_color: Color, accent: Color, torch_glows: Array) -> Node3D:
	var root := Node3D.new()
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var half := Materials.CELL / 2.0
	for p in placements(floor_map):
		var kind: String = p.kind
		var face := _Face.new(DungeonMesh.center(p.cell), p.side, half)
		if kind == "niche":
			_skull(face, verts, colors, wall_color)
		if kind == "chains":
			_chains(face, verts, colors, wall_color)
		else:
			for stroke in STROKES[kind]:
				_stroke(face, stroke, verts, colors, accent if stroke[1] == "accent" else wall_color)
		if kind == "torch":
			torch_glows.append(_glow(root, face, accent))
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		var lines := MeshInstance3D.new()
		lines.mesh = mesh
		lines.material_override = _line_material()
		root.add_child(lines)
	return root


## The skull in a niche: a ring for the head, two eyes.
static func _skull(face, verts: PackedVector3Array, colors: PackedColorArray, color: Color) -> void:
	var ring := [true, "wall"]
	for i in 8:
		ring.append_array([0.5 + 0.06 * cos(TAU * i / 8.0), 0.64 + 0.06 * sin(TAU * i / 8.0)])
	_stroke(face, ring, verts, colors, color)
	for u in [0.48, 0.52]:
		_stroke(face, [false, "wall", u, 0.625, u, 0.64], verts, colors, color)


## Two chains hanging from the top, ring by ring, each ending in a hook.
static func _chains(face, verts: PackedVector3Array, colors: PackedColorArray, color: Color) -> void:
	for pair in [[0.38, 0.5], [0.6, 0.36]]:
		var u: float = pair[0]
		var length: float = pair[1]
		_stroke(face, [false, "wall", u, 0.0, u, length], verts, colors, color)
		var v := 0.06
		while v < length:
			var ring := [true, "wall"]
			for i in 6:
				ring.append_array([u + 0.025 * cos(TAU * i / 6.0), v + 0.03 * sin(TAU * i / 6.0)])
			_stroke(face, ring, verts, colors, color)
			v += 0.08
		_stroke(face, [false, "wall", u - 0.04, length, u, length + 0.06, u + 0.04, length], verts, colors, color)


static func _stroke(face, stroke: Array, verts: PackedVector3Array, colors: PackedColorArray, color: Color) -> void:
	var pts: Array[Vector3] = []
	for i in range(2, stroke.size(), 2):
		pts.append(face.at(stroke[i], stroke[i + 1]))
	if stroke[0]:
		pts.append(pts[0])
	for i in range(pts.size() - 1):
		verts.append_array([pts[i], pts[i + 1]])
		colors.append_array([color, color])


static func _glow(root: Node3D, face, accent: Color) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(accent, 0.45))
	gradient.set_color(1, Color(accent, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	var glow := MeshInstance3D.new()
	glow.mesh = quad
	glow.material_override = mat
	glow.position = face.at(0.5, 0.36) + face.inward * 0.15
	root.add_child(glow)
	return glow


static func _line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return m


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

	func at(u: float, v: float) -> Vector3:
		return a + across * u + Vector3(0, DungeonMesh.WALL_H * (1.0 - v), 0) + inward * 0.012
