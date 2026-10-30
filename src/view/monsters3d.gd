## The six monsters as cel-shaded 3D models (the 3D counterparts of art.gd's line drawings): built from spheres,
## cones and boxes with their colors baked in (MeshKit), inked by the outline pass, and moved by `pose` the way the
## drawings moved: the slime wobbles, the goblin sways, the dragon flaps, the snake sways and flicks its tongue, the
## rock breathes, the bandit shifts its weight.
##
## A model stands on its own origin facing +Z (toward the camera, once Stage3D turns it), its feet at Y = 0. Each is a
## Node3D with a "Rig" child (shaken sideways when hurt) holding one MeshInstance3D per moving part.
## `look.color` repaints the body (the red champion); `look.shiny` makes it gold (art.gd's color rules).
extends RefCounted

const J = preload("res://src/core/js.gd")
const Art = preload("res://src/view/art.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")

const SPECIES = ["slime", "goblin", "dragon", "snake", "rock", "bandit"]

const WHITE := "#f4ecdc"
const DARK := "#120c10"
const TOOTH := "#f2ead8"
const STEEL := "#d6dbe6"
const GOLD := "#f0c24a"


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


static func _tr(x: float, y: float, z: float, axis: Vector3, angle: float) -> Transform3D:
	return Transform3D(Basis(axis.normalized(), angle), Vector3(x, y, z))


## A model of `species` in its look, every part drawn with `material` (Stage3D's monster_material: its own, so
## its flash is its own). Unknown species: an empty model and an error.
static func build(species: String, look: Dictionary, material: Material) -> Node3D:
	var root := Node3D.new()
	root.name = species.capitalize()
	var rig := Node3D.new()
	rig.name = "Rig"
	root.add_child(rig)
	root.set_meta("species", species)
	root.set_meta("material", material)
	var body := MeshKit.lin(Art.color_of(species, look))
	var parts: Dictionary
	match species:
		"slime":
			parts = _slime(body)
		"goblin":
			parts = _goblin(body)
		"dragon":
			parts = _dragon(body)
		"snake":
			parts = _snake(body)
		"rock":
			parts = _rock(body)
		"bandit":
			parts = _bandit(body)
		_:
			push_error("monsters3d: no monster called %s" % species)
			parts = {}
	for part_name in parts:
		var p: Array = parts[part_name] # [Builder, pivot]
		var mesh: ArrayMesh = p[0].commit()
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = part_name
		mi.mesh = mesh
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = p[1]
		mi.set_meta("rest", p[1])
		rig.add_child(mi)
	return root


static func part(model: Node3D, part_name: String) -> MeshInstance3D:
	return model.get_node_or_null("Rig/" + part_name) as MeshInstance3D


## Moves the model's parts for time t (ms; Stage3D passes the hit-stopped clock) and shows a hit: `hurt` 0..1
## shakes it sideways and flashes it white.
static func pose(model: Node3D, t: float, hurt := 0.0) -> void:
	var rig := model.get_node("Rig") as Node3D
	rig.position = Vector3(sin(t / 20.0) * hurt * 0.07, 0, 0) if hurt > 0.0 else Vector3.ZERO
	var mat = model.get_meta("material", null)
	if mat is ShaderMaterial:
		mat.set_shader_parameter("flash", hurt * 0.75)
	match str(model.get_meta("species", "")):
		"slime":
			var wob := sin(t / 380.0)
			_at(model, "Body", Vector3.ZERO, Vector3.ZERO, Vector3(1.0 + wob * 0.035, 1.0 - wob * 0.045, 1.0 + wob * 0.035))
		"goblin":
			var sway := sin(t / 700.0)
			_at(model, "Body", Vector3(sway * 0.035, 0, 0), Vector3(0, 0, -sway * 0.02))
			_at(model, "Club", Vector3(sway * 0.035, sin(t / 350.0) * 0.02, 0), Vector3(0, 0, -sway * 0.05))
		"dragon":
			var flap := sin(t / 600.0)
			_at(model, "WingL", Vector3.ZERO, Vector3(0, 0, -flap * 0.28))
			_at(model, "WingR", Vector3.ZERO, Vector3(0, 0, flap * 0.28))
			_at(model, "Head", Vector3(0, sin(t / 900.0) * 0.02, 0))
		"snake":
			var sway := sin(t / 500.0)
			_at(model, "Upper", Vector3(sway * 0.06, 0, 0), Vector3(0, 0, -sway * 0.05))
			var tongue := part(model, "Tongue")
			_at(model, "Tongue", Vector3(sway * 0.06, 0, 0), Vector3(0, 0, -sway * 0.05))
			if tongue != null:
				tongue.visible = sin(t / 220.0) > 0.2
		"rock":
			_at(model, "Upper", Vector3(0, sin(t / 900.0) * 0.025, 0))
		"bandit":
			var shift := sin(t / 450.0)
			_at(model, "Body", Vector3(shift * 0.04, 0, 0), Vector3(0, shift * 0.05, 0))


