## The floor as 3D geometry: a wall face wherever an open cell meets a wall, a floor and ceiling over every open cell, and
## the stairs down as a stepped pit cut into their cell's floor. One cell is CELL world units; map (x, y) is world (X, Z),
## north is -Z, up is +Y.
extends RefCounted

const FloorMap = preload("res://src/rules/floor_map.gd")
const Materials = preload("res://src/view/materials.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")

const CELL := Materials.CELL
const WALL_H := 1.7
# the stairwell: the hole's half width (in cells), how deep it goes, and the steps going down into it
const STAIRS_HALF := 0.38
const STAIRS_DEPTH := 1.5
const STAIRS_STEPS := 5
const STAIRS_DROP := 0.2
const RIM_W := 0.05
const STEP_LINE := 0.03 # the width of the line along each step: its boxes alone would show no edge where they meet
const RIM_LIFT := 0.01 # how far the rim sits off the floor, so the two don't flicker into each other


## World position of the middle of a cell, at floor level.
static func center(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL, 0.0, c.y * CELL)


## The walls (surface 0) and the floor and ceiling (surface 1) of `floor_map` as one mesh, with the given materials.
static func build(floor_map, wall_mat: Material, flat_mat: Material) -> ArrayMesh:
	var walls := _Quads.new()
	var flats := _Quads.new()
	var half := CELL / 2.0
	for y in floor_map.size:
		for x in floor_map.size:
			var c := Vector2i(x, y)
			if not floor_map.is_open(c):
				continue
			walls.cell_uv = (Vector2(c) + Vector2(0.5, 0.5)) / float(floor_map.size)
			flats.cell_uv = walls.cell_uv
			var mid := center(c)
			if c == floor_map.stairs:
				_floor_round_hole(flats, mid, half)
			else:
				flats.add(mid + Vector3(-half, 0, -half), mid + Vector3(half, 0, -half), mid + Vector3(half, 0, half), mid + Vector3(-half, 0, half))
			flats.add(mid + Vector3(-half, WALL_H, -half), mid + Vector3(half, WALL_H, -half), mid + Vector3(half, WALL_H, half), mid + Vector3(-half, WALL_H, half))
			for i in 4:
				if floor_map.is_open(c + FloorMap.DIRS[i]):
					continue
				# the face of the wall on side i, as seen from inside the cell
				var a: Vector3
				var b: Vector3
				match i:
					0: a = mid + Vector3(-half, 0, -half); b = mid + Vector3(half, 0, -half)
					1: a = mid + Vector3(half, 0, -half); b = mid + Vector3(half, 0, half)
					2: a = mid + Vector3(half, 0, half); b = mid + Vector3(-half, 0, half)
					_: a = mid + Vector3(-half, 0, half); b = mid + Vector3(-half, 0, -half)
				walls.add(a, b, b + Vector3(0, WALL_H, 0), a + Vector3(0, WALL_H, 0))
	var mesh := ArrayMesh.new()
	walls.commit(mesh, wall_mat)
	flats.commit(mesh, flat_mat)
	return mesh


# The stairs' cell has a floor in four strips, around the hole the pit shows through.
static func _floor_round_hole(flats: _Quads, mid: Vector3, half: float) -> void:
	var hole := STAIRS_HALF * CELL
	for r in [[-half, -half, half, -hole], [-half, hole, half, half], [-half, -hole, -hole, hole], [hole, -hole, half, hole]]:
		flats.add(mid + Vector3(r[0], 0, r[1]), mid + Vector3(r[2], 0, r[1]), mid + Vector3(r[2], 0, r[3]), mid + Vector3(r[0], 0, r[3]))


## The stairs down, around the origin at floor level: the four walls of the hole, black, and steps going down all round, a
## square funnel narrowing into the dark, so from whichever side you come up to it the far side's steps face you. Each ring
## is a frame of four boxes, lower and dimmer than the one outside it; the rim round the hole is a line in the same colour.
static func stairwell(accent: Color) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var hw := STAIRS_HALF * CELL
	var depth := STAIRS_DEPTH
	var dark := Color.BLACK
	b.quad(Vector3(-hw, 0, -hw), Vector3(hw, 0, -hw), Vector3(hw, -depth, -hw), Vector3(-hw, -depth, -hw), dark) # north, faces south
	b.quad(Vector3(hw, 0, hw), Vector3(-hw, 0, hw), Vector3(-hw, -depth, hw), Vector3(hw, -depth, hw), dark)
	b.quad(Vector3(-hw, 0, hw), Vector3(-hw, 0, -hw), Vector3(-hw, -depth, -hw), Vector3(-hw, -depth, hw), dark)
	b.quad(Vector3(hw, 0, -hw), Vector3(hw, 0, hw), Vector3(hw, -depth, hw), Vector3(hw, -depth, -hw), dark)
	b.quad(Vector3(-hw, -depth, -hw), Vector3(hw, -depth, -hw), Vector3(hw, -depth, hw), Vector3(-hw, -depth, hw), dark)
	var line := MeshKit.color(accent)
	var w := hw / (STAIRS_STEPS + 1)
	for i in STAIRS_STEPS:
		var top := -(i + 1) * STAIRS_DROP
		var o := hw - i * w
		var n := o - w
		var h := depth + top
		var yc := (top - depth) / 2.0
		var col := MeshKit.shade(line, 0.95 - 0.16 * i)
		b.box(Transform3D(Basis(), Vector3(0, yc, -(o + n) / 2.0)), Vector3(2.0 * o, h, w), col)
		b.box(Transform3D(Basis(), Vector3(0, yc, (o + n) / 2.0)), Vector3(2.0 * o, h, w), col)
		b.box(Transform3D(Basis(), Vector3(-(o + n) / 2.0, yc, 0)), Vector3(w, h, 2.0 * n), col)
		b.box(Transform3D(Basis(), Vector3((o + n) / 2.0, yc, 0)), Vector3(w, h, 2.0 * n), col)
		_frame_line(b, n, top + RIM_LIFT, STEP_LINE, MeshKit.color(col, true))
	_frame_line(b, hw, RIM_LIFT, -RIM_W, MeshKit.color(accent, true))
	return b.commit()


# A flat square line at height `y` round the origin: `w` inside the square of half width `half` (outside it, if negative).
static func _frame_line(b: MeshKit.Builder, half: float, y: float, w: float, col: Color) -> void:
	var o := maxf(half, half - w)
	var n := minf(half, half - w)
	for r in [[-o, -o, o, -n], [-o, n, o, o], [-o, -n, -n, n], [n, -n, o, n]]:
		b.quad(Vector3(r[0], y, r[1]), Vector3(r[2], y, r[1]), Vector3(r[2], y, r[3]), Vector3(r[0], y, r[3]), col)


## Collects quads (corners in order around the face) with UV 0..1 across each.
class _Quads:
	extends RefCounted
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cell_uv := Vector2.ZERO
	var cells := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		var base := verts.size()
		verts.append_array([a, b, c, d])
		cells.append_array([cell_uv, cell_uv, cell_uv, cell_uv])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func commit(mesh: ArrayMesh, material: Material) -> void:
		if verts.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = cells
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
