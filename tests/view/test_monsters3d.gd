## The monsters as 3D models (monsters3d.gd): every species builds, stands on its feet facing you, takes its color
## from art.gd's rules, moves the way its drawing did, and shows a hit.
extends "res://tests/test_case.gd"

const Monsters3D = preload("res://src/view/monsters3d.gd")
const MeshKit = preload("res://src/view/mesh_kit.gd")
const Art = preload("res://src/view/art.gd")
const Species = preload("res://src/rules/species.gd")


func _model(species: String, look := {}) -> Node3D:
	var m := ShaderMaterial.new()
	return Monsters3D.build(species, look, m)


# The model's corners as built, over all its parts (rest poses)
func _bounds(model: Node3D) -> AABB:
	var box = null
	for mi in model.get_node("Rig").get_children():
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		box = b if box == null else box.merge(b)
	return box


# Every vertex color the model's parts carry
func _colors(model: Node3D) -> Array:
	var out := []
	for mi in model.get_node("Rig").get_children():
		out.append_array(Array(mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]))
	return out


# (vertex colors are kept at 8 bits a channel, so only nearly)
func _has_color(model: Node3D, c: Color) -> bool:
	for v in _colors(model):
		if absf(v.r - c.r) < 0.01 and absf(v.g - c.g) < 0.01 and absf(v.b - c.b) < 0.01:
			return true
	return false


func test_the_six_species_are_the_ones_the_rules_know():
	var known := Species.SPECIES.keys()
	known.sort()
	var ours: Array = Monsters3D.SPECIES.duplicate()
	ours.sort()
	eq(ours, known)


func test_every_species_builds_standing_on_the_floor_inside_the_corridor():
	for sp in Monsters3D.SPECIES:
		var model := _model(sp)
		ok(model.get_node("Rig").get_child_count() >= 1, "%s has parts" % sp)
		var box := _bounds(model)
		ok(box.position.y > -0.5 and box.position.y < 0.1, "%s stands on the floor, or sits a little into it (lowest %.2f)" % [sp, box.position.y])
		ok(box.end.y > 0.9 and box.end.y < 2.0, "%s is between knee and ceiling height (%.2f)" % [sp, box.end.y])
		ok(box.size.x < 2.25, "%s about fits a corridor (%.2f wide)" % [sp, box.size.x])
		for mi in model.get_node("Rig").get_children():
			ok(mi.material_override == model.get_meta("material"), "%s draws %s with its own material" % [sp, mi.name])
		model.free()


func test_the_body_takes_the_species_color_unless_the_look_says_otherwise():
	for sp in Monsters3D.SPECIES:
		var plain := _model(sp)
		ok(_has_color(plain, MeshKit.lin(Species.SPECIES[sp].color)), "%s in its own color" % sp)
		plain.free()
		var champ := _model(sp, {"color": Art.BOSS_COLOR})
		ok(_has_color(champ, MeshKit.lin(Art.BOSS_COLOR)), "%s champion in red" % sp)
		ok(not _has_color(champ, MeshKit.lin(Species.SPECIES[sp].color)), "%s champion has none of its usual color" % sp)
		champ.free()
		var shiny := _model(sp, {"shiny": true})
		ok(_has_color(shiny, MeshKit.lin(Art.SHINY_COLOR)), "%s shiny in gold" % sp)
		shiny.free()


func test_glowing_parts_are_the_eyes_of_fire():
	var rock := _model("rock")
	ok(_colors(rock).any(func(c): return c.a == 0.0), "the rock's crack of an eye glows")
	rock.free()
	var slime := _model("slime")
	ok(not _colors(slime).any(func(c): return c.a == 0.0), "a slime has nothing that glows")
	slime.free()


func test_each_species_moves_like_its_drawing():
	var slime := _model("slime")
	Monsters3D.pose(slime, 0.0)
	var a: Vector3 = Monsters3D.part(slime, "Body").scale
	Monsters3D.pose(slime, 380.0 * PI / 2.0)
	var b: Vector3 = Monsters3D.part(slime, "Body").scale
	ok(b.y < a.y and b.x > a.x, "the slime squashes as it wobbles (%s -> %s)" % [a, b])
	slime.free()
	var dragon := _model("dragon")
	Monsters3D.pose(dragon, 0.0)
	var w0: Basis = Monsters3D.part(dragon, "WingL").transform.basis
	Monsters3D.pose(dragon, 600.0 * PI / 2.0)
	ok(not Monsters3D.part(dragon, "WingL").transform.basis.is_equal_approx(w0), "the dragon flaps")
	dragon.free()
	var snake := _model("snake")
	Monsters3D.pose(snake, 220.0 * PI / 2.0) # sin = 1: tongue out
	ok(Monsters3D.part(snake, "Tongue").visible, "the tongue flicks out")
	Monsters3D.pose(snake, 220.0 * PI * 1.5) # sin = -1
	ok(not Monsters3D.part(snake, "Tongue").visible, "and back in")
	snake.free()
	var goblin := _model("goblin")
	Monsters3D.pose(goblin, 700.0 * PI / 2.0)
	ok(Monsters3D.part(goblin, "Body").position.x > 0.0, "the goblin sways")
	goblin.free()


func test_a_hit_shakes_the_model_sideways_and_flashes_it():
	var m := ShaderMaterial.new()
	var model := Monsters3D.build("bandit", {}, m)
	Monsters3D.pose(model, 10.0 * PI, 0.0)
	eq(model.get_node("Rig").position, Vector3.ZERO)
	eq(m.get_shader_parameter("flash"), 0.0)
	Monsters3D.pose(model, 10.0 * PI, 1.0) # sin(t / 20) = 1
	ok(model.get_node("Rig").position.x > 0.05, "shaken")
	near(m.get_shader_parameter("flash"), 0.75, 1e-6, "flashed")
	model.free()