# A part moved from its rest pose: offset, then rotated (radians, XYZ) and scaled
static func _at(model: Node3D, part_name: String, offset := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var mi := part(model, part_name)
	if mi == null:
		return
	var rest: Transform3D = mi.get_meta("rest")
	mi.transform = Transform3D(rest.basis * Basis.from_euler(rot).scaled(scl), rest.origin + offset)


static func _b() -> MeshKit.Builder:
	return MeshKit.Builder.new()


static func _eye(b, x: float, y: float, z: float, r: float, pupil: float, white := WHITE) -> void:
	b.sphere(_t(x, y, z), Vector3(r, r, r * 0.45), MeshKit.lin(white), 12, 6)
	b.sphere(_t(x, y, z + r * 0.4), Vector3(pupil, pupil, pupil * 0.5), MeshKit.lin(DARK), 8, 4)


# ---------------------------------------------------------------- the species

# Orange slime: a glossy wobbling dome with a blank, unblinking stare, sitting in its own puddle.
static func _slime(body: Color) -> Dictionary:
	var b := _b()
	b.sphere(_t(0, 0.36, 0), Vector3(0.6, 0.7, 0.54), body, 20, 10, Vector2(1, 0)) # the dome (glossy)
	b.sphere(_t(-0.34, 0.06, 0.38), Vector3(0.07, 0.09, 0.07), body, 8, 4, Vector2(1, 0)) # drips
	b.sphere(_t(0.27, 0.05, 0.42), Vector3(0.05, 0.07, 0.05), body, 8, 4, Vector2(1, 0))
	_eye(b, -0.19, 0.72, 0.42, 0.13, 0.02)
	_eye(b, 0.19, 0.72, 0.42, 0.13, 0.02)
	b.box(_t(0, 0.5, 0.53), Vector3(0.14, 0.022, 0.02), MeshKit.lin(DARK)) # a flat little mouth
	var puddle := _b()
	puddle.sphere(_t(0, 0.0, 0.04), Vector3(0.8, 0.03, 0.66), MeshKit.shade(body, 0.85), 20, 4, Vector2(1, 0))
	return {"Puddle": [puddle, Transform3D()], "Body": [b, Transform3D()]}


# Huge brown goblin: a potato-sack tunic, big ears, a jagged grin and a knotted club raised high.
static func _goblin(body: Color) -> Dictionary:
	var sack := MeshKit.lin("#cdb489")
	var rope := MeshKit.lin("#6d5130")
	var wood := MeshKit.lin("#94683e")
	var b := _b()
	b.limb(Vector3(-0.2, 0, 0), Vector3(-0.22, 0.55, 0), 0.11, 0.13, body) # legs
	b.limb(Vector3(0.2, 0, 0), Vector3(0.22, 0.55, 0), 0.11, 0.13, body)
	b.sphere(_t(0, 0.86, 0), Vector3(0.5, 0.5, 0.38), sack, 16, 8) # the sack tunic
	b.torus(_t(0, 0.7, 0) * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.78)), Vector3.ZERO), 0.43, 0.5, rope) # rope belt
	b.sphere(_t(0, 0.69, 0.4), Vector3(0.05, 0.05, 0.04), rope, 8, 4) # knot
	b.box(_tr(-0.2, 0.92, 0.34, Vector3(0, 1, 0), -0.4), Vector3(0.14, 0.13, 0.04), MeshKit.shade(sack, 0.7)) # patches
	b.box(_tr(0.24, 1.05, 0.3, Vector3(0, 1, 0), 0.5), Vector3(0.11, 0.1, 0.04), MeshKit.shade(sack, 0.7))
	b.sphere(_t(0, 1.25, 0), Vector3(0.24, 0.12, 0.22), body, 12, 6) # neck
	b.sphere(_t(0, 1.42, 0.02), Vector3(0.34, 0.32, 0.31), body, 18, 9) # head
	b.limb(Vector3(-0.3, 1.47, 0), Vector3(-0.78, 1.66, -0.06), 0.11, 0.0, body, 8) # ears
	b.limb(Vector3(0.3, 1.47, 0), Vector3(0.78, 1.66, -0.06), 0.11, 0.0, body, 8)
	_eye(b, -0.12, 1.5, 0.28, 0.05, 0.026, "#f3e27a") # beady eyes
	_eye(b, 0.12, 1.5, 0.28, 0.05, 0.026, "#f3e27a")
	b.box(_tr(-0.13, 1.57, 0.3, Vector3(0, 0, 1), -0.35), Vector3(0.14, 0.03, 0.04), MeshKit.shade(body, 0.5)) # brows
	b.box(_tr(0.13, 1.57, 0.3, Vector3(0, 0, 1), 0.35), Vector3(0.14, 0.03, 0.04), MeshKit.shade(body, 0.5))
	b.limb(Vector3(0, 1.45, 0.3), Vector3(0, 1.36, 0.44), 0.06, 0.02, body, 8) # hooked nose
	b.box(_t(0, 1.28, 0.27), Vector3(0.3, 0.05, 0.04), MeshKit.lin(DARK)) # the grin
	for i in 6:
		var x := -0.12 + i * 0.048
		b.limb(Vector3(x, 1.3 if i % 2 == 0 else 1.26, 0.295), Vector3(x, 1.27 if i % 2 == 0 else 1.29, 0.295), 0.016, 0.0, MeshKit.lin(TOOTH), 4)
	b.limb(Vector3(-0.42, 1.12, 0), Vector3(-0.62, 0.78, 0.08), 0.1, 0.09, body) # left arm, hanging
	b.limb(Vector3(-0.62, 0.78, 0.08), Vector3(-0.6, 0.55, 0.14), 0.09, 0.08, body)
	b.sphere(_t(-0.6, 0.5, 0.16), Vector3.ONE * 0.12, body, 10, 5) # fist
	var club := _b()
	club.limb(Vector3(0.42, 1.12, 0), Vector3(0.7, 1.22, 0.06), 0.1, 0.09, body) # right arm, raised
	club.limb(Vector3(0.7, 1.22, 0.06), Vector3(0.72, 1.48, 0.08), 0.09, 0.08, body)
	club.sphere(_t(0.72, 1.5, 0.08), Vector3.ONE * 0.1, body, 10, 5)
	club.limb(Vector3(0.72, 1.4, 0.08), Vector3(0.8, 1.86, 0.0), 0.05, 0.12, wood, 10) # the club
	for k in [[0.76, 1.66, 0.1], [0.83, 1.78, -0.02], [0.72, 1.76, 0.02]]:
		club.sphere(_t(k[0], k[1], k[2]), Vector3.ONE * 0.04, MeshKit.shade(wood, 0.8), 6, 3)
	return {"Body": [b, Transform3D()], "Club": [club, Transform3D()]}


