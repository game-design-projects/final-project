## Genre Halls, the scene: drives fights with simulated keys through every faction on a fake clock and checks the flow
## (and, because it lets frames pass, that nothing in the drawing code raises a script error: run_tests counts those).
extends "res://tests/test_case.gd"

const Flags = preload("res://src/core/flags.gd")
const Rules = preload("res://src/genre/genre_rules.gd")
const Render = preload("res://src/view/render.gd")
const SCENE = preload("res://src/genre/genre_halls.tscn")

var scene: Control


func before_each() -> void:
	Flags.override = "nosound" # no audio in the tests: the real Sfx has its own tests


func after_each() -> void:
	Flags.override = null
	if scene != null:
		scene.queue_free()
		scene = null
		await _tree().process_frame


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## A scene on a fake clock (1 s), already past the title, with HP to spare
func _start(species := "") -> Control:
	scene = SCENE.instantiate()
	scene.clock_override = 1000.0
	_tree().root.add_child(scene)
	scene.set_process(false)
	scene.on_key("Enter")
	scene.G.maxHp = 999
	scene.G.hp = 999
	if species != "":
		scene.meet(species)
	return scene


## Advance the fake clock by `ms`, ticking at 60 Hz and letting a frame draw now and then
func _pump(ms: float, seen := {}) -> void:
	var end: float = scene.clock_override + ms
	var n := 0
	while scene.clock_override < end:
		scene.clock_override += 16.0
		scene.tick(scene.clock_override)
		if scene.D != null:
			for h in scene.D.hazards:
				seen[h.kind] = true
		n += 1
		if n % 12 == 0:
			await _draw_frame()


func _draw_frame() -> void:
	scene._view_canvas.queue_redraw()
	scene._map_canvas.queue_redraw()
	await _tree().process_frame


func _monster(species: String) -> Dictionary:
	for m in scene.G.map.monsters:
		if m.species == species:
			return m
	return {}


func _menu_labels() -> Array:
	var out := []
	for it in scene.G.menu:
		out.append(it.label)
	return out


## Play a fight to its end by striking until the foe falls, dodging at random in between
func _slay(species: String) -> void:
	_start(species)
	await _pump(800.0)
	eq(scene.G.mode, "menu", "%s: the command box opens after the intro" % species)
	var give_up: float = scene.clock_override + 400000.0
	while scene.G.mode != "result" and scene.clock_override < give_up:
		if scene.G.mode == "menu":
			scene.on_key("1")
			await _pump(300.0)
			scene.on_key("Enter")
		elif scene.G.mode == "dodge":
			scene.on_key(["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"][randi() % 4])
			await _pump(120.0)
		else:
			await _pump(100.0)
	eq(scene.G.mode, "result", "%s: the fight ends" % species)
	eq(scene.G.tally.slain, 1)
	eq(_monster(species).gone, "slain")
	scene.on_key("Enter")
	eq(scene.G.mode, "explore")


func test_the_title_starts_a_floor_with_five_monsters_and_the_page_text():
	scene = SCENE.instantiate()
	scene.clock_override = 1000.0
	_tree().root.add_child(scene)
	scene.set_process(false)
	eq(scene.G.mode, "title")
	await _draw_frame()
	scene.on_key("x") # any key starts (x is Esc on the other screens)
	eq(scene.G.mode, "explore")
	eq(scene.G.map.monsters.size(), 5)
	ok(scene.last_say.contains("B1F. Four kinds of monster hold this floor"), scene.last_say)
	await _draw_frame()


func test_walking_turning_bumping_and_meeting():
	_start()
	var m := _monster("bandit")
	# stand next to it, facing it
	var placed := false
	for i in 4:
		var d: Array = Render.DIRS[i]
		if scene._open(m.x - d[0], m.y - d[1]):
			scene.G.x = m.x - d[0]
			scene.G.y = m.y - d[1]
			scene.G.dir = i
			placed = true
			break
	ok(placed)
	var dir0: int = scene.G.dir
	scene.on_key("ArrowRight")
	eq(scene.G.dir, (dir0 + 1) % 4)
	scene.on_key("a") # WASD: left
	eq(scene.G.dir, dir0)
	scene.on_key("ArrowUp")
	eq(scene.G.mode, "intro", "walking into a monster starts the encounter")
	eq(scene.G.foe.species, "bandit")
	ok(scene.last_say.contains("It fights in CHESS."), scene.last_say)
	await _draw_frame()
	await _pump(800.0)
	eq(scene.G.mode, "menu")
	eq(_menu_labels(), ["FIGHT", "ACT", "SPARE", "FLEE"])
	# walls: bumping shakes the view and leaves you where you are
	scene.on_key("1")
	scene.on_key("Enter")
	await _pump(2000.0)


