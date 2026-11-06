## Fixed-clock, real Stage + bloom/CRT corridor capture. No player saves.
## godot --path . -s res://tools/panel_reveal_demo.gd -- nosave nosound out=/tmp/panel-reveal
extends SceneTree
const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const Rng = preload("res://src/utils/rng.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Stage = preload("res://src/view/stage.gd")
const PostFx = preload("res://src/view/postfx.gd")
var view: SubViewport
var stage
var state
var out: String
var failed := false

func _initialize() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound"] + Array(OS.get_cmdline_user_args())))
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	failed = failed or not ok

func capture(time: float) -> Image:
	stage.update(state, time, 0.0)
	for i in 3:
		await process_frame
		RenderingServer.force_draw()
	return root.get_texture().get_image()

func _run() -> void:
	out = Flags.value("out", "/tmp/panel-reveal")
	DirAccess.make_dir_recursive_absolute(out + "/frames")
	root.size = Vector2i(1216, 576)
	view = SubViewport.new()
	view.size = Vector2i(608, 288)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var picture := TextureRect.new()
	picture.texture = view.get_texture()
	root.add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fx := PostFx.new()
	fx.attach(picture)
	var flow = Flow.new(Rng.new(7), LocalMind.new())
	await flow.new_run()
	state = flow.state
	var f := FloorMap.new()
	f.size = 15
	for y in f.size:
		var row := []
		row.resize(f.size)
		row.fill(0)
		if y >= 1 and y <= 13:
			row[7] = 1
		f.grid.append(row)
	f.start = Vector2i(7, 13)
	f.stairs = Vector2i(7, 1)
	state.floor_map = f
	state.cell = f.start
	state.facing = 0
	state.palette_id = 0
	state.seen = {f.start: true}
	stage = Stage.new()
	view.add_child(stage)
	stage.update(state, 9.0, 0.0)
	# The fixture submits one visibility batch; production uses state.look().
	for y in range(1, 13):
		state.seen[Vector2i(7, y)] = true
	stage.update(state, 10.0, 0.0)
	var mesh = stage._dungeon.mesh
	for i in 12:
		var stamp: float = stage._reveal_image.get_pixel(7, 12 - i).r
		check(absf(stamp - (10.0 + i * 0.1)) < 0.00001, "cell %d starts at %d ms" % [i + 1, i * 100])
	var shots := {}
	for entry in [[-100, "before"], [1, "floor"], [41, "walls"], [71, "ceiling"], [101, "cell2"], [201, "cell3"], [1700, "settled"]]:
		var img := await capture(10.0 + entry[0] / 1000.0)
		img.save_png(out + "/" + entry[1] + ".png")
		shots[entry[1]] = img
	# Sample panel interiors, not edges: a line-only implementation fails these.
	for sample in [["floor", Vector2i(608, 445)], ["walls", Vector2i(410, 288)], ["ceiling", Vector2i(608, 120)]]:
		var p: Vector2i = sample[1]
		check(shots[sample[0]].get_pixelv(p).r > 0.6, sample[0] + " has a bright filled interior")
		check(shots.before.get_pixelv(p).r < 0.1, sample[0] + " is dark before activation")
	check(shots.floor.get_pixel(410, 288).r < 0.1, "walls wait for 40 ms")
	check(shots.walls.get_pixel(608, 120).r < 0.1, "ceiling waits for 70 ms")
	state.views.erase("dungeon-reveal")
	var classic := await capture(11.7)
	check(classic.get_data() == shots.settled.get_data(), "settled picture exactly matches disabled effect")
	state.views["dungeon-reveal"] = true
	# 60 fps, with half-second lead-in and a settled tail.
	for frame in 150:
		var img := await capture(9.5 + frame / 60.0)
		img.save_png(out + "/frames/%04d.png" % frame)
	check(stage._dungeon.mesh == mesh, "animation never rebuilds mesh")
	# Capture an actual monster and a floor hazard against the lit panels.
	var old_flow = Flow.new(Rng.new(7), LocalMind.new())
	await old_flow.new_run()
	var monster = old_flow.state.floor_map.monsters[0]
	monster.cell = Vector2i(7, 11)
	monster.lurking = false
	f.monsters = [monster]
	f.teleports = [{"a": Vector2i(7, 12), "b": Vector2i(7, 4)}]
	f.changes += 1
	var readable := await capture(10.17)
	readable.save_png(out + "/monster-hazard.png")
	# Walking through fully explored cells must still replay on EVERY step.
	for i in 3:
		state.cell = Vector2i(7, 12 - i)
		state.look()
		var start := 20.0 + i * 0.25
		stage.update(state, start, 0.0)
		check(absf(stage._reveal_image.get_pixel(7, 12 - i).r - start) < 0.00001, "explored step %d restarts panels" % (i + 1))
		var step_image := await capture(start + 0.17)
		step_image.save_png(out + "/walk-%d.png" % (i + 1))
		check(absf(stage._reveal_image.get_pixel(7, 12 - i).r - start) < 0.00001, "stationary frame does not restart panels")
	state.cell = Vector2i(7, 11)
	state.look()
	stage.update(state, 21.0, 0.0)
	check(stage._reveal_image.get_pixel(7, 11).r == 21.0, "backtracking replays panels")
	stage.bump(21.1)
	stage.update(state, 21.1, 0.0)
	check(stage._reveal_image.get_pixel(7, 11).r == 21.0, "wall bump does not restart panels")
	state.views.erase("dungeon-reveal")
	state.cell = Vector2i(7, 10)
	state.look()
	stage.update(state, 22.0, 0.0)
	check(stage._reveal_image.get_pixel(7, 10).r < 0.0, "disabled walking stays settled")
	fx.detach()
	print("panel_reveal_demo: " + out)
	quit(1 if failed else 0)