# Yellow dragon: wings spread, a horned head, a pale belly and a spiked tail curled to one side.
static func _dragon(body: Color) -> Dictionary:
	var belly := MeshKit.lin("#fff1b0")
	var wing_col := MeshKit.shade(body, 0.62)
	var b := _b()
	b.sphere(_t(0, 0.62, 0), Vector3(0.44, 0.38, 0.38), body, 16, 8) # body
	b.sphere(_t(0, 0.6, 0.27), Vector3(0.28, 0.28, 0.13), belly, 12, 6) # belly plates
	for y in [0.48, 0.6, 0.72]:
		b.box(_t(0, y, 0.39), Vector3(0.36 - absf(y - 0.6), 0.015, 0.02), MeshKit.shade(belly, 0.7))
	for s in [-1.0, 1.0]: # legs and claws
		b.limb(Vector3(0.24 * s, 0.4, 0.1), Vector3(0.3 * s, 0.08, 0.18), 0.12, 0.08, body)
		for c in [-0.05, 0.0, 0.05]:
			b.limb(Vector3(0.3 * s + c, 0.06, 0.2), Vector3(0.3 * s + c * 1.6, 0.0, 0.32), 0.03, 0.0, MeshKit.lin(TOOTH), 4)
	b.limb(Vector3(0.0, 0.9, 0.08), Vector3(0.0, 1.22, 0.14), 0.16, 0.1, body) # neck
	var pts := [Vector3(0.3, 0.42, -0.25), Vector3(0.68, 0.24, -0.15), Vector3(0.9, 0.24, 0.1), Vector3(0.95, 0.38, 0.32)]
	for i in pts.size() - 1: # tail
		b.limb(pts[i], pts[i + 1], 0.13 - i * 0.035, 0.1 - i * 0.035, body)
	b.tri(Vector3(0.95, 0.38, 0.32), Vector3(1.08, 0.55, 0.36), Vector3(0.88, 0.5, 0.42), wing_col)
	b.tri(Vector3(0.95, 0.38, 0.32), Vector3(0.88, 0.5, 0.42), Vector3(1.08, 0.55, 0.36), wing_col)
	var head := _b()
	head.sphere(_t(0, 1.34, 0.18), Vector3(0.2, 0.17, 0.22), body, 14, 7)
	head.sphere(_t(0, 1.29, 0.38), Vector3(0.13, 0.1, 0.14), body, 12, 6) # snout
	for s in [-1.0, 1.0]:
		head.limb(Vector3(0.1 * s, 1.45, 0.1), Vector3(0.26 * s, 1.74, -0.06), 0.055, 0.0, MeshKit.lin(TOOTH), 8) # horns
		head.box(_tr(0.085 * s, 1.39, 0.36, Vector3(0, 0, 1), 0.3 * s), Vector3(0.08, 0.022, 0.03), MeshKit.lin("#ff5a1a", true)) # slit eyes
		head.sphere(_t(0.05 * s, 1.31, 0.5), Vector3(0.016, 0.016, 0.01), MeshKit.lin(DARK), 6, 3) # nostrils
	for i in 5:
		var x := -0.08 + i * 0.04
		head.limb(Vector3(x, 1.235, 0.44), Vector3(x, 1.2, 0.45), 0.014, 0.0, MeshKit.lin(TOOTH), 4)
	var wings := {}
	for side in [["WingL", -1.0], ["WingR", 1.0]]:
		var w := _b()
		var s: float = side[1]
		# In the wing's own frame: the shoulder at the origin, the span out along +X (mirrored for the left)
		var tip := Vector3(0.84 * s, 0.68, -0.08)
		var elbow := Vector3(0.42 * s, 0.5, -0.05)
		var fingers := [Vector3(0.78 * s, 0.02, -0.04), Vector3(0.54 * s, -0.22, -0.02), Vector3(0.26 * s, -0.24, 0.0)]
		w.limb(Vector3.ZERO, elbow, 0.06, 0.045, body, 8)
		w.limb(elbow, tip, 0.045, 0.015, body, 8)
		var edge := [tip] + fingers + [Vector3(0.0, -0.1, 0.0)]
		for f in fingers:
			w.limb(elbow, f, 0.025, 0.01, body, 6)
		for i in edge.size() - 1:
			w.tri(elbow, edge[i], edge[i + 1], wing_col)
			w.tri(elbow, edge[i + 1], edge[i], wing_col)
		w.tri(Vector3.ZERO, elbow, Vector3(0.0, -0.1, 0.0), wing_col)
		w.tri(Vector3.ZERO, Vector3(0.0, -0.1, 0.0), elbow, wing_col)
		wings[side[0]] = [w, _t(0.22 * s, 0.86, -0.12)]
	return {"Body": [b, Transform3D()], "Head": [head, Transform3D()], "WingL": wings.WingL, "WingR": wings.WingR}


