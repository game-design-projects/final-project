## The 3D set: the floor's walls, the stairs, every monster still on the floor, and a camera that follows the party. It only
## reads the game's state; it never changes it. Everything is black surfaces with lines (see view/shaders), drawn into a
## small SubViewport and shown through the post-processing pass. Walls hide what stands behind them: the depth buffer decides
## what shows, so nothing pops in or out as you turn. Fights are the flat battle screen, with the set hidden behind it.
##
## Moving eases: when the party's cell or facing changes, the camera glides (a step) or swings (a turn) to its new spot in a
## fixed time, and `bump` lunges it at a wall and back. A new floor, or a change made while the set is hidden, puts it there
## at once.
extends Node3D

const Decor = preload("res://src/view/decor.gd")
const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Materials = preload("res://src/view/materials.gd")
const MonsterModel = preload("res://src/view/monster_model.gd")
const Content = preload("res://src/rules/content.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")
const SecretProps = preload("res://src/view/secret_props.gd")
const Requests = preload("res://src/rules/requests.gd")
const Roaming = preload("res://src/rules/roaming.gd")
const Vision = preload("res://src/rules/vision.gd")

const CELL := Materials.CELL
const SLAB_H := 0.03
const FOV := 68.0
const EYE := 0.85 # camera height
const STEP_MS := 150.0 # how long the camera takes over a step, a turn, and a lunge at a wall and back
const TURN_MS := 170.0
const BUMP_MS := 140.0
const LUNGE := 0.28 # how far the lunge goes, in world units
const CALM_LUNGE := 0.35 # the share of it left with the `calm` setting
const FLASH_S := 0.25
# the name tags: real 3D text the same size on screen near or far, over the model's real top
const TAG_FONT_PX := 16
const TAG_PIXEL_SIZE := 0.00234 # with fixed_size and this FOV, 16 font pixels come out 8 view pixels tall: whole, so nearest stays sharp
const TAG_GAP := 0.12 # above the head
const TAG_FADE_S := 0.12 # how long a tag takes to come and go
const TRADER_LOOK := "bandit" # the model the trader wears, in gold
const WALK_SNAP := 1.5 # a model further than this many cells from its monster goes there at once: nothing walks that far in a step
const MARK_AHEAD := 0.75 # how far before a monster its arrow lies
const MARK_Y := 0.03 # just over the floor
const STIR_TURN := 1.6 # how fast something stirring goes round, in radians a second
# the torches nearest the camera glow on the walls; each flickers on its own, in steps like the flames drawn on them
const MAX_TORCHES := 10 # as in shaders/wire.gdshader
const TORCH_REACH2 := 100.0 # world units, squared
const FLICKER_FPS := 12.0

var palette := {}
var calm := false # the `calm` setting: a softer lunge
var _decor: Node3D
var _torches: Array = [] # {"pos": Vector3, "seed": float}, the floor's
var _wall_mat: ShaderMaterial
var _flicker_key := []

var _camera: Camera3D
var _dungeon: MeshInstance3D
var _stairs: MeshInstance3D
var _stairs_slab: MeshInstance3D
var _models := {} # Monster -> Node3D
var _marks := {} # Monster -> the arrow on the floor for the way it last went, since its model always faces you
var _tags := {} # Monster -> Label3D
var _tag_light := {} # Monster -> 0..1, how far its tag has come in
var _tag_key := []
var _floor_map = null
var _like_sprite := false # the models take the shape of the fight sprites (sprite-look)
var _floor_changes := 0 # the walls broken on it when it was built
var _secrets: Node3D
var _secrets_built := -1 # how many chests and items it was built with
var _trader: Node3D
var _trader_tag: Label3D
var _quester: Node3D
var _quester_tag: Label3D
var _stirs := {} # Monster -> Node3D, what you see of it while it lurks
var _pos := Vector3.ZERO
var _yaw := 0.0
var _yaw_goal := 0.0 # where the camera is turning to, counted past a full circle so a held key keeps it turning one way
var _facing := 0 # the heading the goal was last set for
var _cell := Vector2i.ZERO # the cell the goal was last set for
var _turns := 0 # the game's count of quarter turns the goal has been moved for
var _spin := -1 # which way the last quarter turn went (-1 right, 1 left), for a half turn that could go either
var _glide = null # {from_pos, from_yaw, t0, ms}: the move under way, or null
var _now := 0.0
var _bump_at := -1000.0
var _hit_at := {} # Monster -> seconds when it was last hit


func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = env
	add_child(world)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.near = 0.05
	_camera.far = 60.0
	add_child(_camera)
	_camera.make_current()


