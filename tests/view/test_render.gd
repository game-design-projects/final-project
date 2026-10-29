## Perspective of the corridor view (ports crawler/test/render.test.js) plus parity checks against the JS output.
extends "res://tests/test_case.gd"

const Render = preload("res://src/view/render.gd")

const N := 0 # facing north: forward is -y, left is -x


# Builds a map from rows of "#" (wall) and "." (floor).
func map_of(rows: Array, extra := {}) -> Dictionary:
	var grid := []
	for r: String in rows:
		var row := []
		for c in r:
			row.append(1 if c == "." else 0)
		grid.append(row)
	var m := {"grid": grid, "stairs": {"x": -1, "y": -1}}
	m.merge(extra, true)
	return m


func key_of(cell: Array) -> String:
	return "%d,%d" % [cell[0], cell[1]]


func keys_of(cells: Array) -> Array:
	var out := []
	for c in cells:
		out.append(key_of(c))
	out.sort()
	return out


## A drawing context that only records what it is asked to do (the JS test used a Proxy)
class Rec:
	extends RefCounted
	var size := Vector2(448, 288)
	var ops: Array[String] = []
	var rects: Array = []
	var fill_style = "#000"
	var stroke_style = "#000"
	var line_width := 1.0
	var global_alpha := 1.0
	var text_align := "start"
	var font := ""

	class Grad:
		extends RefCounted
		func add_color_stop(_o, _c) -> void:
			pass

	func save() -> void: ops.append("save")
	func restore() -> void: ops.append("restore")
	func begin_path() -> void: ops.append("begin_path")
	func move_to(_x, _y) -> void: ops.append("move_to")
	func line_to(_x, _y) -> void: ops.append("line_to")
	func close_path() -> void: ops.append("close_path")
	func rect(_x, _y, _w, _h) -> void: ops.append("rect")
	func clip() -> void: ops.append("clip")
	func fill() -> void: ops.append("fill")
	func stroke() -> void: ops.append("stroke")
	func stroke_rect(_x, _y, _w, _h) -> void: ops.append("stroke_rect")
	func fill_text(_s, _x, _y) -> void: ops.append("fill_text")
	func create_linear_gradient(_a, _b, _c, _d) -> Grad: return Grad.new()
	func create_radial_gradient(_a, _b, _c, _d, _e, _f) -> Grad: return Grad.new()

	func fill_rect(x, y, w, h) -> void:
		ops.append("fill_rect")
		rects.append([str(fill_style), x, y, w, h])


func test_scale_is_a_true_1_over_z_perspective_not_a_geometric_series():
	var z := 0.0
	while z <= Render.VIEW:
		ok(absf(Render.scale_at(z) * (Render.EYE + z) - Render.EYE) < 1e-9)
		z += 0.5
	eq(Render.scale_at(0), 1.0)
	for d in Render.DEPTH.size():
		near(Render.DEPTH[d], Render.scale_at(d), 1e-12)
	eq(Render.DEPTH.size(), Render.VIEW + 2)


func test_project_puts_the_near_frame_on_the_canvas_edge_and_converges_on_the_center():
	var p := Render.project(448, 288, -0.5, 0, -0.5)
	eq([p.x, p.y], [4, 4])
	var f := Render.project(448, 288, 0, 1e6, 0.5)
	ok(absf(f.x - 224) < 1e-3 and absf(f.y - 144) < 1e-3)


func test_a_dead_end_straight_ahead_is_one_front_face_plus_the_two_side_walls():
	var map := map_of([
		"###",
		"#.#",
		"#.#",
		"###",
	])
	var faces := Render.corridor_faces(map, 1, 2, N)
	var front := faces.filter(func(f): return f.type == "front").map(func(f): return [f.d, f.k])
	eq(front, [[2, 0]])
	var sides := faces.filter(func(f): return f.type == "side").map(func(f): return "%d,%d" % [f.d, f.k])
	sides.sort()
	eq(sides, ["0,-1", "0,1", "1,-1", "1,1"])