# Green snake person: a hooded serpent torso rising from its coils, clawed arms, a forked tongue that flicks.
static func _snake(body: Color) -> Dictionary:
	var belly := MeshKit.lin("#d8f0a0")
	var dark := MeshKit.shade(body, 0.45)
	var coils := _b()
	coils.torus(_t(0, 0.12, 0), 0.4, 0.66, body)
	coils.torus(_t(0.02, 0.3, 0), 0.3, 0.54, body)
	coils.torus(_t(0.04, 0.46, 0), 0.18, 0.4, body)
	coils.limb(Vector3(0.6, 0.1, 0.1), Vector3(0.88, 0.14, 0.3), 0.12, 0.03, body) # the tail's tip
	var up := _b()
	up.limb(Vector3(0, 0.45, 0), Vector3(0, 1.16, 0.06), 0.21, 0.15, body) # torso rising
	up.sphere(_t(0, 0.82, 0.13), Vector3(0.14, 0.34, 0.08), belly, 12, 6) # belly scales
	for y in [0.62, 0.74, 0.86, 0.98]:
		up.box(_t(0, y, 0.215), Vector3(0.2, 0.012, 0.02), MeshKit.shade(belly, 0.7))
	up.sphere(_t(0, 1.4, -0.04), Vector3(0.38, 0.4, 0.07), body, 16, 8) # the cobra hood
	for s in [-1.0, 1.0]:
		up.sphere(_t(0.18 * s, 1.44, 0.03), Vector3(0.07, 0.1, 0.02), dark, 8, 4) # hood markings
		up.limb(Vector3(0.14 * s, 1.08, 0.04), Vector3(0.44 * s, 0.94, 0.12), 0.07, 0.06, body) # clawed arms
		up.limb(Vector3(0.44 * s, 0.94, 0.12), Vector3(0.4 * s, 0.76, 0.22), 0.06, 0.05, body)
		for c in [-0.04, 0.0, 0.04]:
			up.limb(Vector3(0.4 * s, 0.74, 0.22), Vector3(0.4 * s + c, 0.66, 0.28), 0.018, 0.0, MeshKit.lin(TOOTH), 4)
	up.sphere(_t(0, 1.38, 0.1), Vector3(0.15, 0.16, 0.19), body, 14, 7) # head
	for s in [-1.0, 1.0]:
		up.sphere(_t(0.075 * s, 1.43, 0.25), Vector3(0.04, 0.03, 0.02), MeshKit.lin("#ffe35a", true), 8, 4) # slit eyes
		up.box(_t(0.075 * s, 1.43, 0.27), Vector3(0.008, 0.05, 0.008), MeshKit.lin(DARK))
	var tongue := _b()
	var red := MeshKit.lin("#e0304e")
	tongue.limb(Vector3(0, 1.3, 0.27), Vector3(0, 1.26, 0.4), 0.012, 0.01, red, 4)
	tongue.limb(Vector3(0, 1.26, 0.4), Vector3(-0.03, 1.22, 0.46), 0.01, 0.0, red, 4)
	tongue.limb(Vector3(0, 1.26, 0.4), Vector3(0.03, 1.22, 0.46), 0.01, 0.0, red, 4)
	return {"Coils": [coils, Transform3D()], "Upper": [up, Transform3D()], "Tongue": [tongue, Transform3D()]}


