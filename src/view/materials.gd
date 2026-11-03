## Makes the materials the picture uses. The shaders are in view/shaders/.
extends RefCounted

const CELL := 2.0 # world units per cell, the same as the dungeon mesh

static var _wire_shader: Shader = preload("res://src/view/shaders/wire.gdshader")
static var _solid_shader: Shader = preload("res://src/view/shaders/solid.gdshader")
static var _ink_shader: Shader = preload("res://src/view/shaders/ink.gdshader")


## A dungeon surface: `kind` 0 is walls (lines at the edges), 1 is floor and ceiling (plain black).
static func wire(kind: int, line_color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _wire_shader
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("line_color", Vector3(line_color.r, line_color.g, line_color.b))
	m.set_shader_parameter("cell", CELL)
	return m


## A model's surface: black inside, outlined in `tint`. `flat_color` draws the part solid instead (pupils, slits).
static func model(tint: Color, flat_color := false, no_outline := false) -> ShaderMaterial:
	var v := Vector3(tint.r, tint.g, tint.b)
	var m := ShaderMaterial.new()
	m.shader = _solid_shader
	m.set_shader_parameter("tint", v)
	m.set_shader_parameter("flat_color", flat_color)
	m.set_shader_parameter("cell", CELL)
	if not no_outline and not flat_color:
		var ink := ShaderMaterial.new()
		ink.shader = _ink_shader
		ink.set_shader_parameter("tint", v)
		ink.set_shader_parameter("cell", CELL)
		m.next_pass = ink
	return m
