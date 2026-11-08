## The drawn art: atlases made by tools/art/process.py and described in data/sprites.json. A figure has actions, each a row of frames; any
## other sheet has named drawings. Everything here only says where things are; figure.gd, wall_art.gd and battle_art.gd draw them.
extends RefCounted

const Content = preload("res://src/rules/content.gd")

static var _textures := {}


static func sheet(name: String) -> Dictionary:
	return Content.table("sprites").get(name, {})


static func has(name: String) -> bool:
	return Content.table("sprites").has(name)


static func texture(name: String) -> Texture2D:
	if not _textures.has(name):
		_textures[name] = load(str(sheet(name).file))
		print_verbose("sprites: loaded %s" % name)
	return _textures[name]


static func action(name: String, act: String) -> Dictionary:
	return sheet(name).anims.get(act, {})


static func has_action(name: String, act: String) -> bool:
	return sheet(name).get("anims", {}).has(act)


## Where a figure's frame is in its atlas, in atlas pixels.
static func frame_rect(name: String, act: String, i: int) -> Rect2:
	var s := sheet(name)
	var pad := float(s.pad)
	var cell := Vector2(s.cell[0], s.cell[1])
	return Rect2(Vector2(pad + i * (cell.x + pad), pad + int(s.anims[act].row) * (cell.y + pad)), cell)


## Where a named drawing is in its atlas, in atlas pixels.
static func drawing_rect(name: String, drawing: String) -> Rect2:
	var s := sheet(name)
	var i: int = s.frames.find(drawing)
	if i < 0:
		push_error("sprites: %s has no drawing '%s'" % [name, drawing])
		i = 0
	var pad := float(s.pad)
	var cell := Vector2(s.cell[0], s.cell[1])
	return Rect2(Vector2(pad + (i % int(s.cols)) * (cell.x + pad), pad + (i / int(s.cols)) * (cell.y + pad)), cell)


## Where a named drawing's ink is in its cell, in atlas pixels.
static func ink(name: String, drawing: String) -> Rect2:
	var b: Array = sheet(name).bounds[drawing]
	return Rect2(b[0], b[1], b[2], b[3])


## The same rect as a share of the atlas, for a shader: offset in x and y, size in z and w.
static func uv_rect(name: String, rect: Rect2) -> Vector4:
	var s := sheet(name)
	var size := Vector2(s.size[0], s.size[1])
	return Vector4(rect.position.x / size.x, rect.position.y / size.y, rect.size.x / size.x, rect.size.y / size.y)


## Where the feet are in a frame, from its top left, in atlas pixels.
static func feet(name: String) -> Vector2:
	var s := sheet(name)
	return Vector2(s.feet[0], s.feet[1])


## World units per atlas pixel: the body at rest stands `world_h` tall.
static func world_per_px(name: String) -> float:
	var s := sheet(name)
	return float(s.world_h) / float(s.body_h)
