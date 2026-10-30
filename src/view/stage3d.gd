## The view's 3D set (the cel-shaded, "3D drawn as 2D" look): the floor built by Dungeon3D, a camera where the
## party stands, the monsters of a fight standing in the corridor in front of you (Monsters3D), the floor's
## champion waiting in its cell, and the light every material shares (the lantern at the camera and the nearest
## torches, toon.gdshaderinc). view_canvas.gd owns one and calls it every frame before it paints the 2D layer
## (names, health bars, dice, floating numbers) on top.
##
## Moving eases: when the party's cell or facing changes, the camera glides (a step) or swings (a turn) to the new
## spot over Juice.TRANSITION_MS; `bump()` lunges it at the wall and back. A new floor, reduced motion, or the first
## frame put it there at once.
##
## `project(p)` turns a world point into the 448x288 view's coordinates, for 2D drawn over a 3D thing.
extends Node3D

const J = preload("res://src/core/js.gd")
const Render = preload("res://src/view/render.gd")
const Art = preload("res://src/view/art.gd")
const Juice = preload("res://src/rules/juice.gd")
const Dungeon3D = preload("res://src/view/dungeon3d.gd")
const Monsters3D = preload("res://src/view/monsters3d.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")

const STONE_SHADER = preload("res://src/view/stone.gdshader")
const TOON_SHADER = preload("res://src/view/toon.gdshader")
const INK_SHADER = preload("res://src/view/ink.gdshader")
const FLAME_SHADER = preload("res://src/view/flame.gdshader")

## The view's own size: what `project` measures in (the SubViewport may be a whole multiple of it)
const W := 448.0
const H := 288.0
## The camera: eye height, how far behind the middle of your cell it stands, its vertical field of view
const EYE_H := 1.15
const BACK := 0.85
const FOV := 60.0
## In a fight the camera backs into the cell behind you when it is open (FIGHT_BACK) and the monsters stand
## FIGHT_AHEAD in front of the middle of your cell, FIGHT_DEPTH from the camera. With a wall behind, the camera backs
## up to it (FIGHT_BACK_SHUT) and the monsters stand in the cell ahead instead, as far away; boxed in on both sides,
## they come nearer, scaled down so they still show the size they would at FIGHT_DEPTH.
const FIGHT_BACK := 1.75
const FIGHT_BACK_SHUT := 0.95
const FIGHT_AHEAD := 0.35
const FIGHT_DEPTH := 2.1
## How long the camera takes to back off when a fight starts, and to come back after
const FIGHT_MS := 320.0
## In a fight the camera also looks down a little, like a battle camera, so the monsters sit in the middle; more
## when a monster stands near, so that its feet stay FEET_MARGIN (degrees) above the bottom of the view
const FIGHT_PITCH := -7.0
const FEET_MARGIN := 3.0
## How far from the middle of the corridor a monster to the side may stand
const FIGHT_SIDE_ROOM := 0.8
const MAX_TORCHES := 10
## Torches flicker in steps, like the flames drawn on them
const FLICKER_FPS := 12.0

var camera: Camera3D
var reduced_motion := false

var _env: WorldEnvironment
var _set_root: Node3D
var _fight_root: Node3D
var _boss_root: Node3D
var _mats := {}
var _lit: Array[ShaderMaterial] = [] # every material that reads the shared light
var _shared := {} # the shared light's parameters as last set, for materials made later
var _map = null
var _built: Dictionary = {}
var _palette := {}
## Where the camera is headed ({x, y, dir, fight: how many monsters}) and the move under way to get there
var _goal = null
var _move = null # {from_pos, from_yaw, from_pitch, t0, ms}
var _bump_t0 := -1e12
var _pos := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _shake := Vector2.ZERO
## The models on stage: fight monsters by id, the champion
var _fighters := {}
var _boss = null


