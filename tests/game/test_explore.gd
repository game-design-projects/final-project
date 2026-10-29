# The run outside fights: the opening log, walking and turning (walls, the view's step/turn/bump events), gold,
# camping (and Revivify), the stairs with the Roll of Fate, a test run on floor 5, and the debug switches.
extends "res://tests/game/helpers.gd"


func test_opening_log_and_state():
	make_game()
	var G: Dictionary = game.G
	eq(G.mode, "explore")
	eq(G.floor, 1)
	eq(G.gold, 30)
	eq(G.party.map(func(m): return m.name), ["HORTENSE", "ROLF", "EUGENE"])
	eq(G.party.map(func(m): return m.cls), ["FIGHTR", "CLERIC", "WIZARD"])
	eq(G.party[0].hp, 12, "fighter: d10 + CON 2")
	eq(G.party[0].uses, {"second_wind": 1, "action_surge": 1})
	eq(G.party[2].slots, [2], "a level 1 wizard has two first-circle slots")
	eq(G.party[2].maxSlots, [2])
	eq(G.map.n, 15, "floor 1 is 15x15")
	eq([G.x, G.y], [1, 1])
	eq(Floors.cell(G.map.grid, G.x + Render.DIRS[G.dir][0], G.y + Render.DIRS[G.dir][1]), 1, "you start facing an open cell")
	ok(G.seen.size() > 0, "what you see is on the map")
	eq(G.visited, {16: true})
	eq(lines().slice(0, 4), [
		"You descend into the Donjon. The monsters here listen, if you talk to them.",
		"HORTENSE IS A FIGHTER, ROLF A CLERIC WHO HEALS, EUGENE A WIZARD. EVERY SWING, SPELL AND PLEA IS A DICE ROLL.",
		"FIND THE STAIRS ON EACH FLOOR. EVERY FLOOR YOU CLEAR EARNS A ROLL OF FATE.",
		"FLOOR 1 IS QUIET: SMALL HALLS, LONE SLIMES AND GOBLINS. A GOOD PLACE TO LEARN THE DICE.",
	])
	eq(G.log[0].cls, "dim")
	eq(game.tips.current(), "move", "the first tip says how to move")
	eq(game.store.get_item("hallsOfJev.deepest"), "1")
	eq(game.ui.count("start_audio"), 1)
	ok(game.music.started, "the music starts")
	ok(game.ui.count("render") > 0)
	ok(not game.DEBUG, "debug is off without the flag")


func test_tips_off_says_how_to_move():
	make_game({"tips": false})
	saw("^MOVE WITH THE ARROW KEYS OR WASD")
	eq(game.tips.current(), null)


func test_jev_warning_shows_without_a_key():
	make_game({"jev": {"flags_text": "", "env": {}, "json_text": "", "dotenv_text": "", "exported": true, "latency": 0}})
	saw("^NO JEV KEY FOUND .*JEV IS MOCKED", "the run starts by saying Jev is mocked")
	var line = game.G.log.filter(func(l): return l.text.begins_with("NO JEV KEY"))[0]
	eq(line.cls, "warn")


func test_walls_turns_and_steps():
	make_game()
	var G: Dictionary = game.G
	G.graceSteps = 999 # no fights on this walk
	var events := []
	for name in ["view:step", "view:turn", "view:bump"]:
		game.fx.on(name, func(p): events.append([name, p.get("dir")]))
	# North of the start is the outer wall
	G.dir = 0
	game.key("fwd")
	eq([G.x, G.y], [1, 1], "a wall stops you")
	eq(lines()[-1], "OUCH! A WALL.")
	eq(events, [["view:bump", null]])
	ok(game.sfx.played.has("bump"))
	events.clear()
	game.key("turnR")
	eq(G.dir, 1)
	game.key("turnL")
	game.key("turnL")
	eq(G.dir, 3)
	eq(events, [["view:turn", 1], ["view:turn", -1], ["view:turn", -1]])
	events.clear()
	# Face an open cell and walk into it, with gold on it
	var d := -1
	for i in 4:
		if Floors.cell(G.map.grid, 1 + Render.DIRS[i][0], 1 + Render.DIRS[i][1]) == 1:
			d = i
			break
	G.dir = d
	var nx: int = 1 + Render.DIRS[d][0]
	var ny: int = 1 + Render.DIRS[d][1]
	G.map.gold[ny * G.map.n + nx] = true
	var gold_before: int = G.gold
	game.key("fwd")
	eq([G.x, G.y], [nx, ny], "a step forward")
	eq(events, [["view:step", 1]])
	ok(G.visited.has(ny * G.map.n + nx))
	ok(G.gold - gold_before >= 3 and G.gold - gold_before <= 10, "3-10 gold on floor 1")
	saw("^YOU FIND \\d+ GOLD\\.$")
	ok(not G.map.gold.has(ny * G.map.n + nx), "the gold is picked up")
	events.clear()
	game.key("back")
	eq([G.x, G.y], [1, 1], "a step back")
	eq(G.dir, d, "stepping back keeps your facing")
	eq(events, [["view:step", -1]])
	eq(G.graceSteps, 997)
	# A key that does nothing here still renders (and nudges the tip)
	var renders: int = game.ui.count("render")
	game.key("x")
	eq(game.ui.count("render"), renders + 1)
	game.key("m")
	eq(game.ui.count("toggle_map"), 1)


