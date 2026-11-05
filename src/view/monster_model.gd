## A monster's body in its full detail: spheres, cones, boxes and limbs (mesh_kit.gd), black inside and outlined in its
## colour, with the dots and slits of its face drawn solid (shaders/solid, shaders/ink). The model stands on the floor at its
## origin and faces +Z. `pose` moves its parts the way each species moves: the slime wobbles, the dragon flaps and nods, the
## snake sways and flicks its tongue, the rock breathes, the bandit shifts its weight; a hit shakes the whole thing.
##
## It is a Node3D with a "Rig" child (shaken when hurt) holding one MeshInstance3D per moving part. The meshes of a species
## in a colour are built once and shared; each model has its own material, so a hit can light it alone.
extends RefCounted

const Materials = preload("res://src/view/materials.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")
const SpriteModels = preload("res://src/view/sprite_models.gd")

const HURT_SHAKE := 0.07
const SCALE := 0.92 # every model, the champion too: at this size the tallest still stands under the ceiling
const FACE_LIFT := 0.012 # how far a pupil sits in front of its ring

static var _parts := {} # "species|colour" -> [[part name, ArrayMesh, Transform3D], ...]


## `species` is a key of data/species.json; `tint` the colour of its lines. `like_sprite` shapes it after its fight sprite (sprite-look).
static func build(species: String, tint: Color, like_sprite := false) -> Node3D:
	var root := Node3D.new()
	var rig := Node3D.new() # everything a hit shakes
	rig.name = "Rig"
	root.add_child(rig)
	var material := Materials.model()
	root.set_meta("species", species)
	root.set_meta("material", material)
	for p in _parts_of(species, tint, like_sprite):
		var part := MeshInstance3D.new()
		part.name = p[0]
		part.mesh = p[1]
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.transform = p[2]
		part.set_meta("rest", p[2])
		rig.add_child(part)
	root.scale = Vector3.ONE * SCALE
	return root


## A part of a model by name, or null.
static func part(model: Node3D, part_name: String) -> MeshInstance3D:
	return model.get_node_or_null("Rig/" + part_name) as MeshInstance3D


## Move the parts for time `t` (seconds); `hurt` 0..1 shakes the whole thing.
static func pose(model: Node3D, t: float, hurt: float) -> void:
	var rig: Node3D = model.get_node("Rig")
	rig.position = Vector3(sin(t * 47.0) * HURT_SHAKE * hurt, 0.0, 0.0)
	match str(model.get_meta("species")):
		"slime":
			var wob := sin(t / 0.38)
			_at(model, "Body", Vector3.ZERO, Vector3.ZERO, Vector3(1.0 + wob * 0.035, 1.0 - wob * 0.045, 1.0 + wob * 0.035))
		"dragon":
			var flap := sin(t / 0.6)
			_at(model, "WingL", Vector3.ZERO, Vector3(0, 0, -flap * 0.28))
			_at(model, "WingR", Vector3.ZERO, Vector3(0, 0, flap * 0.28))
			_at(model, "Head", Vector3(0, sin(t / 0.9) * 0.02, 0))
		"snake":
			var sway := sin(t / 0.5)
			_at(model, "Upper", Vector3(sway * 0.06, 0, 0), Vector3(0, 0, -sway * 0.05))
			_at(model, "Tongue", Vector3(sway * 0.06, 0, 0), Vector3(0, 0, -sway * 0.05))
			part(model, "Tongue").visible = sin(t / 0.22) > 0.2
		"rock":
			_at(model, "Upper", Vector3(0, sin(t / 0.9) * 0.025, 0))
		"bandit":
			var shift := sin(t / 0.45)
			_at(model, "Body", Vector3(shift * 0.04, 0, 0), Vector3(0, shift * 0.05, 0))


## Light the whole model up in its colour (a hit). 0 off .. 1 fully lit.
static func flash(model: Node3D, amount: float) -> void:
	model.get_meta("material").set_shader_parameter("flash", amount)


## The height of the model's highest point above its feet, as it stands (its scale counted).
static func top_of(model: Node3D) -> float:
	var best := 0.0
	for p in model.get_node("Rig").get_children():
		var box: AABB = p.mesh.get_aabb()
		for i in 8:
			best = maxf(best, (p.transform * box.get_endpoint(i)).y)
	return best * model.scale.y


