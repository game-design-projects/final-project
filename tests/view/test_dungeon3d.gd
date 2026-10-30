## The floor as a 3D set (dungeon3d.gd) and the mesh builder under it (mesh_kit.gd): which walls get faces, where
## they sit and which way they face, the ink at corners, the stairwell, the decorations, the torches.
extends "res://tests/test_case.gd"

const Dungeon3D = preload("res://src/view/dungeon3d.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")
const Render = preload("res://src/view/render.gd")

const CELL := Dungeon3D.CELL


# Builds a map from rows of "#" (wall) and "." (floor), as test_render does
func map_of(rows: Array, extra := {}) -> Dictionary:
	var grid := []
	for r: String in rows:
		var row := []
		for c in r:
			row.append(1 if c == "." else 0)
		grid.append(row)
	var m := {"grid": grid, "n": grid.size(), "stairs": {"x": -1, "y": -1}, "palette": Render.PALETTES[0], "seed": 1}
	m.merge(extra, true)
	return m


# The normal of a quad given by its corners, the way MeshKit computes it (corners clockwise seen from the front)
func normal_of(c: Array) -> Vector3:
	return (c[2] - c[0]).cross(c[1] - c[0]).normalized()


func test_every_side_of_a_floor_cell_that_meets_a_wall_is_a_face():
	var map := map_of(["#####", "#...#", "#####"]) # a corridor three cells long, running east
	var faces := Dungeon3D.wall_faces(map)
	# each of the 3 cells has a wall north and south; the two ends add one each
	eq(faces.size(), 8)
	eq(faces[0], {"from": [1, 1], "s": 0, "wall": [1, 0]}, "grid order, then N E S W")
	eq(faces.filter(func(f): return f.s == 3).size(), 1, "one west end")


func test_a_face_stands_on_the_floor_between_its_cells_and_faces_into_the_floor_cell():
	var map := map_of(["###", "#.#", "###"])
	for face in Dungeon3D.wall_faces(map):
		var c := Dungeon3D.face_corners(face)
		var mid: Vector3 = (c[0] + c[2]) / 2.0
		var into := -Dungeon3D.dir_vec(face.s)
		ok(normal_of(c).is_equal_approx(into), "face %d faces into its cell (%s)" % [face.s, normal_of(c)])
		near(c[0].y, Dungeon3D.WALL_H, 1e-6, "top at the ceiling")
		near(c[2].y, 0.0, 1e-6, "bottom on the floor")
		near((mid - Dungeon3D.cell_center(1, 1)).dot(-into), CELL / 2.0, 1e-6, "on the cell's edge")
		near(c[0].distance_to(c[1]), CELL, 1e-6, "a cell wide")


func test_the_face_frame_runs_along_the_wall_up_and_out_of_it():
	var map := map_of(["###", "#.#", "###"])
	var north: Dictionary = Dungeon3D.wall_faces(map)[0]
	eq(north.s, 0)
	var f := Dungeon3D.face_frame(north, 0.5, 0.5, 0.1)
	ok(f.basis.x.is_equal_approx(Vector3.RIGHT), "u runs east along a north wall, as you face it")
	ok(f.basis.y.is_equal_approx(Vector3.UP))
	ok(f.basis.z.is_equal_approx(Vector3(0, 0, 1)), "out of the wall, toward you")
	near(f.origin.y, Dungeon3D.WALL_H * 0.5, 1e-6)
	near(f.origin.z, CELL + 0.1, 1e-6, "0.1 out of the wall, which is at z = CELL")


func test_corners_are_inked_full_and_a_wall_running_on_only_faintly():
	var map := map_of(["#####", "#...#", "#####"])
	var grid: Array = map.grid
	# the north wall of the middle cell runs on both ways
	eq(Dungeon3D.edge_ink(grid, 2, 1, 0, -1), Dungeon3D.SEAM_INK)
	eq(Dungeon3D.edge_ink(grid, 2, 1, 0, 1), Dungeon3D.SEAM_INK)
	# at the west end it turns a corner (concave: the end wall), on the east it runs on
	eq(Dungeon3D.edge_ink(grid, 1, 1, 0, -1), 1.0)
	eq(Dungeon3D.edge_ink(grid, 1, 1, 0, 1), Dungeon3D.SEAM_INK)
	# an opening beside you: the wall stops at a convex corner
	var t := map_of(["#####", "#...#", "##.##", "#####"])
	eq(Dungeon3D.edge_ink(t.grid, 1, 1, 2, -1), 1.0, "the south wall of the west cell ends at the opening")
	eq(Dungeon3D.edge_ink(t.grid, 1, 1, 2, 1), 1.0, "and meets the end wall on its other side")


func test_build_makes_one_mesh_each_and_counts_its_faces():
	var map := map_of(["#####", "#...#", "#.#.#", "#...#", "#####"])
	var b := Dungeon3D.build(map)
	eq(b.faces, Dungeon3D.wall_faces(map).size())
	for k in ["walls", "floor", "ceiling"]:
		ok(b[k] is ArrayMesh, "%s is a mesh" % k)
	var cells := 8
	eq(b.walls.surface_get_array_index_len(0), b.faces * 6, "two triangles a face")
	eq(b.floor.surface_get_array_index_len(0), cells * 6)
	eq(b.ceiling.surface_get_array_index_len(0), cells * 6)
	var arr: Array = b.walls.surface_get_arrays(0)
	ok(arr[Mesh.ARRAY_COLOR] != null and arr[Mesh.ARRAY_TEX_UV2] != null, "colors and UV2 for the stone shader")