func _init() -> void:
	name = "Stage3D"
	_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.environment = env
	add_child(_env)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 40.0
	camera.current = true
	add_child(camera)
	_set_root = Node3D.new()
	_set_root.name = "Set"
	add_child(_set_root)
	_boss_root = Node3D.new()
	_boss_root.name = "Champion"
	add_child(_boss_root)
	_fight_root = Node3D.new()
	_fight_root.name = "Fight"
	add_child(_fight_root)
	_mats.walls = _material(STONE_SHADER, {"kind": 0})
	_mats.floor = _material(STONE_SHADER, {"kind": 1})
	_mats.ceiling = _material(STONE_SHADER, {"kind": 2})
	_mats.ink = _material(INK_SHADER)
	_mats.props = _material(TOON_SHADER)
	_mats.props.next_pass = _mats.ink
	_mats.flames = ShaderMaterial.new()
	_mats.flames.shader = FLAME_SHADER


func _material(shader: Shader, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	for k in params:
		m.set_shader_parameter(k, params[k])
	for k in _shared:
		m.set_shader_parameter(k, _shared[k])
	_lit.append(m)
	return m


# A parameter of the shared light, on every material that reads it (and on the ones made from now on)
func _share(key: String, value) -> void:
	_shared[key] = value
	for m in _lit:
		m.set_shader_parameter(key, value)


## A cel material for one monster (its own, so a hit can flash it alone), inked by the shared outline
func monster_material() -> ShaderMaterial:
	var m := _material(TOON_SHADER)
	m.next_pass = _mats.ink
	return m


# ---------------------------------------------------------------- the floor

## Builds the set for `map` unless it is the one on stage. Returns whether it built.
func use_map(map: Dictionary) -> bool:
	if is_same(map, _map):
		return false
	_map = map
	for c in _set_root.get_children():
		_set_root.remove_child(c)
		c.queue_free()
	var t0 := Time.get_ticks_usec()
	_built = Dungeon3D.build(map)
	for k in ["walls", "floor", "ceiling", "props", "flames"]:
		if _built[k] == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = k.capitalize()
		mi.mesh = _built[k]
		mi.material_override = _mats[k]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_root.add_child(mi)
	set_palette(J.nz(map.get("palette"), Render.PALETTES[0]))
	_goal = null
	print_verbose("stage3d: built %d wall faces, %d torches in %d ms" % [_built.faces, _built.torches.size(), (Time.get_ticks_usec() - t0) / 1000])
	return true


## The floor's colors on every material: stone from its wall color, light and flames from its accent
func set_palette(palette: Dictionary) -> void:
	_palette = palette
	var wall := Color.html(palette.wall)
	var accent := Color.html(palette.accent)
	var stone := wall.darkened(0.42)
	_mats.walls.set_shader_parameter("stone_color", stone)
	_mats.walls.set_shader_parameter("joint_color", stone.darkened(0.45))
	_mats.floor.set_shader_parameter("stone_color", wall.darkened(0.62))
	_mats.floor.set_shader_parameter("joint_color", wall.darkened(0.8))
	_mats.ceiling.set_shader_parameter("stone_color", wall.darkened(0.78))
	_mats.ceiling.set_shader_parameter("joint_color", wall.darkened(0.9))
	for k in ["walls", "floor", "ceiling"]:
		_mats[k].set_shader_parameter("ink_color", wall.darkened(0.93))
	_mats.flames.set_shader_parameter("accent", accent)
	_share("torch_color", accent)
	_share("lantern_color", Color(1.0, 0.94, 0.84).lerp(wall, 0.15))


## The camera pose for standing in (x, y) facing dir, `back` behind the middle of the cell
static func pose_of(x: int, y: int, dir: int, back := BACK) -> Dictionary:
	var pos := Dungeon3D.cell_center(x, y) - Dungeon3D.dir_vec(dir) * back + Vector3(0, EYE_H, 0)
	return {"pos": pos, "yaw": -dir * PI / 2.0, "pitch": 0.0}


func _open_toward(x: int, y: int, dir: int) -> bool:
	var d: Array = Render.DIRS[posmod(dir, 4)]
	return _map != null and Render._is_open(_map["grid"], x + d[0], y + d[1])


## How far the camera stands behind the middle of (x, y) facing dir: BACK exploring; in a fight, back into the cell
## behind if it is open
func back_of(x: int, y: int, dir: int, fight: bool) -> float:
	if not fight:
		return BACK
	return FIGHT_BACK if _open_toward(x, y, dir + 2) else FIGHT_BACK_SHUT


## The battle camera's pitch (radians) for `count` monsters: FIGHT_PITCH, or lower if the nearest one's feet need it
## (the front of a model stands nearer than its middle, hence the 0.8)
func fight_pitch(count: int) -> float:
	var near := fight_distance()
	for slot in Art.SLOTS[clampi(count, 1, 3)]:
		near = minf(near, _slot_distance(slot))
	var feet := rad_to_deg(atan(fight_eye() / (near * 0.8)))
	return deg_to_rad(minf(FIGHT_PITCH, FOV / 2.0 - FEET_MARGIN - feet))


## The battle camera's height: the eye's, lowered with the monsters' distance when they must stand near, so the
## shot is the usual one made smaller
func fight_eye() -> float:
	return EYE_H * fight_distance() / FIGHT_DEPTH


func _goal_pose() -> Dictionary:
	if _goal == null:
		return {"pos": _pos, "yaw": _yaw, "pitch": _pitch}
	var p := pose_of(_goal.x, _goal.y, _goal.dir, back_of(_goal.x, _goal.y, _goal.dir, _goal.fight > 0))
	if _goal.fight > 0:
		p.pitch = fight_pitch(_goal.fight)
		p.pos.y = fight_eye()
	return p


## The party is at (x, y) facing dir at time t (J.now_ms()), fighting `fight` monsters (0: exploring): the camera
## goes there, easing if it was elsewhere (a step, a turn, or backing off for a fight)
func place(x: int, y: int, dir: int, t: float, fight := 0) -> void:
	var goal := {"x": x, "y": y, "dir": dir, "fight": fight}
	if _goal == null or reduced_motion:
		_goal = goal
		_move = null
	elif goal != _goal:
		var ms: float = FIGHT_MS
		if goal.x != _goal.x or goal.y != _goal.y:
			ms = Juice.TRANSITION_MS.step
		elif goal.dir != _goal.dir:
			ms = Juice.TRANSITION_MS.turn
		_move = {"from_pos": _pos, "from_yaw": _yaw, "from_pitch": _pitch, "t0": t, "ms": ms}
		_goal = goal
	var to := _goal_pose()
	if _move != null:
		var p: float = (t - _move.t0) / _move.ms
		if p >= 1.0 or p < 0.0:
			_move = null
		else:
			var e := 1.0 - pow(1.0 - p, 3.0)
			_pos = _move.from_pos.lerp(to.pos, e)
			_yaw = lerp_angle(_move.from_yaw, to.yaw, e)
			_pitch = lerpf(_move.from_pitch, to.pitch, e)
	if _move == null:
		_pos = to.pos
		_yaw = to.yaw
		_pitch = to.pitch
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var lunge := 0.0
	var bp := (t - _bump_t0) / float(Juice.TRANSITION_MS.bump)
	if bp >= 0.0 and bp < 1.0 and not reduced_motion:
		lunge = sin(PI * bp) * 0.28
	camera.transform = Transform3D(Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch), _pos + fwd * lunge)
	camera.h_offset = _shake.x
	camera.v_offset = _shake.y


