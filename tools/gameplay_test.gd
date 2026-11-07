## Checks the gameplay scene with no window: after NEW FLOOR (or dying and choosing it) and after loading a save, the
## header, status row, dock and overlay read the new state, not the one that was replaced; and the player's side of it: the
## keys (the title card, numpad digits, the info key), the mouse and the touch pad (a click on the picture strikes, hovering a
## command picks it), the tooltips over the foe, an ally and the map, the autosave at the start of a floor, the pause menu's
## save and load messages, and the flag `debug`. Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/gameplay_test.gd
extends "res://tools/test_base.gd"

const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const Vision = preload("res://src/rules/vision.gd")

var Saves = null # loaded when the test runs, like the other scripts that reach the Store autoload


func _name() -> String:
	return "gameplay_test"


func _run() -> void:
	Saves = load("res://src/menu/saves.gd")
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=11"]))
	var game = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await _title_card(game)
	await game._begin()
	_check(_bound(game), "the views read the first floor's state")
	var first = game.flow.state
	await game.flow.new_run()
	_check(game.flow.state != first, "NEW FLOOR makes a new state")
	_check(_bound(game), "after NEW FLOOR the header, status row, dock and overlay read the new state")
	game.flow.state.hp = 0
	game.flow.state.stage = "dead"
	await game.flow.new_run()
	_check(_bound(game), "the same after a death")
	game.flow.state.gold = 8
	var saved: Dictionary = game.flow.state.to_dict()
	await game.flow.new_run()
	var before = game.flow.state
	before.gold = 99 # so the loaded state is told apart from the one it replaces
	var loaded: bool = await game.flow.load_state(saved)
	_check(loaded and game.flow.state != before and game.flow.state.gold == 8, "loading a save makes a new state with the saved gold (8, not the replaced state's 99)")
	_check(_bound(game), "after loading a save the views read the loaded state (nothing else rebinds them)")
	var kept = game.flow.state
	_check(not await game.flow.load_state({}) and game.flow.state == kept and kept.gold == 8 and _bound(game), "a save that cannot be loaded leaves the state, and the views on it, as they were")
	await _autosave(game)
	await _pause_menu(game)
	await _keys(game)
	await _mouse(game)
	await _hover_and_tips(game)
	await _thinking(game)
	await _sub_text_wraps(game)
	await _start_is_guarded(game)
	await _keys_after_a_fight(game)
	await _wide_view(game)
	game.queue_free()
	await process_frame
	await _pad_and_debug()
	_finish()


## The picture follows the panel's shape, and what lies over it and points at it follows the picture.
func _wide_view(game) -> void:
	if not game.flow.feature("wide-view"):
		_check(game._viewport.size == Vector2i(448, 288) and game._overlay.extra_x == 0.0, "no wide-view: the picture keeps 448:288")
		return
	var script = game.get_script()
	_check(script.picture_width(Vector2(400, 400)) == 448, "a squarer panel keeps the old shape")
	_check(script.picture_width(Vector2(1000, 400)) == 688, "a very wide one stops at the widest (%d)" % script.picture_width(Vector2(1000, 400)))
	_check(script.picture_width(Vector2(1136, 540)) % 16 == 0 and script.picture_width(Vector2(1136, 540)) > 448, "the width moves in steps")
	var was: Vector2i = root.size
	root.size = Vector2i(1500, 1000) # a window with room to the sides
	await process_frame
	await process_frame
	var want: int = script.picture_width(game._room.size)
	_check(want > 448, "this window has a panel wider than the old shape (%s)" % game._room.size)
	_check(game._viewport.size == Vector2i(want, 288), "the picture fills the panel (%s in %s)" % [game._viewport.size, game._room.size])
	_check(is_equal_approx(game._aspect.ratio, want / 288.0), "the frame takes the same shape")
	var shown: float = game._picture.size.x / game._picture.size.y
	_check(absf(shown - game._room.size.x / game._room.size.y) < 0.06, "with no black on either side (%.2f in a panel of %.2f)" % [shown, game._room.size.x / game._room.size.y])
	var extra: float = (want - 448) / 2.0
	_check(game._overlay.extra_x == extra and game._overlay.position.x == extra, "the overlay keeps the middle")
	_check(game._overlay.whole_picture().size.x == want and game._overlay.whole_picture().position.x == -extra, "and its black and flashes reach the edges")
	_check(game._in_picture(game._picture.size / 2.0).is_equal_approx(Vector2(224, 144)), "the middle of the picture is the middle of the overlay")
	var k: float = game._tips.size.x / 448.0
	_check(absf(game._tips.size.y / 288.0 - k) < 0.02, "the tips keep 448:288 too (%s)" % game._tips.size)
	var map: Rect2 = game._tips.automap_rect()
	var corner: Vector2 = game._automap.get_global_rect().get_center()
	var as_seen: Vector2 = game._in_picture(corner - game._picture.get_global_position())
	_check(map.has_point(as_seen), "the map's card knows where the map is (%s in %s)" % [as_seen, map])
	_check(absf(Vision.view_tan - tan(deg_to_rad(34.0)) * want / 288.0) < 0.002, "what the party sees is what the picture shows")
	if game._postfx.attached():
		_check(game._postfx._bloom_view.size.x >= want / 4, "and the glow is worked out for this size")
	root.size = was
	await process_frame
	await process_frame
	_check(game._viewport.size.x == script.picture_width(game._room.size), "and it follows the window back (%d)" % game._viewport.size.x)


