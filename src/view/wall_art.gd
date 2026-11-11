## The things on the walls as drawings: the same placements as decor.gd, flat on the wall, one mesh and one atlas,
## and flames on quads that face you. They answer how warm the halls are (rules/warmth.gd): the torches look at you, look away, shut their
## eyes; a skull nods, then stares; a cracked wall that gives is a guilty smile, then only a crack. At the coldest the flames are the wire ones.
extends RefCounted

const Decor = preload("res://src/view/decor.gd")
const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const Materials = preload("res://src/view/materials.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")
const Sprites = preload("res://src/view/sprites.gd")

const LIFT := 0.012 # how far a drawing stands off the wall
const SIZE := {"torch": 0.74, "chains": 0.86, "banner": 0.96, "crack": 0.9, "window": 1.12, "skull": 1.06, "skull_nod": 1.06, "skull_hollow": 1.06, "guilty": 1.5, "fissure": 1.5, "moss": 0.66, "bat": 0.52}
const DOWN := {"torch": 0.44, "chains": 0.26, "banner": 0.3, "crack": 0.48, "window": 0.42, "skull": 0.5, "skull_nod": 0.5, "skull_hollow": 0.5, "guilty": 0.46, "fissure": 0.46, "moss": 0.82, "bat": 0.16}
const TORCH_BOWL := Vector2(0.13, 0.18) # where a flame stands, off the middle of the torch's drawing, as a share of its size
const EYES_AT_LEVEL := [0, 4, 2, 1, 3] # cold, shut, wary, kind, beloved: what shaders/flame_drawn.gdshader shows
const SKULL_HOLLOW_BELOW := 2 # at this level and under, a skull's eyes are holes
const SKULL_NODS_FROM := 3
const GUILTY_FROM := 2
const OTHER_CRACKS := ["crack", "crack", "moss", "bat"] # what a plain crack may be instead, by the roll that placed it


## A node holding the drawings of `floor_map` at warmth level `level`. `torches` (an Array) gets {"pos": Vector3, "seed": float} per torch, for the caller to light the walls with.
static func build(floor_map, wall_color: Color, accent: Color, torches: Array, level: int) -> Node3D:
	var root := Node3D.new()
	var art := MeshKit.Builder.new()
	var flames := MeshKit.Builder.new()
	var half := Materials.CELL / 2.0
	var ink := MeshKit.color(wall_color)
	for p in Decor.placements(floor_map):
		var face = Decor._Face.new(DungeonMesh.center(p.cell), p.side, half)
		match p.kind:
			"torch":
				_draw_on(art, face, "torch", ink, p.roll)
				_flame(flames, torches, face, p.roll)
			"chains", "banner":
				_draw_on(art, face, p.kind, ink, p.roll)
			"window":
				_draw_on(art, face, "window", ink, p.roll)
			"crack":
				_draw_on(art, face, OTHER_CRACKS[int(p.roll * 97.0) % OTHER_CRACKS.size()], ink, p.roll)
			"niche":
				if level < SKULL_HOLLOW_BELOW:
					_draw_on(art, face, "skull_hollow", ink, p.roll)
				else:
					_draw_on(art, face, "skull", ink, p.roll, "skull_nod" if level >= SKULL_NODS_FROM else "")
			"fissure":
				_draw_on(art, face, "guilty" if level >= GUILTY_FROM else "fissure", MeshKit.color(accent), p.roll)
	if not art.is_empty():
		var shapes := MeshInstance3D.new()
		shapes.name = "Props"
		shapes.mesh = art.commit()
		shapes.material_override = Materials.wall_art()
		shapes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(shapes)
	if not flames.is_empty():
		var fire := MeshInstance3D.new()
		fire.name = "Flames"
		fire.mesh = flames.commit()
		fire.material_override = Materials.flame(accent) if level <= 0 else Materials.flame_drawn(accent, EYES_AT_LEVEL[level])
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.extra_cull_margin = 1.0 # the shader raises the quads off the point their vertices sit at
		root.add_child(fire)
	print_verbose("wall art: %d triangles, %d torches, level %d" % [art.triangles(), torches.size(), level])
	return root


# A drawing flat on the wall. `alt` is a second drawing it swaps to now and then while you are near (shaders/wall_art.gdshader).
static func _draw_on(art: MeshKit.Builder, face, drawing: String, tint: Color, roll: float, alt := "") -> void:
	var size: float = SIZE[drawing]
	var f: Transform3D = face.frame(0.5, DOWN[drawing], LIFT)
	var r := Sprites.uv_rect("decor", Sprites.drawing_rect("decor", drawing))
	var other := 0.0
	if alt != "":
		other = Sprites.uv_rect("decor", Sprites.drawing_rect("decor", alt)).x - r.x
	var s := size / 2.0
	var n: Vector3 = face.inward
	var extra := Vector2(other, roll)
	var a := art.vertex(f * Vector3(-s, s, 0.0), n, tint, Vector2(r.x, r.y), extra)
	var b := art.vertex(f * Vector3(s, s, 0.0), n, tint, Vector2(r.x + r.z, r.y), extra)
	var c := art.vertex(f * Vector3(s, -s, 0.0), n, tint, Vector2(r.x + r.z, r.y + r.w), extra)
	var d := art.vertex(f * Vector3(-s, -s, 0.0), n, tint, Vector2(r.x, r.y + r.w), extra)
	art.tri_idx(a, b, c)
	art.tri_idx(a, c, d)


static func _flame(flames: MeshKit.Builder, torches: Array, face, roll: float) -> void:
	var size: float = SIZE.torch
	var f: Transform3D = face.frame(0.5, DOWN.torch, 0.06)
	var foot: Vector3 = f * Vector3(TORCH_BOWL.x * size, TORCH_BOWL.y * size, 0.0)
	var seed_uv := Vector2(roll, 0)
	var i0 := flames.vertex(foot, Vector3.UP, Color.WHITE, Vector2(-1, 0), seed_uv)
	var i1 := flames.vertex(foot, Vector3.UP, Color.WHITE, Vector2(-1, 1), seed_uv)
	var i2 := flames.vertex(foot, Vector3.UP, Color.WHITE, Vector2(1, 1), seed_uv)
	var i3 := flames.vertex(foot, Vector3.UP, Color.WHITE, Vector2(1, 0), seed_uv)
	flames.tri_idx(i0, i1, i2)
	flames.tri_idx(i0, i2, i3)
	torches.append({"pos": foot + Vector3.UP * 0.2 + (face.inward as Vector3) * 0.3, "seed": roll})
