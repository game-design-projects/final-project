## The view's last pass (ported from crawler/public/postfx.js): a shader over the 448x288 view, shown at the
## screen's real resolution. Lines glow like phosphor on an old vector monitor (bloom), the pixels stay sharp
## instead of blurring when the view is scaled up, rows show faint scanlines, the edges fall off into the dark, and
## the floor's accent color tints the shadows. Game state drives it through a few numbers: a red pulse at the edges
## while the party is in danger (on the heartbeat), a red flash and a split of color when someone is hurt, a flash
## for a critical hit or a kill.
##
## That is the "vector" look, for the wireframe (Genre Halls). The game's cel-shaded 3D view uses the "cel" look
## (LOOKS): only flames and other glowing things bloom, and no scanlines.
##
## Setup (the ui): the view is a SubViewport (448x288, or a whole multiple) shown by a TextureRect scaled up. Call
##     var post = Postfx.PostFx.create({"reducedMotion": reduced, "look": "cel"})   # null with the `nofx` flag
##     if post: post.attach(view_rect)
## `attach` puts the material on the rect, switches the rect to linear filtering (the shader reads the texture with
## it) and adds the small SubViewport that holds the bloom. Then, every frame: `post.set_danger(d)`,
## `post.set_accent(hex)` when the floor changes, and `post.render(J.now_ms())`.
## Without `attach` (material set by hand) everything but the glow works.
##
## Passes per frame: the bloom viewport (112x72: the bright parts at half size, blurred across), then the rect's
## own composite at full size (blur down, tint, scanlines, edges).
extends RefCounted

const J = preload("res://src/core/js.gd")
const Flags = preload("res://src/core/flags.gd")

const POSTFX_SHADER = preload("res://src/view/postfx.gdshader")
const BLOOM_SHADER = preload("res://src/view/postfx_bloom.gdshader")

## How fast the effects fade, per second
const FX_DECAY = {"hurt": 3.2, "flash": 6.0, "pulse": 3.5, "split": 5.0}

## Two looks. "vector" is the wireframe's old vector monitor (Genre Halls): every line glows, scanlines run along
## the rows. "cel" is for the cel-shaded 3D view (the game): lit surfaces stop short of full brightness
## (toon.gdshaderinc EXPOSURE), so only what is near it glows (flames, eyes of fire, the dice), and there are no
## scanlines over the painted picture. `knee`: the bloom's soft knee; `gain`: how strongly the glow adds.
const LOOKS = {
	"vector": {"knee": Vector2(0.12, 0.7), "gain": 1.3, "scanlines": 0.07},
	"cel": {"knee": Vector2(0.84, 1.0), "gain": 0.9, "scanlines": 0.0},
}


