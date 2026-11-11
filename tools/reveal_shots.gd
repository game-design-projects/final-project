## Deterministic real-render captures and lifecycle checks. Always uses in-memory saves.
## godot --path . -s res://tools/reveal_shots.gd -- nosave nosound out=/tmp/reveal
extends SceneTree

const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const Rng = preload("res://src/utils/rng.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Vision = preload("res://src/rules/vision.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Stage = preload("res://src/view/stage.gd")
const PostFx = preload("res://src/view/postfx.gd")
var _out: String
var _view: SubViewport
var _fx
var _failed := false

func _initialize() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=7"] + Array(OS.get_cmdline_user_args())))
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	_failed = _failed or not ok

func _run() -> void:
	_out = Flags.value("out", "/tmp/dungeon-reveal")
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(912, 432)
	_view = SubViewport.new()
	_view.size = Vector2i(608, 288)
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	var picture := TextureRect.new()
	picture.texture = _view.get_texture()
	root.add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx = PostFx.new()
	_fx.attach(picture)
	var flow = Flow.new(Rng.new(7), LocalMind.new())
	await flow.new_run()
	var s = flow.state
	for mode in ["step", "turn"]:
		var best := {}
		var most := 0
		for y in s.floor_map.size:
			for x in s.floor_map.size:
				var c := Vector2i(x, y)
				if not s.floor_map.is_open(c):
					continue
				for facing in 4:
					var dest: Vector2i = c + FloorMap.DIRS[facing] if mode == "step" else c
					if not s.floor_map.is_open(dest):
						continue
					var heading: int = facing if mode == "step" else (facing + 1) % 4
					var before := Vision.sight(s.floor_map, c, facing) + Vision.ahead(s.floor_map, c, facing)
					var fresh := Vision.sight(s.floor_map, dest, heading).filter(func(v): return not before.has(v))
					if fresh.size() > most:
						most = fresh.size()
						best = {"cell": c, "facing": facing, "dest": dest, "heading": heading}
		_check(most > 0, mode + " has newly visible cells")
		s.cell = best.cell
		s.facing = best.facing
		s.seen = {}
		s.look()
		print("reveal_shots: %s %s heading %d -> %s heading %d" % [mode, best.cell, best.facing, best.dest, best.heading])
		var stage := Stage.new()
		_view.add_child(stage)
		stage.update(s, 9.0, 0.0)
		var mesh = stage._dungeon.mesh
		var old_seen: Dictionary = s.seen.duplicate()
		s.cell = best.dest
		s.turn(best.heading - s.facing)
		stage.update(s, 10.0, 0.0)
		var fresh: Array = s.seen.keys().filter(func(c): return not old_seen.has(c))
		_check(not fresh.is_empty(), mode + " schedules reveal")
		var sorted := fresh.duplicate()
		sorted.sort_custom(func(a, b): return a.distance_squared_to(s.cell) < b.distance_squared_to(s.cell))
		var previous := 0.0
		for c in sorted:
			var stamp: float = stage._reveal_image.get_pixel(c.x, c.y).r
			_check(stamp >= previous, "near-to-far order %s" % c)
			previous = stamp
		for c in old_seen:
			_check(stage._reveal_image.get_pixel(c.x, c.y).r < 0.0, "a step leaves explored cells settled, even in sight %s" % c)
		for c in fresh:
			var stamp: float = stage._reveal_image.get_pixel(c.x, c.y).r
			_check(stamp >= 10.0 and stamp <= 10.0 + stage.reveal_stagger * s.floor_map.size * 1.5, "new cell %s stagger in range" % c)
		var scheduled := stage._reveal_image.duplicate()
		for ms in [0, 40, 70, 100, 200, 1000]:
			stage.update(s, 10.0 + ms / 1000.0, 0.016)
			await process_frame
			RenderingServer.force_draw()
			await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png("%s/%s_%03dms.png" % [_out, mode, ms])
		_check(stage._dungeon.mesh == mesh, "animation retains merged mesh")
		s.turn(1)
		stage.update(s, 11.0, 0.016)
		s.turn(-1)
		stage.update(s, 12.0, 0.016)
		for c in fresh:
			_check(stage._reveal_image.get_pixel(c.x, c.y).r == scheduled.get_pixel(c.x, c.y).r, "stationary turn does not restart scheduled cells %s" % c)
		stage.free()
		stage = Stage.new()
		_view.add_child(stage)
		stage.update(s, 13.0, 0.0)
		_check(stage._reveal_image.get_pixel(fresh[0].x, fresh[0].y).r < 0.0, "loaded exploration starts settled")
		stage.free()
		# Feature-disabled materials retain the classic shader path.
		s.views.erase("dungeon-reveal")
		stage = Stage.new()
		_view.add_child(stage)
		stage.update(s, 14.0, 0.0)
		_check(not stage._wall_mat.get_shader_parameter("reveal_enabled"), "feature off disables shader")
		s.turn(2)
		stage.update(s, 15.0, 0.0)
		for c in s.seen:
			_check(stage._reveal_image.get_pixel(c.x, c.y).r < 0.0, "disabled exploration stays settled %s" % c)
		s.views["dungeon-reveal"] = true
		stage.update(s, 15.01, 0.0)
		_check(stage._reveal_image.get_pixel(s.cell.x, s.cell.y).r < 0.0, "enabling does not replay explored cells")
		stage.free()
	_fx.detach()
	print("reveal_shots: " + _out)
	quit(1 if _failed else 0)
