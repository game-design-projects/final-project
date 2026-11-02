## Genre Halls, the scene: drives fights with simulated keys through every faction on a fake clock and checks the flow
## (and, because it lets frames pass, that nothing in the drawing code raises a script error: run_tests counts those).
extends "res://tests/test_case.gd"

const Flags = preload("res://src/core/flags.gd")
const Rules = preload("res://src/genre/genre_rules.gd")
const Render = preload("res://src/view/render.gd")
const Emotions = preload("res://src/rules/emotions.gd")
const SCENE = preload("res://src/genre/genre_halls.tscn")
const Settings = preload("res://src/menu/settings.gd")
const MemoryStore = preload("res://src/core/store.gd").Memory

var scene: Control


func before_each() -> void:
	Flags.override = "nosound" # no audio in the tests: the real Sfx has its own tests
	Settings.store_override = MemoryStore.new() # the player's own settings stay out of the tests
	Settings.apply_enabled = false
	Settings.forget()


func after_each() -> void:
	Flags.override = null
	Settings.store_override = null
	Settings.apply_enabled = true
	Settings.forget()
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


## Let the camera finish its glide or swing, then draw
func _settle() -> void:
	scene.clock_override += 5000.0
	await _draw_frame() # the camera starts moving now (its clock is the drawing's)
	scene.clock_override += 5000.0
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
	ok(scene.last_say.contains("B1F. Find the stairs."), scene.last_say)
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
	await _pump(100.0)
	eq(scene.G.hp, 20, "BOUNCY takes the first hit")
	ok(not scene.D.shield)
	await _draw_frame() # the "BOUNCY!" flash
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
	scene.flee()
	scene.meet("slime")
	await _pump(800.0)
	ok(not scene.G.foe.spoke, "a new encounter gives a new single message")
	scene.on_key("2")
	eq(scene.G.menu[4].sub, "Ask about stairs, the champion or another monster; one line per fight")


func test_personality_clues_are_visible_before_an_act_and_the_act_is_remembered():
	_start("bandit")
	var m: Dictionary = scene.G.foe
	m.traits = ["surprisingly honest about being dishonest", "quick-fingered"]
	m.taste = {}
	await _pump(800.0)
	scene._show_tip("foe", Rect2(), true)
	ok(scene._tip_body.get_child(1).text.contains("straight terms"), "the foe tooltip hints at its need")
	scene._hide_tip()
	scene.on_key("2") # ACT
	scene.on_key("1") # CHECK is free
	ok(scene.last_say.contains("straight terms"), "CHECK gives the same clue before any commitment")
	eq(m.lastIntent, "")
	scene.on_key("2")
	scene.on_key("2") # OFFER A FAIR CUT
	eq(m.lastIntent, "gold")
	ok(Rules.ask_join(m).noul > 0.0 and Rules.ask_join(m).noul < 1.0)


