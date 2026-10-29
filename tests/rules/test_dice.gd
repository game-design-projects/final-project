## The die animation: frame timing, face flicker, shapes, and the pop store.
extends "res://tests/test_case.gd"

const Dice = preload("res://src/rules/dice.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")


## Draws inside a real _draw() through the Canvas2D adapter, so a wrong call or property fails the test.
class Probe:
	extends Node2D
	var calls := Callable()
	var drew := false

	func _draw() -> void:
		calls.call(Canvas2D.new(self, Vector2(448, 288)))
		drew = true


func _draw_with(fn: Callable) -> bool:
	var p := Probe.new()
	p.calls = fn
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(p)
	p.queue_redraw()
	await tree.process_frame
	await tree.process_frame
	var drew := p.drew
	p.queue_free()
	return drew


func _seeded(seed_: int) -> Callable:
	var state := [seed_]
	return func():
		state[0] = (state[0] * 16807) % 2147483647
		return state[0] / 2147483647.0


func test_the_whole_animation_is_200ms_130ms_of_tumbling_then_a_70ms_slam():
	eq(Dice.DIE_TUMBLE_MS, 130)
	eq(Dice.DIE_LAND_MS, 70)
	eq(Dice.DIE_ANIM_MS, 200)


func test_natural_20_and_natural_1_are_only_special_on_a_d20():
	eq(Dice.die_tier(20), "crit")
	eq(Dice.die_tier(1), "fumble")
	eq(Dice.die_tier(13), null)
	eq(Dice.die_tier(20, 20), "crit")
	eq(Dice.die_tier(8, 8), null)
	eq(Dice.die_tier(1, 6), null)


func test_face_sequence_flickers_randomly_and_ends_on_the_real_number():
	for seed_ in range(1, 201):
		var final := 1 + (seed_ % 20)
		var faces := Dice.face_sequence(final, 20, null, _seeded(seed_))
		eq(faces.size(), ceili(float(Dice.DIE_TUMBLE_MS) / Dice.FACE_MS) + 1)
		eq(faces[-1], final)
		ne(faces[-2], final, "the last flicker must differ so the number visibly lands")
		for i in faces.size():
			ok(faces[i] is int and faces[i] >= 1 and faces[i] <= 20)
			if i:
				ne(faces[i], faces[i - 1], "no repeated neighbours")
	# other dice stay on their own faces, even a two-sided one
	for sides in [4, 6, 8, 10, 12, 2]:
		ok(Dice.face_sequence(1, sides, 6, _seeded(sides)).all(func(f): return f >= 1 and f <= sides))
	eq(Dice.face_sequence(7).size(), 6, "the default rng and count")
	eq(Dice.face_sequence(7)[-1], 7)


func test_a_die_is_hidden_before_it_is_thrown_tumbles_for_130ms_then_lands():
	eq(Dice.die_frame(-1).show, false)
	var start := Dice.die_frame(0)
	ok(start.show and not start.landed and start.alpha == 1)
	ok(not Dice.die_frame(Dice.DIE_TUMBLE_MS - 1).landed)
	var slam := Dice.die_frame(Dice.DIE_TUMBLE_MS)
	ok(slam.landed)
	ok(slam.scale > 1.2, "the slam punches the scale up")
	ok(slam.flash > 0.9, "and flashes")
	var settled := Dice.die_frame(Dice.DIE_ANIM_MS)
	ok(settled.landed and settled.flash == 0 and settled.scale == 1)


func test_the_tumble_ends_upright_and_the_faces_advance_through_the_sequence():
	var end := Dice.die_frame(Dice.DIE_TUMBLE_MS - 0.001)
	var turns: float = end.rot / TAU
	ok(absf(turns - roundf(turns)) < 1e-3, "whole turns")
	var idx := [0, 30, 60, 90, 120].map(func(t): return Dice.die_frame(t).faceIdx)
	var sorted := idx.duplicate()
	sorted.sort()
	eq(idx, sorted)
	var distinct := {}
	for i in idx:
		distinct[i] = true
	ok(distinct.size() >= 4, "a new face every ~26ms")
	ok(Dice.die_frame(Dice.DIE_TUMBLE_MS - 1).faceIdx <= ceili(float(Dice.DIE_TUMBLE_MS) / Dice.FACE_MS) - 1)


func test_a_natural_20_slams_harder_and_glows_a_natural_1_shakes_and_cracks_both_linger_longer():
	var normal := Dice.die_frame(Dice.DIE_TUMBLE_MS, null)
	var crit := Dice.die_frame(Dice.DIE_TUMBLE_MS, "crit")
	var fumble := Dice.die_frame(Dice.DIE_TUMBLE_MS, "fumble")
	ok(crit.scale > normal.scale)
	ok(crit.glow > 0 and normal.glow == 0 and fumble.glow == 0)
	ok(fumble.shake > 0 and normal.shake == 0 and crit.shake == 0)
	ok(Dice.pop_life_ms("crit") > Dice.pop_life_ms(null) and Dice.pop_life_ms("fumble") > Dice.pop_life_ms(null))
	ok(Dice.die_frame(Dice.pop_life_ms(null) + 1, null).done)
	ok(not Dice.die_frame(Dice.pop_life_ms(null) + 1, "crit").done, "a crit is still on screen when a normal die has gone")
	ok(Dice.die_frame(Dice.pop_life_ms(null) - 10).alpha < 0.1, "fades out at the end")
	ok(Dice.die_frame(Dice.DIE_ANIM_MS + 100).alpha == 1)
	near(crit.flash, 1.0)
	ok(Dice.die_frame(Dice.DIE_ANIM_MS + 100, "crit").glow >= 0.3, "a crit keeps glowing while it is held")