## The monster was hit: light it up for a moment.
func flash_foe(monster, now: float) -> void:
	_hit_at[monster] = now


## You walked into a wall: the camera lunges at it and springs back.
func bump(now: float) -> void:
	_bump_at = now


## Whether the camera is still on its way somewhere (a step, a turn, a lunge); a held key waits for it.
func moving() -> bool:
	return _glide != null or (_now - _bump_at) * 1000.0 < BUMP_MS


## Where a world point lands in the view, in view pixels (for 2D drawn over the 3D, like name tags).
func project(world_pos: Vector3, view_size: Vector2) -> Vector2:
	var p := _camera.unproject_position(world_pos)
	return p * view_size / Vector2(get_viewport().size)


## Bring the set in line with the game: the floor, the camera, the monsters. `now` is seconds.
func update(state, now: float, dt: float) -> void:
	if state.floor_map == null:
		return
	_like_sprite = state.viewing("sprite-look")
	if state.floor_map != _floor_map or state.floor_map.changes != _floor_changes:
		_load_floor(state)
	if state.floor_map.treasure.size() + state.floor_map.pickups.size() != _secrets_built:
		_build_secrets()
	_now = now
	_move_camera(state, now)
	if is_visible_in_tree():
		_flicker(now)
		_show_monsters(state, now, dt)


## The torches nearest the camera glow on the walls this frame; worked out again only when one could have changed.
func _flicker(now: float) -> void:
	var step := floorf(now * FLICKER_FPS)
	var key := [step, _pos]
	if key == _flicker_key:
		return
	_flicker_key = key
	var near := []
	for t in _torches:
		var d: float = t.pos.distance_squared_to(_pos)
		if d < TORCH_REACH2:
			near.append([d, t])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var lit := PackedVector4Array()
	for i in MAX_TORCHES:
		if i < near.size():
			var t: Dictionary = near[i][1]
			var f: float = 0.88 + 0.12 * sin(step * 1.7 + t.seed * 40.0) * sin(step * 0.9 + t.seed * 17.0)
			lit.append(Vector4(t.pos.x, t.pos.y, t.pos.z, f))
		else:
			lit.append(Vector4.ZERO)
	_wall_mat.set_shader_parameter("torches", lit)


func _load_floor(state) -> void:
	var t0 := Time.get_ticks_usec()
	_floor_map = state.floor_map
	_floor_changes = _floor_map.changes
	palette = Palette.for_run(state.palette_id)
	if _dungeon != null:
		_dungeon.queue_free()
		_stairs.queue_free()
		_decor.queue_free()
	for m in _models:
		_models[m].queue_free()
		_tags[m].queue_free()
	for m in _marks:
		_marks[m].queue_free()
	_marks = {}
	for m in _stirs:
		_stirs[m].queue_free()
	_stirs = {}
	_models = {}
	_tags = {}
	_tag_light = {}
	_tag_key = []
	_flicker_key = []
	_dungeon = MeshInstance3D.new()
	_wall_mat = Materials.wire(0, palette.wall, palette.accent)
	_dungeon.mesh = DungeonMesh.build(_floor_map, _wall_mat, Materials.wire(1, palette.wall, palette.accent))
	add_child(_dungeon)
	_torches = []
	_decor = Decor.build(_floor_map, palette.wall, palette.accent, _torches)
	add_child(_decor)
	_stairs = MeshInstance3D.new()
	_stairs.mesh = DungeonMesh.stairwell(palette.accent)
	_stairs.material_override = Materials.prop()
	_stairs.position = DungeonMesh.center(_floor_map.stairs)
	add_child(_stairs)
	if _stairs_slab != null:
		_stairs_slab.queue_free()
	_stairs_slab = _slab(palette.accent)
	_stairs_slab.position = DungeonMesh.center(_floor_map.stairs) + Vector3(0.0, SLAB_H / 2.0, 0.0)
	add_child(_stairs_slab)
	_build_secrets()
	_build_trader()
	var target := _camera_target(state.cell, state.facing)
	_pos = target.pos
	_yaw = target.yaw
	_yaw_goal = target.yaw
	_facing = state.facing
	_turns = state.quarter_turns
	_cell = state.cell
	_glide = null
	_apply_camera()
	print("stage: built the %dx%d floor, %d torches, in %d ms" % [_floor_map.size, _floor_map.size, _torches.size(), (Time.get_ticks_usec() - t0) / 1000])


func _build_secrets() -> void:
	if _secrets != null:
		_secrets.queue_free()
	_secrets = SecretProps.build(_floor_map, palette.wall, palette.accent)
	add_child(_secrets)
	_secrets_built = _floor_map.treasure.size() + _floor_map.pickups.size()