func test_seeded_personality_slice_changes_the_same_offer_and_can_be_won():
	_start()
	scene.start_personality_slice(7042)
	var honest: Dictionary = scene.G.foe
	var wary: Dictionary = scene.slice_next
	eq([honest.species, wary.species], ["bandit", "bandit"])
	eq([honest.name, wary.name], ["ROOK", "VEX"])
	ok(Rules.personality_clues(honest)[0].contains("straight terms"))
	ok(Rules.personality_clues(wary)[0].contains("exit"))
	ok(Rules.cut_odds(honest) > 0.5 and Rules.cut_odds(wary) < 0.5, "the clues predict different incentives")
	await _pump(800.0)
	scene.on_key("2")
	scene.on_key("2") # the identical fair-cut action succeeds for ROOK
	eq(honest.gone, "spared")
	eq(scene.G.gold, 6)
	eq(scene.G.tally.recruited, 0, "a paid truce does not recruit")
	ok(scene.last_say.contains("takes 6 gold") and scene.last_say.contains("keeps its word"), scene.last_say)
	scene.on_key("Enter")
	eq(scene.G.foe, wary)
	await _pump(800.0)
	scene.on_key("2")
	scene.on_key("2") # VEX hears the same offer and refuses it
	eq(wary.gone, null)
	eq(scene.G.gold, 6)
	ok(scene.last_say.contains("keeps watching the exit") and scene.last_say.contains("keep your gold"), scene.last_say)
	var pressure: float = Rules.ask_pressure(wary).score
	await _pump(800.0)
	eq(scene.G.mode, "dodge")
	ok(is_equal_approx(scene.D.intensity, 0.8 + 0.25 * pressure), "the next chess attack uses the reported pressure")
	await _pump(5500.0)
	eq(scene.G.mode, "menu")
	for hit in 2:
		scene.on_key("1")
		scene.clock_override += 550.0
		scene.on_key("Enter")
		if scene.G.mode == "result":
			break
		await _pump(6300.0)
	eq(wary.gone, "slain", "refusing the offer still leaves a combat victory")
	eq(scene.G.mode, "result")
	ok(scene.G.hp > 0)
	scene.on_key("Enter")
	eq(scene.G.mode, "explore")
	eq(scene.G.tally.spared + scene.G.tally.slain, 2)
	eq(scene.export_state().gold, 6)
	ok(scene.import_state(scene.export_state()), "the completed slice still loads through the ordinary save path")
	eq(scene.G.gold, 6)


func test_personality_slice_flag_starts_the_seeded_pair_from_the_menu_route():
	Flags.override = "nosound personality-slice seed=7042"
	scene = SCENE.instantiate()
	scene.clock_override = 1000.0
	_tree().root.add_child(scene)
	scene.set_process(false)
	eq(scene.G.mode, "intro")
	eq(scene.G.foe.name, "ROOK")
	eq(scene.slice_next.name, "VEX")
	eq(scene.G.gold, 12)


func test_seeded_pair_answers_the_same_question_differently():
	_start()
	scene.start_personality_slice(7042)
	var honest: Dictionary = scene.G.foe
	var wary: Dictionary = scene.slice_next
	await _pump(800.0)
	scene.on_key("2")
	scene.on_key("5")
	scene.submit_talk("Where are the stairs?")
	ok(scene.last_say.contains("corridor") and honest.spoke, scene.last_say)
	var known_step: String = scene._stairs_step()
	ok(scene.last_say.contains("corridor %s" % known_step), "the answer matches this floor")
	if scene.G.mode != "menu":
		await _pump(6300.0)
	eq(scene.G.mode, "menu")
	scene.on_key("2")
	scene.on_key("2")
	eq(honest.gone, "spared")
	scene.on_key("Enter")
	await _pump(800.0)
	scene.on_key("2")
	scene.on_key("5")
	scene.submit_talk("Where are the stairs?")
	ok(scene.last_say.contains("keeps watching the exit") and not scene.last_say.contains("corridor"), scene.last_say)
	ok(wary.spoke)


func test_recruiting_the_first_bandit_makes_a_later_gold_offer_cost_loyalty():
	_start()
	scene.start_personality_slice(7042)
	var honest: Dictionary = scene.G.foe
	await _pump(800.0)
	scene.spare()
	eq(honest.gone, "spared")
	eq(scene.G.allies.size(), 1)
	var old_loyalty: float = scene.G.allies[0].loyalty
	scene.on_key("Enter")
	await _pump(800.0)
	scene.on_key("2")
	scene.on_key("2")
	ok(scene.last_mind.answers.any(func(row): return str(row.id).begins_with("judge-")), "the ally judges the offer")
	ok(scene.G.allies[0].loyalty < old_loyalty, "offering gold to another monster strains the recruited bandit")
	ok(scene.last_say.contains(scene.G.allies[0].name), "the ally's objection reaches the player")
