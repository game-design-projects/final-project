## A drawn figure standing in the set: a quad showing one frame of its atlas, its feet at the node's origin, which the stage turns to the
## camera. The same drawings fill the battle screen (battle_art.gd), so a monster looks the same in both. A Rig child carries what a body
## does (figure_anim.gd); it has the same shape as a wireframe model for the stage's sake.
extends Node3D

const FigureAnim = preload("res://src/view/figure_anim.gd")
const Materials = preload("res://src/view/materials.gd")
const Sprites = preload("res://src/view/sprites.gd")

const SHAKE_WORLD := 0.07

var anim: FigureAnim
var sheet := ""
var _material: ShaderMaterial
var _rig: Node3D
var _per_px := 1.0
var _shown := []


## A figure of `sheet_name` with its lines in `tint`.
static func make(sheet_name: String, tint: Color, seed_value := 0) -> Node3D:
	var out = new()
	out._build(sheet_name, tint, seed_value)
	return out


## A drawing that stands in the set and does nothing but turn to you: a chest, a sack. It has no action. `world_size` is how tall its ink is.
static func prop(sheet_name: String, drawing: String, tint: Color, world_size: float) -> Node3D:
	var out = new()
	out._build_prop(sheet_name, drawing, tint, world_size)
	return out


func _build(sheet_name: String, tint: Color, seed_value: int) -> void:
	sheet = sheet_name
	anim = FigureAnim.new(sheet_name, seed_value)
	_per_px = Sprites.world_per_px(sheet_name)
	var s := Sprites.sheet(sheet_name)
	var feet := Sprites.feet(sheet_name)
	var cell := Vector2(s.cell[0], s.cell[1])
	_add_quad(cell * _per_px, Vector3((cell.x / 2.0 - feet.x) * _per_px, (feet.y - cell.y / 2.0) * _per_px, 0.0), sheet_name, tint)
	set_meta("species", sheet_name)
	_show("idle", 0)


func _build_prop(sheet_name: String, drawing: String, tint: Color, world_size: float) -> void:
	sheet = sheet_name
	var s := Sprites.sheet(sheet_name)
	var cell := Vector2(s.cell[0], s.cell[1])
	var ink := Sprites.ink(sheet_name, drawing)
	_per_px = world_size / ink.size.y
	var mid := ink.get_center()
	_add_quad(cell * _per_px, Vector3((cell.x / 2.0 - mid.x) * _per_px, (ink.end.y - cell.y / 2.0) * _per_px, 0.0), sheet_name, tint)
	_material.set_shader_parameter("cell", Sprites.uv_rect(sheet_name, Sprites.drawing_rect(sheet_name, drawing)))


func _add_quad(size: Vector2, at: Vector3, sheet_name: String, tint: Color) -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_material = Materials.figure(sheet_name, tint)
	set_meta("material", _material)
	var quad := QuadMesh.new()
	quad.size = size
	var part := MeshInstance3D.new()
	part.name = "Body"
	part.mesh = quad
	part.material_override = _material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.position = at
	_rig.add_child(part)


func _show(act: String, frame: int) -> void:
	var key := [act, frame]
	if key == _shown:
		return
	_shown = key
	_material.set_shader_parameter("cell", Sprites.uv_rect(sheet, Sprites.frame_rect(sheet, act, frame)))


## Bring it up to time `now` (seconds).
func pose(now: float) -> void:
	var at: Dictionary = anim.tick(now)
	_show(at.act, at.frame)
	var body := float(Sprites.sheet(sheet).world_h)
	_rig.position = Vector3(float(at.shake) * SHAKE_WORLD, float(at.lift) * body, 0.0)
	_rig.scale = Vector3(at.sx, at.sy, 1.0)
	_rig.rotation.z = at.lean


## Light it up in its colour (a hit). 0 off .. 1 fully lit.
func flash(amount: float) -> void:
	_material.set_shader_parameter("flash", amount)


func set_fade(amount: float) -> void:
	_material.set_shader_parameter("fade_out", amount)


## How high a name over it should float: over what the drawing may raise above its head.
func top() -> float:
	return float(Sprites.sheet(sheet).feet[1]) * _per_px * 0.86
