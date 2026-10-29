extends "res://tests/test_case.gd"

const Flags = preload("res://src/core/flags.gd")
const Store = preload("res://src/core/store.gd")
const Main = preload("res://src/ui/main.gd")
const Layout = preload("res://src/ui/layout.gd")

var main


func before_each():
	Flags.override = "mock"
	Main.store_override = Store.Memory.new({"hallsOfJev.tipsOff": "1"})
	main = load("res://src/ui/main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.game.sleep_scale = 0.0
	await _frames(2)


func after_each():
	main.queue_free()
	# the audio thread lets go of the streams that were playing a moment later
	await (Engine.get_main_loop() as SceneTree).create_timer(0.15).timeout
	Flags.override = null
	Main.store_override = null


func _frames(n: int) -> void:
	for i in n:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _press(k: Key, unicode := 0) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.unicode = unicode
	ev.pressed = true
	main._input(ev)
	ev = ev.duplicate()
	ev.pressed = false
	main._input(ev)
	await _frames(1)


func test_every_ui_hook_game_calls_exists():
	var src := FileAccess.get_file_as_string("res://src/game/game.gd")
	var re := RegEx.create_from_string("\\bui\\.([a-z_]+)\\(")
	var names := {}
	for m in re.search_all(src):
		names[m.get_string(1)] = true
	ok(names.size() >= 10, "found the hooks (%d)" % names.size())
	for n in names:
		ok(main.has_method(n), "ui.%s() exists" % n)


func test_title_then_any_key_starts():
	ok(main.game.G == null, "the title waits")
	eq(main.dock.model.blocks[0].items[0].text, "PRESS ANY KEY TO BEGIN")
	eq(main.dock.model.blocks[0].items[1].key, "g", "the genre halls keycap")
	var title_h: float = main.dock.natural_h
	ok(main.bar.model == null, "an empty bar on the title")
	await _press(KEY_ENTER)
	ok(main.started)
	ok(main.game.G != null, "a run started")
	eq(main.bar.model.loc.floor, "FLOOR 1")
	eq(main.party.rows.size(), 3)
	ok(main.dock.model.blocks[0].items[0].type == "pad", "the exploring dock")
	eq(main.dock.natural_h, title_h, "no layout jump from the title screen on")
	ok(main.log_panel.rtl.get_parsed_text().contains("You descend into the Donjon"), "the log shows the first lines")


func test_keys_reach_the_game():
	await _press(KEY_ENTER)
	var G = main.game.G
	var dir: int = G.dir
	await _press(KEY_RIGHT)
	eq(G.dir, (dir + 1) % 4, "→ turns right")
	await _press(KEY_D, 100)
	eq(G.dir, (dir + 2) % 4, "D turns right too")
	await _press(KEY_M, 109)
	ok(main.map_hidden, "M hides the map")
	await _press(KEY_K, 107)
	ok(main.ach.is_open(), "K opens the achievements")
	ok(main.bar.model.sys.any(func(s): return s.key == "k" and s.open), "the K keycap lights up")
	await _press(KEY_ESCAPE)
	ok(not main.ach.is_open(), "Esc closes them")


func test_talk_box_hooks():
	await _press(KEY_ENTER)
	main.open_input("WHAT DO YOU SAY?", false)
	await _frames(1)
	ok(main.dock.line_edit.visible, "the talk box shows")
	ok(main.dock.input_label == "WHAT DO YOU SAY?")
	main.set_input_text("hello")
	eq(main.input_text(), "hello")
	ok(main.dock.natural_h > 80.0, "the dock grows for the box")
	main.close_input()
	ok(not main.dock.line_edit.visible, "and closes")


func test_fight_layout_fits_the_window():
	await _press(KEY_ENTER)
	main.game.debug_meet(["goblin", "slime", "bandit"])
	await _frames(3)
	var size := Vector2(1180, 820)
	for k in ["crt", "view", "side", "dock"]:
		ok(Rect2(Vector2.ZERO, size).encloses(main.L[k]), "%s inside the window: %s" % [k, main.L[k]])
	ok(main.map_box.fighting, "the map steps aside in a fight")
	# the tallest dock: a menu of eight spells
	var opts := []
	for i in 8:
		opts.append({"label": "SPELL %d" % i, "value": i, "cost": 1, "hint": "x"})
	main.game.G.menu = {"title": "WHAT WILL EUGENE DO? (3 OF 3)", "options": opts, "waiter": null, "sel": 0, "who": main.game.G.party[2]}
	main.render_dock()
	await _frames(1)
	ok(main.dock.natural_h > 150.0, "the menu's dock is tall: %s" % main.dock.natural_h)
	ok(main.L.crt.end.y <= 820.0, "and the CRT still fits: %s" % main.L.crt)
	var small := Layout.compute(Vector2(900, 700), {"jev": true, "dock_h": main.dock.natural_h})
	for k in ["crt", "view", "side", "dock", "jev"]:
		ok(Rect2(Vector2(0, 0), Vector2(900, 700)).encloses(small[k]), "900x700: %s inside: %s" % [k, small[k]])
	main.game.G.menu = null


func test_jev_panel_only_in_debug():
	ok(not main.debug)
	ok(not main.jev.visible, "no Jev panel without debug")
	main.show_jev({"kind": "vow", "to": {"name": "Glop", "species": "slime"}, "vow": {"text": "I WILL TALK TO SLIMES"}, "r": {"ms": 3, "liking": 2.5}})
	eq(main.jev.mind.blocks.size(), 1, "show_jev does nothing outside debug")