## The trader and whoever is asking: figures that turn to you, not monsters to fight, with a name shown while a line reaches them.
func _build_trader() -> void:
	for old in [_trader, _quester]:
		if old != null:
			old.queue_free()
	_trader = null
	_quester = null
	if not _floor_map.merchant.is_empty():
		_trader = _figure(TRADER_LOOK, Palette.MERCY, _floor_map.merchant.cell)
		_trader_tag = _name_tag("TRADER", Palette.MERCY, MonsterModel.top_of(_trader))
		_trader.add_child(_trader_tag)
	if not _floor_map.quester.is_empty():
		_quester = _figure(_floor_map.quester.species, Palette.YOU, _floor_map.quester.cell)
		_quester_tag = _name_tag(str(Requests.table().tag), Palette.YOU, MonsterModel.top_of(_quester))
		_quester.add_child(_quester_tag)


func _figure(look: String, color: Color, cell: Vector2i) -> Node3D:
	var out := MonsterModel.build(look, color, _like_sprite)
	out.position = DungeonMesh.center(cell)
	add_child(out)
	return out


## A name over something, drawn over walls: it is shown only while a line reaches what it names.
func _name_tag(text: String, color: Color, top: float) -> Label3D:
	var tag := Label3D.new()
	tag.text = text
	tag.font = Fonts.title()
	tag.font_size = TAG_FONT_PX
	tag.pixel_size = TAG_PIXEL_SIZE
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.shaded = false
	tag.no_depth_test = true
	tag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tag.outline_size = 0
	tag.modulate = color
	tag.position = Vector3(0.0, top + TAG_GAP, 0.0)
	return tag


## Where the camera stands and looks from a cell.
func _camera_target(cell: Vector2i, facing: int) -> Dictionary:
	var fwd := Vector3(FloorMap.DIRS[facing].x, 0.0, FloorMap.DIRS[facing].y)
	return {
		"pos": DungeonMesh.center(cell) - fwd * CELL * Vision.back + Vector3(0.0, EYE, 0.0),
		"yaw": -facing * PI / 2.0,
	}


func _move_camera(state, now: float) -> void:
	var target := _camera_target(state.cell, state.facing)
	var stepped: bool = state.cell != _cell
	var jumped: bool = absi(state.cell.x - _cell.x) + absi(state.cell.y - _cell.y) > 1 # a pad: there is no gliding across the floor
	var turned: bool = state.quarter_turns != _turns or state.facing != _facing
	if stepped or turned:
		_turn_goal(state.facing, state.quarter_turns)
		_cell = state.cell
		if is_visible_in_tree() and not jumped:
			_glide = {"from_pos": _pos, "from_yaw": _yaw, "t0": now, "ms": STEP_MS if stepped else TURN_MS}
		else:
			_glide = null
	if _glide != null:
		var p: float = (now - _glide.t0) * 1000.0 / _glide.ms
		if p >= 1.0 or p < 0.0:
			_glide = null
		else:
			var e := 1.0 - pow(1.0 - p, 3.0)
			_pos = _glide.from_pos.lerp(target.pos, e)
			_yaw = lerpf(_glide.from_yaw, _yaw_goal, e)
	if _glide == null:
		_pos = target.pos
		_yaw = _yaw_goal
	_apply_camera()


## Each quarter turn since the last frame moves the goal on by a quarter in the same direction, so holding a turn key
## spins on and on. (Taking the shortest way to the heading, which is what lerp_angle does, flips between left and
## right as soon as the key runs ahead of the camera: the view shakes instead of turning.) The turns are counted by the
## game (`quarter_turns`), because the heading alone, mod 4, cannot say which way three turns in one slow frame went. What
## is left, such as the fight camera swinging round to the foe, takes the short way. The goal never gets more than a full
## circle ahead, so letting go does not leave the camera winding down a long spin.
func _turn_goal(facing: int, turns: int) -> void:
	var made := turns - _turns
	_turns = turns
	if made != 0:
		_yaw_goal -= made * PI / 2.0
		_spin = -signi(made)
		_facing = posmod(_facing + made, 4)
	match posmod(facing - _facing, 4):
		1:
			_yaw_goal -= PI / 2.0
			_spin = -1
		3:
			_yaw_goal += PI / 2.0
			_spin = 1
		2:
			_yaw_goal += _spin * PI
	_facing = facing
	while _yaw_goal - _yaw > TAU:
		_yaw_goal -= TAU
	while _yaw_goal - _yaw < -TAU:
		_yaw_goal += TAU