func test_genre_emotion_feedback_reports_applied_meters_instead_of_dnd_conditions():
	_start("slime")
	await _pump(800.0)
	for id in Emotions.EMOTIONS:
		var em: Dictionary = Emotions.EMOTIONS[id]
		var feedback: String = scene.genre_effect(em)
		ok(not feedback.contains("advantage") and not feedback.contains("damage") and not feedback.contains("gold"), "%s: %s" % [id, feedback])
		for meter in em.meters:
			ok(feedback.contains("%s %s" % [meter, "rises" if em.meters[meter] > 0 else "falls"]), "%s: %s" % [id, feedback])
	scene.on_key("2")
	scene.on_key("3") # OFFER COMFORT
	var feeling: String = scene.last_mind.answers[0].a.choice
	ok(scene.last_say.contains(scene.genre_effect(Emotions.EMOTIONS[feeling])), scene.last_say)


func test_pressure_tooltip_shows_the_fixed_value_used_for_the_next_dodge():
	_start("bandit")
	await _pump(800.0)
	var m: Dictionary = scene.G.foe
	var pressure: Dictionary = Rules.ask_pressure(m)
	eq(pressure.type, "pressure")
	ok(not pressure.has("probabilities"))
	var row: Dictionary = {"id": "pressure", "label": "HOW HARD DOES IT ATTACK?", "a": pressure}
	var display: Control = scene._question(row)
	ok(display.get_child(1).get_child(0).text.contains("%.2f / 3" % pressure.score))
	display.queue_free()
	scene.start_dodge(pressure.score)
	ok(is_equal_approx(scene.D.intensity, 0.8 + 0.25 * pressure.score))


func test_a_bandits_personality_changes_the_next_chess_dodge():
	_start("bandit")
	await _pump(800.0)
	var m: Dictionary = scene.G.foe
	m.meters = {"friendliness": 55, "anger": 20, "fear": 20}
	m.lastIntent = "threat"
	m.traits = ["jumpy"]
	scene.start_dodge(Rules.ask_pressure(m).score)
	var cautious: float = scene.D.intensity
	m.traits = ["surprisingly honest about being dishonest"]
	scene.start_dodge(Rules.ask_pressure(m).score)
	ok(scene.D.intensity > cautious, "the defiant bandit's chess attacks are more intense")
	eq(scene.D.genre, "chess", "personality does not change its combat genre")


func test_questions_reveal_floor_facts_and_personality_can_withhold_them():
	_start("slime")
	await _pump(800.0)
	var slime: Dictionary = scene.G.foe
	slime.traits = ["curious"]
	slime.taste = Rules.TRAIT_TASTE.curious.duplicate()
	scene.interaction_roll_override = 0.0
	var direction: String = scene._stairs_step()
	ok(["north", "east", "south", "west"].has(direction))
	var directions := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}
	var next: Vector2i = Vector2i(scene.G.x, scene.G.y) + directions[direction]
	eq(scene.G.map.grid[next.y][next.x], 1, "the first step is an open corridor")
	ok(_distance_to_stairs(next) < _distance_to_stairs(Vector2i(scene.G.x, scene.G.y)), "the step actually approaches the stairs by the maze route")
	scene.on_key("2")
	scene.on_key("5")
	scene.submit_talk("Where are the stairs?")
	ok(scene.last_say.contains("corridor %s toward the stairs" % direction), scene.last_say)
	ok(slime.spoke)
	var snake: Dictionary = _monster("snake")
	snake.taste = {"flattery": 20.0, "rush": -20.0}
	var hint: String = scene.hint_for(slime, "what does the snake want?")
	ok(hint.contains(snake.name) and hint.contains("being rushed"), hint)
	snake.taste = {"flattery": -20.0, "rush": 20.0}
	ok(scene.hint_for(slime, "what does the snake want?").contains("praise"), "the tip uses this monster's current taste")
	ok(scene.hint_for(slime, "what is the champion's opening?").contains("chess"))
	scene.queue_free()
	await _tree().process_frame
	scene = null
	_start("snake")
	await _pump(800.0)
	var secretive: Dictionary = scene.G.foe
	secretive.traits = ["secretive"]
	secretive.taste = Rules.TRAIT_TASTE.secretive.duplicate()
	scene.interaction_roll_override = 0.99
	scene.on_key("2")
	scene.on_key("5")
	scene.submit_talk("Where are the stairs?")
	ok(scene.last_say.contains("guards its secrets") and not scene.last_say.contains("corridor"), scene.last_say)
	ok(secretive.spoke)


