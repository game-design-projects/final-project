## The last pass over the picture (see shaders/postfx.gdshader). Holds the shader material, the small SubViewport of its bloom
## (only while attached: the `crt` setting and the `nofx` flag take both away) and the short-lived effects: a red edge pulse
## when you are low on health, a red edge and a colour split when you are hit, a flash for a strike or a mercy. All of them
## decay here, per second, the pulse from each beat. With `calm` a hit splits no colours and the pulse holds still.
extends RefCounted

const SHADER: Shader = preload("res://src/view/shaders/postfx.gdshader")
const BLOOM_SHADER: Shader = preload("res://src/view/shaders/postfx_bloom.gdshader")

const HURT_DECAY := 3.2 # per second, as a share of what is left
const FLASH_DECAY := 6.0
const PULSE_DECAY := 3.5
const SPLIT_DECAY := 5.0
const SPLIT_BASE := 0.35 # the colour split always there, in picture pixels
const SPLIT_HIT := 2.2 # what a hit adds, up to
const SPLIT_MAX := 3.0
const CALM_PULSE := 0.5
const BLOOM_DIVISOR := 4 # the bloom picture is this many times smaller each way

var material := ShaderMaterial.new()
var calm := false

var _hurt := 0.0
var _split := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _pulse := 0.0
var _time := 0.0
var _rect: TextureRect
var _bloom_view: SubViewport
var _bloom_paint: ColorRect
var _bloom_material := ShaderMaterial.new()


func _init() -> void:
	material.shader = SHADER
	_bloom_material.shader = BLOOM_SHADER


## Put the effect on the TextureRect that shows the picture, with linear filtering (the shader reads the pixels sharply
## through it), and start the bloom's small viewport.
func attach(rect: TextureRect) -> void:
	detach()
	_rect = rect
	rect.material = material
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bloom_view = SubViewport.new()
	_bloom_view.name = "Bloom"
	_bloom_view.disable_3d = true
	_bloom_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bloom_paint = ColorRect.new()
	_bloom_paint.material = _bloom_material
	_bloom_view.add_child(_bloom_paint)
	rect.add_child(_bloom_view)
	_bloom_material.set_shader_parameter("src_tex", rect.texture)
	material.set_shader_parameter("bloom_tex", _bloom_view.get_texture())
	fit()
	print("postfx: on, bloom %s" % _bloom_view.size)


## The picture changed size: everything worked out from it follows.
func fit() -> void:
	if _rect == null:
		return
	var src: Vector2 = _rect.texture.get_size()
	var bloom := Vector2i(ceili(src.x / BLOOM_DIVISOR), ceili(src.y / BLOOM_DIVISOR))
	_bloom_view.size = bloom
	_bloom_paint.size = Vector2(bloom)
	_bloom_material.set_shader_parameter("src_size", src)
	material.set_shader_parameter("src_size", src)
	material.set_shader_parameter("bloom_size", Vector2(bloom))


## Back to the plain picture, pixels scaled as they are: the material comes off and the bloom's viewport goes away.
func detach() -> void:
	if _rect == null:
		return
	if is_instance_valid(_rect):
		_rect.material = null
		_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if is_instance_valid(_bloom_view):
		_bloom_view.queue_free()
	_rect = null
	_bloom_view = null
	_bloom_paint = null
	material.set_shader_parameter("bloom_tex", null)
	_bloom_material.set_shader_parameter("src_tex", null)
	print("postfx: off")


func attached() -> bool:
	return _rect != null


## 0 safe .. 1 about to die.
func set_danger(amount: float) -> void:
	material.set_shader_parameter("danger", clampf(amount, 0.0, 1.0))


## How warm the halls are, 0..1 (rules/warmth.gd); 1 leaves the colours alone.
func set_warmth(amount: float) -> void:
	material.set_shader_parameter("warmth", amount)


func set_accent(color: Color) -> void:
	material.set_shader_parameter("accent", Vector3(color.r, color.g, color.b))


func hurt() -> void:
	_hurt = 1.0
	if not calm:
		_split = minf(SPLIT_MAX, _split + SPLIT_HIT)


func flash(color: Color, strength: float) -> void:
	_flash_color = color
	_flash = maxf(_flash, strength)


func beat() -> void:
	_pulse = 1.0


func update(dt: float) -> void:
	_hurt *= exp(-HURT_DECAY * dt)
	_flash *= exp(-FLASH_DECAY * dt)
	_pulse *= exp(-PULSE_DECAY * dt)
	_split *= exp(-SPLIT_DECAY * dt)
	_time = fmod(_time + dt, 100.0)
	material.set_shader_parameter("hurt_level", _hurt)
	material.set_shader_parameter("split", SPLIT_BASE + _split)
	material.set_shader_parameter("pulse", CALM_PULSE if calm else _pulse)
	material.set_shader_parameter("flash", Vector4(_flash_color.r, _flash_color.g, _flash_color.b, _flash))
	material.set_shader_parameter("fx_time", _time)
