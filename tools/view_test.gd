## Checks what the 3D view shows, with no window: which monsters are in view (down a corridor however far, across a hall,
## not behind a wall or behind you) and that holding a turn key keeps the camera turning one way. Prints one line per check
## and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/view_test.gd
extends "res://tools/test_base.gd"

const FloorGen = preload("res://src/rules/floor_gen.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Flow = preload("res://src/game/flow.gd")
const Flags = preload("res://src/utils/flags.gd")
const Minds = preload("res://src/mind/minds.gd")
const MonsterModel = preload("res://src/view/monster_model.gd")
const Rng = preload("res://src/utils/rng.gd")
const Vision = preload("res://src/rules/vision.gd")

const FRAME := 1.0 / 60.0

# FloorMap.DIRS: 0 north, 1 east, 2 south, 3 west
const EAST := 1
const SOUTH := 2

const FACE_MARGIN := 0.02 # how far in front of the body a face part must reach, in world units


## Stands in for a Monster where only its place matters.
class Standin:
	extends RefCounted
	var cell := Vector2i.ZERO
	var gone := ""

	func _init(at: Vector2i) -> void:
		cell = at

	func is_gone() -> bool:
		return gone != ""


func _name() -> String:
	return "view_test"


func _run() -> void:
	_sight_down_a_corridor()
	_sight_across_a_hall()
	_sight_on_real_floors()
	_faces_are_not_buried()
	await _camera_keeps_turning()
	await _stage_shows_what_vision_says()
	await _slow_frames_keep_the_direction()
	_finish()


## A floor from picture rows: `#` wall, anything else open.
func _floor(rows: Array) -> FloorMap:
	var f := FloorMap.new()
	f.size = rows.size()
	for row in rows:
		var cells := []
		for ch in String(row):
			cells.append(0 if ch == "#" else 1)
		f.grid.append(cells)
	return f


func _sight_down_a_corridor() -> void:
	var f := _floor(["##############", "#............#", "##############"])
	_check(Vision.ahead(f, Vector2i(1, 1), EAST).size() == 12, "the automap learns the whole corridor ahead, to the wall (12 cells, not a fixed few)")
	var far := Standin.new(Vector2i(11, 1))
	f.monsters = [far]
	_check(Vision.sees(f, Vector2i(1, 1), EAST, far.cell), "a monster ten cells down a straight corridor is in view")
	_check(not Vision.sees(f, Vector2i(11, 1), EAST, Vector2i(1, 1)), "one behind you is not")
	far.gone = "slain"
	_check(Vision.monsters(f, Vector2i(1, 1), EAST).is_empty(), "a monster that is gone is not in view")


func _sight_across_a_hall() -> void:
	var f := _floor(["#########", "#.......#", "#.......#", "#.......#", "#...#...#", "#.......#", "#########"])
	var from := Vector2i(1, 1)
	_check(Vision.sees(f, from, EAST, Vector2i(6, 3)), "a monster in another row of an open hall is in view (not only the one straight ahead)")
	_check(not Vision.sees(f, from, EAST, Vector2i(1, 3)), "one beside you is not in front of you")
	_check(not Vision.sees(f, Vector2i(1, 4), EAST, Vector2i(7, 4)), "a pillar hides what stands behind it")
	_check(not Vision.sees(f, from, EAST, from), "your own cell is not 'in view'")
	var corner := _floor(["#####", "#.#.#", "#.#.#", "#...#", "#####"])
	_check(not Vision.sees(corner, Vector2i(1, 3), EAST, Vector2i(3, 1)), "a wall corner on the line hides what is beyond it")
	var near := Standin.new(Vector2i(3, 1))
	var farther := Standin.new(Vector2i(6, 1))
	f.monsters = [farther, near]
	_check(Vision.monsters(f, from, EAST) == [near, farther], "the monsters in view come nearest first")


## In the champion's hall nothing is in the way: from any cell of it, facing the champion, it is in view.
func _sight_on_real_floors() -> void:
	var misses := 0
	var tried := 0
	var hidden_far := 0
	for seed_value in range(1, 31):
		var f = FloorGen.generate(Rng.new(seed_value))
		var boss = f.monsters.back()
		for dy in range(-FloorGen.HALL_RADIUS, FloorGen.HALL_RADIUS + 1):
			for dx in range(-FloorGen.HALL_RADIUS, FloorGen.HALL_RADIUS + 1):
				var c: Vector2i = boss.cell + Vector2i(dx, dy)
				for facing in 4:
					var d: Vector2i = boss.cell - c
					if d != Vector2i.ZERO and d.x * FloorMap.DIRS[facing].x + d.y * FloorMap.DIRS[facing].y > 0:
						tried += 1
						if not Vision.monsters(f, c, facing).has(boss):
							misses += 1
		# and down every corridor: the champion at any distance along a straight open line is seen
		for facing in 4:
			var run: Array = Vision.ahead(f, boss.cell, (facing + 2) % 4)
			if run.size() > 7 and not Vision.monsters(f, run.back(), facing).has(boss):
				hidden_far += 1
	_check(tried > 0 and misses == 0, "from every cell of the hall, facing the champion, it is in view (%d cases, %d missed)" % [tried, misses])
	_check(hidden_far == 0, "a champion more than six cells down a straight line is seen from its far end (%d unseen)" % hidden_far)


## A monster faces +Z. Every eye, mouth and crack (the solid-coloured parts) must stick out of the body in front of it by a
## little, or the body's black fill hides it and the monster looks faceless from the front.
func _faces_are_not_buried() -> void:
	for species in ["slime", "bandit", "snake", "rock", "dragon"]:
		var model: Node3D = MonsterModel.build(species, Color.WHITE)
		var parts := model.get_node("Body").get_children().filter(func(n): return n is MeshInstance3D)
		var buried := []
		var features := 0
		for part in parts:
			if not part.material_override.get_shader_parameter("flat_color"):
				continue
			features += 1
			var front: Vector3 = part.position + Vector3(0.0, 0.0, part.mesh.get_aabb().size.z * part.scale.z / 2.0)
			for other in parts:
				if other != part and not other.material_override.get_shader_parameter("flat_color") and _inside(other, front - Vector3(0.0, 0.0, FACE_MARGIN)):
					buried.append("%s at %s" % [part.mesh.get_class(), part.position])
					break
		_check(features > 0 and buried.is_empty(), "the %s's %d face parts all stand out of its body (buried: %s)" % [species, features, buried])
		model.free()


## Whether a point (in the model's space) is inside a part's box, ball or cone.
func _inside(part: MeshInstance3D, point: Vector3) -> bool:
	var q: Vector3 = part.transform.affine_inverse() * point
	var mesh: Mesh = part.mesh
	if mesh is SphereMesh:
		return q.length() < mesh.radius
	if mesh is BoxMesh:
		return absf(q.x) < mesh.size.x / 2.0 and absf(q.y) < mesh.size.y / 2.0 and absf(q.z) < mesh.size.z / 2.0
	if mesh is CylinderMesh:
		var t: float = q.y / mesh.height + 0.5
		return t > 0.0 and t < 1.0 and Vector2(q.x, q.z).length() < lerpf(mesh.bottom_radius, mesh.top_radius, t)
	return false


## A run on a given seed: the flow, ready to walk.
func _walk(seed_value: int):
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=%d" % seed_value]))
	var rng := Rng.new(seed_value)
	var flow = Flow.new(rng, Minds.create(rng))
	await flow.new_run()
	return flow


## The stage with a state, settled at its heading.
func _stage_for(state):
	var stage = load("res://src/view/stage.gd").new()
	root.add_child(stage)
	stage.update(state, 0.0, FRAME)
	return stage


func _angle_gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


## Holding RIGHT (or LEFT) sends a turn every other frame, faster than the camera swings: it keeps turning that way.
func _camera_keeps_turning() -> void:
	var flow = await _walk(3)
	var s = flow.state
	var stage = _stage_for(s)
	for side in [1, 3]: # right, then left
		var drift := 0.0 # the most the camera went the wrong way in a frame
		var last: float = stage._yaw
		var spun := 0.0
		for frame in 120:
			if frame % 2 == 0:
				s.turn(1 if side == 1 else -1)
			stage.update(s, frame * FRAME, FRAME)
			var step: float = stage._yaw - last
			spun += step
			drift = maxf(drift, step if side == 1 else -step) # right turns the yaw down, left turns it up
			last = stage._yaw
		var name := "right" if side == 1 else "left"
		_check(drift < 1e-6 and absf(spun) > TAU, "holding %s turns the camera one way all along (%.0f degrees, never back)" % [name, rad_to_deg(absf(spun))])
		for frame in 60: # let go: it settles on the heading within a second, not after winding down a long spin
			stage.update(s, frame * FRAME, FRAME)
		_check(_angle_gap(stage._yaw, -s.facing * PI / 2.0) < 0.05, "after letting go of %s the camera is on the heading within a second" % name)
	stage.free()


## The monsters the stage draws are the ones Vision says are in view.
func _stage_shows_what_vision_says() -> void:
	var flow = await _walk(11)
	var s = flow.state
	var boss = s.floor_map.monsters.back()
	var corner: Vector2i = boss.cell + Vector2i(-FloorGen.HALL_RADIUS, -FloorGen.HALL_RADIUS)
	s.cell = corner
	s.facing = EAST # the champion is two rows down and two cells along: not in the column ahead
	s.seen = {}
	s.look()
	_check(s.seen.has(boss.cell), "the automap knows where the champion stands once you see it across the hall")
	var stage = _stage_for(s)
	_check(stage._models.has(boss) and stage._models[boss].visible, "the champion across the hall is drawn, though it is not straight ahead")
	s.turn(-1) # north: it is behind you
	stage.update(s, 0.0, FRAME)
	_check(stage._models[boss].visible, "a turn does not drop the champion while the camera is still swinging past it")
	for frame in 60: # the camera swings round
		stage.update(s, frame * FRAME, FRAME)
	_check(not stage._models[boss].visible, "and it is not drawn once you face away from it and the camera is round")
	stage.free()


## Three turns that land in one frame (a slow frame, a key that repeats faster than the game draws) still turn the camera
## the way they went: the heading alone, mod 4, would read three right turns as one to the left.
func _slow_frames_keep_the_direction() -> void:
	var flow = await _walk(3)
	var s = flow.state
	var stage = _stage_for(s)
	var before: float = stage._yaw_goal
	s.turn(1)
	s.turn(1)
	s.turn(1)
	stage.update(s, 0.0, FRAME)
	_check(stage._yaw_goal < before - PI, "three right turns in one frame move the goal on to the right (%.0f degrees)" % rad_to_deg(stage._yaw_goal - before))
	before = stage._yaw_goal
	s.turn(-1)
	s.turn(-1)
	stage.update(s, 0.0, FRAME)
	_check(stage._yaw_goal > before, "and two left turns in one frame move it back to the left")
	stage.free()
