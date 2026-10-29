## Screenshots of the game's screen on mock Jev (the port of crawler/scripts/shots.mjs), to look at every state the
## ui draws: the title, exploring, a yes/no question, a fight (monster tags, dice), CHOOSE MOVES, the talk box, the
## Jev mind panel (MIND and REQUESTS), the achievements list, the Roll of Fate spinning and landed, an unlock toast,
## the party in danger, game over, a tip, the plain view (nofx) and a smaller window. Opens a window briefly (not
## headless), runs the real main scene with `mock debug`, and exits non-zero on any script error.
##   godot --path . -s res://cli/shots.gd [-- out=/some/dir]
## Sound is muted; the game's saved data is a throwaway in-memory store.
extends SceneTree

const J = preload("res://src/core/js.gd")
const Flags = preload("res://src/core/flags.gd")
const Render = preload("res://src/view/render.gd")
const Store = preload("res://src/core/store.gd")
const Main = preload("res://src/ui/main.gd")

var out_dir := "/private/tmp/claude-501/-private-tmp-temp/9a270d88-2fcd-474a-8038-3c1a423642ac/scratchpad/ui/"
var main: Control
var counter := ErrorCounter.new()
var shots := 0


class ErrorCounter:
	extends Logger
	var errors: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if rationale else code, file, line, function])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_dir = a.trim_prefix("out=").path_join("")
	OS.add_logger(counter)
	DirAccess.make_dir_recursive_absolute(out_dir)
	# A window behind other windows is throttled by macOS: keep it on top and off vsync
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_size(Vector2i(1180, 820))
	DisplayServer.window_move_to_foreground()
	AudioServer.set_bus_mute(0, true)
	seed(3)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await _frames(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	shots += 1
	print("shot %s %s" % [name, img.get_size()])


## A fresh main scene with these flags and saved data
func _open(flags: String, data := {}) -> void:
	if main != null:
		main.queue_free()
		await _frames(2)
	Flags.override = flags
	Main.store_override = Store.Memory.new(data)
	main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)


func _press(k: Key, unicode := 0) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.unicode = unicode
		ev.pressed = down
		Input.parse_input_event(ev)
		await _frames(1)


func _letter(c: String) -> void:
	await _press(OS.find_keycode_from_string(c.to_upper()), c.unicode_at(0))


func _game():
	return main.game


## Wait until `cond` holds (or `secs` pass)
func _until(cond: Callable, secs := 10.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if cond.call():
			return true
		await process_frame
	print("  (gave up waiting after %.0fs)" % secs)
	return false


## Face the longest straight corridor from where the party stands
func _face_long_corridor() -> void:
	var G = _game().G
	var best := 0
	var best_len := -1
	for d in 4:
		var n := 0
		while true:
			var x: int = G.x + Render.DIRS[d][0] * (n + 1)
			var y: int = G.y + Render.DIRS[d][1] * (n + 1)
			if y < 0 or y >= G.map.grid.size() or x < 0 or x >= G.map.grid[y].size() or G.map.grid[y][x] != 1:
				break
			n += 1
		if n > best_len:
			best_len = n
			best = d
	G.dir = best
	_game().render()


func _run() -> void:
	await _open("mock debug", {"hallsOfJev.tipsOff": "1"})
	await _secs(0.5)
	await _shot("01-title")

	await _press(KEY_ENTER)
	await _until(func(): return _game().G != null)
	_face_long_corridor()
	await _secs(0.4)
	await _shot("02-explore")

	_game().debug_ask()
	await _secs(0.45)
	await _shot("03-modal")
	await _letter("n")

	_game().debug_ally("slime", "Glop")
	_game().debug_meet(["goblin", "slime"])
	await _until(func(): return _game().G.combat != null and not _game().G.busy, 15.0)
	await _secs(0.6)
	await _shot("04-combat")

	if _game().G.combat != null:
		await _letter("f")
		await _secs(0.22)
		await _shot("05-dice")
		await _until(func(): return not _game().G.busy, 15.0)
	if _game().G.combat == null:
		_game().debug_meet(["bandit", "goblin", "slime"])
		await _until(func(): return _game().G.combat != null and not _game().G.busy, 15.0)
	await _secs(0.3)
	await _letter("c")
	await _secs(0.3)
	await _shot("06-choose-moves")
	await _press(KEY_ESCAPE)
	await _secs(0.1)

	if _game().G.combat != null and not _game().G.busy:
		await _letter("t")
		await _secs(0.1)
		main.set_input_text("hello there, little goblin")
		await _secs(0.3)
		await _shot("07-talk")
		await _press(KEY_ESCAPE)
	await _shot("08-jev-mind")

	main.jev_tab("requests")
	await _frames(3)
	if not _game().api_log.is_empty():
		var first = main.jev.list.get_child(1) if main.jev.list.get_child_count() > 1 else null
		if first != null and first.has_method("build"):
			main.jev.toggle_request(first.entry.n, first)
	await _secs(0.3)
	await _shot("09-jev-requests")
	main.jev_tab("mind")

	_game().ach.unlock("charmed")
	_game().ach.unlock("all_talk")
	await _until(func(): return not _game().G.busy and _game().G.prompt == null and _game().G.menu == null and _game().G.input == null, 15.0)
	await _secs(4.5)
	await _letter("k")
	await _secs(0.5)
	await _shot("10-achievements")
	await _letter("k")

	# the party in danger: health low, someone dying
	var G = _game().G
	for i in G.party.size():
		var m = G.party[i]
		m.hp = 0 if i == 0 else maxi(1, J.round_js(m.maxHp * 0.15))
	G.party[0].down = true
	G.party[0].stable = false
	G.party[0].saves = {"s": 1, "f": 1}
	_game().fx.emit("party:hurt", {"dmg": 7, "hp": 1, "maxHp": 12})
	_game().render()
	await _secs(1.6)
	await _shot("11-danger")

	await _open("mock debug", {})
	await _press(KEY_ENTER)
	await _until(func(): return _game().G != null)
	_face_long_corridor()
	await _secs(1.6)
	await _shot("12-tip")

	_game().debug_roll()
	await _secs(0.8)
	await _shot("13-roll-spin")
	await _until(func(): return _game().G.waitKey != null, 6.0)
	await _secs(0.5)
	await _shot("14-roll-landed")
	await _letter("x")
	await _secs(0.2)
	_game().ach.unlock("first_friend")
	await _secs(0.75)
	await _shot("15-toast")

	_game().game_over()
	await _secs(0.5)
	await _shot("16-gameover")

	await _open("mock nofx", {"hallsOfJev.tipsOff": "1"})
	await _press(KEY_ENTER)
	await _until(func(): return _game().G != null)
	_face_long_corridor()
	await _secs(0.4)
	await _shot("17-nofx")

	DisplayServer.window_set_size(Vector2i(1500, 900))
	await _open("mock debug", {"hallsOfJev.tipsOff": "1"})
	await _press(KEY_ENTER)
	await _until(func(): return _game().G != null)
	_game().debug_meet(["dragon"])
	await _until(func(): return _game().G.combat != null and not _game().G.busy, 15.0)
	await _secs(0.5)
	await _shot("18-wide-window")

	Flags.override = null
	Main.store_override = null
	var errors := counter.errors
	if errors.is_empty():
		print("ok: %d shots in %s" % [shots, out_dir])
	else:
		print("%d script errors:" % errors.size())
		for e in errors:
			print("  " + e)
	quit(1 if not errors.is_empty() else 0)