func test_question_targeting_prefers_exact_names_and_rejects_ambiguous_or_unknown_topics():
	_start("slime")
	var speaker: Dictionary = scene.G.foe
	var rook: Dictionary = scene.G.map.monsters[1]
	var vex: Dictionary = scene.G.map.monsters[2]
	rook.name = "ROOK"
	rook.gone = "spared"
	vex.name = "VEX"
	vex.species = "bandit"
	var answer: String = scene.hint_for(speaker, "What does bandit VEX want?")
	ok(answer.contains("VEX") and not answer.contains("gone"), answer)
	ok(scene.hint_for(speaker, "What does the bandit want?").contains("which bandit"))
	ok(scene.hint_for(speaker, "ROOK or VEX?").contains("which monster"))
	ok(scene.hint_for(speaker, "Where are the stairs or the champion?").contains("one at a time"))
	ok(scene.hint_for(speaker, "Where are the stairs or the bandit?").contains("one thing at a time"))
	ok(scene.hint_for(speaker, "Where is VEX?").contains("ask what VEX wants"))
	ok(scene.hint_for(speaker, "Are the stairs dangerous?").contains("ask which way"))
	ok(scene.hint_for(speaker, "What does the champion want?").contains("opening genres"))
	var unknown: String = scene.hint_for(speaker, "Who are you?")
	ok(unknown.contains("ask me about") and not unknown.contains("uneasy"), unknown)
	await _pump(800.0)
	scene.interaction_roll_override = 0.0
	scene.on_key("2")
	scene.on_key("5")
	scene.submit_talk("Who are you?")
	ok(scene.last_say.contains("ask me about") and not scene.last_say.contains("uneasy"), scene.last_say)


func _distance_to_stairs(start: Vector2i) -> int:
	var goal := Vector2i(scene.G.map.stairs.x, scene.G.map.stairs.y)
	var queue := [[start, 0]]
	var seen := {start: true}
	var head := 0
	while head < queue.size():
		var entry: Array = queue[head]
		head += 1
		if entry[0] == goal:
			return entry[1]
		for d in Render.DIRS:
			var next: Vector2i = entry[0] + Vector2i(d[0], d[1])
			if next.x >= 0 and next.y >= 0 and next.y < scene.G.map.grid.size() and next.x < scene.G.map.grid[next.y].size() and scene.G.map.grid[next.y][next.x] == 1 and not seen.has(next):
				seen[next] = true
				queue.append([next, entry[1] + 1])
	return 999


func test_a_fair_cut_spends_gold_and_ends_the_fight_without_recruitment():
	_start("bandit")
	await _pump(800.0)
	var m: Dictionary = scene.G.foe
	m.traits = ["surprisingly honest about being dishonest"]
	m.taste = Rules.TRAIT_TASTE["surprisingly honest about being dishonest"].duplicate()
	m.meters.anger = 10
	scene.interaction_roll_override = 0.0
	eq(scene.G.gold, 8)
	scene.on_key("2")
	scene.on_key("2")
	eq(scene.G.gold, 2)
	eq(m.gone, "spared")
	eq(scene.G.tally.spared, 1)
	eq(scene.G.tally.recruited, 0)
	eq(scene.G.allies.size(), 0)
	eq(scene.G.mode, "result")
	ok(scene.last_say.contains("takes 6 gold"), scene.last_say)
	ok(scene.export_state().gold == 2, "the cost survives saving")
	scene.on_key("Enter")
	scene.meet("snake")
	await _pump(800.0)
	scene.G.foe.traits = ["always bargaining"]
	scene.G.foe.meters.anger = 10
	scene.on_key("2")
	scene.on_key("3") # the snake also asks for 6; the same purse cannot pay twice
	eq(scene.G.gold, 2)
	eq(scene.G.foe.gone, null)
	ok(scene.last_say.contains("You have 2"), scene.last_say)


