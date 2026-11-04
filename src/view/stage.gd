## The 3D set: the floor's walls, the stairs, the monsters, and a camera that follows the party. It only reads the game's
## state; it never changes it. Everything is black surfaces with lines (see view/shaders), drawn into a small
## SubViewport and shown through the post-processing pass.
extends Node3D

const Decor = preload("res://src/view/decor.gd")
const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Materials = preload("res://src/view/materials.gd")
const MonsterModel = preload("res://src/view/monster_model.gd")
const Content = preload("res://src/rules/content.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")
const Vision = preload("res://src/rules/vision.gd")

const CELL := Materials.CELL
const FOV := 68.0
const EYE := 0.85 # camera height while walking
const EYE_FIGHT := 1.1
const BACK_WALK := 0.38 # how far behind the middle of your cell the camera stands, in cells
const BACK_FIGHT := 0.85
const FIGHT_PITCH := -7.0 # degrees: look slightly down at the monster
const CAMERA_RATE := 9.0 # how fast the camera eases to where it should be (per second)
const FLASH_S := 0.25

const FIGHT_STAGES := ["intro", "menu", "act", "talk", "fightbar", "wait", "dodge", "dead"]

var palette := {}
var _decor: Node3D
var _glows: Array = [] # a MeshInstance3D per torch, flickering

var _camera: Camera3D
var _dungeon: MeshInstance3D
var _stairs: Node3D
var _models := {} # Monster -> Node3D
var _floor_map = null
var _pos := Vector3.ZERO
var _yaw := 0.0
var _yaw_goal := 0.0 # where the camera is turning to, counted past a full circle so a held key keeps it turning one way
var _facing := 0 # the heading the goal was last set for
var _spin := -1 # which way the last quarter turn went (-1 right, 1 left), for a half turn that could go either
var _pitch := 0.0
var _hit_at := {} # Monster -> seconds when it was last hit


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.near = 0.05
	_camera.far = 60.0
	add_child(_camera)
	_camera.make_current()


## The monster was hit: light it up for a moment.
func flash_foe(monster, now: float) -> void:
	_hit_at[monster] = now


## Where a world point lands in the view, in view pixels (for 2D drawn over the 3D, like name tags).
func project(world_pos: Vector3, view_size: Vector2) -> Vector2:
	var p := _camera.unproject_position(world_pos)
	return p * view_size / Vector2(get_viewport().size)


## Bring the set in line with the game: the floor, the camera, the monsters in view. `now` is seconds.
func update(state, now: float, dt: float) -> void:
	if state.floor_map == null:
		return
	if state.floor_map != _floor_map:
		_load_floor(state)
	_move_camera(state, dt)
	_flicker(now)
	_show_monsters(state, now)


## The name of the kind of fight, floating over a monster so you know what you are walking into.
func _genre_label(m) -> Label3D:
	var label := Label3D.new()
	label.text = "CHAMPION" if m.boss else Content.table("encounter").genres[m.genre].name
	label.font = Fonts.title()
	label.font_size = 24
	label.pixel_size = 0.0075
	label.modulate = Palette.monster(m)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = Vector3(0.0, 1.55, 0.0)
	return label


## The torch glows breathe, each on its own beat.
func _flicker(now: float) -> void:
	for i in _glows.size():
		var s := 1.0 + sin(now * 9.0 + i * 1.7) * 0.06 + sin(now * 23.0 + i * 4.1) * 0.04
		_glows[i].scale = Vector3(s, s, s)


