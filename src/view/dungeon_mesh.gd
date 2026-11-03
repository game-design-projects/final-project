## The floor as 3D geometry: a wall face wherever an open cell meets a wall, and a floor and ceiling over every open cell.
## One cell is CELL world units; map (x, y) is world (X, Z), north is -Z, up is +Y.
extends RefCounted

const FloorMap = preload("res://src/rules/floor_map.gd")
const Materials = preload("res://src/view/materials.gd")

const CELL := Materials.CELL
const WALL_H := 1.7


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
			var mid := center(c)
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


## Collects quads (corners in order around the face) with UV 0..1 across each.
class _Quads:
	extends RefCounted
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		var base := verts.size()
		verts.append_array([a, b, c, d])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func commit(mesh: ArrayMesh, material: Material) -> void:
		if verts.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