func test_rejected_and_unaffordable_cuts_keep_gold_and_do_not_spare():
	_start("bandit")
	await _pump(800.0)
	var m: Dictionary = scene.G.foe
	m.traits = ["jumpy"]
	m.taste = Rules.TRAIT_TASTE.jumpy.duplicate()
	scene.interaction_roll_override = 0.99
	scene.on_key("2")
	scene.on_key("2")
	eq(scene.G.gold, 8)
	eq(m.gone, null)
	ok(scene.last_say.contains("keep your gold"), scene.last_say)
	ok(scene.G.mode == "wait" or scene.G.mode == "menu", "a refused offer uses a turn")
	scene.G.gold = 5
	scene.main_menu()
	scene.on_key("2")
	scene.on_key("2")
	eq(scene.G.gold, 5)
	eq(scene.G.mode, "menu")
	ok(scene.last_say.contains("You have 5"), scene.last_say)


func test_ally_tooltip_warns_that_a_refused_offer_can_cost_loyalty_but_not_gold():
	_start("bandit")
	await _pump(800.0)
	var m: Dictionary = scene.G.foe
	m.traits = ["jumpy"]
	m.taste = Rules.TRAIT_TASTE.jumpy.duplicate()
	scene.interaction_roll_override = 0.99
	scene.G.allies = [{"species": "bandit", "name": "ROOK", "loyalty": 70.0}]
	scene.render_party()
	scene._show_tip("ally0", Rect2(), true)
	var note: String = scene._tip_body.get_child(2).text
	ok(note.contains("gold given away to monsters") and note.contains("refused gold offer"), note)
	scene._hide_tip()
	scene.on_key("2")
	scene.on_key("2")
	eq(scene.G.gold, 8)
	ok(scene.G.allies[0].loyalty < 70.0)


func test_typed_gold_offer_uses_the_same_real_bargain():
	_start("bandit")
	await _pump(800.0)
	var m: Dictionary = scene.G.foe
	m.traits = ["surprisingly honest about being dishonest"]
	m.taste = Rules.TRAIT_TASTE["surprisingly honest about being dishonest"].duplicate()
	m.meters.anger = 10
	scene.interaction_roll_override = 0.0
	scene.on_key("2")
	scene.on_key("5")
	scene.submit_talk("I offer gold, a fair cut")
	eq(m.gone, "spared")
	eq(scene.G.gold, 2)
	ok(m.spoke)
	ok(scene.last_mind.answers.any(func(row): return row.id == "words"), "the typed offer is still read by the local mind")


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
	ok(scene.last_say.contains("refuses mercy") and scene.last_say.contains("chance to accept"), scene.last_say)
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
	eq(_menu_labels(), ["TRY THIS FIGHT AGAIN", "NEW FLOOR", "MAIN MENU"])
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


func test_escape_on_the_title_and_the_route_screen_goes_to_the_main_menu():
	scene = SCENE.instantiate()
	scene.clock_override = 1000.0
	scene.navigate = false # a real scene change would pull the test runner's tree apart
	_tree().root.add_child(scene)
	scene.set_process(false)
	scene.on_key("Escape")
	eq(scene.left_for, "menu", "Esc on the title leaves for the menu")
	eq(scene.G.mode, "title", "and doesn't start a run")
	scene.left_for = ""
	scene.on_key("Enter")
	scene.G.mode = "end"
	scene.on_key("Escape")
	eq(scene.left_for, "menu", "Esc on the route screen too")


func test_the_project_starts_in_the_main_menu_and_the_original_donjon_stays_behind_a_flag():
	eq(ProjectSettings.get_setting("application/run/main_scene"), "res://src/menu/main_menu.tscn", "the menu is the startup scene")
	ok(ResourceLoader.exists(scene_path_of_main()), "the original Donjon is still there (the main flag)")
	ok(ResourceLoader.exists(preload("res://src/genre/genre_halls.gd").MENU_SCENE))
	eq(preload("res://src/genre/genre_halls.gd").TITLE_HINT, "ESC: MENU")