func test_boons_list_and_settings():
	make_game()
	game.key("b")
	eq(lines()[-1], "NO BOONS YET. CLEAR A FLOOR AND ROLL FOR ONE.")
	game.key("o")
	eq(lines()[-1], "SOUND EFFECTS OFF.")
	game.key("o")
	eq(lines()[-1], "SOUND EFFECTS ON.")
	game.key("h")
	eq(lines()[-1], "TIPS OFF. PRESS H TO START THEM OVER.")
	ok(not game.tips.on())
	game.key("p")
	await frame()
	ok(not game.music.on)
	ok(game.ui.count("render_bar") >= 1)
	game.key("j")
	eq(game.ui.count("toggle_jev"), 0, "J is debug only")
	game.key("k")
	ok(game.ach.is_open(), "K opens the achievements")
	game.key("fwd")
	eq([game.G.x, game.G.y], [1, 1], "the achievements list takes every key")
	game.key("escape")
	ok(not game.ach.is_open())


func test_talking_to_allies_needs_one():
	make_game()
	game.key("e")
	eq(lines()[-1], "YOU HAVE NO MONSTER ALLIES YET.")
	game.key("v")
	eq(lines()[-1], "YOU HAVE NO MONSTER ALLIES YET.")


func test_camp_heals_and_refills():
	make_game({"seed": 3})
	var G: Dictionary = game.G
	for m in G.party:
		m.hp = 1
		m.cond = {"poisoned": 2}
	G.party[2].slots = [0]
	G.party[0].uses = {"second_wind": 0, "action_surge": 0}
	game.key("c")
	await settle()
	eq(G.party.map(func(m): return m.hp), [7, 6, 5], "half of max health, rounded up, comes back")
	eq(G.party[0].cond, {})
	eq(G.party[2].slots, [2])
	eq(G.party[0].uses, {"second_wind": 1, "action_surge": 1})
	saw("^THE PARTY RESTS\\. WOUNDS CLOSE; SPELL SLOTS AND SKILLS RETURN\\.$")
	ok(game.sfx.played.has("heal"))
	if logged("SOMETHING FINDS YOUR CAMP"):
		ok(G.combat != null or G.mode == "over" or logged("IS SLAIN|FLEES|LETS YOU PASS|JOINS"), "something found the camp")


func test_camp_revivify_at_level_five():
	make_game({"flags": "#floor5", "seed": 11})
	var G: Dictionary = game.G
	var rolf: Dictionary = G.party[1]
	eq(rolf.level, 5)
	ok(rolf.slots.size() >= 3 and rolf.slots[2] > 0, "a level 5 cleric has a third-circle slot")
	var eugene: Dictionary = G.party[2]
	eugene.dead = true
	eugene.hp = 0
	var third: int = rolf.slots[2]
	game.key("c")
	await settle()
	ok(G.prompt != null, "the cleric offers Revivify")
	eq(G.prompt.text, "ROLF CAN CAST REVIVIFY ON EUGENE (USES A THIRD-CIRCLE SPELL SLOT). DO IT?")
	eq(G.prompt.yes, "REVIVE")
	game.key("y")
	await settle()
	ok(not eugene.dead, "EUGENE lives")
	eq(eugene.hp, 1)
	eq(rolf.slots[2], third - 1)
	saw("^EUGENE GASPS BACK TO LIFE WITH 1 HEALTH!$")


func test_stairs_roll_of_fate_and_floor_two():
	make_game({"seed": 5})
	var G: Dictionary = game.G
	G.graceSteps = 999
	var st: Dictionary = G.map.stairs
	var nb := neighbor_of(st.x, st.y)
	ok(not nb.is_empty(), "the stairs have an open neighbor")
	G.x = nb[0]
	G.y = nb[1]
	G.dir = nb[2]
	game.key("fwd")
	ok(G.prompt != null, "the stairs ask")
	eq(G.prompt.text, "STAIRS DOWN TO FLOOR 2. DESCEND?")
	eq([G.prompt.yes, G.prompt.no, G.prompt.walkAway], ["DESCEND", "STAY", true])
	game.key("q")
	eq(game.ui.count("nudge_modal"), 1, "another key shakes the question")
	# Walking away answers no and moves
	game.key("turnL")
	eq(G.prompt, null)
	eq(G.dir, (nb[2] + 3) % 4)
	game.key("turnR")
	game.key("back")
	game.key("fwd")
	ok(G.prompt != null)
	game.key("y")
	ok(G.roll != null, "the Roll of Fate spins")
	ok(G.busy)
	eq(game.tips_context(), "roll")
	ok(game.music.stings.has("fanfare"))
	await until(func(): return G.waitKey != null)
	ok(G.roll.landed)
	eq(G.boons.size(), 1)
	var boon: Dictionary = G.boons[0]
	eq([boon.floor, boon.great, boon.kind], [1, false, "floor"])
	saw("^ROLL OF FATE: %s! " % boon.name)
	game.key("z")
	await settle()
	eq(G.roll, null)
	eq(G.floor, 2)
	eq(G.map.n, 17)
	eq([G.x, G.y], [1, 1])
	eq(G.graceSteps, 4)
	saw("^YOU DESCEND TO FLOOR 2: THE [A-Z ]+\\. THE MONSTERS HERE ARE TOUGHER\\.$")
	saw("^NEW: MONSTERS NOW ROAM IN PAIRS")
	eq(game.store.get_item("hallsOfJev.deepest"), "2")
	ok(game.ach.names().has("descend"))
	game.key("b")
	saw("^FLOOR 1: %s: " % boon.name)