func test_no_phantom_wall_across_a_side_opening_that_leads_into_a_room():
	# Standing at the bottom of a 3-wide room: the old renderer drew a wall face at the far side of the
	# left opening even though the cell beyond it is open floor.
	var map := map_of([
		"#####",
		"#...#",
		"#...#",
		"#...#",
		"#####",
	])
	var faces := Render.corridor_faces(map, 2, 3, N)
	for f in faces:
		if f.type == "stairs":
			continue
		eq(map.grid[f.wall[1]][f.wall[0]], 0, "face %s at d=%d k=%d is drawn on open floor" % [f.type, f.d, f.k])
	# The room's left and right walls are seen side-on, at k = ±2
	ok(faces.any(func(f): return f.type == "side" and f.k == -2 and f.d == 0))
	ok(faces.any(func(f): return f.type == "side" and f.k == 2 and f.d == 2))


func test_faces_come_far_to_near_outer_to_inner_so_nearer_walls_paint_over_farther_ones():
	var map := map_of([
		"#######",
		"#.....#",
		"#.#.#.#",
		"#.....#",
		"###.###",
		"###.###",
		"#######",
	])
	var faces := Render.corridor_faces(map, 3, 5, N).filter(func(f): return f.type != "stairs")
	ok(faces.size() > 0)
	for i in range(1, faces.size()):
		var a: Dictionary = faces[i - 1]
		var b: Dictionary = faces[i]
		ok(a.d > b.d or (a.d == b.d and absi(a.k) >= absi(b.k)), "order broken at %d" % i)


func test_only_floor_you_could_actually_see_goes_on_the_automap():
	var map := map_of([
		"#######",
		"#.#...#",
		"#.#.#.#",
		"#.....#",
		"###.###",
		"#######",
	])
	var cells := Render.visible_cells(map, 3, 4, N)
	var seen := {}
	for c in cells:
		seen[key_of(c)] = true
	ok(seen.has("3,4") and seen.has("3,3") and seen.has("3,2") and seen.has("3,1"))
	ok(seen.has("2,3") and seen.has("4,3"), "the cross corridor, where it shows through the gap")
	ok(not seen.has("1,3"), "two cells to the side, one ahead: outside the field of view")
	ok(not seen.has("1,1"), "around the corner behind a wall")
	for c in cells:
		eq(map.grid[c[1]][c[0]], 1)


func test_decorations_on_a_side_wall_are_foreshortened_the_middle_of_the_wall_sits_past_the_screen_midpoint():
	var P := Render.face_mapper(448, 288, {"type": "side", "d": 0, "k": -1})
	var x_near: float = P.call(0, 0.5).x
	var x_mid: float = P.call(0.5, 0.5).x
	var x_far: float = P.call(1, 0.5).x
	ok(x_near < x_mid and x_mid < x_far)
	ok(x_mid - x_near > x_far - x_mid, "the near half of the wall should look wider than the far half")


func test_front_faces_and_right_side_walls_map_u_left_to_right_as_you_see_them():
	var front := Render.face_mapper(448, 288, {"type": "front", "d": 1, "k": 0})
	ok(front.call(0, 0).x < front.call(1, 0).x)
	eq(front.call(0, 0).y, front.call(1, 0).y)
	var right := Render.face_mapper(448, 288, {"type": "side", "d": 0, "k": 1})
	ok(right.call(0, 0.5).x < right.call(1, 0.5).x, "a wall on your right reads far-to-near, left to right")
	ok(right.call(0.5, 0).y < right.call(0.5, 1).y, "v runs from the top of the face down")


func test_automap_walls_an_edge_for_every_side_of_seen_floor_that_faces_a_wall_none_toward_unseen_floor():
	var map := map_of([
		"#####",
		"#...#",
		"#.#.#",
		"#####",
	])
	var at := func(x: int, y: int) -> int: return y * 5 + x # cells are keyed y * width + x, as in the game
	# Seen: the top row of floor only
	var seen := {at.call(1, 1): true, at.call(2, 1): true, at.call(3, 1): true}
	var edges := []
	for e in Render.wall_edges(map, seen):
		edges.append("%d,%d,%d" % [e[0], e[1], e[2]])
	edges.sort()
	# (x, y, side) with side 0..3 = N E S W
	var want := ["1,1,0", "1,1,3", "2,1,0", "2,1,2", "3,1,0", "3,1,1"]
	want.sort()
	eq(edges, want)


