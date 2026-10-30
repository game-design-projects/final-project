## The 3D set (stage3d.gd): the camera where the party stands and how it eases there, the fight's camera and where
## the monsters stand, the champion, the torches that light the set, and the title corridor.
extends "res://tests/test_case.gd"

const Stage3D = preload("res://src/view/stage3d.gd")
const Dungeon3D = preload("res://src/view/dungeon3d.gd")
const Render = preload("res://src/view/render.gd")
const Art = preload("res://src/view/art.gd")
const Juice = preload("res://src/rules/juice.gd")

var vp: SubViewport
var stage: Stage3D


func before_each():
	vp = SubViewport.new()
	vp.size = Vector2i(448, 288)
	vp.own_world_3d = true
	(Engine.get_main_loop() as SceneTree).root.add_child(vp)
	stage = Stage3D.new()
	vp.add_child(stage)


func after_each():
	vp.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func map_of(rows: Array, extra := {}) -> Dictionary:
	var grid := []
	for r: String in rows:
		var row := []
		for c in r:
			row.append(1 if c == "." else 0)
		grid.append(row)
	var m := {"grid": grid, "n": grid.size(), "stairs": {"x": -1, "y": -1}, "palette": Render.PALETTES[1], "seed": 3, "boss": null}
	m.merge(extra, true)
	return m


# A long corridor running north, with room behind
const HALL = ["#####", "##.##", "##.##", "##.##", "##.##", "##.##", "#####"]


func _fwd() -> Vector3:
	return -stage.camera.transform.basis.z


func test_the_camera_stands_behind_the_middle_of_your_cell_looking_your_way():
	for dir in 4:
		var p := Stage3D.pose_of(2, 3, dir)
		var look := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
		ok(look.is_equal_approx(Dungeon3D.dir_vec(dir)), "facing %s (%s)" % [Render.DIR_NAMES[dir], look])
		var back: Vector3 = Dungeon3D.cell_center(2, 3) - Vector3(p.pos.x, 0, p.pos.z)
		near(back.dot(Dungeon3D.dir_vec(dir)), Stage3D.BACK, 1e-5, "BACK behind the middle")
		near(p.pos.y, Stage3D.EYE_H)


func test_the_first_place_is_at_once_then_steps_and_turns_ease_over_the_transition_times():
	var map := map_of(HALL)
	stage.use_map(map)
	stage.place(2, 4, 0, 1000.0)
	ok(stage.camera.transform.origin.is_equal_approx(Stage3D.pose_of(2, 4, 0).pos), "there at once")
	ok(not stage.moving())
	stage.place(2, 3, 0, 2000.0) # a step forward
	ok(stage.moving(), "a step eases")
	stage.place(2, 3, 0, 2000.0 + Juice.TRANSITION_MS.step / 2.0)
	var mid := stage.camera.transform.origin
	var a: Vector3 = Stage3D.pose_of(2, 4, 0).pos
	var b: Vector3 = Stage3D.pose_of(2, 3, 0).pos
	ok(mid.z < a.z and mid.z > b.z, "halfway there (%s)" % mid)
	ok(mid.distance_to(b) < mid.distance_to(a), "easing out: past the middle by half time")
	stage.place(2, 3, 0, 2000.0 + Juice.TRANSITION_MS.step + 1.0)
	ok(stage.camera.transform.origin.is_equal_approx(b), "arrived")
	ok(not stage.moving())
	stage.place(2, 3, 1, 3000.0) # a turn to the east
	stage.place(2, 3, 1, 3000.0 + Juice.TRANSITION_MS.turn / 4.0)
	var f := _fwd()
	ok(f.x > 0.3 and f.z < -0.3, "between north and east (%s)" % f)
	stage.place(2, 3, 1, 3000.0 + Juice.TRANSITION_MS.turn + 1.0)
	ok(_fwd().is_equal_approx(Vector3.RIGHT), "facing east")