## Whether the camera is still on its way somewhere
func moving() -> bool:
	return _move != null


## You walked into a wall: the camera lunges at it and springs back
func bump(t: float) -> void:
	_bump_t0 = t


## The screen shake, in the view's pixels
func set_shake(px: float, py: float) -> void:
	var k := 2.0 * FIGHT_DEPTH * tan(deg_to_rad(FOV) / 2.0) / H # world units per pixel where the monsters stand
	_shake = Vector2(-px * k, py * k)


## The torches nearest the camera light the set this frame; each flickers on its own
func light(t: float) -> void:
	var cam := camera.global_transform.origin if camera.is_inside_tree() else camera.transform.origin
	var near := []
	for tor in _built.get("torches", []):
		var d: float = tor.pos.distance_squared_to(cam)
		if d < 100.0:
			near.append([d, tor])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var arr := PackedVector4Array()
	var ft := floorf(t * FLICKER_FPS / 1000.0)
	for i in MAX_TORCHES:
		if i < near.size():
			var tor: Dictionary = near[i][1]
			var f: float = 0.88 + 0.12 * sin(ft * 1.7 + tor.seed * 40.0) * sin(ft * 0.9 + tor.seed * 17.0)
			arr.append(Vector4(tor.pos.x, tor.pos.y, tor.pos.z, f))
		else:
			arr.append(Vector4.ZERO)
	# The lantern hangs up and to the left of the camera, so faces are shaded, not lit flat from the front
	var b := camera.transform.basis
	var hang := b.x * -0.9 + Vector3.UP * 0.6
	_share("torches", arr)
	_share("lantern_offset", hang)