func test_every_die_shape_is_a_closed_polygon_inside_the_unit_circle_with_finite_inner_lines():
	for sides in [4, 6, 8, 10, 12, 20, 7]:
		var shape := Dice.die_shape(sides)
		ok(shape.outline.size() >= 3, "d%d" % sides)
		for p in shape.outline:
			ok(Vector2(p[0], p[1]).length() <= 1.001)
		for e in shape.inner:
			eq(e.size(), 4)
			ok(e.all(func(v): return is_finite(v)))
	eq(Dice.die_shape(20).outline.size(), 6, "d20 is drawn as the classic hexagon")
	ok(Dice.die_shape(20).inner.size() >= 9, "with its inner triangle and spokes")
	eq(Dice.die_shape(4).outline.size(), 3)
	eq(Dice.die_shape(12).outline.size(), 5)
	eq(Dice.die_shape(12).inner.size(), 10)


func test_pops_are_drawn_and_expire_rolls_at_the_same_target_sit_side_by_side():
	var pops := Dice.DicePops.new()
	var a := pops.add({"x": 100, "y": 100, "rolls": [13], "now": 0, "rng": _seeded(1)})
	var b := pops.add({"x": 300, "y": 100, "rolls": [7, 16], "kept": 16, "now": 0, "rng": _seeded(2), "label": "=21"})
	eq(pops.size, 2)
	ok(await _draw_with(func(ctx):
		pops.draw(ctx, 50, {})
		pops.draw(ctx, 400, {"ink": "#fff", "hot": "#ff0"})))
	eq(pops.size, 2)
	# a second and third roll at the first one's target: neighbours, not a pile
	var c := pops.add({"x": 104, "y": 98, "rolls": [20], "now": 100, "rng": _seeded(3)})
	var d := pops.add({"x": 104, "y": 98, "rolls": [5], "now": 100, "rng": _seeded(4)})
	var xs := [a, c, d].map(func(p): return p.x)
	xs.sort()
	ok(xs[1] - xs[0] >= 48 and xs[2] - xs[1] >= 48, "spread out: %s" % [xs])
	ok(xs.all(func(x): return x > 20 and x < 428))
	eq(b.x, 300, "unrelated pops don't move")
	ok(await _draw_with(func(ctx): pops.draw(ctx, 100 + Dice.pop_life_ms("crit") + 1, {})))
	eq(pops.size, 0, "everything expires")


func test_with_no_room_left_a_new_roll_pushes_the_oldest_result_at_that_spot_out():
	var pops := Dice.DicePops.new(20)
	for i in 5:
		pops.add({"x": 224, "y": 100, "rolls": [i + 2], "now": 0, "rng": _seeded(i + 1)})
	var jammed := pops.add({"x": 224, "y": 100, "rolls": [9], "now": 600, "rng": _seeded(9)})
	eq(jammed.x, 224)
	ok(pops.pops[0].t0 <= 600 - Dice.DIE_ANIM_MS - 500, "an old pop at that spot jumped to its fade")


func test_advantage_throws_two_dice_and_keeps_the_right_one_the_pop_count_is_capped():
	var pops := Dice.DicePops.new(3)
	var p := pops.add({"x": 50, "y": 50, "rolls": [4, 18], "kept": 18, "now": 0, "rng": _seeded(5)})
	eq(p.dice.size(), 2)
	eq(p.dice.map(func(x): return x.kept), [false, true])
	eq(p.tier, null)
	for i in 6:
		pops.add({"x": 50 + i * 60, "y": 50, "rolls": [i + 1], "now": 0, "rng": _seeded(i + 1)})
	eq(pops.size, 3)
	var crit := pops.add({"x": 400, "y": 50, "rolls": [20, 3], "kept": 20, "now": 0})
	eq(crit.tier, "crit")
	eq(crit.dice[0].faces[-1], 20)
	eq(pops.add({"x": 10, "y": 200, "rolls": [11, 6]}).kept, 11, "kept defaults to the first roll")


func test_draw_die_paints_every_phase_for_every_tier_without_error():
	ok(await _draw_with(func(ctx):
		for tier in [null, "crit", "fumble"]:
			for age in [0, 40, 129, 130, 165, 199, 300, 900, 1200]:
				var frame := Dice.die_frame(age, tier)
				Dice.draw_die(ctx, {"x": 100, "y": 100, "face": 7, "frame": frame, "tier": tier, "label": "=12", "dim": age % 2 == 0})
		for sides in [4, 6, 8, 10, 12, 20, 3]:
			Dice.draw_die(ctx, {"x": 200, "y": 100, "r": 20, "sides": sides, "face": 12, "frame": Dice.die_frame(60), "ink": "#fff", "hot": "#ff0"})))


func test_land_punch_bumps_then_settles_within_200ms():
	eq(Dice.land_punch(-1), 1)
	near(Dice.land_punch(0, 0.5), 1.5, 1e-9)
	ok(Dice.land_punch(100, 0.5) < 1.5 and Dice.land_punch(100, 0.5) > 1)
	eq(Dice.land_punch(Dice.DIE_ANIM_MS), 1)