func test_a_wall_bump_shakes_and_stays_put():
	_start()
	for i in 4:
		var d: Array = Render.DIRS[i]
		if not scene._open(scene.G.x + d[0], scene.G.y + d[1]):
			scene.G.dir = i
			break
	var x: int = scene.G.x
	var y: int = scene.G.y
	scene.on_key("ArrowUp")
	eq([scene.G.x, scene.G.y], [x, y])
	ok(scene.G.shake > scene.clock_override)
	await _pump(300.0)


func test_each_faction_attacks_in_its_own_genre():
	var expect := {"slime": "goo", "bandit": "chess", "snake": "light", "rock": "stomp"}
	for species in expect:
		_start(species)
		await _pump(800.0)
		scene.start_dodge(1.0)
		eq(scene.G.mode, "dodge")
		var seen := {}
		await _pump(3200.0, seen)
		ok(seen.has(expect[species]), "%s lights %s squares, saw %s" % [species, expect[species], seen.keys()])
		eq(seen.size(), 1, "%s lights only its own kind" % species)
		scene.queue_free()
		await _tree().process_frame


func test_the_champion_changes_genre_every_turn():
	_start("dragon")
	await _pump(800.0)
	var order := []
	for turn in 4:
		scene.G.foe.turn = turn
		order.append(scene.foe_genre())
	eq(order, ["chess", "shadow", "rhythm", "bullet"])
	for turn in 4:
		scene.G.foe.turn = turn
		scene.start_dodge(2.0)
		await _pump(2500.0)
		scene.D = null
		scene.G.mode = "menu"


func test_a_lit_square_hurts_once_per_safe_window_and_bouncy_absorbs_a_hit():
	_start("slime")
	await _pump(800.0)
	scene.G.hp = 20
	scene.start_dodge(1.0)
	scene.D.next = 1e12 # no spawns: only the hazard laid by hand
	var here: int = Rules.idx(scene.D.soul.c, scene.D.soul.r)
	var t: float = scene.clock_override
	scene.D.hazards.append({"cells": {here: true}, "warn": t, "hit": t + 100.0, "end": t + 1500.0, "kind": "goo", "sounded": false})
	await _pump(60.0)
	eq(scene.G.hp, 20, "a warning does not hurt")
	await _pump(200.0)
	eq(scene.G.hp, 17, "a lit square costs 3")
	await _pump(400.0)
	eq(scene.G.hp, 17, "the safe window protects you")
	await _pump(600.0)
	eq(scene.G.hp, 14, "and ends")
	# with a slime ally, the first hit is absorbed
	scene.G.allies = [{"species": "slime", "name": "GLOP", "loyalty": 70.0}]
	scene.G.hp = 20
	scene.D = null
	scene.start_dodge(1.0)
	scene.D.next = 1e12
	ok(scene.D.shield)
	t = scene.clock_override
	scene.D.hazards.append({"cells": {here: true}, "warn": t, "hit": t + 50.0, "end": t + 3000.0, "kind": "goo", "sounded": false})
	await _pump(200.0)
	eq(scene.G.hp, 20, "BOUNCY takes the first hit")
	ok(not scene.D.shield)
	await _pump(1200.0)
	eq(scene.G.hp, 17, "and the next one lands")


func test_the_soul_moves_one_square_inside_the_box_and_stops_at_the_pillars():
	_start("snake")
	await _pump(800.0)
	scene.start_dodge(1.0)
	scene.D.next = 1e12
	eq([scene.D.soul.c, scene.D.soul.r], [3, 3])
	scene.on_key("ArrowLeft")
	eq(scene.D.soul.c, 2)
	scene.on_key("ArrowUp") # (2, 2) is a pillar in the shadow box
	eq(scene.D.soul.r, 3)
	for i in 8:
		scene.on_key("ArrowDown")
	eq(scene.D.soul.r, 6)
	for i in 8:
		scene.on_key("a")
	eq(scene.D.soul.c, 0)


