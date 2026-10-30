## Builds the view's 3D meshes by hand: a `Builder` collects triangles (positions, normals, vertex colors, UV, UV2)
## and turns them into one ArrayMesh, so a whole monster or the whole maze is one mesh with one material. Shapes come
## from Godot's primitive meshes (sphere, box, cylinder, torus...) moved by a Transform3D and painted one color;
## quads and triangles are added directly. Colors go in linear (`lin`), the way the shaders read them.
##
## Winding: Godot draws faces whose corners run clockwise as you look at them, so `quad(a, b, c, d)` takes the
## corners clockwise seen from the front (top left, top right, bottom right, bottom left).
extends RefCounted


## "#rrggbb" (or a Color) in linear space, with `glow` making the vertex alpha 0 (toon.gdshader: lit by nothing)
static func lin(c, glow := false) -> Color:
	var col: Color = c if c is Color else Color.html(str(c))
	var out := col.srgb_to_linear()
	out.a = 0.0 if glow else 1.0
	return out


## A color scaled toward black (k < 1) in linear space, keeping its alpha
static func shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


class Builder:
	extends RefCounted

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	# Primitive meshes' arrays, made once per shape
	static var _prims := {}

	static func _arrays(key: String, make: Callable) -> Array:
		if not _prims.has(key):
			var m: PrimitiveMesh = make.call()
			_prims[key] = m.get_mesh_arrays()
		return _prims[key]

	func is_empty() -> bool:
		return indices.is_empty()

	func vertex(p: Vector3, n: Vector3, c: Color, uv := Vector2.ZERO, uv2 := Vector2.ZERO) -> int:
		verts.append(p)
		normals.append(n)
		colors.append(c)
		uvs.append(uv)
		uv2s.append(uv2)
		return verts.size() - 1

	func tri_idx(a: int, b: int, c: int) -> void:
		indices.append(a)
		indices.append(b)
		indices.append(c)

	## A flat triangle, corners clockwise seen from the front
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, uv2 := Vector2.ZERO) -> void:
		var n := (c - a).cross(b - a).normalized()
		tri_idx(vertex(a, n, col, Vector2.ZERO, uv2), vertex(b, n, col, Vector2.ZERO, uv2), vertex(c, n, col, Vector2.ZERO, uv2))

	## A flat quad, corners clockwise seen from the front. `uv` gives the four corners' UVs (default: the unit square
	## from the top left); `uv2` is the same for every corner.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv2 := Vector2.ZERO, uv := []) -> void:
		var n := (c - a).cross(b - a).normalized()
		if n == Vector3.ZERO:
			n = (d - a).cross(b - a).normalized()
		var u: Array = uv if uv.size() == 4 else [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var i0 := vertex(a, n, col, u[0], uv2)
		var i1 := vertex(b, n, col, u[1], uv2)
		var i2 := vertex(c, n, col, u[2], uv2)
		var i3 := vertex(d, n, col, u[3], uv2)
		tri_idx(i0, i1, i2)
		tri_idx(i0, i2, i3)

	## A primitive's arrays (ArrayMesh layout) moved by `xf` and painted `col`
	func add_arrays(arr: Array, xf: Transform3D, col: Color, uv2 := Vector2.ZERO) -> void:
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var puv = arr[Mesh.ARRAY_TEX_UV]
		var pi = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0 # a mirrored part turns its faces inside out unless re-wound
		var base := verts.size()
		for i in pv.size():
			vertex(xf * pv[i], (nb * pn[i]).normalized(), col, puv[i] if puv != null and i < puv.size() else Vector2.ZERO, uv2)
		if pi == null or pi.is_empty():
			for i in range(0, pv.size(), 3):
				if flip:
					tri_idx(base + i, base + i + 2, base + i + 1)
				else:
					tri_idx(base + i, base + i + 1, base + i + 2)
		else:
			for i in range(0, pi.size(), 3):
				if flip:
					tri_idx(base + pi[i], base + pi[i + 2], base + pi[i + 1])
				else:
					tri_idx(base + pi[i], base + pi[i + 1], base + pi[i + 2])

	## An ellipsoid: a sphere of radius 1 stretched to `radii`, then moved by `xf`
	func sphere(xf: Transform3D, radii: Vector3, col: Color, segs := 16, rings := 8, uv2 := Vector2.ZERO) -> void:
		var arr := _arrays("sphere:%d:%d" % [segs, rings], func():
			var m := SphereMesh.new()
			m.radius = 1.0
			m.height = 2.0
			m.radial_segments = segs
			m.rings = rings
			return m)
		add_arrays(arr, xf * Transform3D(Basis.from_scale(radii), Vector3.ZERO), col, uv2)

	## A box of `size`, centered on `xf`'s origin
	func box(xf: Transform3D, size: Vector3, col: Color, uv2 := Vector2.ZERO) -> void:
		var arr := _arrays("box", func():
			var m := BoxMesh.new()
			m.size = Vector3.ONE
			return m)
		add_arrays(arr, xf * Transform3D(Basis.from_scale(size), Vector3.ZERO), col, uv2)

	## A cylinder (or a cone, with one radius 0) standing on `xf`'s origin along its +Y, `h` tall
	func cylinder(xf: Transform3D, r_bottom: float, r_top: float, h: float, col: Color, segs := 12, uv2 := Vector2.ZERO) -> void:
		var r := maxf(r_bottom, r_top)
		if r <= 0.0:
			return
		var rb := snappedf(r_bottom / r, 0.01)
		var rt := snappedf(r_top / r, 0.01)
		var arr := _arrays("cyl:%d:%s:%s" % [segs, rb, rt], func():
			var m := CylinderMesh.new()
			m.bottom_radius = rb
			m.top_radius = rt
			m.height = 1.0
			m.radial_segments = segs
			m.rings = 1
			return m)
		add_arrays(arr, xf * Transform3D(Basis.from_scale(Vector3(r, h, r)), Vector3(0, h / 2.0, 0)), col, uv2)

	## A cylinder from point a to point b (a limb, a bar, a club)
	func limb(a: Vector3, b: Vector3, r_a: float, r_b: float, col: Color, segs := 10, uv2 := Vector2.ZERO) -> void:
		var d := b - a
		var h := d.length()
		if h < 1e-5:
			return
		var y := d / h
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		cylinder(Transform3D(Basis(x, y, z), a), r_a, r_b, h, col, segs, uv2)

	## A ring in `xf`'s XZ plane (its axis is +Y), `rings` segments round and `sides` round its tube
	func torus(xf: Transform3D, r_in: float, r_out: float, col: Color, uv2 := Vector2.ZERO, rings := 16, sides := 8) -> void:
		var k := snappedf(r_in / r_out, 0.01)
		var arr := _arrays("torus:%s:%d:%d" % [k, rings, sides], func():
			var m := TorusMesh.new()
			m.inner_radius = k
			m.outer_radius = 1.0
			m.rings = rings
			m.ring_segments = sides
			return m)
		add_arrays(arr, xf * Transform3D(Basis.from_scale(Vector3.ONE * r_out), Vector3.ZERO), col, uv2)

	## The whole lot as one ArrayMesh (null if nothing was added)
	func commit() -> ArrayMesh:
		if is_empty():
			return null
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
		arr[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return mesh