## Where a world point lands in the 448x288 view (behind the camera: off the view)
func project(p: Vector3) -> Vector2:
	if camera.is_position_behind(p):
		return Vector2(-1000, -1000)
	var vp := camera.get_viewport()
	var scale := 1.0
	if vp != null:
		scale = vp.get_visible_rect().size.x / W
	return camera.unproject_position(p) / scale


# ---------------------------------------------------------------- the title

## The corridor behind the title card: a short hall lit by torches, the camera breathing a little
const TITLE_ROWS = [
	"#########",
	"#.......#",
	"####.####",
	"##.....##",
	"####.####",
	"####.####",
	"###...###",
	"####.####",
	"####.####",
	"#########",
]
const TITLE_SEED = 7
static var _title_map = null


static func title_map() -> Dictionary:
	if _title_map == null:
		var grid := []
		for r: String in TITLE_ROWS:
			var row := []
			for c in r:
				row.append(1 if c == "." else 0)
			grid.append(row)
		_title_map = {"grid": grid, "n": grid.size(), "stairs": {"x": 4, "y": 1}, "palette": Render.PALETTES[0], "seed": TITLE_SEED}
	return _title_map


func title(t: float) -> void:
	use_map(title_map())
	set_fight_visible(false)
	show_champion(null, t)
	var p := pose_of(4, 8, 0)
	_goal = {"x": 4, "y": 8, "dir": 0, "fight": 0}
	_move = null
	_pos = p.pos + Vector3(0, sin(t / 2100.0) * 0.03, 0)
	_yaw = p.yaw + sin(t / 3400.0) * 0.06
	_pitch = 0.0
	camera.transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)
	light(t)


# ---------------------------------------------------------------- who stands there

## How far the monster in the middle of a fight stands from the camera (once it has backed off)
func fight_distance() -> float:
	if _goal == null:
		return FIGHT_DEPTH
	if back_of(_goal.x, _goal.y, _goal.dir, true) == FIGHT_BACK or _open_toward(_goal.x, _goal.y, _goal.dir):
		return FIGHT_DEPTH
	return FIGHT_BACK_SHUT + FIGHT_AHEAD


# How far a monster in `slot` stands: the middle one at fight_distance, the outer ones of a V nearer
func _slot_distance(slot: Dictionary) -> float:
	var ndc: float = (float(slot.cx) - W / 2.0) / (W / 2.0)
	var d := fight_distance()
	if absf(ndc) > 0.01:
		d = minf(d, FIGHT_SIDE_ROOM / (absf(ndc) * tan(deg_to_rad(FOV) / 2.0) * (W / H)))
	return d