func test_every_faction_can_be_fought_to_the_end_with_the_keys():
	for species in ["slime", "bandit", "snake", "rock", "dragon"]:
		await _slay(species)
		scene.queue_free()
		await _tree().process_frame


func test_act_check_and_say_something_once():
	_start("slime")
	await _pump(800.0)
	scene.on_key("2")
	eq(scene.G.mode, "act")
	eq(_menu_labels().slice(0, 1) + _menu_labels().slice(4), ["CHECK", "SAY SOMETHING"])
	eq(_menu_labels().slice(1, 4), ["TELL A JOKE", "OFFER COMFORT", "CALL IT GROSS"])
	scene.on_key("1") # CHECK is free: back to the main menu with a read of the monster
	eq(scene.G.mode, "menu")
	ok(scene.last_say.contains(" seems ") and scene.last_say.contains(" likes "), scene.last_say)
	scene.on_key("2")
	scene.on_key("Escape")
	eq(scene.G.mode, "menu", "Esc backs out of ACT")
	scene.on_key("2")
	scene.on_key("5")
	eq(scene.G.mode, "talk")
	ok(scene._talk.visible)
	scene.submit_talk("hello friend, where are the stairs?")
	ok(not scene._talk.visible)
	ok(scene.G.foe.spoke)
	var ids := []
	for q in scene.last_mind.answers:
		ids.append(q.id)
	ok(ids.has("words") and ids.has("feeling") and ids.has("mercy") and ids.has("pressure"), str(ids))
	await _pump(3000.0)
	for i in 30:
		if scene.G.mode == "dodge":
			await _pump(6000.0)
	eq(scene.G.mode, "menu")
	scene.on_key("2")
	var sub: String = scene.G.menu[4].sub
	eq(sub, "Already spoke this fight")
	scene.on_key("5")
	eq(scene.G.mode, "menu")
	ok(scene.last_say.contains("You've had your say this fight."))


func test_an_empty_line_goes_back_to_the_acts_and_nonsense_is_noticed():
	_start("rock")
	await _pump(800.0)
	scene.on_key("2")
	scene.on_key("5")
	scene.submit_talk("   ")
	eq(scene.G.mode, "act")
	eq(scene.G.foe.spoke, false)
	scene.on_key("5")
	scene.submit_talk("asdfgh qwrtzp")
	eq(scene.last_mind.answers[0].a.choice, "gibberish")
	ok(scene.last_say.contains("It didn't understand a word of that.") or scene.G.mode == "menu", scene.last_say)


func test_sparing_a_friendly_monster_ends_the_fight_and_it_may_join():
	seed(3)
	_start("slime")
	await _pump(800.0)
	var m: Dictionary = scene.G.foe
	m.meters.friendliness = 100.0
	m.meters.anger = 0.0
	m.meters.fear = 0.0
	ok(scene.spareable(m))
	scene.on_key("3")
	eq(scene.G.mode, "result")
	eq(m.gone, "spared")
	eq(scene.G.tally.spared, 1)
	ok(scene.last_say.contains("SPARED."), scene.last_say)
	var ids := []
	for q in scene.last_mind.answers:
		ids.append(q.id)
	ok(ids.has("join"), str(ids))
	if scene.G.tally.recruited > 0:
		eq(scene.G.allies.size(), 1)
		ok(scene.last_say.contains("It joins you: BOUNCY"), scene.last_say)
	await _draw_frame()
	scene.on_key("Enter")
	eq(scene.G.mode, "explore")
	ok(scene._hp.text.contains("999"))


func test_mercy_refused_costs_a_round_and_a_champion_cannot_be_fled():
	seed(5)
	_start("rock")
	await _pump(800.0)
	var m: Dictionary = scene.G.foe
	m.meters.friendliness = 0.0
	m.meters.anger = 100.0
	scene.on_key("3")
	ok(scene.last_say.contains("isn't ready to stop."), scene.last_say)
	await _pump(5000.0)
	for i in 20:
		if scene.G.mode == "dodge":
			await _pump(1000.0)
	eq(scene.G.mode, "menu")
	scene.on_key("4")
	eq(scene.G.mode, "explore", "fleeing a normal monster backs away")
	eq(scene.G.tally.fled, 1)
	eq(m.hp, m.maxHp)
	_start("dragon")
	await _pump(800.0)
	scene.on_key("4")
	eq(scene.G.mode, "menu")
	ok(scene.last_say.contains("The champion's tail blocks the way back."))


