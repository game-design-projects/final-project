## The last pass over the picture (see shaders/postfx.gdshader). Holds the shader material and the short-lived effects:
## a red edge pulse when you are low on health, a colour split when you are hit, a flash for a strike or a mercy.
extends RefCounted

const SHADER: Shader = preload("res://src/view/shaders/postfx.gdshader")

const HURT_DECAY := 3.0 # per second
const FLASH_DECAY := 5.0

var material := ShaderMaterial.new()

var _hurt := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE


func _init() -> void:
	material.shader = SHADER


## 0 safe .. 1 about to die.
func set_danger(amount: float) -> void:
	material.set_shader_parameter("danger", clampf(amount, 0.0, 1.0))


func set_accent(color: Color) -> void:
	material.set_shader_parameter("accent", Vector3(color.r, color.g, color.b))


func hurt() -> void:
	_hurt = 1.0


func flash(color: Color, strength: float) -> void:
	_flash_color = color
	_flash = strength


func beat() -> void:
	material.set_shader_parameter("pulse", 1.0)


func update(dt: float) -> void:
	_hurt = maxf(0.0, _hurt - HURT_DECAY * dt)
	_flash = maxf(0.0, _flash - FLASH_DECAY * dt)
	material.set_shader_parameter("hurt", _hurt)
	material.set_shader_parameter("flash", Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash))