func _bound(game) -> bool:
	var s = game.flow.state
	return game._header.state == s and game._status.state == s and game._dock.state == s and game._overlay.state == s and game._tips.state == s


# ---------------------------------------------------------------- helpers

func _key(code: int, mods := {}, unicode := 0) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.physical_keycode = code as Key
	e.unicode = unicode
	e.pressed = true
	e.shift_pressed = mods.get("shift", false)
	e.meta_pressed = mods.get("meta", false)
	e.ctrl_pressed = mods.get("ctrl", false)
	return e


func _click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = button as MouseButton
	e.pressed = true
	return e


func _move(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	return e


## A point of the picture (in its own 448 x 288 pixels) as the picture control sees it.
func _on_picture(game, p: Vector2) -> Vector2:
	return (p + Vector2(game._overlay.extra_x, 0.0)) / Vector2(game._viewport.size) * game._picture.size


## Put the party in a fight with the first monster and in its command menu.
func _fight(game) -> void:
	await game.flow.go("explore")
	game.flow._keys_back_at = -1.0 # as if the moment after the last fight has passed
	var m = game.flow.state.floor_map.monsters[0]
	await game.flow.go("intro", {"foe": m})
	await game.flow.go("menu")


# ---------------------------------------------------------------- the title card

func _title_card(game) -> void:
	_check(game._on_title, "the scene opened on its own starts on the title card")
	for ev in [_key(KEY_SHIFT, {"shift": true}), _key(KEY_CTRL, {"ctrl": true}), _key(KEY_META, {"meta": true}), _key(KEY_F5), _key(KEY_TAB), _key(KEY_CAPSLOCK), _key(KEY_K, {"meta": true}, 107)]:
		game._unhandled_input(ev)
	_check(game._on_title and game.flow.state.stage == "", "Shift, Ctrl, Cmd, F5, Tab, Caps Lock and Cmd+K do not start the run")
	game._unhandled_input(_key(KEY_A, {}, 97))
	await process_frame
	_check(not game._on_title and game.flow.state.stage == "explore", "a letter starts it")
	# the same card, left by a click on the picture
	var again = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(again)
	await process_frame
	_check(again._on_title, "a second scene is on its title card")
	again._on_picture_input(_click(_on_picture(again, Vector2(224, 144))))
	await process_frame
	_check(not again._on_title and again.flow.state.stage == "explore", "a click on the picture starts the run, as the first key did")
	again.queue_free()
	await process_frame
	var third = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(third)
	await process_frame
	third._unhandled_input(_key(KEY_ENTER))
	await process_frame
	_check(third.flow.state.stage == "explore", "Enter starts it too")
	third.queue_free()
	await process_frame


# ---------------------------------------------------------------- saving

func _autosave(game) -> void:
	Saves.delete_all()
	await game.flow.new_run()
	var first: Dictionary = Saves.info(Saves.AUTO)
	_check(not first.empty and not first.corrupt, "a new floor is autosaved as soon as it starts, before the first step")
	_check(Saves.read(Saves.AUTO).get("cell") == [game.flow.state.cell.x, game.flow.state.cell.y], "with the party standing at its start")
	await game.flow.new_run()
	_check(Saves.info(Saves.AUTO).seq > first.seq, "NEW FLOOR is autosaved too, so Continue returns to this floor, not the one before")
	Saves.delete_all()
	var saved: Dictionary = game.flow.state.to_dict()
	await game.flow.load_state(saved)
	_check(Saves.info(Saves.AUTO).empty, "loading a save does not write the autosave")
	# the playtest slice's floor is never autosaved
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=11", "personality-slice"]))
	var PersonalitySlice = load("res://src/game/personality_slice.gd")
	PersonalitySlice.reset()
	var slice = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(slice)
	await process_frame
	await process_frame # the scene begins the slice itself
	_check(Saves.info(Saves.AUTO).empty, "the personality slice's floor is not autosaved")
	slice.queue_free()
	await process_frame
	PersonalitySlice.reset()
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=11"]))
	Saves.delete_all()


func _pause_menu(game) -> void:
	await game.flow.new_run()
	Saves.delete_all()
	game._open_pause()
	var panel = game._pause
	var items: Array = panel._page.items
	_check(items[1].label == "SAVE GAME" and not items[1].get("disabled", false), "the pause menu can save while walking")
	# SAVE GAME is the way in: the list of slots, and a slot saved from it says so in the log
	items[1].act.call()
	var slot_item: Dictionary = panel._page.items[3] # slot 3, after the autosave and slots 1 and 2
	slot_item.act.call()
	_check(not Saves.info("3").empty, "saving into a slot writes it")
	var said: String = " ".join(game.flow.state.lines.map(func(l): return l.text))
	_check(said.contains("Saved to slot 3"), "and the log says 'Saved to slot 3.' (%s)" % said)
	game._resume()
	# a load that cannot work keeps the menu, and says so
	game._open_pause()
	var state = game.flow.state
	await game._load_slot("5") # an empty slot
	_check(game._pause.visible and game.flow.state == state, "loading an empty slot keeps the pause menu open and the run as it was")
	_check(panel._page.get("title", "") == "CAN'T LOAD", "and says it can't load (%s)" % panel._page.get("title", ""))
	panel.pop()
	Saves.write("5", {"cell": "nowhere", "floor": 5}, "a bad one")
	await game._load_slot("5")
	_check(game._pause.visible and game.flow.state == state and panel._page.get("title", "") == "CAN'T LOAD", "a save that cannot be played does the same")
	panel.pop()
	Saves.write("5", state.to_dict(), "a good one")
	await game._load_slot("5")
	_check(not game._pause.visible and game.flow.state != state, "a save that can be played loads, and the menu closes")
	Saves.delete_all()


# ---------------------------------------------------------------- keys

func _keys(game) -> void:
	await _fight(game)
	var s = game.flow.state
	game._unhandled_input(_key(KEY_KP_2, {}, 50))
	await process_frame
	_check(s.stage == "act", "numpad 2 picks the second command, as the 2 above the letters does")
	game._unhandled_input(_key(KEY_ESCAPE))
	await process_frame
	_check(s.stage == "menu", "Esc goes back")
	# Esc on the route screen goes to the main menu
	var left := {"v": false}
	game.flow.happened.connect(func(name, _d): if name == "leave": left.v = true)
	s.cell = s.floor_map.stairs
	await game.flow.go("explore")
	game.flow._keys_back_at = -1.0
	await game.flow.go("end")
	await game.flow.press("cancel")
	_check(left.v, "Esc on the route screen leaves for the main menu")
	await game.flow.new_run()


# ---------------------------------------------------------------- the mouse

func _mouse(game) -> void:
	var s = game.flow.state
	# a click on the picture while the strike bar sweeps is OK
	await _fight(game)
	await game.flow.press("1") # FIGHT
	_check(s.stage == "fightbar" and s.bar != null, "FIGHT starts the strike bar")
	game._on_picture_input(_click(_on_picture(game, Vector2(224, 144))))
	await process_frame
	_check(s.stage != "fightbar" and s.bar == null, "a click on the picture stops the bar (it strikes)")
	# a click on the picture does nothing while walking, and does not act as a command in the menu
	await game.flow.new_run()
	var cell = s.cell
	game._on_picture_input(_click(_on_picture(game, Vector2(224, 144))))
	game._on_picture_input(_click(_on_picture(game, Vector2(10, 10)), MOUSE_BUTTON_RIGHT))
	await process_frame
	_check(game.flow.state.stage == "explore" and game.flow.state.cell == cell, "a click on the picture while walking does nothing")
	await _fight(game)
	game._on_picture_input(_click(_on_picture(game, Vector2(10, 270))))
	await process_frame
	_check(game.flow.state.stage == "menu", "and in the fight menu it does not pick a command by itself")
	# touch: with the mouse emulated from it, the screen touch is not a second click
	var touch := InputEventScreenTouch.new()
	touch.position = _on_picture(game, Vector2(224, 144))
	touch.pressed = true
	game.flow.state.selected = 0
	await game.flow.press("1")
	game._on_picture_input(touch)
	await process_frame
	if Input.is_emulating_mouse_from_touch():
		_check(game.flow.state.stage == "fightbar", "a screen touch is the emulated click's, not a second one")
	await game.flow.press("confirm")
	# a click on a command in the dock picks it
	await game.flow.new_run()
	await _fight(game)
	var dock = game._dock
	await process_frame
	var rect: Rect2 = dock.command_rects()[1]
	dock._gui_input(_click(rect.get_center()))
	await process_frame
	_check(game.flow.state.stage == "act", "a click on ACT in the dock opens it")


# ---------------------------------------------------------------- hover and tooltips

func _hover_and_tips(game) -> void:
	await game.flow.new_run()
	await _fight(game)
	await game.flow.encounter.decide(game.flow.state.foe, [{"intent": "kindness", "w": 1.0}], "KIND") # the mind has said a few things
	await process_frame
	var s = game.flow.state
	var dock = game._dock
	var rects: Array = dock.command_rects()
	_check(rects.size() == s.menu.size() and rects.size() >= 4, "the dock knows where its commands are, and they all fit (%d)" % rects.size())
	var picks := []
	dock.hovered.connect(func(i): picks.append(i))
	dock._gui_input(_move(rects[2].get_center()))
	_check(s.selected == 2 and picks == [2], "hovering SPARE picks it (the key row then shows what it does)")
	_check(dock.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "over a command the cursor is a hand")
	dock._gui_input(_move(rects[2].get_center() + Vector2(1, 0)))
	_check(picks == [2], "moving inside the same command says nothing more")
	dock._gui_input(_move(Vector2(dock.size.x * 0.5, dock.size.y - 2)))
	_check(dock.mouse_default_cursor_shape == Control.CURSOR_ARROW and s.selected == 2, "off the commands the cursor is an arrow and the pick stays")
	s.selected = 0
	_check(dock.sub_text() == s.menu[0].sub and not dock.sub_text().is_empty(), "the key row shows the picked command's sub text")
	# the command's help is a tooltip when the mouse rests on it
	var tips = game._tips
	dock._gui_input(_move(rects[2].get_center()))
	_check(tips.shown() == "command2", "resting on SPARE shows its help (%s)" % tips.shown())
	_check(tips.blocks().any(func(b): return str(b.get("text", "")).contains("chance to accept")), "which is the command's own text")
	dock.mouse_exited.emit()
	_check(tips.shown() == "", "and goes when the mouse leaves")
	# the foe
	tips.hover(Vector2(224, 150))
	_check(tips.shown() == "foe", "the mouse over the foe shows its mind card")
	var m = s.foe
	m.checks = m.clues().size() # as if read: the feature reveal hides what isn't yet
	m.known_traits = m.traits.duplicate()
	var text := _text_of(tips.blocks())
	_check(text.contains("FRIENDLY") and text.contains("ANGER") and text.contains("FEAR"), "the card has the three meters")
	_check(text.contains(str(roundi(m.meters.friendliness))) and text.contains("Seems %s." % " and ".join(m.traits)), "with their numbers and 'Seems X and Y.' (%s)" % text.left(120))
	_check(m.clues().all(func(c): return text.contains(c)), "and each clue the traits give")
	_check(text.contains(m.name) and text.contains(str(load("res://src/rules/content.gd").species(m.species).label).to_upper()), "and who it is")
	var rows: Array = s.mind_rows
	_check(rows.size() >= 2 and tips.blocks().filter(func(b): return b.kind == "question").size() == 2, "and the last two answers of the mind as questions (%d rows in all)" % rows.size())
	_check(tips.blocks().filter(func(b): return b.kind == "question").all(func(q): return q.bars.size() > 0 or str(q.get("note", "")) != ""), "each with its bars")
	tips.hover(Vector2(5, 280))
	_check(tips.shown() == "", "the card goes when the mouse leaves the foe")
	tips.hover(Vector2(224, 150))
	game._on_picture_input(_click(_on_picture(game, Vector2(224, 150))))
	tips.hover(Vector2(5, 280))
	_check(tips.shown() == "foe", "a click on the foe keeps the card open (touch has no hover)")
	game._on_picture_input(_click(_on_picture(game, Vector2(224, 150))))
	_check(tips.shown() == "", "a second click closes it")
	# the info key
	s.chat = [] # the talk so far has a card too, once there is talk (features_test)
	s.allies = [] # she has a card too, once she is there
	game._unhandled_input(_key(KEY_I, {}, 105))
	_check(tips.shown() == "foe", "I shows the foe's card from the keyboard")
	game._unhandled_input(_key(KEY_I, {}, 105))
	_check(tips.shown() == "", "I again closes it (no allies to look at)")
	game._unhandled_input(_key(KEY_I, {}, 105))
	game._unhandled_input(_key(KEY_DOWN))
	await process_frame
	_check(tips.shown() == "", "any other key closes it")
	# the allies
	var Ally = load("res://src/game/ally.gd")
	s.allies = [Ally.make("slime", "GLOP", 80.0), Ally.make("rock", "STONE", 20.0)]
	await process_frame
	await process_frame
	_check(tips.chip_count() == 2, "each ally is a chip over the picture")
	tips.hover_chip(0, true)
	_check(tips.shown() == "ally0", "hovering a chip shows the ally's card")
	text = _text_of(tips.blocks())
	var sp = load("res://src/rules/content.gd").species("slime")
	_check(text.contains("GLOP") and text.contains("DEVOTED") and text.contains(s.allies[0].charm().name) and text.contains("80"), "with its name, mood, charm and loyalty (%s)" % text.left(100))
	_check(text.contains("Cares about: " + sp.values) and text.contains(s.allies[0].charm().text), "what it cares about and what its charm does")
	tips.hover_chip(0, false)
	tips.hover_chip(1, true)
	_check(_text_of(tips.blocks()).contains("MAY LEAVE") and _text_of(tips.blocks()).contains("STONE"), "an ally that may leave says so")
	tips.hover_chip(1, false)
	_check(tips.shown() == "", "the card goes when the mouse leaves the chip")
	game._unhandled_input(_key(KEY_I, {}, 105))
	game._unhandled_input(_key(KEY_I, {}, 105))
	_check(tips.shown() == "ally0", "I goes from the foe to the first ally")
	game._unhandled_input(_key(KEY_I, {}, 105))
	_check(tips.shown() == "ally1", "then to the next")
	game._unhandled_input(_key(KEY_I, {}, 105))
	_check(tips.shown() == "", "then closes")
	# the map legend, while walking
	await game.flow.go("explore")
	await process_frame
	tips.hover(Vector2(400, 30))
	_check(tips.shown() == "map", "the mouse over the automap shows what its colours mean")
	text = _text_of(tips.blocks())
	_check(["SLIME", "BANDIT", "SNAKE", "ROCK", "DRAGON"].all(func(n): return text.contains(n)) and text.contains("goo rain") and text.contains("chess") and text.contains("all four"), "every monster's colour with its kind of fight")
	tips.hover(Vector2(5, 140))
	game._unhandled_input(_key(KEY_I, {}, 105))
	_check(tips.shown() == "ally0", "walking, I looks at the first ally")
	game._unhandled_input(_key(KEY_I, {}, 105))
	game._unhandled_input(_key(KEY_I, {}, 105))
	_check(tips.shown() == "map", "then the legend")
	game._unhandled_input(_key(KEY_I, {}, 105))
	s.allies = []
	await process_frame
	_check(tips.chip_count() == 0, "no allies, no chips")


func _text_of(blocks: Array) -> String:
	var out := []
	for b in blocks:
		match b.kind:
			"head":
				out.append(str(b.left) + " " + str(b.right))
			"text":
				out.append(b.text)
			"meters":
				for cell in b.cells:
					out.append("%s %s" % [cell[0], cell[1]])
			"question":
				out.append(str(b.label))
				out.append(str(b.get("note", "")))
				for bar in b.bars:
					out.append("%s %s" % [bar[0], bar[2]])
			"bar":
				out.append("%s %s" % [b.label, b.pct])
			"swatch":
				out.append("%s %s" % [b.left, b.right])
	return " ".join(out)


# ---------------------------------------------------------------- waiting for Jev

func _thinking(game) -> void:
	var Network = load("res://src/network/network.gd")
	var dock = game._dock
	game._process(0.016)
	_check(dock.thinking_ms == 0 and not dock.is_thinking(), "nothing says 'thinking' while no question is out")
	Network._flights[-1] = Time.get_ticks_msec() - 900
	game._process(0.016)
	_check(dock.thinking_ms >= 800 and dock.is_thinking(), "a question that has been out for a while shows as thinking (%d ms)" % dock.thinking_ms)
	Network._flights[-1] = Time.get_ticks_msec() - 20
	game._process(0.016)
	_check(not dock.is_thinking(), "a quick answer does not flicker it")
	Network._flights.erase(-1)


# ---------------------------------------------------------------- the help line under the keys

## SPARE's help is about 980 px at the dock's font: in a window narrower than that it wraps to a second line and the dock makes
## room for it, rather than running off the bottom of the window.
func _sub_text_wraps(game) -> void:
	await _fight(game)
	var Hud = load("res://src/view/hud.gd")
	var dock = Hud.new()
	dock.part = Hud.Part.DOCK
	dock.state = game.flow.state
	var longest := 0.0
	for item in game.flow.state.menu:
		longest = maxf(longest, load("res://src/view/fonts.gd").body().get_string_size(str(item.sub), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)
	_check(longest > 900.0 and longest < 1100.0, "SPARE's help is about 980 px wide at the dock's font (%d)" % longest)
	dock.size = Vector2(1180, 200)
	dock._process(0.0)
	_check(not dock._sub_wraps() and is_equal_approx(dock.custom_minimum_size.y, Hud.DOCK_H), "in a wide window it is one line and the dock keeps its height")
	dock.size = Vector2(800, 200)
	dock._process(0.0)
	_check(dock._sub_wraps() and is_equal_approx(dock.custom_minimum_size.y, Hud.DOCK_H + Hud.SUB_LINE_H), "in a narrow one it wraps and the dock is a line taller")
	dock.size = Vector2(1180, 200)
	dock._process(0.0)
	_check(is_equal_approx(dock.custom_minimum_size.y, Hud.DOCK_H), "and goes back when the window is wide again")
	dock.free()


# ---------------------------------------------------------------- a start that must not race a tick

## A mind that takes its time, as Jev does.
class SlowMind:
	extends "res://src/mind/local_mind.gd"

	func mercy(m) -> float:
		await Engine.get_main_loop().create_timer(0.25).timeout
		return super.mercy(m)


func _start_is_guarded(game) -> void:
	await game.flow.new_run()
	var flow = game.flow
	var real = flow.mind
	flow.mind = SlowMind.new()
	var m = flow.state.floor_map.monsters[0]
	flow.exclusive(func(): await flow.go("intro", {"foe": m})) # not awaited: the mind is still answering
	_check(flow.busy and flow.state.stage == "intro", "a start from outside holds input off while the mind answers")
	flow.tick(flow.clock + 100000.0)
	await process_frame
	_check(flow.state.stage == "intro", "so a tick arriving meanwhile does not run the intro's own tick (it would have moved on to the menu)")
	await create_timer(0.5).timeout
	_check(not flow.busy, "and input is free again when it is done")
	flow.tick(flow.clock + 100000.0)
	await create_timer(0.4).timeout
	_check(flow.state.stage == "menu", "after that the intro runs its course")
	flow.mind = real
	await game.flow.new_run()


# ---------------------------------------------------------------- the end of a fight

## Ends the fight on `game` with a key held and a key mashed, and returns where the party stood.
func _end_a_fight(game) -> Vector2i:
	await game.flow.new_run()
	var s = game.flow.state
	s.banner = null
	var open: Vector2i = s.cell + s.floor_map.DIRS[s.facing]
	_check(s.floor_map.is_open(open), "(a way to walk on from the start)")
	await game.flow.go("intro", {"foe": s.floor_map.monsters[0]})
	await game.flow.go("menu")
	s.floor_map.monsters[0].gone = "spared"
	await game.flow.encounter.leave_fight([])
	_check(s.stage == "explore", "the fight is over (%s)" % s.stage)
	return s.cell


func _echo(code: int) -> InputEventKey:
	var e := _key(code)
	e.echo = true
	return e


func _keys_after_a_fight(game) -> void:
	if not game.flow.feature("input-cooldown"):
		return
	var stood := await _end_a_fight(game)
	var s = game.flow.state
	game._unhandled_input(_echo(KEY_UP))
	await process_frame
	_check(s.cell == stood, "an arrow still held from the fight doesn't walk you on")
	game._unhandled_input(_key(KEY_UP))
	await process_frame
	_check(s.cell == stood, "and for a moment nor does a mashed one")
	await create_timer(Flow.AFTER_FIGHT_MS / 1000.0 + 0.1).timeout
	game._unhandled_input(_echo(KEY_UP))
	await process_frame
	_check(s.cell == stood, "held on after the moment has passed, it still does nothing")
	game._unhandled_input(_key(KEY_UP))
	await process_frame
	_check(s.cell != stood, "pressed afresh it walks")
	await create_timer(0.3).timeout
	var on: Vector2i = s.cell
	s.facing = _way_on(s)
	game._unhandled_input(_echo(KEY_UP))
	await process_frame
	_check(s.cell != on, "and held from there it goes on walking")
	game.flow._keys_back_at = -1.0
	game.flow._held_over = false


## A way to walk from here.
func _way_on(s) -> int:
	for i in 4:
		var c: Vector2i = s.cell + s.floor_map.DIRS[i]
		if s.floor_map.is_open(c) and not s.floor_map.in_the_way(c) and s.floor_map.monster_at(c) == null and c != s.floor_map.stairs:
			return i
	return s.facing


# ---------------------------------------------------------------- the touch pad and the debug flag

func _pad_and_debug() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=11", "pad", "debug"]))
	var game = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._unhandled_input(_key(KEY_A, {}, 97))
	await process_frame
	var s = game.flow.state
	var pad = game._pad
	_check(pad != null and pad.visible, "the flag `pad` shows the touch pad without a touch screen")
	_check(["up", "down", "left", "right", "confirm", "cancel", "info"].all(func(k): return pad.has_button(k)), "it has arrows, OK, BACK and INFO")
	var facing: int = s.facing
	pad.tap("right")
	await process_frame
	_check(s.facing == (facing + 1) % 4, "RIGHT turns")
	pad.tap("left")
	await process_frame
	_check(s.facing == facing, "LEFT turns back")
	var cell = s.cell
	for i in 4: # one of the four ways is a step, the others are walls: turn until UP walks
		pad.tap("up")
		await process_frame
		if s.cell != cell:
			break
		pad.tap("right")
	_check(s.cell != cell, "UP walks")
	# held, an arrow keeps acting while walking: it says its key again after a moment
	var repeats := []
	pad.repeated.connect(func(k): repeats.append(k))
	pad.press("left")
	await create_timer(0.6).timeout
	pad.release("left")
	_check(repeats.size() >= 2 and repeats.all(func(k): return k == "left"), "a held arrow repeats (%d times in 0.6 s)" % repeats.size())
	var after: int = repeats.size()
	await create_timer(0.3).timeout
	_check(repeats.size() == after, "and stops when it is let go")
	pad.tap("cancel")
	await process_frame
	_check(game._pause.visible, "BACK while walking opens the pause menu")
	game._resume()
	# in a fight: OK picks and strikes, the arrows dodge
	await _fight(game)
	s.selected = 0
	pad.tap("confirm")
	await process_frame
	_check(s.stage == "fightbar", "OK on FIGHT starts the bar")
	pad.tap("confirm")
	await process_frame
	_check(s.stage != "fightbar", "and OK stops it")
	await game.flow.new_run()
	s = game.flow.state
	await _fight(game)
	await game.flow.go("wait", {"pressure": 1.0})
	await game.flow.go("dodge", {"pressure": 1.0})
	var soul: Vector2i = s.dodge.soul
	pad.tap("left")
	pad.tap("up")
	_check(s.dodge.soul != soul, "the arrows move the heart in the dodge")
	# the info button
	s.dodge = null
	await game.flow.go("menu")
	pad.tap("info")
	_check(game._tips.shown() == "foe", "INFO shows the foe's card")
	# the flag debug keeps the mind panel open
	_check(game._tips.debug and game._tips.panel_open(), "with `debug` the mind panel stays open while a fight waits")
	game.queue_free()
	await process_frame
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=11"]))
