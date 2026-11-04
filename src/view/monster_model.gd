## A monster's body, built from a few simple shapes (spheres, boxes, cones), black inside and outlined in its colour.
## Each species has its own silhouette. The model stands on the floor at its origin and faces +Z; `pose` moves its parts
## (breathing, wings) and shakes it when hurt.
extends RefCounted

const Materials = preload("res://src/view/materials.gd")

const HURT_SHAKE := 0.07


## `species` is a key of data/species.json; `tint` the colour of its lines; `boss` makes it larger.
static func build(species: String, tint: Color, boss := false) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new() # everything that bobs together
	body.name = "Body"
	root.add_child(body)
	var solid := Materials.model(tint)
	var flat := Materials.model(tint, true)
	match species:
		"slime":
			_slime(body, solid, flat)
		"bandit":
			_bandit(body, solid, flat)
		"snake":
			_snake(body, solid, flat)
		"rock":
			_rock(body, solid, flat)
		"dragon":
			_dragon(body, solid, flat)
		_:
			push_warning("monster_model: no model for '%s', using a block" % species)
			_part(body, _box(Vector3(0.8, 1.0, 0.8)), Vector3(0, 0.5, 0), solid)
	root.set_meta("materials", [solid, flat])
	if boss:
		root.scale = Vector3.ONE * 1.25
	return root


## Move the parts for time `t` (seconds); `hurt` 0..1 shakes the whole thing.
static func pose(model: Node3D, t: float, hurt: float) -> void:
	var body: Node3D = model.get_node("Body")
	body.position = Vector3(sin(t * 47.0) * HURT_SHAKE * hurt, sin(t * 2.2) * 0.04, 0.0)
	var flap := sin(t * 3.0) * 0.25
	for wing in body.find_children("Wing*", "Node3D", true, false):
		wing.rotation.z = (flap if wing.name.ends_with("L") else -flap) + (0.35 if wing.name.ends_with("L") else -0.35)


## Light the whole model up in its colour (a hit). 0 off .. 1 fully lit.
static func flash(model: Node3D, amount: float) -> void:
	for m in model.get_meta("materials"):
		m.set_shader_parameter("flash", amount)


# ---------------------------------------------------------------- species

static func _slime(body: Node3D, solid: Material, flat: Material) -> void:
	_part(body, _sphere(0.55), Vector3(0, 0.42, 0), solid, Vector3(1.25, 0.8, 1.15))
	_part(body, _sphere(0.1), Vector3(-0.2, 0.55, 0.5), flat)
	_part(body, _sphere(0.1), Vector3(0.2, 0.55, 0.5), flat)
	_part(body, _sphere(0.05), Vector3(0, 0.38, 0.64), flat, Vector3(2.2, 0.8, 0.6)) # a small mouth


static func _bandit(body: Node3D, solid: Material, flat: Material) -> void:
	_part(body, _cone(0.42, 0.3, 1.0), Vector3(0, 0.5, 0), solid)
	_part(body, _sphere(0.25), Vector3(0, 1.18, 0), solid)
	_part(body, _cone(0.0, 0.34, 0.5), Vector3(0, 1.5, -0.02), solid) # the hood
	_part(body, _sphere(0.04), Vector3(-0.09, 1.2, 0.22), flat)
	_part(body, _sphere(0.04), Vector3(0.09, 1.2, 0.22), flat)
	_part(body, _box(Vector3(0.07, 0.8, 0.07)), Vector3(0.5, 0.85, 0.25), solid, Vector3.ONE, Vector3(0, 0, -0.5)) # a blade


