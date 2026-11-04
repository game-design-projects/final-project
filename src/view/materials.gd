## Makes the materials the picture uses. The shaders are in view/shaders/.
extends RefCounted

const CELL := 2.0 # world units per cell, the same as the dungeon mesh
const MONSTER_LINE := 2.5 # line widths, in the view's pixels
const PROP_LINE := 1.5
const MONSTER_FADE_FLOOR := 0.55 # the dimmest a monster's lines get, so one down a long corridor still shows
const WALL_FADE_FLOOR := 0.15

static var _wire_shader: Shader = preload("res://src/view/shaders/wire.gdshader")
static var _solid_shader: Shader = preload("res://src/view/shaders/solid.gdshader")
static var _ink_shader: Shader = preload("res://src/view/shaders/ink.gdshader")
static var _flame_shader: Shader = preload("res://src/view/shaders/flame.gdshader")


## A dungeon surface: `kind` 0 is walls (lines at the edges, torches glowing in `accent` on them), 1 is floor and ceiling
## (plain black).
static func wire(kind: int, line_color: Color, accent: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _wire_shader
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("line_color", Vector3(line_color.r, line_color.g, line_color.b))
	m.set_shader_parameter("torch_color", Vector3(accent.r, accent.g, accent.b))
	m.set_shader_parameter("cell", CELL)
	return m


## The surface of a mesh built with mesh_kit.gd: black inside, outlined in its vertex colours, `ink_px` of the view's pixels
## wide; its lines fade with distance down to `fade_floor`. Each call makes a new material, so a hit can light one model alone.
static func model(ink_px := MONSTER_LINE, fade_floor := MONSTER_FADE_FLOOR) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _solid_shader
	m.set_shader_parameter("fade_floor", fade_floor)
	m.set_shader_parameter("cell", CELL)
	var ink := ShaderMaterial.new()
	ink.shader = _ink_shader
	ink.set_shader_parameter("ink_px", ink_px)
	ink.set_shader_parameter("fade_floor", fade_floor)
	ink.set_shader_parameter("cell", CELL)
	m.next_pass = ink
	return m


## The surface of the things on the floor and the walls: finer lines than a monster's, which fade as far as the walls do.
static func prop() -> ShaderMaterial:
	return model(PROP_LINE, WALL_FADE_FLOOR)


## Torch flames in `accent`.
static func flame(accent: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _flame_shader
	m.set_shader_parameter("accent", Vector3(accent.r, accent.g, accent.b))
	return m