func test_the_main_flag_asks_for_the_main_game_and_nothing_else_does():
	var Halls = preload("res://src/genre/genre_halls.gd")
	for yes in ["main", "main mock", "mock main debug", "--main", "?main&nofx", "#main", "floor5 main"]:
		Flags.override = yes
		ok(Halls.wants_main(), "'%s' asks for the main game" % yes)
	for no in ["", "mock", "meet=rock", "--only=ui/main", "domain", "main_menu", "floor5-debug"]:
		Flags.override = no
		ok(not Halls.wants_main(), "'%s' stays in the Genre Halls" % no)
	Flags.override = null


func scene_path_of_main() -> String:
	return preload("res://src/genre/genre_halls.gd").MAIN_SCENE


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


func test_a_spared_monster_can_join_and_shows_in_the_party():
	var joined := false
	for attempt in 40:
		_start("bandit")
		await _pump(800.0)
		var m: Dictionary = scene.G.foe
		m.meters.friendliness = 100.0
		m.meters.anger = 0.0
		m.meters.fear = 0.0
		scene.on_key("3")
		if scene.G.tally.recruited > 0:
			joined = true
			break
		scene.queue_free()
		await _tree().process_frame
	ok(joined, "a friendly bandit joins within a few tries")
	eq(scene.G.allies.size(), 1)
	eq(scene.G.allies[0].species, "bandit")
	ok(scene.G.allies[0].loyalty >= 60.0 and scene.G.allies[0].loyalty <= 80.0)
	ok(scene.last_say.contains("It joins you: KEEN EYE, warnings stay lit longer."), scene.last_say)
	await _draw_frame()
	# the ally's charm shows in the next dodge, and the hints name the other monsters' tastes
	scene.on_key("Enter")
	scene.meet("snake")
	await _pump(800.0)
	scene.start_dodge(1.0)
	await _pump(1500.0)
	for sp in ["slime", "bandit", "snake", "rock", "dragon"]:
		scene.G.foe = _monster(sp)
		ok(scene.hint_for(scene.G.foe).begins_with("..."))


func test_a_monster_diagonal_to_you_is_in_the_view():
	_start()
	scene.G.map = {"grid": [[0, 0, 0, 0, 0], [0, 1, 1, 1, 0], [0, 1, 1, 1, 0], [0, 1, 1, 1, 0], [0, 0, 0, 0, 0]], "n": 5, "stairs": {"x": 3, "y": 3}, "monsters": [_monster("slime")], "palette": scene.G.map.palette, "seed": 1}
	scene.G.map.monsters[0].x = 2
	scene.G.map.monsters[0].y = 2
	scene.G.x = 1
	scene.G.y = 3
	scene.G.dir = 0
	var seen: Array = scene.monsters_in_view()
	eq(seen.size(), 1)
	eq([seen[0].d, seen[0].k], [1, 1])
	await _draw_frame()
	scene.G.dir = 2 # turned away: nothing in view
	await _settle() # (the camera swings round first, and sight is what the camera sees)
	eq(scene.monsters_in_view().size(), 0)


func test_the_text_box_has_an_hp_bar_and_the_automap_steps_aside_in_a_fight():
	_start()
	scene.G.hp = 5
	scene.G.maxHp = 20
	scene.hud()
	ok(scene._hp.text.contains("5/20"), scene._hp.text)
	eq(scene._hp_bar.hp, 5)
	eq(scene._hp_bar.max_hp, 20)
	ok(scene._map_panel.visible, "the map shows while exploring")
	scene.meet("slime")
	ok(not scene._map_panel.visible, "and steps aside in a fight")