func test_the_corridor_layers_key_unchanged_while_you_stand_still_ticking_at_the_flame_rate_only_with_a_torch_in_sight():
	var frame := 1000.0 / Render.FLAME_FPS
	eq(Render.layer_key("1,2,0", false, 0), Render.layer_key("1,2,0", false, 99999), "no torch: one paint per position")
	eq(Render.layer_key("1,2,0", true, 1), Render.layer_key("1,2,0", true, frame - 1), "within one flame frame")
	ne(Render.layer_key("1,2,0", true, 1), Render.layer_key("1,2,0", true, frame + 1), "the next flame frame repaints")
	ne(Render.layer_key("1,2,0", false, 0), Render.layer_key("1,2,1", false, 0), "turning repaints")


func test_what_you_see_from_a_spot_is_worked_out_once_faces_with_their_decorations_and_whether_a_torch_is_lit():
	var map := map_of(["#####", "#...#", "#...#", "#...#", "#####"], {"seed": 11})
	var v := Render.corridor_view(map, 2, 3, N)
	eq(v.decor.size(), v.faces.size())
	for i in v.faces.size():
		if v.faces[i].type == "stairs":
			eq(v.decor[i], null)
	eq(v.torches, v.decor.any(func(d): return d != null and d.kind == "torch"))
	ok(v.cells.size() > 0)


func test_the_corridor_paints_straight_into_the_view():
	var ctx := Rec.new()
	var map := map_of(["###", "#.#", "#.#", "###"], {"seed": 1})
	var cells := Render.draw_corridor(ctx, map, 1, 2, N, 0)
	ok(ctx.ops.has("fill_rect") and ctx.ops.has("stroke"), "it drew")
	eq(keys_of(cells), ["1,1", "1,2"])


func test_the_corridor_view_is_reused_while_you_stay_put_and_follows_you_when_you_move():
	var ctx := Rec.new()
	var map := map_of(["#####", "#...#", "#...#", "#...#", "#####"], {"seed": 3})
	var a := Render.draw_corridor(ctx, map, 2, 3, N, 0)
	var b := Render.draw_corridor(ctx, map, 2, 3, N, 5000)
	ok(is_same(a, b), "same spot: the same worked-out view")
	var c := Render.draw_corridor(ctx, map, 2, 2, N, 0)
	ok(not is_same(a, c))
	var other := map_of(["###", "#.#", "#.#", "###"], {"seed": 1})
	eq(keys_of(Render.draw_corridor(ctx, other, 1, 2, N, 0)), ["1,1", "1,2"], "another map: not the cached view")


func test_stairs_in_view_are_a_face_of_their_own():
	var map := map_of(["###", "#.#", "#.#", "###"], {"stairs": {"x": 1, "y": 1}})
	var faces := Render.corridor_faces(map, 1, 2, N)
	var stairs := faces.filter(func(f): return f.type == "stairs")
	eq(stairs.size(), 1)
	eq([stairs[0].d, stairs[0].k], [1, 0])
	var ctx := Rec.new()
	Render.draw_corridor(ctx, map, 1, 2, N, 0)
	ok(ctx.ops.has("clip"), "the hole is clipped to its rim")


func test_reach_and_columns_follow_from_the_camera():
	eq(Render.REACH, ceili(0.5 * (Render.EYE + Render.VIEW + 1) / Render.EYE))
	var want := []
	for i in Render.REACH:
		want.append_array([-(Render.REACH - i), Render.REACH - i])
	want.append(0)
	eq(Render.COLUMNS, want)


# ---- parity with render.js (values computed by running the JS)

func test_the_wall_hash_matches_the_js_32_bit_arithmetic():
	near(Render._hash([1, 2, 3, 4, 0]), 0.8962773277889937, 1e-12)
	near(Render._hash([5, 6, 7, 8, 123456789]), 0.4095715794246644, 1e-12)
	near(Render._hash([0, 0, 0, 0, 999999999]), 0.6591040396597236, 1e-12)
	near(Render._hash([3, 1, 2, 7, 42]), 0.05460421089082956, 1e-12)
	near(Render._hash([9, 9, 1, 1, 999999999]), 0.8864385148044676, 1e-12)


