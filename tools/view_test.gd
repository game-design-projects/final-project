## Checks what the 3D view shows, with no window: which cells the automap learns (the camera's field of view, down a corridor
## however far, through a side opening, not behind a wall or behind you), the models' detail and movement, that every monster
## stands on the set for the walls to hide, the camera's timing, the name tags, the set's parts, and the marks on the map.
## Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/view_test.gd
extends "res://tools/test_base.gd"

const FloorGen = preload("res://src/rules/floor_gen.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Flow = preload("res://src/game/flow.gd")
const Flags = preload("res://src/utils/flags.gd")
const Minds = preload("res://src/mind/minds.gd")
const MonsterModel = preload("res://src/view/monster_model.gd")
const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const Monster = preload("res://src/rules/monster.gd")
const Roaming = preload("res://src/rules/roaming.gd")
const Rng = preload("res://src/utils/rng.gd")
const Automap = preload("res://src/view/automap.gd")
const DodgeRun = preload("res://src/rules/dodge_run.gd")
const Hud = preload("res://src/view/hud.gd")
const Overlay = preload("res://src/view/overlay.gd")
const PostFx = preload("res://src/view/postfx.gd")
const Ally = preload("res://src/game/ally.gd")
const Decor = preload("res://src/view/decor.gd")
const Palette = preload("res://src/view/palette.gd")
const State = preload("res://src/game/state.gd")
const Stage = preload("res://src/view/stage.gd")
const Vision = preload("res://src/rules/vision.gd")

const FRAME := 1.0 / 60.0

# FloorMap.DIRS: 0 north, 1 east, 2 south, 3 west
const EAST := 1
const SOUTH := 2

const FACE_MARGIN := 0.02 # how far in front of the body a face part must reach, in world units
const SPRITE_SHAPE := {"slime": 1.2, "bandit": 0.98, "snake": 1.2, "rock": 1.35} # width over height of the sprites in art.gd
const BEFORE_TRIS := {"slime": 1308, "bandit": 1572, "snake": 2384, "rock": 762, "dragon": 2356} # what the models had before the rewrite


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
	_sight_through_a_side_opening()
	_sight_on_real_floors()
	for like_sprite in [false, true]:
		_faces_are_not_buried(like_sprite)
		_models_have_their_detail(like_sprite)
	_models_match_their_sprites()
	await _stage_wears_the_look()
	_models_move_by_species()
	_far_monsters_stay_readable()
	await _camera_keeps_turning()
	await _camera_glides_in_fixed_time()
	await _camera_lunges_at_a_wall()
	await _fights_do_not_move_the_camera()
	await _every_monster_stands_on_the_set()
	await _name_tags()
	await _the_set_has_its_parts()
	await _automap_marks()
	await _palette_is_picked_and_saved()
	await _held_key_waits_for_the_camera()
	await _fight_staging()
	await _models_follow_their_monsters()
	_style()
	_postfx_decays()
	await _picture_is_set_up()
	await _slow_frames_keep_the_direction()
	_finish()


## A monster that moves glides there at the pace of a step, with its name; one replaced by a retried fight leaves no model behind.
func _models_follow_their_monsters() -> void:
	var flow = await _walk(11)
	var s = flow.state
	var stage = _stage_for(s)
	var m = s.floor_map.monsters.filter(func(o): return not o.lurking and not o.boss)[0]
	stage.update(s, 0.0, FRAME)
	var model: Node3D = stage._models[m]
	var start: Vector3 = model.position
	var tag_y: float = stage._tags[m].position.y
	m.cell += FloorMap.DIRS[0]
	var goal: Vector3 = DungeonMesh.center(m.cell)
	stage.update(s, 0.0, FRAME)
	_check(model.position != start and model.position != goal, "a monster's model doesn't jump to its new cell")
	for i in 20:
		stage.update(s, FRAME * i, FRAME)
	_check(model.position == goal, "it gets there within a step's time")
	_check(stage._marks[m].visible and absf(angle_difference(stage._marks[m].rotation.y, atan2(FloorMap.DIRS[0].x, FloorMap.DIRS[0].y))) < 0.01, "and the arrow at its feet says which way it went")
	_check(stage._tags[m].position == Vector3(goal.x, tag_y, goal.z), "and its name comes with it")
	m.hunting = true
	stage.update(s, 1.0, FRAME)
	_check(stage._tags[m].text == str(Roaming.table().tag), "a hunter's name says so")
	m.hunting = false
	stage.update(s, 1.0, FRAME)
	_check(stage._tags[m].text != str(Roaming.table().tag), "and stops saying so")
	m.cell += FloorMap.DIRS[0] * 5
	stage.update(s, 2.0, FRAME)
	_check(model.position == DungeonMesh.center(m.cell), "from far away (a load) it goes at once")
	var fresh = Monster.from_dict(m.to_dict())
	s.floor_map.monsters[s.floor_map.monsters.find(m)] = fresh
	stage.update(s, 3.0, FRAME)
	stage.update(s, 3.0, FRAME)
	_check(not stage._models.has(m) and stage._models.has(fresh), "the one it replaced is gone from the set")
	stage.free()


## A floor from picture rows: `#` wall, anything else open.
func _floor(rows: Array) -> FloorMap:
	var f := FloorMap.new()
	f.size = maxi(rows.size(), String(rows[0]).length())
	for row in rows:
		var cells := []
		for ch in String(row):
			cells.append(0 if ch == "#" else 1)
		f.grid.append(cells)
	return f


func _sight_down_a_corridor() -> void:
	var f := _floor(["##############", "#............#", "##############"])
	_check(Vision.ahead(f, Vector2i(1, 1), EAST).size() == 12, "the whole corridor ahead counts, to the wall (12 cells, not a fixed few)")
	var from_start := Vision.sight(f, Vector2i(1, 1), EAST)
	_check(from_start.has(Vector2i(11, 1)), "a cell ten cells down a straight corridor is in sight")
	_check(from_start.has(Vector2i(1, 1)), "and so is your own")
	_check(not Vision.sight(f, Vector2i(11, 1), EAST).has(Vector2i(1, 1)), "one behind you is not")


func _sight_across_a_hall() -> void:
	var f := _floor(["#########", "#.......#", "#.......#", "#.......#", "#...#...#", "#.......#", "#########"])
	var from := Vector2i(1, 1)
	var seen := Vision.sight(f, from, EAST)
	_check(seen.has(Vector2i(6, 3)), "a cell in another row of an open hall is in sight (not only the row ahead)")
	_check(not seen.has(Vector2i(1, 3)), "one beside you is outside the field of view")
	_check(not Vision.sight(f, Vector2i(1, 4), EAST).has(Vector2i(7, 4)), "a pillar hides what stands behind it")
	var corner := _floor(["#####", "#.#.#", "#.#.#", "#...#", "#####"])
	_check(not Vision.sight(corner, Vector2i(1, 3), EAST).has(Vector2i(3, 1)), "a wall corner on the line hides what is beyond it")
	_check(absf(Vision.VIEW_TAN - tan(deg_to_rad(Stage.FOV / 2.0)) * 448.0 / 288.0) < 0.001, "the field of view on the floor plan is the camera's")
	var stage = Stage.new()
	var where: Dictionary = stage._camera_target(Vector2i(3, 3), EAST)
	_check(is_equal_approx(where.pos.x, DungeonMesh.center(Vector2i(3, 3)).x - Vision.back * DungeonMesh.CELL), "and so is where it stands")
	stage.free()


## Walking down a corridor you see into a side opening, as far as a line reaches; `look` adds that to the corridor ahead.
func _sight_through_a_side_opening() -> void:
	var f := _floor(["#######", "#.....#", "###.###", "###.###", "#######"])
	var seen := Vision.sight(f, Vector2i(1, 1), EAST)
	_check(seen.has(Vector2i(3, 2)), "the cell just inside a side opening is seen from the corridor")
	_check(not seen.has(Vector2i(3, 3)), "the one deeper in, with no line to it, is not")
	var s = State.new()
	s.floor_map = f
	s.cell = Vector2i(1, 1)
	s.facing = EAST
	s.look()
	_check(s.seen.has(Vector2i(3, 2)) and s.seen.has(Vector2i(5, 1)), "look learns the side opening as well as the corridor ahead")
	s.facing = 3
	s.seen = {}
	s.look()
	_check(s.seen.size() == 1, "facing the wall at the end, only your own cell (%d)" % s.seen.size())


## In the champion's hall nothing is in the way: from any cell of it, with the champion inside the camera's field of view, its
## cell is learned; and down a corridor however long.
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
					var dir: Vector2i = FloorMap.DIRS[facing]
					var d: Vector2i = boss.cell - c
					var ahead_by: int = d.x * dir.x + d.y * dir.y
					if ahead_by > 0 and absi(d.x * dir.y - d.y * dir.x) <= ahead_by:
						tried += 1
						if not Vision.sight(f, c, facing).has(boss.cell):
							misses += 1
		# and down every corridor: the champion at any distance along a straight open line is seen
		for facing in 4:
			var run: Array = Vision.ahead(f, boss.cell, (facing + 2) % 4)
			if run.size() > 7 and not Vision.sight(f, run.back(), facing).has(boss.cell):
				hidden_far += 1
	_check(tried > 0 and misses == 0, "from every cell of the hall, the champion in the field of view is seen (%d cases, %d missed)" % [tried, misses])
	_check(hidden_far == 0, "a champion more than six cells down a straight line is seen from its far end (%d unseen)" % hidden_far)


## A monster faces +Z. Every eye, mouth and crack (the solid-coloured parts) must stick out of the body in front of it by a
## little, or the body's black fill hides it and the monster looks faceless from the front.
func _faces_are_not_buried(like_sprite: bool) -> void:
	for species in BEFORE_TRIS:
		var model: Node3D = MonsterModel.build(species, Color.WHITE, like_sprite)
		var black := []
		var features := []
		for part in model.get_node("Rig").get_children():
			var arrays: Array = part.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				if colors[idx[i]].a > 0.25:
					black.append([part.transform * verts[idx[i]], part.transform * verts[idx[i + 1]], part.transform * verts[idx[i + 2]]])
			for group in _solid_groups(verts, colors, idx):
				features.append(group.map(func(v): return part.transform * v))
		var buried := []
		for feature in features:
			var front: Vector3 = feature[0]
			for v in feature:
				if v.z > front.z:
					front = v
			for t in black:
				if Geometry3D.ray_intersects_triangle(front - Vector3(0.0, 0.0, FACE_MARGIN), Vector3(0, 0, 1), t[0], t[1], t[2]) != null:
					buried.append(front)
					break
		_check(features.size() > 0 and buried.is_empty(), "the %s's %d face parts all stand out of its body (buried: %s)" % [species, features.size(), buried])
		model.free()


## The solid-coloured vertices of a mesh, one list per connected piece (an eye, a slit, a crack). Faces of a box don't share
## vertices, only their places, so a piece is told by where its corners are.
func _solid_groups(verts: PackedVector3Array, colors: PackedColorArray, idx: PackedInt32Array) -> Array:
	var root_of := {}
	var find := func(find_ref: Callable, k: Vector3) -> Vector3:
		if not root_of.has(k):
			root_of[k] = k
		if root_of[k] != k:
			root_of[k] = find_ref.call(find_ref, root_of[k])
		return root_of[k]
	for i in range(0, idx.size(), 3):
		if colors[idx[i]].a < 0.25:
			var a: Vector3 = find.call(find, verts[idx[i]].snappedf(0.001))
			root_of[find.call(find, verts[idx[i + 1]].snappedf(0.001))] = a
			root_of[find.call(find, verts[idx[i + 2]].snappedf(0.001))] = a
	var groups := {}
	for k in root_of.keys():
		var r: Vector3 = find.call(find, k)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(k)
	return groups.values()


## Every species at the detail it had before the rewrite (near BEFORE_TRIS triangles), under the ceiling.
func _models_have_their_detail(like_sprite: bool) -> void:
	for species in BEFORE_TRIS:
		var model: Node3D = MonsterModel.build(species, Color.WHITE, like_sprite)
		var tris := 0
		for part in model.get_node("Rig").get_children():
			tris += part.mesh.surface_get_array_index_len(0) / 3
		_check(tris >= int(BEFORE_TRIS[species] * 0.95), "the %s keeps its detail (%d triangles, it had %d)" % [species, tris, BEFORE_TRIS[species]])
		var top := MonsterModel.top_of(model)
		_check(top > 0.5 and top < DungeonMesh.WALL_H, "the %s stands under the ceiling (top at %.2f)" % [species, top])
		model.free()


## With sprite-look a model from the front has the shape of its sprite. The dragon's (1.63) has wings and a tail too wide for a
## corridor, drawn in along x, so it is only held to staying wider than it is tall.
func _models_match_their_sprites() -> void:
	for species in BEFORE_TRIS:
		var model: Node3D = MonsterModel.build(species, Color.WHITE, true)
		var box := AABB()
		var first := true
		for part in model.get_node("Rig").get_children():
			var verts: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var at: Vector3 = part.transform * v
				box = AABB(at, Vector3.ZERO) if first else box.expand(at)
				first = false
		var shape: float = box.size.x / box.size.y
		var want: float = SPRITE_SHAPE.get(species, shape if shape > 1.0 else 1.0)
		_check(absf(shape - want) < 0.1 and (species != "dragon" or shape > 1.0), "the %s from the front is the sprite's shape (%.2f wide per tall, the sprite %.2f)" % [species, shape, want])
		var widest: float = maxf(absf(box.position.x), absf(box.end.x)) * model.scale.x
		_check(widest < DungeonMesh.CELL / 2.0, "the %s stays out of the walls of a corridor (%.2f from its middle)" % [species, widest])
		model.free()
	for species in BEFORE_TRIS:
		var plain: Node3D = MonsterModel.build(species, Color.WHITE)
		var drawn: Node3D = MonsterModel.build(species, Color.WHITE, true)
		_check(plain.get_node("Rig").get_child_count() == drawn.get_node("Rig").get_child_count(), "the %s moves the same parts in either look" % species)
		plain.free()
		drawn.free()
	var unknown: Node3D = MonsterModel.build("no such thing", Color.WHITE, true)
	_check(unknown.get_node("Rig").get_child_count() > 0, "a species with no sprite shape gets a block too")
	unknown.free()


## The set builds what the game says to show (the suite in classic has sprite-look off).
func _stage_wears_the_look() -> void:
	var flow = await _walk(31)
	var s = flow.state
	var stage = _stage_for(s)
	stage.update(s, 0.0, FRAME)
	var m = s.floor_map.monsters.filter(func(x): return stage._models.has(x)).front()
	if s.viewing("hand-drawn"):
		_check(stage._models[m].get_meta("species") == m.species and stage._models[m].sheet == m.species, "the set shows its drawing (hand-drawn)")
	else:
		var wanted: Array = MonsterModel._parts_of(m.species, Palette.monster(m), s.viewing("sprite-look"))
		_check(stage._models[m].get_node("Rig").get_child(0).mesh == wanted[0][1], "the set shows the look the game asks for (sprite-look %s)" % s.viewing("sprite-look"))
	stage.free()


## Each species moves its own way: the slime wobbles, the snake sways, the rock breathes, the bandit shifts, the dragon
## flaps and nods. A pose at any time is a transform of the parts, never a rebuild.
func _models_move_by_species() -> void:
	var parts := {"slime": "Body", "bandit": "Body", "snake": "Upper", "rock": "Upper", "dragon": "WingL"}
	for species in parts:
		var model: Node3D = MonsterModel.build(species, Color.WHITE)
		MonsterModel.pose(model, 0.2, 0.0)
		var before: Transform3D = MonsterModel.part(model, parts[species]).transform
		MonsterModel.pose(model, 0.9, 0.0)
		_check(not before.is_equal_approx(MonsterModel.part(model, parts[species]).transform), "the %s's %s moves on its own" % [species, parts[species]])
		model.free()
	var dragon: Node3D = MonsterModel.build("dragon", Color.WHITE)
	MonsterModel.pose(dragon, 0.0, 0.0)
	var head_rest: Transform3D = MonsterModel.part(dragon, "Head").transform
	MonsterModel.pose(dragon, 1.4, 0.0)
	_check(not head_rest.is_equal_approx(MonsterModel.part(dragon, "Head").transform), "the dragon's head bobs")
	dragon.free()
	var snake: Node3D = MonsterModel.build("snake", Color.WHITE)
	var shown := {}
	var lengths := {}
	for i in 200:
		MonsterModel.pose(snake, i * 0.02, 0.0)
		var tongue := MonsterModel.part(snake, "Tongue")
		shown[tongue.visible] = true
		if tongue.visible:
			lengths[snappedf(tongue.basis.get_scale().y, 0.1)] = true
	_check(shown.size() == 2, "the snake's tongue goes in and out")
	_check(lengths.size() >= 4, "sliding, not blinking on and off (%s)" % [lengths.keys()])
	snake.free()
	var unknown: Node3D = MonsterModel.build("no such thing", Color.WHITE)
	MonsterModel.pose(unknown, 1.0, 1.0)
	_check(unknown.get_node("Rig").get_child_count() > 0, "a species with no model gets a block, and a pose doesn't break it")
	unknown.free()


## A monster down a long corridor stays readable: its lines fade only to 0.55, the walls' keep fading to 0.15.
func _far_monsters_stay_readable() -> void:
	var model: Node3D = MonsterModel.build("slime", Color.WHITE)
	var fill: ShaderMaterial = model.get_node("Rig").get_child(0).material_override
	_check(is_equal_approx(fill.get_shader_parameter("fade_floor"), 0.55), "a walking monster's fill fades no lower than 0.55")
	_check(is_equal_approx(fill.next_pass.get_shader_parameter("fade_floor"), 0.55), "nor do its lines")
	_check(is_equal_approx(fill.next_pass.get_shader_parameter("ink_px"), 2.5), "its lines are 2.5 pixels wide")
	model.free()


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
	var t := 0.0
	for side in [1, 3]: # right, then left
		var drift := 0.0 # the most the camera went the wrong way in a frame
		var last: float = stage._yaw
		var spun := 0.0
		for frame in 120:
			if frame % 2 == 0:
				s.turn(1 if side == 1 else -1)
			t += FRAME
			stage.update(s, t, FRAME)
			var step: float = stage._yaw - last
			spun += step
			drift = maxf(drift, step if side == 1 else -step) # right turns the yaw down, left turns it up
			last = stage._yaw
		var name := "right" if side == 1 else "left"
		_check(drift < 1e-6 and absf(spun) > TAU, "holding %s turns the camera one way all along (%.0f degrees, never back)" % [name, rad_to_deg(absf(spun))])
		for frame in 60: # let go: it settles on the heading within a second, not after winding down a long spin
			t += FRAME
			stage.update(s, t, FRAME)
		_check(_angle_gap(stage._yaw, -s.facing * PI / 2.0) < 0.05, "after letting go of %s the camera is on the heading within a second" % name)
	stage.free()


## A step takes 150 ms and a turn 170, easing out (a cubic), and `moving` says so; then the camera is exactly there.
func _camera_glides_in_fixed_time() -> void:
	var flow = await _walk(3)
	var s = flow.state
	var stage = _stage_for(s)
	_check(not stage.moving(), "the camera starts settled")
	var from: Vector3 = stage._camera.position
	var heading: Vector2i = FloorMap.DIRS[s.facing]
	s.cell += heading
	var to: Vector3 = from + Vector3(heading.x, 0, heading.y) * Stage.CELL
	stage.update(s, 10.0, FRAME)
	_check(stage.moving(), "a step starts a glide")
	stage.update(s, 10.075, FRAME)
	_check(stage._camera.position.is_equal_approx(from.lerp(to, 0.875)), "half way through the time it has come seven eighths of the way (a cubic ease out)")
	stage.update(s, 10.149, FRAME)
	_check(stage.moving(), "a step is still gliding at 149 ms")
	stage.update(s, 10.15, FRAME)
	_check(not stage.moving() and stage._camera.position.is_equal_approx(to), "and has arrived at 150 ms, exactly on the spot")
	s.facing = (s.facing + 1) % 4
	stage.update(s, 20.0, FRAME)
	stage.update(s, 20.169, FRAME)
	_check(stage.moving(), "a turn is still swinging at 169 ms")
	stage.update(s, 20.17, FRAME)
	_check(not stage.moving() and _angle_gap(stage._yaw, -s.facing * PI / 2.0) < 1e-5, "and has arrived at 170 ms")
	stage.free()


## Walking into a wall lunges the camera 0.28 at it and back in 140 ms, softer with the `calm` setting; a held key waits for it.
func _camera_lunges_at_a_wall() -> void:
	var flow = await _walk(3)
	var s = flow.state
	var stage = _stage_for(s)
	var rest: Vector3 = stage._camera.position
	var fwd := Vector3(FloorMap.DIRS[s.facing].x, 0, FloorMap.DIRS[s.facing].y)
	stage.update(s, 30.0, FRAME)
	stage.bump(30.0)
	_check(stage.moving(), "a held key waits for the lunge")
	stage.update(s, 30.07, FRAME)
	_check(absf((stage._camera.position - rest).dot(fwd) - 0.28) < 0.001, "half way through it the camera is 0.28 toward the wall (%.3f)" % (stage._camera.position - rest).dot(fwd))
	stage.update(s, 30.14, FRAME)
	_check(stage._camera.position.is_equal_approx(rest) and not stage.moving(), "at 140 ms it is back")
	stage.calm = true
	stage.bump(40.0)
	stage.update(s, 40.07, FRAME)
	var calm_lunge: float = (stage._camera.position - rest).dot(fwd)
	_check(calm_lunge > 0.0 and calm_lunge < 0.15, "with calm the lunge is softer (%.3f)" % calm_lunge)
	stage.free()


## There is no fight camera: a fight changes nothing, so the set comes back exactly as it was, with nothing to settle.
func _fights_do_not_move_the_camera() -> void:
	var flow = await _walk(11)
	var s = flow.state
	var stage = _stage_for(s)
	var rest: Vector3 = stage._camera.position
	var yaw: float = stage._yaw
	s.foe = s.floor_map.monsters[0]
	s.stage = "menu"
	stage.update(s, 1.0, FRAME)
	_check(stage._camera.position == rest and stage._yaw == yaw and stage._camera.rotation.x == 0.0, "a fight leaves the camera where it was")
	s.foe = null
	s.stage = "explore"
	stage.update(s, 1.1, FRAME)
	_check(stage._camera.position == rest and not stage.moving(), "and there is nothing to settle afterwards")
	stage.visible = false # the battle screen hides the set; a change while it is hidden is not played back
	s.cell += FloorMap.DIRS[s.facing]
	stage.update(s, 2.0, FRAME)
	_check(not stage.moving(), "a move while the set is hidden does not glide")
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


## Every monster still on the floor stands on the set whichever way you face, and the walls hide them. Nothing shows or hides
## them by the logic of who is in view, so nothing pops.
func _every_monster_stands_on_the_set() -> void:
	var flow = await _walk(11)
	var s = flow.state
	var stage = _stage_for(s)
	var all: Array = s.floor_map.monsters
	var boss = all.back()
	for facing in 4:
		s.facing = facing
		stage.update(s, 0.0, FRAME)
		_check(all.all(func(m): return (stage._stirs.has(m) and stage._stirs[m].visible and not stage._models.has(m)) if m.lurking else (stage._models.has(m) and stage._models[m].visible)), "all %d monsters are on the set, facing %s" % [all.size(), FloorMap.DIR_NAMES[facing]])
	var stirring: Array = all.filter(func(m): return m.lurking)
	if not stirring.is_empty():
		stirring[0].lurking = false
		stage.update(s, 0.0, FRAME)
		_check(not stage._stirs[stirring[0]].visible and stage._models[stirring[0]].visible, "what stirred shows itself once you walk into it")
	var victim = all[0]
	victim.gone = "slain"
	stage.update(s, 0.1, FRAME)
	_check(not stage._models[victim].visible and not stage._tags[victim].visible, "one that is gone is off the set, tag and all")
	s.cell = boss.cell
	stage.update(s, 0.2, FRAME)
	_check(not stage._models[boss].visible, "and so is one in your own cell")
	stage.free()


func _name_tags() -> void:
	_no_name_without_a_body()
	var f := _floor(["##########", "#........#", "##########", "#........#", "##########"])
	var near = load("res://src/rules/monster.gd").new()
	near.species = "slime"
	near.genre = "bullet"
	near.cell = Vector2i(4, 1)
	var far = load("res://src/rules/monster.gd").new()
	far.species = "bandit"
	far.genre = "chess"
	far.cell = Vector2i(8, 1)
	var walled = load("res://src/rules/monster.gd").new()
	walled.species = "dragon"
	walled.genre = "bullet"
	walled.boss = true
	walled.cell = Vector2i(4, 3)
	f.monsters = [near, far, walled]
	var s = State.new()
	s.floor_map = f
	s.cell = Vector2i(1, 1)
	s.facing = EAST
	var stage = _stage_for(s)
	var t := 0.0
	for i in 30:
		t += FRAME
		stage.update(s, t, FRAME)
	var tag: Label3D = stage._tags[near]
	_check(tag.fixed_size and tag.no_depth_test and tag.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "a tag is the same size near or far, sharp, and no wall edge slices it")
	var model: Node3D = stage._models[far]
	_check(is_equal_approx(stage._tags[far].position.y, MonsterModel.top_of(model) + Stage.TAG_GAP), "a tag floats just over its model's real top")
	_check(stage._tags[far].position.y != tag.position.y, "so a tall monster's sits higher than a slime's")
	_check(tag.visible and tag.modulate.a > stage._tags[far].modulate.a, "a nearer tag is brighter than a farther one (%.2f, %.2f)" % [tag.modulate.a, stage._tags[far].modulate.a])
	_check(not stage._tags[walled].visible, "a monster behind a wall shows no name")
	s.cell = Vector2i(3, 1)
	far.cell = Vector2i(4, 1)
	near.cell = Vector2i(4, 1)
	stage._tags[far].position = stage._tags[near].position
	stage._tag_key = []
	for i in 30:
		t += FRAME
		stage.update(s, t, FRAME)
	_check(stage._tags[near].visible != stage._tags[far].visible, "of two tags that would overlap only one shows")
	near.gone = "slain"
	stage._tag_key = []
	for i in 30:
		t += FRAME
		stage.update(s, t, FRAME)
	_check(stage._tags[far].visible, "and the other comes in once it is free")
	stage.free()


func _the_set_has_its_parts() -> void:
	var flow = await _walk(11)
	var s = flow.state
	var stage = _stage_for(s)
	var f = s.floor_map
	var mesh: ArrayMesh = stage._dungeon.mesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	var at: Vector3 = DungeonMesh.center(f.stairs)
	var hole := DungeonMesh.STAIRS_HALF * DungeonMesh.CELL
	var over_hole := 0
	var idx: PackedInt32Array = mesh.surface_get_arrays(1)[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size(), 3):
		var c: Vector3 = (verts[idx[i]] + verts[idx[i + 1]] + verts[idx[i + 2]]) / 3.0
		if c.y < 0.01 and absf(c.x - at.x) < hole and absf(c.z - at.z) < hole:
			over_hole += 1
	_check(over_hole == 0, "the floor has a hole at the stairs")
	var pit: ArrayMesh = stage._stairs.mesh
	var box := pit.get_aabb()
	_check(box.position.y <= -DungeonMesh.STAIRS_DEPTH + 0.01 and pit.surface_get_array_index_len(0) / 3 > 100, "the stairs are a pit %.1f deep with its funnel rings (%d triangles)" % [-box.position.y, pit.surface_get_array_index_len(0) / 3])
	var colors: PackedColorArray = pit.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var accent: Color = stage.palette.accent
	var rim := 0
	var dims := {}
	for col in colors:
		if col.a < 0.25 and col.is_equal_approx(Color(accent, 0.0)):
			rim += 1
		elif col.a > 0.75 and col != Color.BLACK:
			dims[snappedf(col.r / maxf(accent.r, 0.01), 0.01)] = true
	_check(rim > 0 and dims.size() == DungeonMesh.STAIRS_STEPS, "its rim is in the accent colour and %d rings dim going down" % dims.size())
	# the walls: a third of the faces carry something, the same every time
	var faces := 0
	for seed_value in range(1, 21):
		var g = FloorGen.generate(Rng.new(seed_value))
		for y in g.size:
			for x in g.size:
				if g.is_open(Vector2i(x, y)):
					for d in 4:
						if not g.is_open(Vector2i(x, y) + FloorMap.DIRS[d]):
							faces += 1
	var decorated := 0
	for seed_value in range(1, 21):
		decorated += Decor.placements(FloorGen.generate(Rng.new(seed_value))).size()
	var share := float(decorated) / faces
	_check(absf(share - 0.32) < 0.05, "about a third of the wall faces carry a decoration (%.2f)" % share)
	_check(Decor.placements(f) == Decor.placements(f), "a floor is decorated the same every time")
	# a decoration is a real shape, off the wall, and fades like the walls' lines; a torch has a flame and lights the wall
	var props: MeshInstance3D = stage._decor.get_node("Props")
	var shapes: int = props.mesh.surface_get_array_index_len(0) / 3
	var least := 2 * Decor.placements(f).size() if s.viewing("hand-drawn") else 1000
	_check(shapes >= least, "decorations are all there: drawings when hand-drawn, or else real 3D shapes (%d triangles)" % shapes)
	_check(is_equal_approx(props.material_override.get_shader_parameter("fade_floor"), 0.15), "they fade with distance like the walls")
	var torches := Decor.placements(f).filter(func(p): return p.kind == "torch").size()
	_check(stage._torches.size() == torches and torches > 0, "every torch is known to the stage (%d)" % torches)
	_check(stage._decor.get_node("Flames").mesh.surface_get_array_index_len(0) / 6 == torches, "and has one flame quad")
	stage.update(s, 5.0, FRAME)
	var lit: PackedVector4Array = stage._wall_mat.get_shader_parameter("torches")
	var a: Vector4 = lit[0]
	stage.update(s, 5.5, FRAME)
	var b: Vector4 = stage._wall_mat.get_shader_parameter("torches")[0]
	_check(lit.size() == Stage.MAX_TORCHES and a.w > 0.0 and a.w != b.w, "the nearest torches light the walls and flicker (%.3f, %.3f)" % [a.w, b.w])
	var env: WorldEnvironment = null
	for child in stage.get_children():
		if child is WorldEnvironment:
			env = child
	_check(env != null and env.environment.background_color == Color.BLACK and env.environment.background_mode == Environment.BG_COLOR, "the background is black whatever the project's clear colour")
	stage.free()


## A monster on the move shows on the map where you last saw it, darker once it's out of sight, and never where it really is.
func _last_seen_on_the_map(s, map) -> void:
	var m = s.floor_map.monsters[0]
	var had: Vector2i = m.cell
	var dot := func(at: Vector2i): return map.monster_marks().filter(func(k): return Rect2(Vector2(at) * map.cell_px(), Vector2.ONE * map.cell_px()).encloses(k.rect))
	m.last_seen = Vector2i(-1, -1)
	s.in_sight = {}
	_check(dot.call(had).is_empty(), "a monster you never saw isn't on the map, even over floor you have seen")
	m.last_seen = had
	s.in_sight = {had: true}
	var near: Array = dot.call(had)
	_check(near.size() == 1 and near[0].color == Palette.monster(m), "one in sight shows at its cell in its colour")
	s.in_sight = {}
	m.cell = had + Vector2i(1, 0)
	var left: Array = dot.call(had)
	_check(left.size() == 1 and left[0].color != Palette.monster(m), "out of sight it stays where you saw it, darker")
	_check(dot.call(m.cell).is_empty(), "and doesn't show where it went")
	m.cell = had
	m.last_seen = Vector2i(-1, -1)


func _automap_marks() -> void:
	var flow = await _walk(11)
	var s = flow.state
	s.floor_map = FloorGen.generate(Rng.new(11)) # the classic floor, whichever the run's first one is
	s.cell = s.floor_map.start
	var map = Automap.new()
	map.state = s
	s.seen = {s.cell: true}
	_check(map.cell_px() == 8, "a cell of a 13x13 floor is 8 pixels on the map (105 across)")
	var boss = s.floor_map.monsters.back()
	s.seen[boss.cell] = true # the map keeps it hidden until seen (features_test)
	var marks: Array = map.monster_marks()
	s.seen.erase(boss.cell)
	if s.viewing("roaming"):
		_last_seen_on_the_map(s, map)
	_check(marks.any(func(k): return k.color == Palette.BOSS and k.rect.size == Vector2(8, 8)), "the champion is on the map, in red, from the start")
	_check(not s.seen.has(boss.cell), "though you have not seen its cell")
	var m = s.floor_map.monsters[0]
	_check(not marks.any(func(k): return k.rect.position == Vector2(m.cell) * 8.0 + Vector2(2, 2)), "a monster you have not seen is not")
	s.seen[m.cell] = true
	m.last_seen = m.cell
	s.in_sight[m.cell] = true
	var dot: Array = map.monster_marks().filter(func(k): return k.rect.position == Vector2(m.cell) * 8.0 + Vector2(2, 2))
	_check(dot.size() == 1 and dot[0].rect.size == Vector2(4, 4) and dot[0].color == Palette.monster(m), "a seen monster is a dot of its colour, with a size")
	m.gone = "spared"
	_check(map.monster_marks().filter(func(k): return k.rect.position == Vector2(m.cell) * 8.0 + Vector2(2, 2)).is_empty(), "a monster that is gone is not on the map")
	boss.gone = "slain"
	_check(not map.monster_marks().any(func(k): return k.color == Palette.BOSS), "nor a defeated champion")
	_check(map.stairs_mark().is_empty(), "the stairs are not marked until seen")
	s.seen[s.floor_map.stairs] = true
	var ring: Array = map.stairs_mark()
	_check(ring.size() == 2 and ring[0].encloses(ring[1]) and ring[1].size == Vector2(4, 4), "then they are a ring")
	s.seen = {Vector2i(1, 1): true}
	var lines: Array = map.wall_lines()
	var walls := 0
	for d in 4:
		if not s.floor_map.is_open(Vector2i(1, 1) + FloorMap.DIRS[d]):
			walls += 1
	_check(lines.size() == walls and lines.all(func(r): return r.size.x == 1.0 or r.size.y == 1.0), "walls are 1-pixel lines on the edges of seen floor (%d)" % walls)
	map.free()


## Each run picks one of the eight palettes from its seed and keeps it in its save; a save from before that still loads.
func _palette_is_picked_and_saved() -> void:
	_check(Palette.RUNS.size() == 8, "eight palettes")
	_check(Palette.RUNS.all(func(p): return p.name != ""), "each with a name")
	var picked := {}
	for seed_value in range(100, 124):
		var run = await _walk(seed_value)
		picked[Palette.for_run(run.state.palette_id).name] = true
	_check(picked.size() == 8, "different seeds wear different palettes (%d of 8)" % picked.size())
	var flow = await _walk(103)
	var s = flow.state
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	_check(int(saved.palette) == s.palette_id, "the palette goes into the save")
	s.palette_id += 3
	var kept = State.from_dict(s.to_dict())
	_check(kept.palette_id == s.palette_id, "and comes back from it, whatever the floor's seed")
	saved.erase("palette")
	var old = State.from_dict(saved)
	_check(old != null and old.palette_id == s.floor_map.seed_value, "a save without one loads, in the colours its seed would pick")
	var stage = _stage_for(kept)
	_check(stage.palette.name == Palette.for_run(kept.palette_id).name, "the set wears the run's palette")
	stage.free()


func _key(code: Key, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	return event


## A held arrow (the key's repeats) waits for the camera; a fresh press does not. Other stages are as they were.
func _held_key_waits_for_the_camera() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=9"]))
	var scene = load("res://src/gameplay/gameplay.tscn").instantiate()
	scene.request = {"kind": "new"}
	root.add_child(scene)
	while scene.flow == null or scene.flow.state.stage != "explore":
		await process_frame
	for i in 10: # past the long frame that builds the floor
		await process_frame
	var s = scene.flow.state
	var facing: int = s.facing
	scene._unhandled_input(_key(KEY_RIGHT))
	await process_frame # (this signal comes before the nodes' _process of its frame, so one more for the stage to see the turn)
	await process_frame
	_check(s.facing == (facing + 1) % 4 and scene._stage.moving(), "a press turns, and the camera starts to swing")
	scene._unhandled_input(_key(KEY_RIGHT, true))
	_check(s.facing == (facing + 1) % 4, "a repeat of the key while it swings is dropped")
	scene._unhandled_input(_key(KEY_RIGHT))
	_check(s.facing == (facing + 2) % 4, "a fresh press is not")
	await process_frame
	await process_frame
	scene._clock_ms += 1000.0
	await process_frame
	await process_frame
	_check(not scene._stage.moving(), "the swing ends")
	scene._unhandled_input(_key(KEY_RIGHT, true))
	_check(s.facing == (facing + 3) % 4, "and then the repeat acts")
	# walking into a wall: find one, and the event lunges the camera
	var wall := -1
	for d in 4:
		if not s.floor_map.is_open(s.cell + FloorMap.DIRS[d]):
			wall = d
	s.facing = wall
	scene._clock_ms += 1000.0
	await process_frame
	await process_frame
	await scene.flow.press("up")
	_check(scene._stage.moving(), "walking into a wall lunges the camera")
	# the key stays down against that wall: the one lunge, not one every time the key repeats
	var bumps := [0]
	var count_bumps := func(n, _d):
		if n == "bump":
			bumps[0] += 1
	scene.flow.happened.connect(count_bumps)
	scene._clock_ms += 1000.0
	await process_frame
	await process_frame
	await scene.flow.press("up", true)
	await process_frame
	await process_frame
	_check(bumps[0] == 0 and not scene._stage.moving(), "a held key doesn't lunge at the wall again and again")
	await scene.flow.press("up")
	_check(bumps[0] == 1, "a fresh press does")
	scene.free()


## Round a corner: only the far corner of the monster's cell shows, so it has no name yet, as nothing stands there to name. A step on it has.
func _no_name_without_a_body() -> void:
	var f := _floor(["#######", "#.....#", "#####.#", "#####.#", "#######"])
	var m = load("res://src/rules/monster.gd").new()
	m.species = "slime"
	m.genre = "bullet"
	m.cell = Vector2i(5, 2)
	f.monsters = [m]
	var s = State.new()
	s.floor_map = f
	s.cell = Vector2i(3, 1)
	s.facing = EAST
	var stage = _stage_for(s)
	var t := 0.0
	for i in 30:
		t += FRAME
		stage.update(s, t, FRAME)
	var eye := Vector2(3.5 - Vision.back, 1.5)
	_check(Vision.reaches(f, eye, m.cell) and not Vision.sees_body(f, eye, m.cell), "from here a corner of its cell shows and the monster doesn't")
	_check(not stage._tags[m].get_meta("wanted"), "a monster you can't see has no name hanging over the wall")
	s.cell = Vector2i(4, 1)
	for i in 30:
		t += FRAME
		stage.update(s, t, FRAME)
	_check(stage._tags[m].get_meta("wanted"), "and a step on, when it can be seen, it has")
	stage.free()


## The flat battle screen: the flash as a fight begins, mercy by the name, and what the dodge box shows.
## Your soul glides to its square, and the battle screen fades out as the fight ends.
## The strike bar is what you are watching: nothing lies over it.
func _strike_bar_stands_clear(s, m) -> void:
	var overlay = Overlay.new()
	overlay.state = s
	var stage_was: String = s.stage
	var foe_was = s.foe
	s.foe = m
	s.stage = "fightbar"
	s.bar = {"t0": 0.0, "dur": 1000.0, "heavy": true}
	s.banner = {"title": "TIP", "text": "words", "t0": 0.0, "ms": 1000.0}
	s.lines = [State.speech(m.name, "words")]
	_check(not overlay.speech().is_empty() and not overlay.strike_bar_rect().intersects(Overlay.SPEECH), "the bar stands above the foe's words")
	_check(not overlay.strike_bar_rect().intersects(overlay.banner_rect()), "and a banner stands above the bar")
	overlay.free()
	s.stage = stage_was
	s.foe = foe_was
	s.bar = null
	s.banner = null


func _fight_eases(s, m) -> void:
	var overlay = Overlay.new()
	overlay.state = s
	s.foe = m
	s.stage = "dodge"
	s.dodge = {"soul": Vector2i(1, 1)}
	overlay._process(FRAME)
	var from: Vector2 = overlay._soul_shown
	s.dodge.soul = Vector2i(2, 1)
	var goal: Vector2 = Overlay.soul_square(s.dodge)
	overlay._process(FRAME)
	_check(overlay._soul_shown != from and overlay._soul_shown != goal, "your soul doesn't jump to its new square")
	for _i in 30:
		overlay._process(FRAME)
	_check(overlay._soul_shown.distance_to(goal) < 0.5, "it is there within half a second")
	overlay.clock_ms = 500.0
	overlay._process(FRAME)
	_check(overlay.leave_fade() == 0.0, "no fade during a fight")
	s.stage = "explore"
	s.foe = null
	s.dodge = null
	overlay._process(FRAME)
	_check(overlay.leave_fade() == 1.0, "the fight ends in black")
	overlay.clock_ms = 500.0 + Overlay.LEAVE_FADE_MS / 2.0
	_check(is_equal_approx(overlay.leave_fade(), 0.5), "half gone halfway")
	overlay.clock_ms = 500.0 + Overlay.LEAVE_FADE_MS
	_check(overlay.leave_fade() == 0.0, "and the halls are back")
	overlay.free()


func _fight_staging() -> void:
	var flow = await _walk(21)
	var s = flow.state
	var overlay = Overlay.new()
	overlay.state = s
	var m = s.floor_map.monsters[0]
	_fight_eases(s, m)
	_strike_bar_stands_clear(s, m)
	s.foe = m
	s.stage = "intro"
	overlay.intro_at = 1000.0
	overlay.clock_ms = 1000.0
	_check(is_equal_approx(overlay.intro_flash(), 0.5), "a fight begins in a flash of half white")
	overlay.clock_ms = 1350.0
	_check(is_equal_approx(overlay.intro_flash(), 0.25), "half gone after 350 ms")
	overlay.clock_ms = 1700.0
	_check(overlay.intro_flash() == 0.0, "gone after 700 ms")
	overlay.clock_ms = 1000.0
	s.stage = "menu"
	_check(overlay.intro_flash() == 0.0, "and only as the fight begins")
	s.mind_rows = [{"id": "mercy", "label": "", "answer": 0.5}]
	_check(overlay.can_spare(), "at a 50% chance of mercy the name says so")
	s.mind_rows = [{"id": "mercy", "label": "", "answer": 0.49}]
	_check(not overlay.can_spare(), "below it, not")
	s.mind_rows = []
	_check(not overlay.can_spare(), "nor when the mind has not been asked")

	s.dodge = DodgeRun.start("shadow", 1.0, false, 0, 5000.0, {"slime": true})
	var bar: Rect2 = overlay.time_bar()
	_check(Rect2(0, 0, Overlay.W, Overlay.H).encloses(bar), "the time-left bar is inside the picture (%s)" % bar)
	overlay.clock_ms = 5000.0
	var a: Vector2 = overlay.lantern_spot()
	overlay.clock_ms = 5500.0
	var b: Vector2 = overlay.lantern_spot()
	_check(a != b and a.distance_to(b) < 60.0, "the lantern moves smoothly all through a shadow dodge")
	var h := {"warn": 5000.0, "hit": 6000.0, "at": 24}
	overlay.clock_ms = 5000.0
	var start_fill: float = overlay.warning_fill(h)
	var start_ball: Vector2 = overlay.goo_ball(h)
	overlay.clock_ms = 5900.0
	_check(overlay.warning_fill(h) > start_fill, "a warning fills up as the hit comes near")
	var near_ball: Vector2 = overlay.goo_ball(h)
	_check(near_ball.y > start_ball.y and absf(near_ball.x - start_ball.x) < 0.01, "goo falls toward its square")
	overlay.clock_ms = 6000.0
	_check(overlay.goo_ball(h).is_equal_approx(Rect2(Overlay.BOX_X + 3 * Overlay.BOX_CELL, Overlay.BOX_Y + 3 * Overlay.BOX_CELL, Overlay.BOX_CELL, Overlay.BOX_CELL).get_center()), "and lands on it")
	s.allies = [Ally.make("slime", "GLOP", 60.0), Ally.make("snake", "SSS", 60.0)]
	var rows: Array = overlay.charm_rows()
	_check(rows.size() == 2 and rows[0].color != Overlay.CHARM_USED, "the charms are listed, the slime's still ready")
	s.dodge.shield = false
	rows = overlay.charm_rows()
	_check(rows[0].color == Overlay.CHARM_USED and rows[1].color != Overlay.CHARM_USED, "and greyed once its shield is used")
	overlay.free()


func _style() -> void:
	_check(Hud.hp_color(0.39) == Palette.WARN and Hud.hp_color(0.4) == Palette.YOU, "the health bar goes red under 40%")
	var overlay = Overlay.new()
	overlay.clock_ms = 100.0
	var on: bool = overlay.title_prompt_on()
	overlay.clock_ms = 700.0
	_check(on and not overlay.title_prompt_on(), "PRESS ANY KEY blinks")
	overlay.free()


## The last pass's effects all die away by themselves; `calm` splits no colours and holds the pulse still.
func _postfx_decays() -> void:
	var fx = PostFx.new()
	var mat: ShaderMaterial = fx.material
	fx.beat()
	fx.update(0.0)
	_check(is_equal_approx(mat.get_shader_parameter("pulse"), 1.0), "a beat pulses")
	fx.update(0.2)
	var pulse: float = mat.get_shader_parameter("pulse")
	_check(absf(pulse - exp(-3.5 * 0.2)) < 0.001, "the pulse decays between beats (%.3f)" % pulse)
	fx.hurt()
	fx.update(0.0)
	_check(is_equal_approx(mat.get_shader_parameter("hurt_level"), 1.0), "a hit shows a red edge")
	_check(mat.get_shader_parameter("split") > 2.0, "and splits the colours")
	fx.update(1.0)
	_check(mat.get_shader_parameter("hurt_level") < 0.05 and mat.get_shader_parameter("split") < 0.4, "both fade within a second")
	fx.flash(Color.WHITE, 0.5)
	fx.update(0.0)
	_check(is_equal_approx(mat.get_shader_parameter("flash").w, 0.5), "a flash starts at its strength")
	fx.calm = true
	fx.hurt()
	fx.update(0.0)
	_check(mat.get_shader_parameter("split") < 0.4, "calm: a hit splits no colours")
	_check(is_equal_approx(mat.get_shader_parameter("pulse"), 0.5), "calm: the pulse holds still")
	_check(mat.get_shader_parameter("hurt_level") > 0.9, "calm: a hit still shows at the edge")


## The picture in the running scene: anti-aliased, scaled sharply, its bloom gated on the `crt` setting, and the accent back to
## the run's when a fight is over.
func _picture_is_set_up() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=9"]))
	var scene = load("res://src/gameplay/gameplay.tscn").instantiate()
	scene.request = {"kind": "new"}
	root.add_child(scene)
	while scene.flow == null or scene.flow.state.stage != "explore":
		await process_frame
	await process_frame
	await process_frame
	var s = scene.flow.state
	var Settings = load("res://src/menu/settings.gd") # (at run time: it needs the Store autoload)
	_check(scene._viewport.msaa_3d == Viewport.MSAA_4X, "the 3D picture is anti-aliased (4x)")
	_check(scene._postfx.attached() and scene._picture.material == scene._postfx.material, "the last pass is on")
	_check(scene._picture.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "and reads the picture linearly, to scale it sharply")
	_check(scene._picture.find_child("Bloom", true, false) != null, "with its bloom viewport")
	Settings.set_value("crt", false)
	await process_frame
	await process_frame
	_check(not scene._postfx.attached() and scene._picture.material == null, "crt off takes the last pass away")
	_check(scene._picture.find_child("Bloom", true, false) == null or scene._picture.find_child("Bloom", true, false).is_queued_for_deletion(), "and its bloom with it")
	_check(scene._picture.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "and pixels scale as they are")
	Settings.set_value("crt", true)
	await process_frame
	await process_frame
	_check(scene._postfx.attached(), "crt on brings it back")
	var run_accent: Color = Palette.for_run(s.palette_id).accent
	var foe = s.floor_map.monsters[0]
	var accent := func() -> Vector3: return scene._postfx.material.get_shader_parameter("accent")
	_check(accent.call().is_equal_approx(Vector3(run_accent.r, run_accent.g, run_accent.b)), "walking, the accent is the run's")
	await scene.flow.go("intro", {"foe": foe})
	var monster_accent: Color = Palette.monster(foe)
	_check(accent.call().is_equal_approx(Vector3(monster_accent.r, monster_accent.g, monster_accent.b)), "in a fight it is the monster's")
	_check(scene._overlay.intro_flash() > 0.0, "and the fight begins in a flash")
	await scene.flow.go("menu")
	await scene.flow.go("explore")
	_check(accent.call().is_equal_approx(Vector3(run_accent.r, run_accent.g, run_accent.b)), "after the fight the run's accent is back (no stale monster colour)")
	scene._automap.state = s
	await process_frame
	await process_frame
	_check(scene._automap.visible, "the automap shows while walking")
	await scene.flow.go("intro", {"foe": foe})
	await process_frame
	await process_frame
	_check(not scene._automap.visible, "and steps aside in a fight")
	scene.free()