func test_spare_turns_gold_when_it_would_work_and_its_tooltip_explains_charms():
	_start("slime")
	await _pump(800.0)
	eq(scene.chance_label(0.001), "<1%")
	eq(scene.chance_label(0.999), ">99%")
	var m: Dictionary = scene.G.foe
	m.meters.friendliness = 100.0
	m.meters.anger = 0.0
	m.meters.fear = 0.0
	scene.main_menu()
	eq(scene.G.menu[2].label, "SPARE")
	ok(scene.G.menu[2].gold, "ready to stop: SPARE is gold")
	ok(scene.G.menu[2].sub.contains("chance to accept") and scene.G.menu[2].sub.contains("not a guarantee"), scene.G.menu[2].sub)
	m.meters.friendliness = 0.0
	m.meters.anger = 100.0
	scene.main_menu()
	ok(not scene.G.menu[2].gold, "not ready: plain")
	ok(scene.G.menu[2].sub.contains("Acceptance is a roll at any odds"), scene.G.menu[2].sub)
	# the help is a tooltip, not text on the button or the log
	ok(not scene._tip.visible)
	scene._on_menu_hover(2, true)
	ok(scene._tip.visible)
	eq(scene._tip_key, "menu2")
	scene._on_menu_hover(2, false)
	ok(not scene._tip.visible)
	# the keys light the highlighted command's tooltip too
	scene.move_sel(1)
	scene.move_sel(1)
	ok(scene._tip.visible, "keyboard: the highlighted SPARE shows its help")
	scene.on_key("1")
	ok(not scene._tip.visible, "a new screen starts without one")
	scene.queue_free()


func test_the_foe_tooltip_holds_the_mind_and_allies_are_chips_with_a_tooltip():
	_start("slime")
	await _pump(800.0)
	scene._show_tip("foe", Rect2(), true)
	ok(scene._tip.visible)
	ok(scene._tip_body.get_child_count() >= 3, "name, feelings and the questions")
	scene._hide_tip()
	eq(scene._chips.get_child_count(), 0)
	scene.G.allies = [{"name": "PIP", "species": "slime", "loyalty": 20.0}]
	scene.render_party()
	eq(scene._chips.get_child_count(), 1)
	ok(scene._chips.get_child(0).warn, "about to leave: red")
	scene._on_chip_hover(true, 0)
	ok(scene._tip.visible)
	scene._on_chip_hover(false, 0)
	ok(not scene._tip.visible)


func test_the_view_keeps_its_size_through_every_mode():
	var win := _tree().root
	var was := win.size
	win.size = Vector2i(1180, 820) # the game's own window: tall enough that the height is what limits the view
	_start()
	await _tree().process_frame
	await _tree().process_frame
	var base: Vector2 = scene._view_rect.size
	ok(base.x > 400.0 and base.y > 250.0, "the view fills the window: %s" % base)
	scene.G.allies = [{"name": "PIP", "species": "bandit", "loyalty": 50.0}]
	scene.render_party()
	scene.meet("slime")
	await _pump(800.0)
	var seen := {"menu": scene._view_rect.size}
	scene.on_key("2") # ACT: more commands, maybe a second row
	await _tree().process_frame
	await _tree().process_frame
	seen["act"] = scene._view_rect.size
	scene.on_key("Enter") # CHECK: a long log
	await _tree().process_frame
	await _tree().process_frame
	seen["log"] = scene._view_rect.size
	scene.on_key("2")
	scene.on_key(str(scene.G.menu.size())) # SAY SOMETHING: the talk box
	await _tree().process_frame
	await _tree().process_frame
	seen["talk"] = scene._view_rect.size
	win.size = was
	for k in seen:
		eq(seen[k], base, "%s: %s vs %s" % [k, seen[k], base])