func test_test_run_floor_five_with_its_champion():
	make_game({"flags": "#floor5", "seed": 9, "handler": taming("attack")})
	var G: Dictionary = game.G
	eq(G.floor, 5)
	eq(G.party.map(func(m): return m.level), [5, 5, 5])
	eq(G.boons.size(), 4)
	eq(G.gold, 210)
	eq(G.party.map(func(m): return m.hp == m.maxHp), [true, true, true], "rested")
	eq(lines()[0], "TEST RUN: STARTING ON FLOOR 5 WITH A LEVEL 5 PARTY, 4 BOONS AND 210 GOLD.")
	eq(G.log[0].cls, "big")
	saw("^FLOOR 4: ")
	saw("^A RED CHAMPION WAITS AT THE HEART OF THIS FLOOR")
	ok(G.map.boss != null, "floor 5 has a champion")
	eq([G.map.boss.x, G.map.boss.y], [11, 11], "in the middle of the 23x23 floor")
	ok(G.party[0].mods.critMin <= 20)
	ok(not logged("REACHES LEVEL"), "the level-ups happen off the log")
	# Walk onto the champion
	var nb := neighbor_of(G.map.boss.x, G.map.boss.y)
	G.x = nb[0]
	G.y = nb[1]
	G.dir = nb[2]
	game.key("fwd")
	ok(G.combat != null and G.combat.boss, "a boss fight")
	saw("^THE AIR TURNS RED\\. [A-Z]+ THE RED RISES TO MEET YOU\\.$")
	saw("^[A-Z]+ THE RED, CHAMPION OF FLOOR 5! \\d+ HEALTH, ARMOR \\d+, TWO ATTACKS A TURN\\.$")
	var boss: Dictionary = G.combat.enemies[0]
	eq([boss.boss, boss.legendary, boss.multiattack, boss.recharge], [true, 2, 2, 2])
	ok(game.sfx.played.has("boss"))
	await win_fight()
	await until(func(): return G.waitKey != null or G.mode == "over")
	if G.mode == "over":
		fail("the party fell to the champion")
		return
	saw("^THE CHAMPION IS OVERCOME\\. FATE OWES YOU A GREAT ROLL\\.$")
	ok(G.roll.great)
	game.key("enter")
	await settle()
	ok(G.map.boss.defeated)
	eq(G.boons.size(), 5)
	ok(G.boons[4].great, "a great roll")
	saw("^GREAT ROLL OF FATE: ")


func test_debug_mode_records_requests():
	make_game({"flags": "debug", "seed": 4})
	ok(game.DEBUG, "the debug flag turns debug mode on")
	game.debug_ally("goblin", "Grak")
	eq(game.G.party[3].name, "GRAK")
	game.key("e")
	ok(game.G.input != null, "one ally: the talk box opens at once")
	eq(game.ui.calls.open_input[-1], ["SAY TO GRAK:", false])
	game.close_input("you fight well")
	await settle()
	saw('^YOU, TO GRAK: "you fight well"$')
	saw("^GRAK: ")
	saw("^\\[DEBUG\\] LANDED \\d\\.\\d/4, LOYALTY [+-]\\d+ → \\d+ \\(")
	eq(game.G.party[3].talkedFloor, 1)
	eq(game.api_log.size(), 1)
	var e: Dictionary = game.api_log[0]
	eq([e.n, e.path, e.status], [1, "/api/ally-talk", 200])
	ok(e.jev is Array and e.jev.size() == 1, "the raw Jev call is traced")
	ok(not e.response.has("_debug"))
	eq(e.request.message, "you fight well")
	ok(game.ui.count("render_requests") >= 2)
	eq(game.ui.calls.show_jev[-1][0].kind, "talk")
	game.key("e")
	await settle()
	eq(lines()[-1], "GRAK HAS SAID ALL IT WANTS TO SAY ON THIS FLOOR.")
	game.key("j")
	eq(game.ui.count("toggle_jev"), 1)


func test_store_debug_and_nodebug():
	make_game({"store": {"donjon.debug": "1"}})
	ok(game.DEBUG, "localStorage donjon.debug = 1")
	game.queue_free()
	game = null
	make_game({"store": {"donjon.debug": "1"}, "flags": "nodebug"})
	ok(not game.DEBUG, "nodebug wins")