func _apply_camera() -> void:
	var lunge := 0.0
	var p := (_now - _bump_at) * 1000.0 / BUMP_MS
	if p >= 0.0 and p < 1.0:
		lunge = sin(PI * p) * LUNGE * (CALM_LUNGE if calm else 1.0)
	_camera.position = _pos + Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * lunge
	_camera.rotation = Vector3(0.0, _yaw, 0.0)


## Every monster still on the floor stands in its cell, turned toward the camera, with a name tag; walls hide them. Not
## while you stand in its cell too (a test put you there): it would be in the camera's face.
## What a monster standing on the stairs stands on: a slab over the pit, gone once the way is clear (the feature boss-at-exit).
static func _slab(color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(DungeonMesh.CELL, SLAB_H, DungeonMesh.CELL)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = color.darkened(0.82)
	box.material = look
	var out := MeshInstance3D.new()
	out.mesh = box
	out.visible = false
	return out


func _show_monsters(state, now: float, dt: float) -> void:
	_drop_the_replaced(state.floor_map)
	if _trader != null:
		_show_figure(_trader, _trader_tag, state.floor_map, state.floor_map.merchant.cell, now)
	if _quester != null:
		_quester.visible = not state.floor_map.quester.is_empty()
		if _quester.visible:
			_show_figure(_quester, _quester_tag, state.floor_map, state.floor_map.quester.cell, now)
	_stairs_slab.visible = state.floor_map.monster_at(state.floor_map.stairs) != null
	for m in state.floor_map.monsters:
		var here: bool = not m.is_gone() and m.cell != state.cell
		_show_stir(m, here and m.lurking, state.floor_map, now)
		if not here or m.lurking:
			if _models.has(m):
				_models[m].visible = false
				_tags[m].visible = false
				_tag_light[m] = 0.0
			if _marks.has(m):
				_marks[m].visible = false
			continue
		if not _models.has(m):
			_add_monster(m)
		var model: Node3D = _models[m]
		model.visible = true
		_walk_model(m, model, dt)
		var to_camera := _camera.position - model.position
		model.rotation.y = atan2(to_camera.x, to_camera.z)
		var since: float = now - _hit_at.get(m, -10.0)
		MonsterModel.flash(model, clampf(1.0 - since / FLASH_S, 0.0, 1.0))
		MonsterModel.pose(model, now, clampf(1.0 - since / 0.4, 0.0, 1.0))
	_show_tags(state, dt)


## A fight tried again has a fresh monster in the list (Encounter.retry_fight): the one it replaced must not go on standing there.
func _drop_the_replaced(f) -> void:
	if _models.keys().all(func(m): return f.monsters.has(m)):
		return
	for m in _models.keys():
		if not f.monsters.has(m):
			_models[m].queue_free()
			_tags[m].queue_free()
			_models.erase(m)
			_tags.erase(m)
			if _marks.has(m):
				_marks[m].queue_free()
				_marks.erase(m)
			_tag_light.erase(m)
			_tag_key = []


## The arrow on the floor at a monster's feet, pointing the way it went.
func _mark_heading(m, way: Vector3) -> void:
	if not _marks.has(m):
		var shape := SurfaceTool.new()
		shape.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in [Vector3(-0.28, 0, 0), Vector3(0, 0, 0.3), Vector3(0, 0, 0.1), Vector3(0, 0, 0.1), Vector3(0, 0, 0.3), Vector3(0.28, 0, 0)]:
			shape.add_vertex(p)
		var look := StandardMaterial3D.new()
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.cull_mode = BaseMaterial3D.CULL_DISABLED
		look.albedo_color = Palette.monster(m)
		var mark := MeshInstance3D.new()
		mark.mesh = shape.commit()
		mark.material_override = look
		add_child(mark)
		_marks[m] = mark
	_marks[m].rotation.y = atan2(way.x, way.z)


## A model goes where its monster has gone at the pace you walk, with its name over it; a hunter's name says so.
func _walk_model(m, model: Node3D, dt: float) -> void:
	var tag: Label3D = _tags[m]
	var goal := DungeonMesh.center(m.cell)
	if model.position != goal:
		var far := model.position.distance_to(goal) > CELL * WALK_SNAP
		if not far:
			_mark_heading(m, (goal - model.position).normalized())
		model.position = goal if far else model.position.move_toward(goal, dt * CELL * 1000.0 / STEP_MS)
		tag.position = Vector3(model.position.x, tag.position.y, model.position.z)
	if _marks.has(m):
		var mark: MeshInstance3D = _marks[m]
		mark.visible = true
		mark.position = model.position + mark.basis.z * MARK_AHEAD + Vector3.UP * MARK_Y
	var word: String = str(Roaming.table().tag) if m.hunting else _plain_tag(m)
	if tag.text != word:
		tag.text = word
		var look: Color = Palette.WARN if m.hunting else Palette.monster(m)
		tag.modulate = Color(look, tag.modulate.a)
		_tag_key = []


func _show_figure(figure: Node3D, tag: Label3D, f, cell: Vector2i, now: float) -> void:
	var to_you := _camera.position - figure.position
	figure.rotation.y = atan2(to_you.x, to_you.z)
	MonsterModel.pose(figure, now, 0.0)
	tag.visible = Vision.sees_body(f, Vector2(_pos.x / CELL + 0.5, _pos.z / CELL + 0.5), cell)


## Something stirring goes round and round where it waits, until you walk into it.
func _show_stir(m, showing: bool, f, now: float) -> void:
	if not showing:
		if _stirs.has(m):
			_stirs[m].visible = false
		return
	if not _stirs.has(m):
		var made := SecretProps.stir(Palette.STIR)
		made.position = DungeonMesh.center(m.cell)
		made.add_child(_name_tag(str(Content.table("npcs").lurkers.tag), Palette.STIR, SecretProps.STIR_HEIGHT + TAG_GAP))
		add_child(made)
		_stirs[m] = made
	var stir: Node3D = _stirs[m]
	stir.visible = true
	stir.rotation.y = now * STIR_TURN
	stir.get_child(0).visible = Vision.sees_body(f, Vector2(_pos.x / CELL + 0.5, _pos.z / CELL + 0.5), m.cell)


func _add_monster(m) -> void:
	var model := MonsterModel.build(m.species, Palette.monster(m), _like_sprite)
	model.position = DungeonMesh.center(m.cell)
	add_child(model)
	_models[m] = model
	var tag := Label3D.new()
	tag.text = _plain_tag(m)
	tag.font = Fonts.title()
	tag.font_size = TAG_FONT_PX
	tag.pixel_size = TAG_PIXEL_SIZE
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.shaded = false
	tag.double_sided = true
	tag.no_depth_test = true # a wall's edge must not slice the name in two; it is hidden when no line reaches its monster
	tag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tag.outline_size = 0
	tag.modulate = Palette.monster(m)
	tag.position = model.position + Vector3(0.0, MonsterModel.top_of(model) + TAG_GAP, 0.0)
	add_child(tag)
	_tags[m] = tag
	_tag_light[m] = 0.0
	tag.set_meta("wanted", false)


static func _plain_tag(m) -> String:
	return "CHAMPION" if m.boss else str(Content.table("encounter").genres[m.genre].name)


## Which tags show: its monster is in a straight line of open floor from the camera, and it doesn't overlap a nearer tag. The
## tags then ease in and out and fade with distance, like the lines.
func _show_tags(state, dt: float) -> void:
	var key := [_pos, _yaw, state.floor_map.monsters_left(), state.floor_map.steps]
	if key != _tag_key:
		_tag_key = key
		_pick_tags(state)
	for m in _tags:
		var tag: Label3D = _tags[m]
		if m.is_gone() or m.cell == state.cell:
			continue
		var light: float = move_toward(_tag_light[m], 1.0 if tag.get_meta("wanted") else 0.0, dt / TAG_FADE_S)
		_tag_light[m] = light
		var d: float = _pos.distance_to(_models[m].position) / CELL
		tag.modulate.a = clampf(1.15 - maxf(0.0, d - 0.43) * 0.16, 0.35, 1.0) * light
		tag.visible = light > 0.0


func _pick_tags(state) -> void:
	var from := Vector2(_pos.x / CELL + 0.5, _pos.z / CELL + 0.5) # the camera on the floor plan
	var order := _tags.keys()
	order.sort_custom(func(a, b): return _tags[a].position.distance_squared_to(_pos) < _tags[b].position.distance_squared_to(_pos))
	var placed := []
	for m in order:
		var tag: Label3D = _tags[m]
		tag.set_meta("wanted", false)
		if m.is_gone() or m.cell == state.cell or _camera.is_position_behind(tag.position) or not Vision.sees_body(state.floor_map, from, m.cell):
			continue
		var at := project(tag.position, Vector2(get_viewport().size))
		var rect := Rect2(at.x - tag.text.length() * 4.0, at.y - 8.0, tag.text.length() * 8.0, 8.0).grow(5.0)
		if not placed.any(func(r): return r.intersects(rect)):
			placed.append(rect)
			tag.set_meta("wanted", true)