func test_reduced_motion_and_a_new_floor_put_the_camera_there_at_once():
	stage.reduced_motion = true
	stage.use_map(map_of(HALL))
	stage.place(2, 4, 0, 0.0)
	stage.place(2, 3, 0, 10.0)
	ok(not stage.moving(), "no easing with reduced motion")
	ok(stage.camera.transform.origin.is_equal_approx(Stage3D.pose_of(2, 3, 0).pos))
	stage.reduced_motion = false
	stage.use_map(map_of(HALL)) # another floor
	stage.place(2, 1, 2, 20.0)
	ok(not stage.moving(), "a new floor: no easing from the last one")


func test_a_bump_lunges_at_the_wall_and_springs_back():
	stage.use_map(map_of(HALL))
	stage.place(2, 1, 0, 0.0)
	var rest := stage.camera.transform.origin
	stage.bump(100.0)
	stage.place(2, 1, 0, 100.0 + Juice.TRANSITION_MS.bump / 2.0)
	ok((stage.camera.transform.origin - rest).dot(Vector3.FORWARD) > 0.2, "lunged forward")
	stage.place(2, 1, 0, 100.0 + Juice.TRANSITION_MS.bump + 1.0)
	ok(stage.camera.transform.origin.is_equal_approx(rest), "back")


func test_a_fight_backs_the_camera_into_the_open_cell_behind_and_looks_down():
	stage.reduced_motion = true
	stage.use_map(map_of(HALL))
	stage.place(2, 3, 0, 0.0, 1)
	var behind: Vector3 = Dungeon3D.cell_center(2, 3) - Vector3(stage.camera.transform.origin.x, 0, stage.camera.transform.origin.z)
	near(behind.dot(Vector3.FORWARD), Stage3D.FIGHT_BACK, 1e-5)
	near(stage.fight_distance(), Stage3D.FIGHT_DEPTH, 1e-5)
	ok(_fwd().y < -0.05, "the battle camera looks down a little")
	stage.place(2, 3, 0, 0.0, 0)
	near(_fwd().y, 0.0, 1e-5, "and level again after")


func test_with_a_wall_behind_the_monsters_stand_ahead_and_boxed_in_they_come_near_and_small():
	stage.reduced_motion = true
	stage.use_map(map_of(HALL))
	stage.place(2, 5, 0, 0.0, 1) # the south end: a wall behind, the hall ahead
	near(stage.back_of(2, 5, 0, true), Stage3D.FIGHT_BACK_SHUT, 1e-6)
	near(stage.fight_distance(), Stage3D.FIGHT_DEPTH, 1e-6, "they stand in the next cell")
	stage.use_map(map_of(["#####", "#...#", "#####"]))
	stage.place(2, 1, 0, 0.0, 1) # facing a wall with a wall behind
	var d := stage.fight_distance()
	near(d, Stage3D.FIGHT_BACK_SHUT + Stage3D.FIGHT_AHEAD, 1e-6)
	var place := stage.fight_place(Art.SLOTS[1][0])
	near(place.scale, d / Stage3D.FIGHT_DEPTH, 1e-6, "scaled to look as big as at FIGHT_DEPTH")
	near(stage.camera.transform.origin.y, Stage3D.EYE_H * d / Stage3D.FIGHT_DEPTH, 1e-6, "and the camera lowered with them")


func test_monsters_show_where_their_slots_are_and_stay_inside_the_corridor():
	stage.reduced_motion = true
	stage.use_map(map_of(HALL))
	for n in [1, 2, 3]:
		stage.place(2, 3, 0, 0.0, n)
		for slot in Art.SLOTS[n]:
			var place := stage.fight_place(slot)
			var middle: float = Dungeon3D.cell_center(2, 3).x
			ok(absf(place.pos.x - middle) <= Stage3D.FIGHT_SIDE_ROOM + 1e-5, "inside the corridor (%d at %s)" % [n, place.pos])
			near(place.pos.y, 0.0, 1e-6, "on the floor")
			var seen := stage.project(place.pos + Vector3(0, 0.6 * place.scale, 0))
			near(seen.x, slot.cx, 24.0, "%d monsters: shows near x = %s" % [n, slot.cx])
			ok(seen.y > 30.0 and seen.y < 288.0, "on screen, below the names (%s)" % seen)
		var d: Array = Art.SLOTS[n].map(func(s): return stage.fight_place(s).pos.distance_to(Vector3(stage.camera.transform.origin.x, 0, stage.camera.transform.origin.z)))
		if n == 3:
			ok(d[0] < d[1] and d[2] < d[1], "three stand in a V, the middle one farthest")


