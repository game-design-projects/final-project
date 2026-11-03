## Shots of a monster seen down a long corridor, near to far (issue #20), plus the camera while an arrow key is held:
##   godot --path . -s res://cli/far_shots.gd -- out=/some/dir [seed=N]
extends SceneTree

const Render = preload("res://src/view/render.gd")
const Flags = preload("res://src/core/flags.gd")

var out_dir := ProjectSettings.globalize_path("res://build/shots/far/")
var scene: Control


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + name + ".png")
	print("shot ", name)


func _initialize() -> void:
	var sd := 5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.trim_prefix("out=").path_join("")
		elif a.begins_with("seed="):
			sd = int(a.trim_prefix("seed="))
	Flags.override = "nosound"
	DirAccess.make_dir_recursive_absolute(out_dir)
	seed(sd)
	_run.call_deferred()


func _run() -> void:
	scene = load("res://src/genre/genre_halls.tscn").instantiate()
	root.add_child(scene)
	await _frames(2)
	scene.on_key("Enter")
	await _frames(5)
	# longest open straight line to a monster
	var best := {}
	for m in scene.G.map.monsters:
		for dir in 4:
			var d: Array = Render.DIRS[dir]
			var k := 0
			while scene._open(m.x - d[0] * (k + 1), m.y - d[1] * (k + 1)):
				k += 1
			if k > int(best.get("k", -1)):
				best = {"m": m, "dir": dir, "k": k}
	print("longest corridor: ", best.k, " cells to ", best.m.species)
	var d: Array = Render.DIRS[best.dir]
	for dist in [2, 4, 6, 8, 10, 12]:
		if dist > best.k:
			break
		scene.G.x = best.m.x - d[0] * dist
		scene.G.y = best.m.y - d[1] * dist
		scene.G.dir = best.dir
		await _secs(0.5)
		await _shot("dist-%02d" % dist)
	quit()


func _secs(s: float) -> void:
	await create_timer(s).timeout