func test_the_floor_faces_up_and_the_ceiling_down():
	var map := map_of(["###", "#.#", "###"])
	var b := Dungeon3D.build(map)
	# (normals come back from the mesh compressed, so only nearly exact)
	for v in b.floor.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]:
		ok(v.distance_to(Vector3.UP) < 1e-3, "floor normal %s" % v)
	for v in b.ceiling.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]:
		ok(v.distance_to(Vector3.DOWN) < 1e-3, "ceiling normal %s" % v)
	for v in b.ceiling.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		near(v.y, Dungeon3D.WALL_H)


func test_the_stairs_are_a_hole_in_the_floor_with_steps_going_down():
	var plain := Dungeon3D.build(map_of(["####", "#..#", "####"]))
	var with := Dungeon3D.build(map_of(["####", "#..#", "####"], {"stairs": {"x": 2, "y": 1}}))
	eq(with.floor.surface_get_array_index_len(0), plain.floor.surface_get_array_index_len(0) + 3 * 6, "four strips round the hole for one whole cell")
	ok(with.props != null, "the stairwell")
	var lowest := 0.0
	for v in with.props.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		lowest = minf(lowest, v.y)
	near(lowest, -Dungeon3D.STAIRS_DEPTH, 1e-5, "it goes down into the dark")
	# no floor across the hole: nothing of the floor mesh is within the hole
	var c := Dungeon3D.cell_center(2, 1)
	var hw := Dungeon3D.STAIRS_HALF * CELL
	var tris: PackedInt32Array = with.floor.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = with.floor.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0, tris.size(), 3):
		var mid: Vector3 = (verts[tris[i]] + verts[tris[i + 1]] + verts[tris[i + 2]]) / 3.0
		ok(absf(mid.x - c.x) >= hw - 1e-4 or absf(mid.z - c.z) >= hw - 1e-4, "a floor triangle in the hole at %s" % mid)


func test_decorations_follow_the_wireframe_hash_and_every_torch_is_a_light_and_a_flame():
	var map := map_of(["#########", "#.......#", "#.#.#.#.#", "#.......#", "#########"], {"seed": 31})
	var want := 0
	var kinds := {}
	for face in Dungeon3D.wall_faces(map):
		var dec = Render._decor_for(map, face.wall, face.from)
		if dec != null:
			kinds[dec.kind] = true
			if dec.kind == "torch":
				want += 1
	var b := Dungeon3D.build(map)
	ok(not kinds.is_empty(), "some decoration on this floor")
	eq(b.torches.size(), want, "one light per torch")
	if want > 0:
		eq(b.flames.surface_get_array_index_len(0), want * 6, "one flame quad per torch")
		for tor in b.torches:
			ok(tor.pos.y > 1.0 and tor.pos.y < Dungeon3D.WALL_H, "a torch hangs at head height (%s)" % tor.pos)
	else:
		ok(b.flames == null, "no torch, no flames")
	eq(Dungeon3D.build(map).torches, b.torches, "the same floor builds the same")


func test_the_builder_winds_quads_clockwise_from_the_front_and_mirrored_parts_stay_outside_out():
	var b := MeshKit.Builder.new()
	b.quad(Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 0), Color.WHITE)
	ok(b.normals[0].is_equal_approx(Vector3(0, 0, 1)), "a quad seen from +Z faces +Z (%s)" % b.normals[0])
	eq(b.indices, PackedInt32Array([0, 1, 2, 0, 2, 3]))
	# every triangle of a sphere, mirrored or not, winds so that its face normal points away from the center
	for xf in [Transform3D(), Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)]:
		var s := MeshKit.Builder.new()
		s.sphere(xf, Vector3.ONE, Color.WHITE, 8, 4)
		var inward := 0
		for i in range(0, s.indices.size(), 3):
			var a: Vector3 = s.verts[s.indices[i]]
			var bb: Vector3 = s.verts[s.indices[i + 1]]
			var c: Vector3 = s.verts[s.indices[i + 2]]
			var n := (c - a).cross(bb - a)
			if n.length() > 1e-6 and n.dot((a + bb + c) / 3.0) <= 0.0:
				inward += 1
		eq(inward, 0, "triangles facing in, %s" % ("mirrored" if xf.basis.determinant() < 0.0 else "as made"))


func test_colors_go_in_linear_and_glow_is_a_zero_alpha():
	var c := MeshKit.lin("#ff8a1f")
	ok(c.is_equal_approx(Color.html("#ff8a1f").srgb_to_linear()))
	eq(c.a, 1.0)
	eq(MeshKit.lin("#ffffff", true).a, 0.0)
	ok(MeshKit.shade(Color(1, 0.5, 0.2, 0.0), 0.5).is_equal_approx(Color(0.5, 0.25, 0.1, 0.0)))
	eq(MeshKit.Builder.new().commit(), null, "nothing added, no mesh")