func test_dying_offers_the_fight_again_with_full_health():
	_start("bandit")
	await _pump(800.0)
	scene.G.hp = 2
	scene.start_dodge(1.0)
	scene.D.next = 1e12
	var here: int = Rules.idx(scene.D.soul.c, scene.D.soul.r)
	var t: float = scene.clock_override
	scene.D.hazards.append({"cells": {here: true}, "warn": t, "hit": t + 50.0, "end": t + 2000.0, "kind": "chess", "sounded": false})
	await _pump(300.0)
	eq(scene.G.mode, "dead")
	eq(_menu_labels(), ["TRY THIS FIGHT AGAIN", "NEW FLOOR"])
	await _draw_frame()
	scene.on_key("Enter")
	eq(scene.G.mode, "intro")
	eq(scene.G.hp, scene.G.maxHp)
	await _pump(800.0)
	eq(scene.G.mode, "menu")
	scene.G.hp = 1
	scene.start_dodge(1.0)
	scene.D.next = 1e12
	t = scene.clock_override
	scene.D.hazards.append({"cells": {here: true}, "warn": t, "hit": t + 50.0, "end": t + 2000.0, "kind": "chess", "sounded": false})
	await _pump(300.0)
	eq(scene.G.mode, "dead")
	scene.on_key("2") # NEW FLOOR
	eq(scene.G.mode, "explore")
	eq(scene.G.hp, scene.G.maxHp)


func test_the_stairs_name_the_route():
	_start()
	var cases := [
		[{"spared": 0, "slain": 0}, "THE GHOST ROUTE"],
		[{"spared": 2, "slain": 0}, "THE QUIET ROUTE"],
		[{"spared": 0, "slain": 3}, "THE BLOOD ROUTE"],
		[{"spared": 1, "slain": 1}, "THE TANGLED ROUTE"],
	]
	for c in cases:
		scene.G.tally = {"spared": c[0].spared, "slain": c[0].slain, "fled": 0, "recruited": 0, "left": 0}
		scene.ending()
		eq(scene.G.mode, "end")
		ok(scene.last_say.contains(c[1]), "%s in %s" % [c[1], scene.last_say])
		await _draw_frame()
	scene.on_key("Enter") # NEW FLOOR
	eq(scene.G.mode, "explore")


func test_allies_judge_what_you_do_and_leave_when_crossed():
	seed(9)
	_start("rock")
	await _pump(800.0)
	scene.G.allies = [{"species": "slime", "name": "GLOP", "loyalty": 31.0}]
	scene.render_party()
	scene.judge("slay_begging") # a slime hates killing something that begged
	ok(scene.pending_judgement != null)
	ok(scene.G.allies.size() == 0 or scene.G.allies[0].loyalty < 31.0)
	scene.pending_judgement = null
	scene.G.allies = [{"species": "rock", "name": "ORE", "loyalty": 90.0}, {"species": "dragon", "name": "EMBER", "loyalty": 90.0}]
	scene.judge("flee")
	ok(scene.pending_judgement != null and scene.pending_judgement.rows.size() >= 2)
	scene.judge(null)
	scene.judge("no_such_event")
	await _draw_frame()


func test_charms_change_the_fight():
	_start("rock")
	await _pump(800.0)
	scene.G.allies = [{"species": "rock", "name": "ORE", "loyalty": 70.0}]
	scene.fight_bar()
	eq(scene.bar.dur, 1500.0, "STEADY slows the strike bar")
	scene.G.allies = []
	scene.fight_bar()
	eq(scene.bar.dur, 1100.0)
	await _pump(1300.0) # too late: the bar times out as a miss
	ok(scene.bar == null)
	ok(scene.last_say.contains("You swing wide and miss."), scene.last_say)


func test_meet_flag_jumps_straight_into_that_fight():
	Flags.override = "nosound meet=rock"
	scene = SCENE.instantiate()
	scene.clock_override = 1000.0
	_tree().root.add_child(scene)
	scene.set_process(false)
	eq(scene.G.mode, "intro")
	eq(scene.G.foe.species, "rock")
	await _pump(800.0)
	eq(scene.G.mode, "menu")