func test_fight_models_are_kept_by_id_and_cleared_after():
	stage.reduced_motion = true
	stage.use_map(map_of(HALL))
	stage.place(2, 3, 0, 0.0, 2)
	stage.set_fight_visible(true)
	var list := [
		{"id": "a", "species": "slime", "look": {"shiny": false}, "slot": Art.SLOTS[2][0], "hurt": 0.0},
		{"id": "b", "species": "goblin", "look": {"shiny": false}, "slot": Art.SLOTS[2][1], "hurt": 1.0},
	]
	var lit := stage._lit.size()
	stage.show_fight(list, 100.0)
	eq(stage._fighters.size(), 2)
	eq(stage._lit.size(), lit + 2, "each takes the shared light")
	var first: Node3D = stage._fighters.values()[0]
	stage.show_fight(list, 200.0)
	ok(stage._fighters.values()[0] == first, "the same model next frame")
	stage.show_fight(list.slice(1), 300.0)
	eq(stage._fighters.size(), 1, "one left")
	stage.set_fight_visible(false)
	eq(stage._fighters.size(), 0)
	eq(stage._lit.size(), lit, "and their materials let go")


func test_the_champion_waits_in_its_cell_facing_you_until_it_is_overcome():
	stage.reduced_motion = true
	var boss := {"x": 2, "y": 1, "species": "dragon", "defeated": false}
	stage.use_map(map_of(HALL, {"boss": boss}))
	stage.place(2, 4, 0, 0.0)
	stage.show_champion(boss, 0.0)
	var model: Node3D = stage._boss
	ok(model != null and model.visible)
	ok(model.position.is_equal_approx(Dungeon3D.cell_center(2, 1)))
	var front := model.transform.basis.z.normalized()
	ok(front.dot(Vector3(0, 0, 1)) > 0.99, "turned toward you (%s)" % front)
	stage.place(2, 1, 0, 0.0)
	stage.show_champion(boss, 0.0)
	ok(not model.visible, "not while you stand in its cell")
	boss.defeated = true
	stage.show_champion(boss, 0.0)
	ok(stage._boss == null, "gone once overcome")


func test_the_nearest_torches_light_the_set():
	var rows := ["#########", "#.......#", "#.#.#.#.#", "#.......#", "#.#.#.#.#", "#.......#", "#########"]
	var map := map_of(rows, {"seed": 5})
	stage.use_map(map)
	stage.place(1, 1, 1, 0.0)
	stage.light(0.0)
	var arr: PackedVector4Array = stage._shared.torches
	eq(arr.size(), Stage3D.MAX_TORCHES)
	var lit := 0
	for v in arr:
		if v.w > 0.0:
			lit += 1
			ok(v.w > 0.7 and v.w <= 1.0, "a flicker, not out (%s)" % v.w)
	eq(lit, mini(Stage3D.MAX_TORCHES, stage.torches().filter(func(t): return t.pos.distance_to(stage.camera.transform.origin) < 10.0).size()))
	ok(stage._shared.has("lantern_offset"), "the lantern hangs off the camera")
	var late := stage.monster_material()
	eq(late.get_shader_parameter("torches"), arr, "a material made later gets the light too")


func test_the_title_is_a_lit_corridor_and_the_map_builds_once():
	stage.title(0.0)
	ok(stage._map == Stage3D.title_map())
	ok(not stage.use_map(Stage3D.title_map()), "already built")
	ok(stage.torches().size() > 0, "torches in the title hall")
	var a := stage.camera.transform
	stage.title(1700.0)
	ok(not stage.camera.transform.is_equal_approx(a), "the camera breathes")
	ok(stage._set_root.get_child_count() >= 3, "walls, floor and ceiling")