## Where a monster in `slot` ({cx, s}, Art.SLOTS) stands, and how big it is, so that it shows at slot.cx:
## {pos (on the floor), scale}. One stands in the middle; two or three stand in a V, the outer ones nearer the camera
## so that they keep inside the corridor (FIGHT_SIDE_ROOM from its middle) and still show where their slot is.
## Every one is scaled to its distance, so they show the size their slot asks for wherever they stand.
func fight_place(slot: Dictionary) -> Dictionary:
	var p := pose_of(_goal.x, _goal.y, _goal.dir, back_of(_goal.x, _goal.y, _goal.dir, true)) if _goal != null else {"pos": _pos, "yaw": _yaw}
	var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	var right := Vector3(cos(p.yaw), 0, -sin(p.yaw))
	var tan_w := tan(deg_to_rad(FOV) / 2.0) * (W / H)
	var ndc: float = (float(slot.cx) - W / 2.0) / (W / 2.0)
	var d := _slot_distance(slot)
	var ground: Vector3 = p.pos
	ground.y = 0.0
	return {"pos": ground + fwd * d + right * (ndc * d * tan_w), "scale": slot_scale(float(slot.s)) * d / FIGHT_DEPTH}


## A slot's size (Art.SLOTS: 1, 0.6 or 0.46 for one, two or three) as a model's: groups shrink less than the
## drawings did, since a model on its own leaves room around it
static func slot_scale(s: float) -> float:
	return 0.4 + 0.6 * s


## The spot on the floor where a monster in `slot` stands
func fight_spot(slot: Dictionary) -> Vector3:
	return fight_place(slot).pos


## The monsters of a fight: `list` is [{id, species, look, slot, hurt}], `t` the (hit-stopped) animation clock.
## Models are kept by id and rebuilt only when a monster's species or look changes.
func show_fight(list: Array, t: float) -> void:
	var keep := {}
	for e in list:
		var key := "%s|%s|%s" % [e.species, JSON.stringify(e.look), e.id]
		keep[key] = true
		var model = _fighters.get(key)
		if model == null:
			model = Monsters3D.build(e.species, e.look, monster_material())
			_fighters[key] = model
			_fight_root.add_child(model)
		var at := fight_place(e.slot)
		model.position = at.pos
		model.rotation = Vector3(0, _yaw_toward_camera(), 0)
		model.scale = Vector3.ONE * float(at.scale)
		Monsters3D.pose(model, t, float(e.get("hurt", 0.0)))
	for key in _fighters.keys():
		if not keep.has(key):
			_drop(_fighters[key])
			_fighters.erase(key)


# A model leaves the stage, and its material stops taking the shared light
func _drop(model: Node3D) -> void:
	_lit.erase(model.get_meta("material", null))
	model.queue_free()


func _yaw_toward_camera() -> float:
	return _goal_pose().yaw


## The floor's champion standing in its cell, turned toward you (null, or a fight under way: nobody). Not while you
## stand in its cell too (after running from it): it would be in the camera's face.
func show_champion(boss, t: float) -> void:
	if boss == null or J.truthy(boss.get("defeated")):
		if _boss != null:
			_drop(_boss)
			_boss = null
		return
	var key := "%s|%d,%d" % [boss.species, int(boss.x), int(boss.y)]
	if _boss == null or _boss.get_meta("key") != key:
		if _boss != null:
			_drop(_boss)
		_boss = Monsters3D.build(boss.species, {"color": Art.BOSS_COLOR}, monster_material())
		_boss.set_meta("key", key)
		_boss_root.add_child(_boss)
	_boss.visible = _goal == null or _goal.x != int(boss.x) or _goal.y != int(boss.y)
	var at := Dungeon3D.cell_center(boss.x, boss.y)
	_boss.position = at
	var to_cam := camera.transform.origin - at
	_boss.rotation = Vector3(0, atan2(to_cam.x, to_cam.z), 0)
	_boss.scale = Vector3.ONE * 0.92
	Monsters3D.pose(_boss, t, 0.0)


func set_fight_visible(on: bool) -> void:
	_fight_root.visible = on
	_boss_root.visible = not on
	if not on and not _fighters.is_empty():
		for key in _fighters:
			_drop(_fighters[key])
		_fighters.clear()


func torches() -> Array:
	return _built.get("torches", [])
