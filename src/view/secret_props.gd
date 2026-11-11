## What a floor hides, once you can see it: the pads, rings of light on the floor, the chests, and things lying about. Built from the
## floor's lists, so building it again is how a chest that was taken goes away.
extends RefCounted

const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const Figure = preload("res://src/view/figure.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Materials = preload("res://src/view/materials.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")

const PAD_RINGS := [[0.42, 0.04], [0.26, 0.03], [0.1, 0.1]] # half width and thickness of each ring, in cells
const LIFT := 0.012 # how far a ring sits off the floor, so the two don't flicker into each other
const CHEST := Vector3(0.9, 0.42, 0.6)
const DRAWN_CHEST := 0.56 # how tall the drawings stand
const DRAWN_SACK := 0.44
const LID_H := 0.16
const STIR_MOTES := 18
const STIR_RADIUS := 0.26
const STIR_HEIGHT := 1.0
const STIR_MOTE := 0.07


## A node holding them all, or an empty one for a floor that hides nothing.
static func build(floor_map, wall_color: Color, accent: Color, drawn := false) -> Node3D:
	var root := Node3D.new()
	var b := MeshKit.Builder.new()
	for t in floor_map.teleports:
		_pad(b, DungeonMesh.center(t.a), accent)
		_pad(b, DungeonMesh.center(t.b), accent)
	for t in floor_map.treasure:
		if drawn:
			_standing(root, "chest", accent, DRAWN_CHEST, t.cell)
		else:
			_chest(b, DungeonMesh.center(t.cell), wall_color, accent)
	for p in floor_map.pickups:
		if drawn:
			_standing(root, "sack", wall_color, DRAWN_SACK, p.cell)
		else:
			_sack(b, DungeonMesh.center(p.cell), wall_color, accent)
	if not b.is_empty():
		var shapes := MeshInstance3D.new()
		shapes.name = "Secrets"
		shapes.mesh = b.commit()
		shapes.material_override = Materials.prop()
		shapes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(shapes)
	return root


## A drawing that stands in its cell and turns to you (the stage turns it).
static func _standing(root: Node3D, drawing: String, tint: Color, height: float, cell: Vector2i) -> void:
	var out: Node3D = Figure.prop("props", drawing, tint, height)
	out.position = DungeonMesh.center(cell)
	root.add_child(out)


## What you see of something stirring: motes going round a pillar of air, in a node of their own, which the stage turns.
static func stir(color: Color) -> MeshInstance3D:
	var b := MeshKit.Builder.new()
	var glow := MeshKit.color(color, true)
	for i in STIR_MOTES:
		var a := float(i) / STIR_MOTES * TAU * 3.0
		var at := Vector3(cos(a) * STIR_RADIUS, 0.12 + float(i) / STIR_MOTES * STIR_HEIGHT, sin(a) * STIR_RADIUS)
		b.box(Transform3D(Basis(Vector3.UP, a), at), Vector3.ONE * STIR_MOTE, glow)
	var out := MeshInstance3D.new()
	out.mesh = b.commit()
	out.material_override = Materials.prop()
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return out


## A small sack with a bright tie, sat on the floor.
static func _sack(b: MeshKit.Builder, mid: Vector3, wall_color: Color, accent: Color) -> void:
	b.sphere(Transform3D(Basis(), mid + Vector3(0, 0.2, 0)), Vector3(0.24, 0.2, 0.24), MeshKit.color(wall_color), 10, 6)
	b.box(Transform3D(Basis(), mid + Vector3(0, 0.42, 0)), Vector3(0.14, 0.06, 0.14), MeshKit.color(accent, true))


static func _pad(b: MeshKit.Builder, mid: Vector3, accent: Color) -> void:
	var col := MeshKit.color(accent, true)
	for ring in PAD_RINGS:
		var o: float = ring[0] * Materials.CELL
		var n: float = (ring[0] - ring[1]) * Materials.CELL
		var y := LIFT
		for r in [[-o, -o, o, -n], [-o, n, o, o], [-o, -n, -n, n], [n, -n, o, n]]:
			b.quad(mid + Vector3(r[0], y, r[1]), mid + Vector3(r[2], y, r[1]), mid + Vector3(r[2], y, r[3]), mid + Vector3(r[0], y, r[3]), col)


static func _chest(b: MeshKit.Builder, mid: Vector3, wall_color: Color, accent: Color) -> void:
	var ink := MeshKit.color(wall_color)
	var gold := MeshKit.color(accent, true)
	b.box(Transform3D(Basis(), mid + Vector3(0, CHEST.y / 2.0, 0)), CHEST, ink)
	b.box(Transform3D(Basis(), mid + Vector3(0, CHEST.y + LID_H / 2.0, 0)), Vector3(CHEST.x + 0.06, LID_H, CHEST.z + 0.06), ink)
	var top := CHEST.y + LID_H + 0.005
	var lid := Vector3(CHEST.x * 0.42, 0.0, CHEST.z * 0.36)
	b.quad(mid + Vector3(-lid.x, top, -lid.z), mid + Vector3(lid.x, top, -lid.z), mid + Vector3(lid.x, top, lid.z), mid + Vector3(-lid.x, top, lid.z), gold) # a lid that catches the eye from the door
	for side in 4: # a clasp on every face: you may come at it from any side
		var out := Vector3(FloorMap.DIRS[side].x, 0, FloorMap.DIRS[side].y)
		var reach: float = (CHEST.z if side % 2 == 0 else CHEST.x) / 2.0 + 0.04
		var size := Vector3(0.16, 0.22, 0.02) if side % 2 == 0 else Vector3(0.02, 0.22, 0.16)
		b.box(Transform3D(Basis(), mid + out * reach + Vector3(0, CHEST.y, 0)), size, gold)
