extends "res://tests/test_case.gd"

const Canvas2D = preload("res://src/view/canvas2d.gd")


class Probe:
	extends Node2D
	var drew := false
	var calls := Callable()

	func _draw() -> void:
		var ctx = Canvas2D.new(self)
		calls.call(ctx)
		drew = true


func _draw_with(fn: Callable) -> bool:
	var p := Probe.new()
	p.calls = fn
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	p.queue_redraw()
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	var drew := p.drew
	p.queue_free()
	return drew


func test_css_colors():
	eq(Canvas2D.css("#fff"), Color(1, 1, 1, 1))
	eq(Canvas2D.css("#ff000080").r, 1.0)
	near(Canvas2D.css("#ff000080").a, 128 / 255.0, 0.002)
	near(Canvas2D.css("rgba(255, 243, 176, 0.9)").a, 0.9, 0.001)
	near(Canvas2D.css("rgb(255,0,0)").r, 1.0, 0.001)
	near(Canvas2D.css("hsl(120, 100%, 50%)").g, 1.0, 0.001)
	eq(Canvas2D.css("transparent").a, 0.0)


func test_every_call_runs_in_draw():
	var ok_ := await _draw_with(func(ctx):
		ctx.save()
		ctx.translate(10, 10)
		ctx.scale(2, 2)
		ctx.rotate(0.3)
		ctx.global_alpha = 0.5
		ctx.begin_path()
		ctx.move_to(0, 0)
		ctx.line_to(20, 0)
		ctx.bezier_curve_to(20, 10, 10, 20, 0, 20)
		ctx.quadratic_curve_to(-5, 10, 0, 0)
		ctx.close_path()
		ctx.fill_style = "#ff0000"
		ctx.fill()
		ctx.stroke_style = "rgba(0,255,0,0.5)"
		ctx.line_width = 2
		ctx.shadow_blur = 8
		ctx.shadow_color = "#fff"
		ctx.stroke()
		ctx.restore()
		ctx.begin_path()
		ctx.arc(50, 50, 10, 0, TAU)
		var g = ctx.create_radial_gradient(50, 50, 0, 50, 50, 10)
		g.add_color_stop(0, "rgba(255,243,176,0.9)")
		g.add_color_stop(1, "rgba(255,243,176,0)")
		ctx.fill_style = g
		ctx.fill()
		var lg = ctx.create_linear_gradient(0, 0, 100, 0)
		lg.add_color_stop(0, "#000")
		lg.add_color_stop(1, "#fff")
		ctx.fill_style = lg
		ctx.fill_rect(0, 0, 100, 10)
		ctx.save()
		ctx.begin_path()
		ctx.rect(4, 4, 100, 100)
		ctx.clip()
		ctx.stroke_rect(0, 0, 200, 200)
		ctx.fill_rect(0, 0, 200, 200)
		ctx.restore()
		ctx.set_line_dash([4, 2])
		ctx.begin_path()
		ctx.move_to(0, 0)
		ctx.line_to(100, 0)
		ctx.stroke()
		ctx.set_line_dash([])
		ctx.font = "9px \"Press Start 2P\", monospace"
		ctx.text_align = "center"
		ctx.text_baseline = "middle"
		ctx.fill_text("HELLO", 50, 50)
		ctx.ellipse(224, 252, 104, 9, 0, 0, TAU)
		ctx.clear_rect(0, 0, 448, 288)
	)
	ok(ok_, "the draw callback ran")


func test_measure_text_scales_with_size():
	var widths := []
	await _draw_with(func(ctx):
		ctx.font = "8px \"Press Start 2P\", monospace"
		widths.append(ctx.measure_text("ABCD").width)
		ctx.font = "16px \"Press Start 2P\", monospace"
		widths.append(ctx.measure_text("ABCD").width)
	)
	eq(widths.size(), 2)
	near(widths[1], widths[0] * 2, 1.0, "Press Start 2P is 1em per glyph")
	near(widths[0], 32, 1.0)
