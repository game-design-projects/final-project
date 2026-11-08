## Makes the materials the picture uses. The shaders are in view/shaders/.
extends RefCounted

const Sprites = preload("res://src/view/sprites.gd")

const CELL := 2.0 # world units per cell, the same as the dungeon mesh
const MONSTER_LINE := 2.5 # line widths, in the view's pixels
const PROP_LINE := 1.5
const MONSTER_FADE_FLOOR := 0.55 # the dimmest a monster's lines get, so one down a long corridor still shows
const WALL_FADE_FLOOR := 0.15

static var _wire_shader: Shader = preload("res://src/view/shaders/wire.gdshader")
static var _solid_shader: Shader = preload("res://src/view/shaders/solid.gdshader")
static var _ink_shader: Shader = preload("res://src/view/shaders/ink.gdshader")
static var _flame_shader: Shader = preload("res://src/view/shaders/flame.gdshader")
static var _figure_shader: Shader = preload("res://src/view/shaders/figure.gdshader")
static var _wall_art_shader: Shader = preload("res://src/view/shaders/wall_art.gdshader")
static var _flame_drawn_shader: Shader = preload("res://src/view/shaders/flame_drawn.gdshader")


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


## A drawn figure (view/figure.gd): one frame of `sheet` with its line in `tint`. Each call makes a new material, so each shows its own frame.
static func figure(sheet: String, tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _figure_shader
	var s := Sprites.sheet(sheet)
	m.set_shader_parameter("sheet", Sprites.texture(sheet))
	m.set_shader_parameter("sheet_px", Vector2(s.size[0], s.size[1]))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("cell_size", CELL)
	m.set_shader_parameter("fade_floor", MONSTER_FADE_FLOOR)
	return m


## What is drawn on the walls (view/wall_art.gd).
static func wall_art() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _wall_art_shader
	m.set_shader_parameter("sheet", Sprites.texture("decor"))
	m.set_shader_parameter("cell_size", CELL)
	m.set_shader_parameter("fade_floor", WALL_FADE_FLOOR)
	return m


## A drawn torch flame in `accent`, with `eyes` as in shaders/flame_drawn.gdshader.
static func flame_drawn(accent: Color, eyes: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _flame_drawn_shader
	var s := Sprites.sheet("flame")
	var size := Vector2(s.size[0], s.size[1])
	m.set_shader_parameter("sheet", Sprites.texture("flame"))
	m.set_shader_parameter("accent", Vector3(accent.r, accent.g, accent.b))
	m.set_shader_parameter("grid", Vector2(s.cols, s.rows))
	m.set_shader_parameter("frame_uv", Vector2(s.cell[0], s.cell[1]) / size)
	m.set_shader_parameter("pad_uv", Vector2(s.pad, s.pad) / size)
	m.set_shader_parameter("eyes", eyes)
	return m