func test_walking_is_the_3d_set_and_a_fight_is_the_flat_battle_screen():
	_start()
	ok(scene.stage != null, "the 3D set is there")
	await _draw_frame()
	ok(scene.stage.visible, "walking shows it")
	eq(scene.stage._map, scene.G.map, "built from the floor's map")
	var x: int = scene.G.x
	var y: int = scene.G.y
	var spot = scene.stage._goal
	eq([spot.x, spot.y, spot.dir], [x, y, scene.G.dir], "the camera stands where the party does")
	# a monster in view stands in the 3D set: stand next to one, facing it
	var m: Dictionary = scene.G.map.monsters[0]
	for i in 4:
		var d: Array = Render.DIRS[i]
		if scene._open(m.x - d[0], m.y - d[1]):
			scene.G.x = m.x - d[0]
			scene.G.y = m.y - d[1]
			scene.G.dir = i
			break
	await _settle()
	ok(scene.monsters_in_view().any(func(v): return is_same(v.m, m)), "the monster is in view")
	ok(scene.stage._wild.size() >= 1, "and stands in the 3D set")
	scene.start_encounter(m)
	await _draw_frame()
	ok(not scene.stage.visible, "a fight is drawn flat")
	scene.explore()
	await _draw_frame()
	ok(scene.stage.visible, "and the corridor comes back")


func test_the_flat_flag_keeps_the_old_2d_corridor():
	Flags.override = "nosound flat"
	scene = SCENE.instantiate()
	scene.clock_override = 1000.0
	_tree().root.add_child(scene)
	scene.set_process(false)
	scene.on_key("Enter")
	ok(scene.stage == null, "no 3D set with `flat`")
	await _draw_frame()
	eq(scene.G.mode, "explore")


class MusicLog:
	extends RefCounted
	var log: Array = []

	func set_mood(m: String) -> void:
		log.append("mood:" + m)

	func sting(n: String) -> void:
		log.append("sting:" + n)


func test_the_music_follows_the_fight_and_the_stairs():
	var s := _start()
	var m := MusicLog.new()
	s.music = m
	s.meet("slime")
	eq(m.log.back(), "mood:battle")
	s.defeat(s.G.foe, "spared")
	eq(m.log.back(), "sting:victory")
	s.explore()
	eq(m.log.back(), "mood:explore")
	s.ending()
	eq(m.log.back(), "sting:fanfare")


func test_slice_retry_restores_each_encounter_and_player_state():
	_start()
	scene.G.maxHp = 20
	scene.start_personality_slice(7042)
	for encounter in 2:
		var foe: Dictionary = scene.G.foe
		var original: Dictionary = foe.duplicate(true)
		var hp: int = scene.G.hp
		var gold: int = scene.G.gold
		foe.meters.anger = 99.0
		foe.traits = ["changed"]
		foe.hp = 1
		scene.G.gold = 0
		scene.G.hp = 0
		scene.dead()
		scene.retry_fight()
		eq(foe, original, "retry restores the actual foe")
		eq(scene.G.hp, hp)
		eq(scene.G.gold, gold)
		if encounter == 0:
			await _pump(800.0)
			scene.on_key("2")
			scene.on_key("2")
			scene.on_key("Enter")
			eq(scene.G.foe.name, "VEX")


func test_slice_normal_hp_offer_then_flee_and_cleanup():
	_start()
	scene.G.maxHp = 20
	scene.start_personality_slice(7042)
	eq(scene.G.hp, 20)
	await _pump(800.0)
	scene.on_key("2")
	scene.on_key("2")
	eq(scene.G.gold, 6)
	scene.on_key("Enter")
	await _pump(800.0)
	scene.on_key("2")
	scene.on_key("2")
	eq(scene.G.gold, 6)
	await _pump(6300.0)
	print("normal HP offer route after VEX attack: %d HP" % scene.G.hp)
	if scene.G.hp > 0:
		scene.flee()
		eq(scene.G.mode, "explore")
		eq(scene.interaction_roll_override, -1.0)
	else:
		ok(false, "normal HP route died before fleeing")


func test_slice_override_clears_on_restart_and_load():
	_start()
	scene.start_personality_slice(7042)
	var saved: Dictionary = scene.export_state().duplicate(true)
	scene.new_run()
	eq(scene.interaction_roll_override, -1.0)
	ok(scene.slice_next.is_empty())
	scene.start_personality_slice(7042)
	ok(scene.import_state(saved))
	eq(scene.interaction_roll_override, -1.0)
	ok(scene.slice_next.is_empty())
