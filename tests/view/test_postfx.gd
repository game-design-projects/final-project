## The post-processing controller (postfx.js): decay constants, hurt/flash/beat behaviour, the uniforms it pushes.
extends "res://tests/test_case.gd"

const Postfx = preload("res://src/view/postfx.gd")
const Flags = preload("res://src/core/flags.gd")


func uniform(post, name: String):
	return post.material.get_shader_parameter(name)


func test_the_fade_rates_are_the_js_ones():
	eq(Postfx.FX_DECAY, {"hurt": 3.2, "flash": 6.0, "pulse": 3.5, "split": 5.0})


func test_hex_colors_become_0_to_1_triples():
	var c := Postfx.PostFx.hex_rgb("#ffb347")
	near(c[0], 1.0)
	near(c[1], 0xb3 / 255.0)
	near(c[2], 0x47 / 255.0)
	eq(Postfx.PostFx.hex_rgb("ff2a2a"), [1.0, 0x2a / 255.0, 0x2a / 255.0], "the # is optional")
	eq(Postfx.PostFx.hex_rgb("#e8e2d055"), Postfx.PostFx.hex_rgb("#e8e2d0"), "only the first six digits count")


func test_hurt_adds_up_to_one_and_splits_the_colors_unless_motion_is_reduced():
	var post := Postfx.PostFx.new()
	post.hurt(0.45)
	near(post.hurt_level, 0.45)
	near(post.split_level, 0.99)
	post.hurt(0.8)
	eq(post.hurt_level, 1.0, "capped at 1")
	near(post.split_level, 0.99 + 2.2 * 0.8)
	post.hurt(0.8)
	eq(post.split_level, 3.0, "capped at 3")
	var calm := Postfx.PostFx.new({"reducedMotion": true})
	calm.hurt(1.0)
	eq(calm.hurt_level, 1.0)
	eq(calm.split_level, 0.0, "no color split with reduced motion")


func test_flash_keeps_the_strongest_and_is_softer_with_reduced_motion():
	var post := Postfx.PostFx.new()
	post.flash("#ffe03a", 0.2)
	post.flash("#ffffff", 0.1)
	near(post.flash_level, 0.2)
	eq(post.flash_color, [1.0, 1.0, 1.0], "the latest color shows")
	post.flash("#ff2a2a")
	near(post.flash_level, 0.35, 1e-9, "default strength")
	var calm := Postfx.PostFx.new({"reducedMotion": true})
	calm.flash("#ffffff", 0.5)
	near(calm.flash_level, 0.15)


func test_levels_ease_out_by_the_decay_rates_with_a_step_capped_at_a_tenth_of_a_second():
	var post := Postfx.PostFx.new()
	post.hurt(1.0)
	post.flash("#ffffff", 0.5)
	post.render(1000.0) # the first frame has no dt
	eq(post.hurt_level, 1.0)
	post.render(1050.0) # 50 ms
	near(post.hurt_level, exp(-3.2 * 0.05), 1e-9)
	near(post.flash_level, 0.5 * exp(-6.0 * 0.05), 1e-9)
	near(post.split_level, 2.2 * exp(-5.0 * 0.05), 1e-9)
	var before := post.hurt_level
	post.render(9000.0) # a long stall counts as 100 ms
	near(post.hurt_level, before * exp(-3.2 * 0.1), 1e-9)


func test_a_heartbeat_pulses_the_edge_when_its_time_comes():
	var post := Postfx.PostFx.new()
	post.render(0.0)
	post.beat(500.0)
	post.beat(900.0)
	post.render(400.0)
	eq(post.pulse_level, 0.0, "not yet")
	post.render(500.0)
	eq(post.pulse_level, 1.0, "the beat lands")
	eq(post.beats, [900.0], "and is used up")
	post.render(560.0)
	near(post.pulse_level, exp(-3.5 * 0.06), 1e-9)


func test_render_pushes_the_state_to_the_shader():
	var post := Postfx.PostFx.new()
	post.set_accent("#7fffd4")
	post.set_danger(0.8)
	post.hurt(0.5)
	post.flash("#ffe03a", 0.4)
	post.render(2500.0)
	var a: Vector3 = uniform(post, "accent")
	near(a.x, 0x7f / 255.0)
	near(a.y, 1.0)
	near(a.z, 0xd4 / 255.0)
	near(uniform(post, "danger"), 0.8)
	near(uniform(post, "hurt_level"), 0.5)
	near(uniform(post, "split"), 0.35 + 2.2 * 0.5, 1e-6)
	var f: Vector4 = uniform(post, "flash")
	near(f.w, 0.4, 1e-6)
	near(f.x, 1.0, 1e-6)
	near(uniform(post, "fx_time"), 2.5, 1e-9)
	near(uniform(post, "pulse"), 0.0)
	post.render(102500.0)
	near(uniform(post, "fx_time"), fmod(102.5, 100.0), 1e-9, "time wraps at 100 s")


func test_reduced_motion_holds_the_pulse_at_half():
	var post := Postfx.PostFx.new({"reducedMotion": true})
	post.render(0.0)
	near(uniform(post, "pulse"), 0.5)
	post.beat(10.0)
	post.render(20.0)
	near(uniform(post, "pulse"), 0.5, 1e-9, "no pulsing")


func test_the_view_and_bloom_sizes_are_pushed_for_the_448_by_288_view():
	var post := Postfx.PostFx.new()
	eq(uniform(post, "src_size"), Vector2(448, 288))
	eq(uniform(post, "bloom_size"), Vector2(112, 72), "a quarter of the view")
	post.set_output_size(Vector2(1120, 720))
	eq(uniform(post, "out_size"), Vector2(1120, 720))


func test_nofx_in_the_flags_means_no_post_processing():
	Flags.override = "debug nofx"
	var off := Postfx.PostFx.create()
	Flags.override = "debug"
	var on := Postfx.PostFx.create({"reducedMotion": false})
	Flags.override = null
	ok(off == null)
	ok(on != null)


func test_the_shaders_are_loaded():
	var post := Postfx.PostFx.new()
	ok(post.material.shader != null)
	ok(post.material.shader.code.contains("shader_type canvas_item"))
	ok(post.material.shader.code.contains("sharp("))
	ok(Postfx.BLOOM_SHADER.code.contains("bright_lin"))


func test_attach_puts_the_material_and_a_bloom_viewport_on_the_rect_and_detach_takes_them_off():
	var rect := TextureRect.new()
	var post := Postfx.PostFx.new()
	post.attach(rect)
	eq(rect.material, post.material)
	eq(rect.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "the shader needs linear filtering")
	eq(rect.get_child_count(), 1)
	var vp := rect.get_child(0) as SubViewport
	ok(vp != null)
	eq(vp.size, Vector2i(112, 72))
	eq(vp.render_target_update_mode, SubViewport.UPDATE_WHEN_PARENT_VISIBLE)
	ok(uniform(post, "bloom_tex") != null)
	post.detach()
	ok(rect.material == null)
	ok(uniform(post, "bloom_tex") == null)
	post.kill("test")
	eq(post.alive, false)
	post.render(0.0) # dead: does nothing
	rect.free()
