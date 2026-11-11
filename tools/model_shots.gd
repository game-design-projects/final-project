## The walk model and the fight sprite of each species side by side, for looking at (tests can't judge looks): the model from in
## front and from a little to one side, at the distance of the next cell, then the line art. A sheet, models.png, of all five.
##   godot --path . -s res://tools/model_shots.gd -- out=<dir> nosound
extends SceneTree

const Art = preload("res://src/view/art.gd")
const Content = preload("res://src/rules/content.gd")
const Flags = preload("res://src/utils/flags.gd")
const MonsterModel = preload("res://src/view/monster_model.gd")
const Stage = preload("res://src/view/stage.gd")

const SPECIES := ["slime", "bandit", "snake", "rock", "dragon"]
const SIZE := Vector2i(448, 288)
const DISTANCE := 2.4 # world units from the camera to the model: the next cell, at the camera's place in its own
const SIDE := 0.45 # how far round the model's middle the second picture stands, in radians

var _out := ""


## One monster's line art, the way the fight draws it.
class Sprite extends Control:
	var species := ""
	var color := Color.WHITE

	func _draw() -> void:
		Art.draw(self, species, 0.0, color)


func _initialize() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound"] + Array(OS.get_cmdline_user_args())))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://model_shots"))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var sheet := Image.create(SIZE.x * 3, SIZE.y * SPECIES.size(), false, Image.FORMAT_RGBA8)
	for row in SPECIES.size():
		var species: String = SPECIES[row]
		var color := Color(Content.species(species).color)
		var pictures := [await _model_picture(species, color, 0.0), await _model_picture(species, color, SIDE), await _sprite_picture(species, color)]
		for col in pictures.size():
			pictures[col].convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(pictures[col], Rect2i(Vector2i.ZERO, SIZE), Vector2i(col * SIZE.x, row * SIZE.y))
	sheet.save_png("%s/models.png" % _out)
	print("model_shots: written to %s/models.png" % _out)
	quit()


func _model_picture(species: String, color: Color, angle: float) -> Image:
	var view := _view()
	view.own_world_3d = true
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLACK
	view.add_child(world)
	var model := MonsterModel.build(species, color, true)
	view.add_child(model)
	MonsterModel.pose(model, 0.0, 0.0)
	var camera := Camera3D.new()
	camera.fov = Stage.FOV
	view.add_child(camera)
	camera.position = Vector3(sin(angle) * DISTANCE, Stage.EYE, cos(angle) * DISTANCE)
	camera.rotation.y = angle
	camera.make_current()
	var picture: Image = await _capture(view)
	view.queue_free()
	return picture


func _sprite_picture(species: String, color: Color) -> Image:
	var view := _view()
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.size = Vector2(SIZE)
	view.add_child(back)
	var sprite := Sprite.new()
	sprite.species = species
	sprite.color = color
	sprite.size = Vector2(SIZE)
	view.add_child(sprite)
	var picture: Image = await _capture(view)
	view.queue_free()
	return picture


func _view() -> SubViewport:
	var view := SubViewport.new()
	view.size = SIZE
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.transparent_bg = false
	root.add_child(view)
	return view


func _capture(view: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