# Grey rock entity: a heap of boulders with arms, cracked all over, one glowing crack for an eye.
static func _rock(body: Color) -> Dictionary:
	var dark := MeshKit.lin(DARK)
	var glow := MeshKit.lin("#ffc864", true)
	var moss := MeshKit.lin("#7fa45a")
	var low := _b()
	for p in [[-0.5, 0.06, 0.4, 0.1], [0.46, 0.05, 0.45, 0.08], [0.62, 0.07, -0.1, 0.11]]: # pebbles
		low.sphere(_t(p[0], p[1], p[2]), Vector3.ONE * p[3], MeshKit.shade(body, 0.8), 6, 3)
	var up := _b()
	up.sphere(_tr(0, 0.62, 0, Vector3(0, 1, 0), 0.4), Vector3(0.62, 0.58, 0.5), body, 7, 4) # the heap
	up.sphere(_tr(0.05, 1.27, 0.02, Vector3(0, 1, 0), 0.9), Vector3(0.33, 0.3, 0.3), body, 6, 4) # head
	up.sphere(_t(-0.25, 1.02, 0.25), Vector3(0.12, 0.05, 0.1), moss, 8, 4) # moss
	for s in [-1.0, 1.0]:
		up.sphere(_tr(0.7 * s, 0.86, 0.05, Vector3(0, 0, 1), 0.6 * s), Vector3(0.26, 0.22, 0.22), body, 6, 3) # upper arm
		up.sphere(_tr(0.82 * s, 0.44, 0.15, Vector3(1, 1, 0), 0.5), Vector3(0.27, 0.25, 0.25), body, 6, 3) # fist
	# Cracks over the heap, dark, and the eye: a crack that glows
	var crack := [Vector3(-0.08, 0.95, 0.44), Vector3(0.02, 0.76, 0.5), Vector3(-0.04, 0.6, 0.5), Vector3(0.06, 0.42, 0.47)]
	for i in crack.size() - 1:
		up.limb(crack[i], crack[i + 1], 0.018, 0.018, dark, 4)
	up.limb(Vector3(0.3, 0.85, 0.38), Vector3(0.22, 0.66, 0.44), 0.015, 0.015, dark, 4)
	var eye := [Vector3(-0.17, 1.3, 0.26), Vector3(-0.09, 1.34, 0.28), Vector3(-0.02, 1.29, 0.3), Vector3(0.07, 1.35, 0.29), Vector3(0.16, 1.31, 0.27)]
	for i in eye.size() - 1:
		up.limb(eye[i], eye[i + 1], 0.024, 0.024, glow, 5)
	return {"Low": [low, Transform3D()], "Upper": [up, Transform3D()]}


