## The monster line art (art.js): placement, colors, and that every species draws with balanced state.
extends "res://tests/test_case.gd"

const Art = preload("res://src/view/art.gd")
const Species = preload("res://src/rules/species.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")

const ALL := ["slime", "goblin", "dragon", "snake", "rock", "bandit"]


## Records what the art asks of the context
class Rec:
	extends RefCounted
	var size := Vector2(448, 288)
	var depth := 0
	var min_depth := 0
	var strokes: Array = [] # [stroke_style, line_width]
	var fills := 0
	var translates: Array = []
	var scales: Array = []
	var fill_style = "#000"
	var stroke_style = "#000"
	var line_width := 1.0
	var line_join := "miter"

	func save() -> void:
		depth += 1

	func restore() -> void:
		depth -= 1
		min_depth = mini(min_depth, depth)

	func translate(x, y) -> void: translates.append([x, y])
	func scale(x, y) -> void: scales.append([x, y])
	func begin_path() -> void: pass
	func move_to(_x, _y) -> void: pass
	func line_to(_x, _y) -> void: pass
	func close_path() -> void: pass
	func bezier_curve_to(_a, _b, _c, _d, _e, _f) -> void: pass
	func arc(_x, _y, _r, _a0, _a1, _ccw := false) -> void: pass
	func ellipse(_x, _y, _rx, _ry, _rot, _a0, _a1, _ccw := false) -> void: pass
	func fill() -> void: fills += 1
	func stroke() -> void: strokes.append([stroke_style, line_width])


class Probe:
	extends Node2D
	var drew := false
	var species := "slime"
	var shiny := false

	func _draw() -> void:
		var ctx = Canvas2D.new(self, Vector2(448, 288))
		Art.draw_monster(ctx, species, 1234.0, 0.5, {"cx": 224, "s": 1}, 1, {"shiny": shiny})
		drew = true


func test_slots_place_one_two_or_three_monsters_with_aligned_feet():
	eq(Art.SLOTS[1], [{"cx": 224, "s": 1}])
	eq(Art.SLOTS[2], [{"cx": 116, "s": 0.6}, {"cx": 332, "s": 0.6}])
	eq(Art.SLOTS[3], [{"cx": 76, "s": 0.46}, {"cx": 224, "s": 0.46}, {"cx": 372, "s": 0.46}])
	eq(Art.SHINY_COLOR, "#f5b72a")
	eq(Art.BOSS_COLOR, "#ff2a2a")
	eq(Art.ART.pixel, 1)


func test_color_is_the_look_override_then_gold_when_shiny_then_the_species_color():
	for sp in ALL:
		eq(Art.color_of(sp), Species.SPECIES[sp].color)
		eq(Art.color_of(sp, {"shiny": true}), Art.SHINY_COLOR)
		eq(Art.color_of(sp, {"color": Art.BOSS_COLOR}), Art.BOSS_COLOR)
		eq(Art.color_of(sp, {"color": Art.BOSS_COLOR, "shiny": true}), Art.BOSS_COLOR, "an explicit color wins")


func test_every_species_draws_lines_in_its_color_with_balanced_state():
	for sp in ALL:
		var r := Rec.new()
		Art.draw_monster(r, sp, 500.0)
		ok(r.strokes.size() > 8, "%s draws many strokes (%d)" % [sp, r.strokes.size()])
		eq(r.depth, 0, "%s leaves save/restore balanced" % sp)
		eq(r.min_depth, 0, "%s never restores more than it saved" % sp)
		for s in r.strokes:
			eq(s[0], Species.SPECIES[sp].color, "%s stroke color" % sp)
			near(s[1], 2.0, 1e-9, "%s line width at full scale" % sp)
		ok(r.fills > 0, "%s has eyes or teeth to fill" % sp)


func test_the_slot_scales_the_monster_and_thins_less_than_it_shrinks():
	var r := Rec.new()
	Art.draw_monster(r, "goblin", 0.0, 0.0, Art.SLOTS[3][0])
	# 0.46 is below the 0.6 floor: the line is 2 / 0.6 wide before the scale makes it thinner
	near(r.strokes[0][1], 2.0 / 0.6, 1e-9)
	var s: float = Art.SLOTS[3][0].s
	ok(r.scales.has([s, s]))
	# feet stay on the bottom: y offset is 284 - 284 s, x offset puts the monster's middle (224) on cx
	near(r.translates[0][0], 76 - 224.0 * s, 1e-9)
	near(r.translates[0][1], 284 - 284.0 * s, 1e-9)
	var r2 := Rec.new()
	Art.draw_monster(r2, "goblin", 0.0, 0.0, {"cx": 224, "s": 0.9, "by": 144 + 140 * 0.9})
	near(r2.translates[0][1], 144 + 140 * 0.9 - 284 * 0.9, 1e-9, "slot.by lifts the feet")


func test_hurt_shakes_the_monster_sideways_and_shiny_adds_glints():
	var calm := Rec.new()
	Art.draw_monster(calm, "slime", 100.0, 0.0)
	var hit := Rec.new()
	Art.draw_monster(hit, "slime", 100.0, 1.0)
	eq(hit.translates.size(), calm.translates.size() + 1, "a hurt monster is nudged")
	near(hit.translates[1][0], sin(100.0 / 20.0) * 6.0, 1e-9)
	var plain := Rec.new()
	Art.draw_monster(plain, "dragon", 0.0)
	var shiny := Rec.new()
	Art.draw_monster(shiny, "dragon", 1700.0, 0.0, {"cx": 224, "s": 1}, 1, {"shiny": true})
	ok(shiny.strokes.size() > plain.strokes.size(), "glints are extra strokes")
	for s in shiny.strokes:
		eq(s[0], Art.SHINY_COLOR)


func test_pixel_above_one_still_draws_smooth_lines():
	var r := Rec.new()
	Art.draw_monster(r, "rock", 0.0, 0.0, {"cx": 224, "s": 1}, 3)
	ok(r.strokes.size() > 10)
	eq(r.depth, 0)


func test_every_species_draws_through_a_real_canvas2d():
	for sp in ALL:
		for shiny in [false, true]:
			var p := Probe.new()
			p.species = sp
			p.shiny = shiny
			(Engine.get_main_loop() as SceneTree).root.add_child(p)
			p.queue_redraw()
			await (Engine.get_main_loop() as SceneTree).process_frame
			await (Engine.get_main_loop() as SceneTree).process_frame
			ok(p.drew, "%s drew" % sp)
			p.queue_free()