# A part moved from its rest pose: offset, then rotated (radians, XYZ) and scaled.
static func _at(model: Node3D, part_name: String, offset := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var p := part(model, part_name)
	var rest: Transform3D = p.get_meta("rest")
	p.transform = Transform3D(rest.basis * Basis.from_euler(rot).scaled(scl), rest.origin + offset)


static func _parts_of(species: String, tint: Color, like_sprite: bool) -> Array:
	var key := "%s|%s|%s" % [species, tint.to_html(), like_sprite]
	if _parts.has(key):
		return _parts[key]
	var ln := MeshKit.color(tint) # lines
	var dot := MeshKit.color(tint, true) # drawn solid
	var built: Dictionary = SpriteModels.parts(species, ln) if like_sprite else {}
	match species if built.is_empty() else "":
		"slime":
			built = _slime(ln, dot)
		"bandit":
			built = _bandit(ln, dot)
		"snake":
			built = _snake(ln, dot)
		"rock":
			built = _rock(ln, dot)
		"dragon":
			built = _dragon(ln, dot)
		"":
			pass
		_:
			push_warning("monster_model: no model for '%s', using a block" % species)
			var block := _b()
			block.box(_t(0, 0.5, 0), Vector3(0.8, 1.0, 0.8), ln)
			built = {"Body": [block, Transform3D()]}
	var out := []
	var tris := 0
	for part_name in built:
		var b: MeshKit.Builder = built[part_name][0]
		tris += b.triangles()
		out.append([part_name, b.commit(), built[part_name][1]])
	print_verbose("monster_model: %s, %d parts, %d triangles" % [species, out.size(), tris])
	_parts[key] = out
	return out


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


static func _tr(x: float, y: float, z: float, axis: Vector3, angle: float) -> Transform3D:
	return Transform3D(Basis(axis.normalized(), angle), Vector3(x, y, z))


static func _b() -> MeshKit.Builder:
	return MeshKit.Builder.new()


# An eye: a ring (a flat disc, outlined) round a dot of a pupil, in front of the disc so its black doesn't hide it.
static func _eye(b: MeshKit.Builder, x: float, y: float, z: float, r: float, pupil: float, ln: Color, dot: Color) -> void:
	b.sphere(_t(x, y, z), Vector3(r, r, r * 0.45), ln, 12, 6)
	b.sphere(_t(x, y, z + r * 0.45 + FACE_LIFT), Vector3(pupil, pupil, pupil * 0.5), dot, 8, 4)


# ---------------------------------------------------------------- species

# Orange slime: a wobbling dome with a blank, unblinking stare, sitting in its own puddle.
static func _slime(ln: Color, dot: Color) -> Dictionary:
	var b := _b()
	b.sphere(_t(0, 0.36, 0), Vector3(0.6, 0.7, 0.54), ln, 20, 10) # the dome
	b.sphere(_t(-0.34, 0.06, 0.38), Vector3(0.07, 0.09, 0.07), ln, 8, 4) # drips
	b.sphere(_t(0.27, 0.05, 0.42), Vector3(0.05, 0.07, 0.05), ln, 8, 4)
	_eye(b, -0.19, 0.72, 0.42, 0.13, 0.02, ln, dot)
	_eye(b, 0.19, 0.72, 0.42, 0.13, 0.02, ln, dot)
	b.box(_t(0, 0.5, 0.545), Vector3(0.14, 0.022, 0.02), dot) # a flat little mouth
	var puddle := _b()
	puddle.sphere(_t(0, 0.0, 0.04), Vector3(0.8, 0.03, 0.66), ln, 20, 4)
	return {"Puddle": [puddle, Transform3D()], "Body": [b, Transform3D()]}


# Yellow dragon: wings spread, a horned head, a plated belly and a spiked tail curled to one side.
static func _dragon(ln: Color, dot: Color) -> Dictionary:
	var b := _b()
	b.sphere(_t(0, 0.62, 0), Vector3(0.44, 0.38, 0.38), ln, 16, 8) # body
	b.sphere(_t(0, 0.6, 0.27), Vector3(0.28, 0.28, 0.13), ln, 12, 6) # belly plates
	for y in [0.48, 0.6, 0.72]:
		b.box(_t(0, y, 0.39), Vector3(0.36 - absf(y - 0.6), 0.015, 0.02), ln)
	for s in [-1.0, 1.0]: # legs and claws
		b.limb(Vector3(0.24 * s, 0.4, 0.1), Vector3(0.3 * s, 0.08, 0.18), 0.12, 0.08, ln)
		for c in [-0.05, 0.0, 0.05]:
			b.limb(Vector3(0.3 * s + c, 0.06, 0.2), Vector3(0.3 * s + c * 1.6, 0.0, 0.32), 0.03, 0.0, ln, 4)
	b.limb(Vector3(0.0, 0.9, 0.08), Vector3(0.0, 1.22, 0.14), 0.16, 0.1, ln) # neck
	var pts := [Vector3(0.3, 0.42, -0.25), Vector3(0.68, 0.24, -0.15), Vector3(0.9, 0.24, 0.1), Vector3(0.95, 0.38, 0.32)]
	for i in pts.size() - 1: # tail
		b.limb(pts[i], pts[i + 1], 0.13 - i * 0.035, 0.1 - i * 0.035, ln)
	for e in [[Vector3(0.95, 0.38, 0.32), Vector3(1.08, 0.55, 0.36)], [Vector3(1.08, 0.55, 0.36), Vector3(0.88, 0.5, 0.42)], [Vector3(0.88, 0.5, 0.42), Vector3(0.95, 0.38, 0.32)]]:
		b.limb(e[0], e[1], 0.01, 0.01, ln, 4) # the tail's spade
	var head := _b()
	head.sphere(_t(0, 1.34, 0.18), Vector3(0.2, 0.17, 0.22), ln, 14, 7)
	head.sphere(_t(0, 1.29, 0.38), Vector3(0.13, 0.1, 0.14), ln, 12, 6) # snout
	for s in [-1.0, 1.0]:
		head.limb(Vector3(0.1 * s, 1.45, 0.1), Vector3(0.26 * s, 1.74, -0.06), 0.055, 0.0, ln, 8) # horns
		head.box(_tr(0.085 * s, 1.39, 0.395, Vector3(0, 0, 1), 0.3 * s), Vector3(0.08, 0.022, 0.03), dot) # slit eyes
		head.sphere(_t(0.05 * s, 1.31, 0.525), Vector3(0.016, 0.016, 0.01), dot, 6, 3) # nostrils
	for i in 5:
		var x := -0.08 + i * 0.04
		head.limb(Vector3(x, 1.235, 0.44), Vector3(x, 1.2, 0.45), 0.014, 0.0, ln, 4) # teeth
	var parts := {"Body": [b, Transform3D()], "Head": [head, Transform3D()]}
	for side in [["WingL", -1.0], ["WingR", 1.0]]:
		parts[side[0]] = [_wing(side[1], ln), _t(0.22 * side[1], 0.86, -0.12)]
	return parts


# In the wing's own frame: the shoulder at the origin, the span out along +X (mirrored for the left). Bones are limbs; the
# membrane between them is black on both sides, hiding what is behind it, its scalloped edge drawn.
static func _wing(s: float, ln: Color) -> MeshKit.Builder:
	var w := _b()
	var tip := Vector3(0.84 * s, 0.68, -0.08)
	var elbow := Vector3(0.42 * s, 0.5, -0.05)
	var fingers := [Vector3(0.78 * s, 0.02, -0.04), Vector3(0.54 * s, -0.22, -0.02), Vector3(0.26 * s, -0.24, 0.0)]
	w.limb(Vector3.ZERO, elbow, 0.06, 0.045, ln, 8)
	w.limb(elbow, tip, 0.045, 0.015, ln, 8)
	var edge := [tip] + fingers + [Vector3(0.0, -0.1, 0.0)]
	for f in fingers:
		w.limb(elbow, f, 0.025, 0.01, ln, 6)
	for i in edge.size() - 1:
		w.tri(elbow, edge[i], edge[i + 1], MeshKit.bare(ln))
		w.tri(elbow, edge[i + 1], edge[i], MeshKit.bare(ln))
		w.limb(edge[i], edge[i + 1], 0.008, 0.008, ln, 4)
	w.tri(Vector3.ZERO, elbow, Vector3(0.0, -0.1, 0.0), MeshKit.bare(ln))
	w.tri(Vector3.ZERO, Vector3(0.0, -0.1, 0.0), elbow, MeshKit.bare(ln))
	return w


# Green snake person: a hooded serpent torso rising from its coils, clawed arms, a forked tongue that flicks.
static func _snake(ln: Color, dot: Color) -> Dictionary:
	var coils := _b()
	coils.torus(_t(0, 0.14, 0), 0.4, 0.66, ln) # (its tube clear of the floor, which would eat the outline under it)
	coils.torus(_t(0.02, 0.3, 0), 0.3, 0.54, ln)
	coils.torus(_t(0.04, 0.46, 0), 0.18, 0.4, ln)
	coils.limb(Vector3(0.6, 0.1, 0.1), Vector3(0.88, 0.14, 0.3), 0.12, 0.03, ln) # the tail's tip
	var up := _b()
	up.limb(Vector3(0, 0.45, 0), Vector3(0, 1.16, 0.06), 0.21, 0.15, ln) # torso rising
	up.sphere(_t(0, 0.82, 0.13), Vector3(0.14, 0.34, 0.08), ln, 12, 6) # belly scales
	for y in [0.62, 0.74, 0.86, 0.98]:
		up.box(_t(0, y, 0.215), Vector3(0.2, 0.012, 0.02), ln)
	up.sphere(_t(0, 1.4, -0.04), Vector3(0.38, 0.4, 0.07), ln, 16, 8) # the cobra hood
	for s in [-1.0, 1.0]:
		up.sphere(_t(0.18 * s, 1.44, 0.03), Vector3(0.07, 0.1, 0.02), ln, 8, 4) # hood markings
		up.limb(Vector3(0.14 * s, 1.08, 0.04), Vector3(0.44 * s, 0.94, 0.12), 0.07, 0.06, ln) # clawed arms
		up.limb(Vector3(0.44 * s, 0.94, 0.12), Vector3(0.4 * s, 0.76, 0.22), 0.06, 0.05, ln)
		for c in [-0.04, 0.0, 0.04]:
			up.limb(Vector3(0.4 * s, 0.74, 0.22), Vector3(0.4 * s + c, 0.66, 0.28), 0.018, 0.0, ln, 4)
	up.sphere(_t(0, 1.38, 0.1), Vector3(0.15, 0.16, 0.19), ln, 14, 7) # head
	for s in [-1.0, 1.0]:
		up.sphere(_t(0.075 * s, 1.43, 0.27), Vector3(0.04, 0.03, 0.02), dot, 8, 4) # slit eyes
		up.box(_t(0.075 * s, 1.43, 0.29), Vector3(0.008, 0.05, 0.008), dot)
	var tongue := _b()
	tongue.limb(Vector3(0, 1.3, 0.27), Vector3(0, 1.26, 0.4), 0.012, 0.01, ln, 4)
	tongue.limb(Vector3(0, 1.26, 0.4), Vector3(-0.03, 1.22, 0.46), 0.01, 0.0, ln, 4)
	tongue.limb(Vector3(0, 1.26, 0.4), Vector3(0.03, 1.22, 0.46), 0.01, 0.0, ln, 4)
	return {"Coils": [coils, Transform3D()], "Upper": [up, Transform3D()], "Tongue": [tongue, Transform3D()]}


# Grey rock entity: a heap of boulders with arms, cracked all over, one glowing crack for an eye.
static func _rock(ln: Color, dot: Color) -> Dictionary:
	var low := _b()
	for p in [[-0.5, 0.06, 0.4, 0.1], [0.46, 0.05, 0.45, 0.08], [0.62, 0.07, -0.1, 0.11]]: # pebbles
		low.sphere(_t(p[0], p[1], p[2]), Vector3.ONE * p[3], ln, 6, 3)
	var up := _b()
	up.sphere(_tr(0, 0.62, 0, Vector3(0, 1, 0), 0.4), Vector3(0.62, 0.58, 0.5), ln, 7, 4) # the heap
	up.sphere(_tr(0.05, 1.27, 0.02, Vector3(0, 1, 0), 0.9), Vector3(0.33, 0.3, 0.3), ln, 6, 4) # head
	up.sphere(_t(-0.25, 1.02, 0.25), Vector3(0.12, 0.05, 0.1), ln, 8, 4) # moss
	for s in [-1.0, 1.0]:
		up.sphere(_tr(0.7 * s, 0.86, 0.05, Vector3(0, 0, 1), 0.6 * s), Vector3(0.26, 0.22, 0.22), ln, 6, 3) # upper arm
		up.sphere(_tr(0.82 * s, 0.44, 0.15, Vector3(1, 1, 0), 0.5), Vector3(0.27, 0.25, 0.25), ln, 6, 3) # fist
	# cracks over the heap, and the crack of an eye, drawn solid
	var crack := [Vector3(-0.08, 0.95, 0.44), Vector3(0.02, 0.76, 0.5), Vector3(-0.04, 0.6, 0.5), Vector3(0.06, 0.42, 0.47)]
	for i in crack.size() - 1:
		up.limb(crack[i], crack[i + 1], 0.018, 0.018, dot, 4)
	up.limb(Vector3(0.3, 0.85, 0.38), Vector3(0.22, 0.66, 0.44), 0.015, 0.015, dot, 4)
	var eye := [Vector3(-0.17, 1.3, 0.3), Vector3(-0.09, 1.34, 0.32), Vector3(-0.02, 1.29, 0.34), Vector3(0.07, 1.35, 0.33), Vector3(0.16, 1.31, 0.31)]
	for i in eye.size() - 1:
		up.limb(eye[i], eye[i + 1], 0.024, 0.024, dot, 5)
	return {"Low": [low, Transform3D()], "Upper": [up, Transform3D()]}


# Red bandit: a hooded cloak, a bandana over the face, a belt with a coin pouch, a knife in each hand.
static func _bandit(ln: Color, dot: Color) -> Dictionary:
	var b := _b()
	b.limb(Vector3(-0.14, 0, 0.02), Vector3(-0.13, 0.5, 0.02), 0.08, 0.1, ln) # legs
	b.limb(Vector3(0.14, 0, 0.02), Vector3(0.13, 0.5, 0.02), 0.08, 0.1, ln)
	b.cylinder(_t(0, 0.12, -0.04), 0.5, 0.24, 1.1, ln, 16) # the cloak
	b.box(_t(0, 0.82, 0.2), Vector3(0.36, 0.62, 0.12), ln) # tunic, the cloak open over it
	b.box(_t(0, 0.68, 0.27), Vector3(0.4, 0.07, 0.04), ln) # belt
	b.box(_t(0, 0.68, 0.3), Vector3(0.08, 0.07, 0.02), ln) # buckle
	b.sphere(_t(0.14, 0.56, 0.3), Vector3(0.07, 0.08, 0.05), ln, 8, 4) # coin pouch
	b.sphere(_t(0, 1.43, 0.08), Vector3(0.17, 0.2, 0.17), ln, 14, 7) # head, the face out of the hood
	b.sphere(_t(0, 1.48, -0.09), Vector3(0.25, 0.29, 0.23), ln, 16, 8) # hood
	b.limb(Vector3(0, 1.66, -0.16), Vector3(0, 1.8, -0.26), 0.09, 0.0, ln, 8) # the hood's point
	b.sphere(_t(0, 1.355, 0.12), Vector3(0.175, 0.09, 0.14), ln, 12, 6) # bandana mask
	b.limb(Vector3(0.14, 1.37, 0.0), Vector3(0.3, 1.26, -0.06), 0.03, 0.0, ln, 6) # knot tails
	b.limb(Vector3(0.14, 1.37, 0.0), Vector3(0.33, 1.36, -0.04), 0.03, 0.0, ln, 6)
	for s in [-1.0, 1.0]:
		b.box(_tr(0.065 * s, 1.465, 0.27, Vector3(0, 0, 1), 0.15 * s), Vector3(0.07, 0.02, 0.02), dot) # narrowed eyes
	# left arm: the knife held forward
	b.limb(Vector3(-0.28, 1.18, 0), Vector3(-0.4, 0.9, 0.16), 0.08, 0.07, ln)
	b.limb(Vector3(-0.4, 0.9, 0.16), Vector3(-0.28, 0.86, 0.38), 0.07, 0.06, ln)
	b.sphere(_t(-0.27, 0.86, 0.4), Vector3.ONE * 0.06, ln, 8, 4)
	b.box(_tr(-0.2, 0.92, 0.5, Vector3(1, 0, 0), -0.9), Vector3(0.035, 0.22, 0.012), ln)
	# right arm: the knife raised
	b.limb(Vector3(0.28, 1.18, 0), Vector3(0.5, 1.32, 0.1), 0.08, 0.07, ln)
	b.limb(Vector3(0.5, 1.32, 0.1), Vector3(0.56, 1.56, 0.12), 0.07, 0.06, ln)
	b.sphere(_t(0.56, 1.58, 0.12), Vector3.ONE * 0.06, ln, 8, 4)
	b.box(_tr(0.6, 1.72, 0.1, Vector3(0, 0, 1), -0.25), Vector3(0.035, 0.2, 0.012), ln)
	b.box(_t(0.57, 1.63, 0.12), Vector3(0.1, 0.025, 0.03), ln) # crossguard
	return {"Body": [b, Transform3D()]}