class PostFx:
	extends RefCounted

	var reduced_motion := false
	var alive := true
	var material: ShaderMaterial
	var accent := [1.0, 0.7, 0.28]
	var danger := 0.0
	var hurt_level := 0.0
	var split_level := 0.0
	var pulse_level := 0.0
	var flash_color := [1.0, 1.0, 1.0]
	var flash_level := 0.0
	var beats: Array = [] # J.now_ms() times of upcoming heartbeats
	var last = null
	## The view's size in pixels (the SubViewport's), 448x288 unless attach finds another
	var src_size := Vector2(448, 288)

	var _rect: TextureRect
	var _bloom_vp: SubViewport
	var _bloom_rect: ColorRect
	var _bloom_material: ShaderMaterial
	var _out_size := Vector2.ZERO


	## `opts`: {"reducedMotion": bool, "look": "vector" (default) or "cel" (LOOKS)}
	func _init(opts := {}) -> void:
		reduced_motion = J.truthy(opts.get("reducedMotion", false))
		material = ShaderMaterial.new()
		material.shader = POSTFX_SHADER
		_bloom_material = ShaderMaterial.new()
		_bloom_material.shader = BLOOM_SHADER
		var look: Dictionary = LOOKS.get(opts.get("look", "vector"), LOOKS.vector)
		_bloom_material.set_shader_parameter("knee", look.knee)
		material.set_shader_parameter("bloom_gain", look.gain)
		material.set_shader_parameter("scanlines", look.scanlines)
		_push_sizes()


	## "#rrggbb" as [r, g, b] in 0..1
	static func hex_rgb(hex) -> Array:
		var n := str(hex).replace("#", "").left(6).hex_to_int()
		return [((n >> 16) & 255) / 255.0, ((n >> 8) & 255) / 255.0, (n & 255) / 255.0]


	## Null when effects are off (`nofx` in the flags): the plain view shows instead.
	static func create(opts := {}) -> PostFx:
		if Flags.test("nofx"):
			print_verbose("postfx off (nofx)")
			return null
		return PostFx.new(opts)


	## Put the effect on the TextureRect that shows the view (its texture is the SubViewport's).
	func attach(rect: TextureRect) -> void:
		detach()
		_rect = rect
		rect.material = material
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		alive = true
		if rect.texture != null:
			src_size = rect.texture.get_size()
		_bloom_vp = SubViewport.new()
		_bloom_vp.name = "PostFxBloom"
		_bloom_vp.disable_3d = true
		_bloom_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE # idle while the view is hidden
		_bloom_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_bloom_rect = ColorRect.new()
		_bloom_rect.material = _bloom_material
		_bloom_vp.add_child(_bloom_rect)
		rect.add_child(_bloom_vp)
		_bloom_material.set_shader_parameter("src_tex", rect.texture)
		material.set_shader_parameter("bloom_tex", _bloom_vp.get_texture())
		_push_sizes()


	## Back to the plain view: the material comes off the rect and the bloom viewport goes away.
	func detach() -> void:
		if _rect != null and is_instance_valid(_rect):
			_rect.material = null
		if _bloom_vp != null and is_instance_valid(_bloom_vp):
			_bloom_vp.queue_free()
		_rect = null
		_bloom_vp = null
		_bloom_rect = null
		material.set_shader_parameter("bloom_tex", null)


	func kill(why: String) -> void:
		if not alive:
			return
		alive = false
		push_warning("postfx: off (%s)" % why)
		detach()


	## The rect's size on screen in physical pixels, if the shader should not measure it by itself
	func set_output_size(size: Vector2) -> void:
		_out_size = size
		material.set_shader_parameter("out_size", size)


	# ---- what the game tells it

	func set_accent(hex) -> void:
		accent = hex_rgb(hex)


	func set_danger(x: float) -> void:
		danger = x


	func hurt(strength := 1.0) -> void:
		hurt_level = minf(1.0, hurt_level + strength)
		if not reduced_motion:
			split_level = minf(3.0, split_level + 2.2 * strength)


	func flash(hex, strength := 0.35) -> void:
		flash_color = hex_rgb(hex)
		flash_level = maxf(flash_level, strength * 0.3 if reduced_motion else strength)


	## A heartbeat lands at this J.now_ms() time (the audio clock's beat, converted): the red edge pulses with it
	func beat(at_ms: float) -> void:
		beats.append(at_ms)


	# ---- one frame

	## Eases the effects and pushes them to the shader. `now` is J.now_ms().
	func render(now: float) -> void:
		if not alive:
			return
		var dt := 0.0 if last == null else minf(0.1, (now - last) / 1000.0)
		last = now
		hurt_level = _decay(hurt_level, FX_DECAY.hurt, dt)
		split_level = _decay(split_level, FX_DECAY.split, dt)
		flash_level = _decay(flash_level, FX_DECAY.flash, dt)
		pulse_level = _decay(pulse_level, FX_DECAY.pulse, dt)
		if not beats.is_empty() and beats[0] <= now:
			beats = beats.filter(func(t): return t > now)
			pulse_level = 1.0
		if _rect != null and is_instance_valid(_rect):
			if _bloom_material.get_shader_parameter("src_tex") != _rect.texture:
				_bloom_material.set_shader_parameter("src_tex", _rect.texture)
			if _rect.texture != null and _rect.texture.get_size() != src_size:
				src_size = _rect.texture.get_size()
				_push_sizes()
		material.set_shader_parameter("accent", Vector3(accent[0], accent[1], accent[2]))
		material.set_shader_parameter("fx_time", fmod(now / 1000.0, 100.0))
		material.set_shader_parameter("danger", danger)
		material.set_shader_parameter("pulse", 0.5 if reduced_motion else pulse_level)
		material.set_shader_parameter("hurt_level", hurt_level)
		material.set_shader_parameter("flash", Vector4(flash_color[0], flash_color[1], flash_color[2], flash_level))
		material.set_shader_parameter("split", 0.35 + split_level)


	static func _decay(v: float, rate: float, dt: float) -> float:
		return v * exp(-rate * dt)


	func _push_sizes() -> void:
		var bloom := Vector2i(ceili(src_size.x / 4.0), ceili(src_size.y / 4.0))
		material.set_shader_parameter("src_size", src_size)
		material.set_shader_parameter("bloom_size", Vector2(bloom))
		_bloom_material.set_shader_parameter("src_size", src_size)
		if _bloom_vp != null:
			_bloom_vp.size = bloom
		if _bloom_rect != null:
			_bloom_rect.size = Vector2(bloom)