func _load_floor(state) -> void:
	_floor_map = state.floor_map
	palette = Palette.for_floor(state.depth - 1)
	if _dungeon != null:
		_dungeon.queue_free()
		_stairs.queue_free()
		_decor.queue_free()
	for m in _models.values():
		m.queue_free()
	_models = {}
	_dungeon = MeshInstance3D.new()
	_dungeon.mesh = DungeonMesh.build(_floor_map, Materials.wire(0, palette.wall), Materials.wire(1, palette.wall))
	add_child(_dungeon)
	_glows = []
	_decor = Decor.build(_floor_map, palette.wall, palette.accent, _glows)
	add_child(_decor)
	_stairs = _build_stairs(palette.accent)
	_stairs.position = DungeonMesh.center(_floor_map.stairs)
	add_child(_stairs)
	var target := _camera_target(state)
	_pos = target.pos
	_yaw = target.yaw
	_yaw_goal = target.yaw
	_facing = target.facing
	_pitch = target.pitch
	_apply_camera()


## Three shrinking slabs: a stepped marker where the stairs are.
func _build_stairs(accent: Color) -> Node3D:
	var root := Node3D.new()
	var mat := Materials.model(accent)
	for i in 3:
		var size := 1.6 - i * 0.4
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(size, 0.07, size)
		slab.mesh = box
		slab.material_override = mat
		slab.position = Vector3(0, 0.04 + i * 0.07, 0)
		root.add_child(slab)
	return root


func _in_fight(state) -> bool:
	return state.foe != null and state.stage in FIGHT_STAGES


## Where the camera should stand and look: behind the middle of your cell while walking; pulled back, lower and
## looking down at the monster in a fight.
func _camera_target(state) -> Dictionary:
	var facing: int = state.facing
	var fight := _in_fight(state)
	if fight:
		for i in 4:
			if state.cell + FloorMap.DIRS[i] == state.foe.cell:
				facing = i
	var fwd := Vector3(FloorMap.DIRS[facing].x, 0.0, FloorMap.DIRS[facing].y)
	var back := BACK_WALK
	if fight:
		back = BACK_FIGHT if state.floor_map.is_open(state.cell - FloorMap.DIRS[facing]) else BACK_WALK
	var eye := EYE_FIGHT if fight else EYE
	return {
		"pos": DungeonMesh.center(state.cell) - fwd * CELL * back + Vector3(0.0, eye, 0.0),
		"facing": facing,
		"yaw": -facing * PI / 2.0,
		"pitch": deg_to_rad(FIGHT_PITCH) if fight else 0.0,
	}


func _move_camera(state, dt: float) -> void:
	var target := _camera_target(state)
	var k := 1.0 - exp(-CAMERA_RATE * dt)
	_pos = _pos.lerp(target.pos, k)
	_turn_goal(target.facing)
	_yaw = lerpf(_yaw, _yaw_goal, k)
	_pitch = lerpf(_pitch, target.pitch, k)
	_apply_camera()


## Each quarter turn since the last frame moves the goal on by a quarter in the same direction, so holding a turn key
## spins on and on. (Taking the shortest way to the heading, which is what lerp_angle does, flips between left and
## right as soon as the key runs ahead of the camera: the view shakes instead of turning.) The goal never gets more than
## a full circle ahead, so letting go does not leave the camera winding down a long spin.
func _turn_goal(facing: int) -> void:
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
	_camera.position = _pos
	_camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _show_monsters(state, now: float) -> void:
	var visible := {}
	if _in_fight(state):
		visible[state.foe] = true
	else:
		for m in Vision.monsters(state.floor_map, state.cell, state.facing):
			visible[m] = true
	for m in visible:
		if not _models.has(m):
			var model := MonsterModel.build(m.species, Palette.monster(m), m.boss)
			model.add_child(_genre_label(m))
			add_child(model)
			_models[m] = model
		var model: Node3D = _models[m]
		model.visible = true
		model.position = DungeonMesh.center(m.cell)
		var to_camera := _camera.position - model.position
		model.rotation.y = atan2(to_camera.x, to_camera.z)
		var since: float = now - _hit_at.get(m, -10.0)
		MonsterModel.flash(model, clampf(1.0 - since / FLASH_S, 0.0, 1.0))
		MonsterModel.pose(model, now, clampf(1.0 - since / 0.4, 0.0, 1.0))
	for m in _models:
		if not visible.has(m):
			_models[m].visible = false