func test_decorations_and_visible_cells_match_the_js_for_a_seeded_floor():
	var map := map_of(["#########", "#.......#", "#.#.#.#.#", "#.......#", "#.##.##.#", "#.......#", "#..#.#..#", "#.......#", "#########"], {"seed": 20260101, "stairs": {"x": 7, "y": 7}})
	var a := Render.corridor_view(map, 4, 7, 0)
	eq(a.faces.size(), 30)
	eq(a.torches, true)
	var kinds := []
	for d in a.decor:
		kinds.append(null if d == null else d.kind)
	eq(kinds, [null, null, null, "chains", "chains", null, null, "niche", null, null, "banner", "niche", "chains", "banner", null, "torch", null, null, "chains", "crack", null, null, "niche", null, null, null, null, null, null, null])
	near(a.decor[15].seed, 0.247794786, 1e-9)
	near(a.decor[19].seed, 0.099542092, 1e-9)
	eq(keys_of(a.cells), ["3,1", "3,2", "3,5", "3,7", "4,3", "4,4", "4,5", "4,6", "4,7", "5,1", "5,2", "5,5", "5,7"])
	var b := Render.corridor_view(map, 1, 1, 1)
	eq(b.faces.size(), 19)
	eq(b.torches, false)
	eq(b.decor[8].kind, "crack")
	eq(b.decor[16].kind, "chains")
	eq(keys_of(b.cells), ["1,1", "1,2", "2,1", "3,1", "3,2", "4,1", "5,1", "6,1", "7,1"])
	var c := Render.corridor_view(map, 7, 5, 2)
	eq(c.faces.size(), 13)
	eq(c.decor[2].kind, "chains")
	eq(c.decor[4].kind, "niche")
	eq(c.decor[11].kind, "niche")
	eq(keys_of(c.cells), ["5,7", "6,5", "6,6", "6,7", "7,5", "7,6", "7,7"])


# ---- the automap and the title card

func test_the_automap_marks_seen_floor_walls_stairs_the_champion_and_you():
	var map := map_of(["#####", "#...#", "#.#.#", "#...#", "#####"], {"stairs": {"x": 3, "y": 1}, "boss": {"x": 1, "y": 1, "defeated": false}, "palette": Render.PALETTES[1]})
	var seen := {1 * 5 + 1: true, 1 * 5 + 2: true, 1 * 5 + 3: true}
	var visited := {1 * 5 + 1: true}
	var ctx := Rec.new()
	ctx.size = Vector2(100, 100)
	Render.draw_map(ctx, map, seen, visited, 1, 1, 1)
	var rects := ctx.rects.map(func(r): return r.slice(0, 5))
	# cell size 100 / 5 rows = 20
	ok(rects.has(["#5a5a5a", 20, 20, 20, 20]), "visited floor")
	ok(rects.has(["#262626", 40, 20, 20, 20]), "seen floor")
	ok(rects.has(["#8fd3e8", 20, 20, 20, 1]), "a wall line in the floor's wall color")
	ok(rects.has(["#e8e8e8", 61, 21, 18, 18]), "stairs frame")
	ok(rects.has(["#000", 62, 22, 16, 16]), "stairs hole")
	ok(rects.has(["#ff2a2a", 20, 20, 20, 20]), "the red champion")
	ok(ctx.ops.has("fill"), "the arrow")
	map.boss.defeated = true
	var ctx2 := Rec.new()
	ctx2.size = Vector2(100, 100)
	Render.draw_map(ctx2, map, seen, visited, 1, 1, 1)
	ok(not ctx2.rects.any(func(r): return r[0] == "#ff2a2a"), "a defeated champion leaves the map")


func test_the_title_blinks_its_prompt():
	var on := Rec.new()
	Render.draw_title(on, 0)
	var off := Rec.new()
	Render.draw_title(off, 700)
	eq(on.ops.count("fill_text"), 2)
	eq(off.ops.count("fill_text"), 1)
	eq(on.ops.count("stroke_rect"), 6, "five receding frames and the title box")