# Red bandit: a hooded cloak, a dark bandana over the face, a belt with a coin pouch, a knife in each hand.
static func _bandit(body: Color) -> Dictionary:
	var skin := MeshKit.lin("#e0aa82")
	var tunic := MeshKit.lin("#6e4c3c")
	var mask := MeshKit.lin("#2a1c22")
	var leather := MeshKit.lin("#6b4a2e")
	var steel := MeshKit.lin(STEEL)
	var b := _b()
	b.limb(Vector3(-0.14, 0, 0.02), Vector3(-0.13, 0.5, 0.02), 0.08, 0.1, tunic) # legs
	b.limb(Vector3(0.14, 0, 0.02), Vector3(0.13, 0.5, 0.02), 0.08, 0.1, tunic)
	b.cylinder(_t(0, 0.12, -0.04), 0.5, 0.24, 1.1, body, 16) # the cloak
	b.box(_t(0, 0.82, 0.2), Vector3(0.36, 0.62, 0.12), tunic) # tunic, the cloak open over it
	b.box(_t(0, 0.68, 0.27), Vector3(0.4, 0.07, 0.04), leather) # belt
	b.box(_t(0, 0.68, 0.3), Vector3(0.08, 0.07, 0.02), MeshKit.lin(GOLD)) # buckle
	b.sphere(_t(0.14, 0.56, 0.3), Vector3(0.07, 0.08, 0.05), leather, 8, 4) # coin pouch
	b.sphere(_t(0, 1.43, 0.08), Vector3(0.17, 0.2, 0.17), skin, 14, 7) # head, the face out of the hood
	b.sphere(_t(0, 1.48, -0.09), Vector3(0.25, 0.29, 0.23), body, 16, 8) # hood
	b.limb(Vector3(0, 1.66, -0.16), Vector3(0, 1.8, -0.26), 0.09, 0.0, body, 8) # the hood's point
	b.sphere(_t(0, 1.355, 0.12), Vector3(0.175, 0.09, 0.14), mask, 12, 6) # bandana mask
	b.limb(Vector3(0.14, 1.37, 0.0), Vector3(0.3, 1.26, -0.06), 0.03, 0.0, mask, 6) # knot tails
	b.limb(Vector3(0.14, 1.37, 0.0), Vector3(0.33, 1.36, -0.04), 0.03, 0.0, mask, 6)
	for s in [-1.0, 1.0]:
		b.box(_tr(0.065 * s, 1.465, 0.24, Vector3(0, 0, 1), 0.15 * s), Vector3(0.07, 0.02, 0.02), MeshKit.lin(DARK)) # narrowed eyes
	# Left arm: the knife held forward
	b.limb(Vector3(-0.28, 1.18, 0), Vector3(-0.4, 0.9, 0.16), 0.08, 0.07, body)
	b.limb(Vector3(-0.4, 0.9, 0.16), Vector3(-0.28, 0.86, 0.38), 0.07, 0.06, skin)
	b.sphere(_t(-0.27, 0.86, 0.4), Vector3.ONE * 0.06, skin, 8, 4)
	b.box(_tr(-0.2, 0.92, 0.5, Vector3(1, 0, 0), -0.9), Vector3(0.035, 0.22, 0.012), steel) # blade
	# Right arm: the knife raised
	var r := b
	r.limb(Vector3(0.28, 1.18, 0), Vector3(0.5, 1.32, 0.1), 0.08, 0.07, body)
	r.limb(Vector3(0.5, 1.32, 0.1), Vector3(0.56, 1.56, 0.12), 0.07, 0.06, skin)
	r.sphere(_t(0.56, 1.58, 0.12), Vector3.ONE * 0.06, skin, 8, 4)
	r.box(_tr(0.6, 1.74, 0.1, Vector3(0, 0, 1), -0.25), Vector3(0.035, 0.24, 0.012), steel)
	r.box(_t(0.57, 1.63, 0.12), Vector3(0.1, 0.025, 0.03), MeshKit.lin(GOLD)) # crossguard
	return {"Body": [b, Transform3D()]}