static func _snake(body: Node3D, solid: Material, flat: Material) -> void:
	_part(body, _sphere(0.55), Vector3(0, 0.17, 0), solid, Vector3(1.1, 0.34, 1.1))
	_part(body, _sphere(0.42), Vector3(0, 0.46, 0), solid, Vector3(1.0, 0.36, 1.0))
	_part(body, _sphere(0.3), Vector3(0, 0.72, 0), solid, Vector3(1.0, 0.45, 1.0))
	_part(body, _sphere(0.24), Vector3(0, 1.02, 0.12), solid, Vector3(1.0, 0.85, 1.35))
	_part(body, _sphere(0.045), Vector3(-0.1, 1.08, 0.41), flat)
	_part(body, _sphere(0.045), Vector3(0.1, 1.08, 0.41), flat)
	_part(body, _box(Vector3(0.03, 0.02, 0.22)), Vector3(0, 0.98, 0.5), flat) # a tongue


static func _rock(body: Node3D, solid: Material, flat: Material) -> void:
	_part(body, _box(Vector3(0.95, 0.85, 0.85)), Vector3(0, 0.43, 0), solid, Vector3.ONE, Vector3(0, 0.35, 0))
	_part(body, _box(Vector3(0.6, 0.5, 0.6)), Vector3(0.5, 0.25, 0.3), solid, Vector3.ONE, Vector3(0, -0.4, 0))
	_part(body, _box(Vector3(0.5, 0.65, 0.5)), Vector3(-0.45, 0.55, -0.1), solid, Vector3.ONE, Vector3(0, 0.7, 0))
	_part(body, _sphere(0.15), Vector3(0, 0.58, 0.5), flat, Vector3(1.0, 0.7, 0.4)) # one eye
	_part(body, _box(Vector3(0.5, 0.03, 0.04)), Vector3(0, 0.82, 0.5), flat, Vector3.ONE, Vector3(0, 0, 0.1)) # a crack


static func _dragon(body: Node3D, solid: Material, flat: Material) -> void:
	_part(body, _sphere(0.7), Vector3(0, 0.95, 0), solid, Vector3(1.0, 0.85, 1.45))
	_part(body, _cone(0.22, 0.3, 0.9), Vector3(0, 1.55, 0.55), solid, Vector3.ONE, Vector3(0.6, 0, 0)) # neck
	_part(body, _box(Vector3(0.45, 0.35, 0.7)), Vector3(0, 2.0, 0.95), solid) # head
	_part(body, _cone(0.0, 0.08, 0.35), Vector3(-0.17, 2.3, 0.75), solid)
	_part(body, _cone(0.0, 0.08, 0.35), Vector3(0.17, 2.3, 0.75), solid)
	_part(body, _sphere(0.05), Vector3(-0.15, 2.06, 1.28), flat)
	_part(body, _sphere(0.05), Vector3(0.15, 2.06, 1.28), flat)
	_part(body, _cone(0.0, 0.3, 1.3), Vector3(0, 0.75, -1.2), solid, Vector3.ONE, Vector3(-1.45, 0, 0)) # tail
	for side in [-1, 1]:
		var wing := Node3D.new()
		wing.name = "WingL" if side < 0 else "WingR"
		wing.position = Vector3(side * 0.55, 1.35, -0.1)
		body.add_child(wing)
		_part(wing, _box(Vector3(1.5, 0.04, 0.9)), Vector3(side * 0.8, 0.0, 0.0), solid)
		_part(wing, _cone(0.0, 0.09, 0.7), Vector3(side * 1.55, 0.0, 0.1), solid, Vector3.ONE, Vector3(0, 0, -side * 1.57))


# ---------------------------------------------------------------- building blocks

static func _sphere(radius: float) -> Mesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _box(size: Vector3) -> Mesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## A cone or tapered cylinder standing on its base.
static func _cone(top_radius: float, bottom_radius: float, height: float) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = top_radius
	c.bottom_radius = bottom_radius
	c.height = height
	c.radial_segments = 10
	c.rings = 1
	return c


static func _part(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, part_scale := Vector3.ONE, rotation := Vector3.ZERO) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = material
	inst.position = at
	inst.scale = part_scale
	inst.rotation = rotation
	parent.add_child(inst)
	return inst