func test_every_screen_draws_without_errors():
	_start()
	await _draw_frame()
	scene.G.mode = "title"
	await _draw_frame()
	scene.G.mode = "explore"
	for k in ["ArrowRight", "ArrowUp", "ArrowUp", "ArrowLeft", "ArrowDown"]:
		scene.on_key(k)
		await _draw_frame()
	for species in ["slime", "bandit", "snake", "rock", "dragon"]:
		scene.meet(species)
		await _pump(300.0) # the intro flash
		await _pump(600.0)
		scene.on_key("1")
		await _pump(500.0) # the strike bar
		scene.bar = null
		scene.G.mode = "menu"
		for turn in (4 if species == "dragon" else 1):
			scene.G.foe.turn = turn
			scene.start_dodge(2.0)
			await _pump(2200.0)
			scene.D = null
		scene.G.mode = "menu"
		scene.G.foe.gone = "slain"
		scene.explore()
		await _draw_frame()


func _key(keycode: Key, unicode := 0, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.unicode = unicode
	e.pressed = true
	e.echo = echo
	return e


func test_key_events_become_the_js_key_names_and_drive_the_game():
	_start()
	eq(scene._js_key(_key(KEY_UP)), "ArrowUp")
	eq(scene._js_key(_key(KEY_ENTER)), "Enter")
	eq(scene._js_key(_key(KEY_KP_ENTER)), "Enter")
	eq(scene._js_key(_key(KEY_ESCAPE)), "Escape")
	eq(scene._js_key(_key(KEY_SPACE, 32)), " ")
	eq(scene._js_key(_key(KEY_W, 119)), "w")
	eq(scene._js_key(_key(KEY_3, 51)), "3")
	eq(scene._js_key(_key(KEY_SHIFT)), "")
	var dir0: int = scene.G.dir
	scene._input(_key(KEY_RIGHT))
	eq(scene.G.dir, (dir0 + 1) % 4)
	scene._input(_key(KEY_D, 100))
	eq(scene.G.dir, (dir0 + 2) % 4)
	var cmd := _key(KEY_LEFT)
	cmd.meta_pressed = true
	scene._input(cmd) # shortcuts belong to the OS
	eq(scene.G.dir, (dir0 + 2) % 4)
	scene.meet("slime")
	await _pump(800.0)
	scene._input(_key(KEY_DOWN, 0, true)) # a held key does not repeat on the menus
	eq(scene.G.sel, 0)
	scene._input(_key(KEY_DOWN))
	eq(scene.G.sel, 1)
	scene._input(_key(KEY_2, 50)) # ACT
	eq(scene.G.mode, "act")


func test_escape_in_the_typed_line_goes_back_to_the_acts_and_enter_says_it():
	_start("snake")
	await _pump(800.0)
	scene.on_key("2")
	scene.on_key("5")
	eq(scene.G.mode, "talk")
	scene._on_talk_gui_input(_key(KEY_ESCAPE))
	eq(scene.G.mode, "act")
	ok(not scene._talk.visible)
	scene.on_key("5")
	scene._talk_in.text = "you have such beautiful scales"
	scene._talk_in.text_submitted.emit(scene._talk_in.text)
	ok(scene.G.foe.spoke)
	ok(scene.last_say.contains("You say \"you have such beautiful scales\"."), scene.last_say)


func test_escape_on_the_title_and_the_route_screen_goes_back_when_there_is_a_main_scene():
	scene = SCENE.instantiate()
	scene.clock_override = 1000.0
	_tree().root.add_child(scene)
	scene.set_process(false)
	if ResourceLoader.exists(scene.MAIN_SCENE):
		return # changing scenes would pull the test runner's tree apart: it is checked by hand
	scene.on_key("Escape")
	eq(scene.G.mode, "explore", "no main scene: Esc is just a key")


func test_with_the_real_sfx_the_fight_makes_its_sounds():
	Flags.override = "" # sound on
	_start("rock")
	ok(scene.sfx is Node, "the effects live under the scene")
	ok(scene.sfx.running, "audio is up from the first key")
	scene.sfx.log_plays = true
	await _pump(800.0)
	scene.on_key("1")
	await _pump(400.0)
	scene.on_key("Enter") # a strike
	await _pump(1000.0)
	scene.start_dodge(1.0)
	await _pump(3000.0) # the stomps tick on the beat
	var names := []
	for p in scene.sfx.plays:
		names.append(p.name)
	ok(names.has("tick"), str(names))
	ok(names.has("hit") or names.has("crit") or names.has("miss"), str(names))
	ok(scene.sfx.stats.played > 0)
