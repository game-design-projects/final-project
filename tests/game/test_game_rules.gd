# The game's own rules as units: floors, levels, monsters and champions, boons, buffs from ally talk, the menu's
# keys, ally reactions (a traitor comes back to fight), shiny and boss rolls, and the vow ledger's checks.
extends "res://tests/game/helpers.gd"

const Species = preload("res://src/rules/species.gd")


func test_floor_rules_and_generation():
	eq(Floors.floor_rules(1).size, 15)
	eq(Floors.floor_rules(6).size, 25)
	eq(Floors.floor_rules(7).size, 25, "capped")
	eq(Floors.floor_rules(1).maxGroup, 1)
	eq(Floors.floor_rules(2).maxGroup, 2)
	eq(Floors.floor_rules(9).maxGroup, 3)
	eq(Floors.floor_rules(3).conditions, true)
	eq(Floors.floor_rules(5).elite, 0.0)
	near(Floors.floor_rules(8).elite, 0.2)
	near(Floors.floor_rules(20).elite, 0.4)
	near(Floors.floor_rules(4).encounter, 0.1)
	eq(Floors.floor_rules(10).boss, true)
	eq(Floors.floor_rules(4).pool.keys(), ["slime", "goblin", "bandit", "snake", "rock", "dragon"])
	seed(3)
	for f in [1, 2, 5, 10]:
		var map := Floors.gen_floor(f)
		var n: int = map.n
		eq(n, Floors.floor_rules(f).size)
		eq(map.grid[1][1], 1, "the start is open")
		for i in n:
			ok(map.grid[0][i] == 0 and map.grid[n - 1][i] == 0 and map.grid[i][0] == 0 and map.grid[i][n - 1] == 0, "walled in")
		eq(Floors.cell(map.grid, map.stairs.x, map.stairs.y), 1)
		eq(map.gold.size(), 4 + floori(n / 6.0))
		ok(not map.gold.has(n + 1), "no gold on the start")
		ok(not map.gold.has(map.stairs.y * n + map.stairs.x), "no gold on the stairs")
		# Stairs: farthest reachable cell outside the boss hall
		var dist := _bfs(map)
		var far := 0
		var c := floori(n / 2.0)
		for k in dist:
			var x: int = k % n
			var y: int = k / n
			if map.boss == null or absi(x - c) > 2 or absi(y - c) > 2:
				far = maxi(far, dist[k])
		eq(dist[map.stairs.y * n + map.stairs.x], far, "the stairs are as far as it gets")
		for k in map.gold:
			ok(dist.has(k), "gold lies where you can reach it")
		if f % 5 == 0:
			ok(map.boss != null)
			eq([map.boss.x, map.boss.y, map.boss.defeated, map.boss.enemy], [c, c, false, null])
			for yy in range(c - 2, c + 3):
				for xx in range(c - 2, c + 3):
					eq(map.grid[yy][xx], 1, "the champion's hall is open")
			ok(Floors.floor_rules(f).pool.has(map.boss.species))
		else:
			eq(map.boss, null)


func _bfs(map: Dictionary) -> Dictionary:
	var n: int = map.n
	var dist := {n + 1: 0}
	var q := [[1, 1]]
	while not q.is_empty():
		var at: Array = q.pop_front()
		for d in Render.DIRS:
			var x: int = at[0] + d[0]
			var y: int = at[1] + d[1]
			if Floors.cell(map.grid, x, y) == 1 and not dist.has(y * n + x):
				dist[y * n + x] = dist[at[1] * n + at[0]] + 1
				q.append([x, y])
	return dist


func test_levels_and_experience():
	make_game({"tips": false})
	eq(Game.xp_for(1), 30)
	eq(Game.xp_for(2), 91)
	eq(Game.xp_for(4), 276)
	var G: Dictionary = game.G
	var hortense: Dictionary = G.party[0]
	game.grant_xp(30)
	eq(hortense.level, 2)
	eq(hortense.xp, 0)
	eq(hortense.maxHp, 12 + 5 + 1 + 2, "half the hit die + 1 + CON")
	saw("^HORTENSE REACHES LEVEL 2!$")
	saw("^EUGENE REACHES LEVEL 2!$")
	eq(G.party[2].maxSlots, [3])
	eq(G.party[2].slots, [3], "the new slot comes in full")
	game.grant_xp(91)
	saw("^EUGENE REACHES LEVEL 3! LEARNS SCORCHING RAY, HOLD MONSTER\\.$")
	saw("^ROLF REACHES LEVEL 3! LEARNS PRAYER OF HEALING\\.$")
	eq(G.party[2].maxSlots, [4, 2])
	eq(G.party[2].slots, [4, 2])
	G.party[2].slots = [1, 0]
	game.grant_xp(Game.xp_for(3))
	eq(G.party[2].maxSlots, [4, 3])
	eq(G.party[2].slots, [1, 1], "a level-up adds only the new slots")
	game.grant_xp(Game.xp_for(4))
	saw("^HORTENSE REACHES LEVEL 5! EXTRA ATTACK: SWINGS TWICE A TURN\\. TRAINING BONUS \\+3 TO ATTACKS, SPELLS AND TALKING\\.$")
	saw("^EUGENE REACHES LEVEL 5! LEARNS FIREBALL\\. FREE SPELLS NOW ROLL 2 DICE OF DAMAGE\\. TRAINING BONUS \\+3 TO ATTACKS, SPELLS AND TALKING\\.$")
	eq(G.party[2].maxSlots, [4, 3, 2])
	eq(Game.attack_count(hortense), 2)
	ok(game.sfx.played.has("levelup"))
	# Monster allies grow too
	game.debug_ally("slime", "Glop")
	var glop: Dictionary = G.party[3]
	eq(glop.dmg, [1, 3])
	game.grant_xp(30)
	eq(glop.level, 2)
	eq(glop.maxHp, 10 + 4)
	eq(glop.dmg, [2, 4])
	eq(G.log[-1].color, "#ff8a1f", "an ally's level-up line is in its color")


func test_monsters_scale_with_depth():
	make_game({"tips": false, "seed": 12})
	var G: Dictionary = game.G
	var e: Dictionary = game.make_enemy("goblin")
	eq(e.species, "goblin")
	ok(Species.SPECIES.goblin.names.has(e.name))
	eq(e.ac, 12 + (1 if e.shiny else 0))
	eq(e.meters, {"friendliness": 20, "anger": 10, "fear": 5}, "a goblin's starting mood")
	ok(e.traits.size() >= 2)
	eq([e.legendary, e.multiattack, e.recharge, e.cooldown, e.paid, e.demanded, e.formerAlly], [0, 1, 3, 0, false, false, false])
	eq(e.impressions, [])
	G.floor = 9
	var deep: Dictionary = game.make_enemy("rock")
	eq(deep.ac, 17 + 2 + (1 if deep.shiny else 0))
	eq(deep.hit, 5 + 2 + (2 if deep.elite else 0) + (1 if deep.shiny else 0))
	eq(deep.dc, 13 + 4 + (1 if deep.shiny else 0))
	# Kin: one of its own kind in your party warms it
	game.debug_ally("rock", "Pebble")
	var kin: Dictionary = game.make_enemy("rock")
	eq(kin.impressions, ["One of your own kind travels with this party."])
	eq(kin.meters.friendliness, 30 + 15, "kin warms it")
	# The champion
	var boss: Dictionary = game.make_boss("goblin")
	ok(boss.name.ends_with(" the Red"))
	eq([boss.boss, boss.shiny, boss.elite, boss.legendary, boss.multiattack, boss.recharge], [true, false, false, 2, 2, 2])
	eq(boss.traits[-1], "the towering red champion of this floor, far stronger than others of its kind")
	ok(not boss.traits.any(func(t): return "shiny" in t or "veteran" in t))
	eq(boss.meters, {"friendliness": 5, "anger": 20, "fear": 0}, "a champion starts colder and angrier")
	eq(Game.color_of(boss), "#ff2a2a")
	# A shiny glitters gold
	var shiny: Dictionary = {}
	for i in 200:
		shiny = game.make_enemy("slime")
		if shiny.shiny:
			break
	ok(shiny.shiny)
	eq(Game.color_of(shiny), "#f5b72a")
	ok(shiny.traits.has("a rare shiny gold one of its kind, and proud of it"))


func test_groups_never_hold_two_dragons():
	make_game({"tips": false, "seed": 13})
	game.G.floor = 9
	for i in 60:
		var group: Array = game.make_group()
		ok(group.size() >= 1 and group.size() <= 3)
		eq(group.filter(func(e): return e.species == "dragon").size() <= 1, true)
		var names: Array = group.map(func(e): return e.name)
		for nm in names:
			eq(names.count(nm), 1, "no two of a group share a name")


func test_enemy_from_a_former_ally():
	make_game({"tips": false})
	game.debug_ally("snake", "Hiss")
	var ally: Dictionary = game.G.party[3]
	ally.hp = 0
	var foe: Dictionary = game.enemy_from_ally(ally, "You turned on them.")
	eq([foe.name, foe.species, foe.hp, foe.maxHp, foe.formerAlly, foe.paid, foe.impressions], ["HISS", "snake", 1, ally.maxHp, true, true, ["You turned on them."]])
	eq(foe.meters, {"friendliness": 10, "anger": 75, "fear": 5})
	eq(foe.hit, 2 + 2)


func test_boons():
	make_game({"tips": false, "seed": 17})
	var G: Dictionary = game.G
	var h: Dictionary = G.party[0]
	eq(game._boon_whetstone(h, 1), "HORTENSE DEALS +12% DAMAGE (NOW X1.12)")
	eq(game._boon_keen_eye(h, 1), "HORTENSE NOW SCORES CRITICAL HITS ON A 19-20 (CRITICAL HITS ROLL DOUBLE DAMAGE DICE)")
	eq(game._boon_true_aim(h, 3), "HORTENSE GETS +2 TO HIT (NOW +2 FROM BOONS)")
	eq(game._boon_flurry(h, 1), "HORTENSE NOW STRIKES 2 TIMES EVERY TURN")
	eq(game._boon_flurry(h, 1), "HORTENSE NOW STRIKES 3 TIMES EVERY TURN")
	eq(game._boon_iron_skin(h, 1), "HORTENSE'S ARMOR RISES BY 1 TO 17. MONSTERS MISS IT MORE")
	eq(game._boon_vampiric(h, 2), "HORTENSE HEALS 16% OF THE DAMAGE IT DEALS")
	var e: Dictionary = G.party[2]
	eq(game._boon_arcane_surge(e, 3), "EUGENE GETS MORE SPELL SLOTS (NOW 4) AND SPELLS HIT X1.60")
	eq(e.bonusSlots, [2, 1, 0])
	eq(game._boon_vigor(game.living(), 2), "THE WHOLE PARTY GAINS +4 MAX HEALTH")
	eq(G.party[1].maxHp, 14)
	eq(game._boon_golden_touch(null, 2), "ALL GOLD FROM MONSTERS IS NOW X1.30")
	G.party[1].dead = true
	eq(game._boon_phoenix(null, 1), "THE FALLEN RISE AT FULL HEALTH, AND EVERYONE WILL CHEAT DEATH ONCE")
	ok(not G.party[1].dead and G.party[1].hp == 14 and G.party[0].phoenix)
	eq(game._boon_twin_soul(h, 1), "HORTENSE NOW STRIKES 6 TIMES EVERY TURN")
	eq(game._boon_archmage(e, 1), "EUGENE GAINS 2 SPELL SLOTS OF EVERY CIRCLE (NOW 6) AND SPELLS HIT X2.40")
	# Who a boon can go to
	var flurry = game.BOONS.filter(func(b): return b.name == "FLURRY")[0]
	eq(game.targets_for(flurry).map(func(m): return m.name), ["HORTENSE", "ROLF"], "not the wizard")
	var surge = game.BOONS.filter(func(b): return b.name == "ARCANE SURGE")[0]
	eq(game.targets_for(surge).map(func(m): return m.name), ["ROLF", "EUGENE"], "casters only")
	# Drawing one: applied and listed
	var before: int = G.boons.size()
	var drawn: Dictionary = game.draw_boon(3)
	eq(G.boons.size(), before + 1)
	eq(G.boons[-1], {"name": drawn.boon.name, "text": drawn.text, "floor": 3, "great": false, "kind": "floor"})
	ok(game.index_of(game.BOONS, drawn.boon) >= 0)
	var great: Dictionary = game.draw_boon(5, true)
	ok(G.boons[-1].great)
	eq(game.boon_title(h).split(" · ")[0], "LEVEL 1")
	match_re(game.boon_title(h), "STRIKES \\d TIMES A TURN")
	ok(game.boon_title(h).contains("STRENGTH +3 DEXTERITY +1 CONSTITUTION +2 INTELLIGENCE +0 WISDOM +1 CHARISMA +0"))
	ok(great.boon != null)


func test_menu_keys():
	make_game({"tips": false})
	var G: Dictionary = game.G
	var picked := []
	var options := []
	for i in 10:
		options.append({"label": "OPTION %d" % i, "value": i})
	var run := func():
		picked.append(await game.choose("PICK ONE", options))
	run.call()
	eq(G.menu.title, "PICK ONE")
	eq(game.tips_context(), "prompt")
	game.key("turnR")
	eq(G.menu.sel, 5, "right jumps a column of 5")
	game.key("turnR")
	eq(G.menu.sel, 5, "no column further right")
	eq(game.ui.count("nudge_dock"), 1)
	game.key("back")
	eq(G.menu.sel, 6)
	game.key("fwd")
	game.key("fwd")
	eq(G.menu.sel, 4)
	game.key("q")
	eq(game.ui.count("nudge_dock"), 2, "a key the menu doesn't take shakes the dock")
	game.key("0")
	eq(picked, [9], "0 is the tenth")
	eq(G.menu, null)
	run.call()
	game.key("3")
	eq(picked, [9, 2])
	run.call()
	game.key("pick:7")
	run.call()
	game.key("enter")
	run.call()
	game.key("escape")
	eq(picked, [9, 2, 7, 0, null])


func test_ally_buffs_open_the_next_fight():
	make_game({"tips": false, "seed": 81, "handler": taming("defend")})
	var G: Dictionary = game.G
	game.debug_ally("dragon", "Ember")
	game.debug_ally("rock", "Boulder")
	var ember: Dictionary = G.party[3]
	var boulder: Dictionary = G.party[4]
	ember.buff = {"id": "STORMING", "desc": "crackling"}
	boulder.buff = {"id": "BULWARK", "desc": "planted"}
	var group := [game.make_enemy("goblin"), game.make_enemy("bandit")]
	for e in group:
		e.hp = 500
		e.maxHp = 500
	game.encounter(group)
	saw("^EMBER OPENS WITH A STORM OF LIGHTNING!$")
	var re := RegEx.create_from_string("^[A-Z ]+ TAKES \\d+\\.$")
	eq(lines().filter(func(t): return re.search(t) != null).size(), 2, "the storm hits every foe")
	eq(group.map(func(e): return e.hp < 500), [true, true])
	saw("^BOULDER PLANTS ITSELF IN FRONT OF THE PARTY LIKE A WALL\\.$")
	eq(ember.buff, null, "spent")
	eq(boulder.buff, null)
	eq(G.combat.soaks, 2)
	ok(is_same(G.combat.bouncy, boulder))
	# A blow aimed at the party is soaked
	var goblin = game.present()[0] if not game.present().is_empty() else null
	if goblin != null:
		ok(game.soak(G.party[0], "HEAD."))
		saw("^HEAD\\. BOULDER TAKES THE BLOW ON ITS STONE HIDE FOR HORTENSE!$")
		eq(G.combat.soaks, 1)


func test_ally_reactions_and_a_traitor():
	var reacting := func(path: String, body: Dictionary, o: Dictionary) -> Dictionary:
		var res: Dictionary = await JevApi.handle(path, body, o)
		if path == "/api/group-turn":
			for r in res.body.results:
				r.action = "flee"
				r.join = null
		if path == "/api/ally-reactions":
			for x in res.body.reactions:
				x.decision = "turn_on_party"
		return res
	make_game({"tips": false, "seed": 91, "handler": reacting})
	var G: Dictionary = game.G
	game.debug_ally("goblin", "Snik")
	var snik: Dictionary = G.party[3]
	game.debug_meet(["bandit"])
	var bandit: Dictionary = G.combat.enemies[0]
	await settle()
	if G.combat != null and is_same(G.combat.enemies[0], bandit):
		game.key("t")
		game.close_input("go away")
	if not await until(func(): return G.combat != null and G.combat.enemies.any(func(e): return e.formerAlly)):
		return
	var reacted: Array = sent("/api/ally-reactions")
	eq(reacted.size(), 1, "allies judged the fight")
	eq(reacted[0].body.allies[0].id, snik.id)
	ok(reacted[0].body.events.size() >= 2)
	ok(index_of_party(snik) < 0, "it left the party")
	var foe: Dictionary = G.combat.enemies[0]
	eq([foe.name, foe.formerAlly], ["SNIK", true])
	saw("^SNIK TURNS ON YOU!$")
	ok(game.ach.names().has("ally-decision"))


func index_of_party(m) -> int:
	return Game.index_of(game.G.party, m)


func test_a_shiny_recruit_earns_a_roll():
	make_game({"tips": false, "seed": 95, "handler": taming("join_party")})
	var G: Dictionary = game.G
	game.debug_shiny("slime")
	var shiny: Dictionary = G.combat.enemies[0]
	ok(shiny.shiny)
	eq(shiny.meters.friendliness, 90)
	saw("^A SHINY ORANGE SLIME APPEARS! IT GLITTERS GOLD!$")
	await settle()
	if G.prompt == null:
		game.key("t")
		game.close_input("shiny friend")
		await settle()
	ok(G.prompt != null, "it asks to join")
	game.key("y")
	saw("^A SHINY JOINED YOU! FATE OWES YOU A ROLL AFTER THIS FIGHT\\.$")
	await until(func(): return G.waitKey != null)
	eq(G.roll.kind, "shiny")
	saw("^SHINY ROLL OF FATE: ")
	game.key("enter")
	await settle()
	eq(G.boons[-1].kind, "shiny")
	eq(G.roll, null)


func test_a_champion_that_flees_still_waits():
	make_game({"tips": false, "seed": 96, "handler": taming("flee")})
	var G: Dictionary = game.G
	game.debug_boss()
	ok(G.combat.boss)
	await settle()
	if G.combat != null:
		game.key("t")
		game.close_input("leave")
		await settle()
	eq(G.combat, null)
	saw("^.+ THE RED FLEES\\.$")
	saw("^.+ THE RED STILL HOLDS THE HEART OF THIS FLOOR\\.$")
	ok(not G.map.boss.defeated)
	eq(G.boons.size(), 0, "no great roll")


func test_vow_rules():
	make_game({"tips": false})
	var G: Dictionary = game.G
	G.vows = [
		{"id": "v1", "will": false, "verb": "kill", "target": "slime", "status": "active", "text": "I WON'T KILL SLIMES", "toId": "x"},
		{"id": "v2", "will": true, "verb": "talk", "target": "monsters", "status": "active", "text": "I WILL TALK TO ANYONE", "toId": "x"},
		{"id": "v3", "will": true, "verb": "kill", "target": "goblin", "status": "active", "text": "I WILL KILL GOBLINS", "toId": "x"},
	]
	game.vow_event("kill", "goblin", "x")
	eq(G.vows.map(func(v): return v.status), ["active", "active", "active"], "killing goblins keeps them all")
	game.vow_event("spare", "goblin", "The party let it go.")
	eq(G.vows[2].status, "broken")
	eq([G.vows[2].fresh, G.vows[2].justBroken, G.vows[2].brokenHow], [true, true, "The party let it go."])
	game.vow_event("attack_unspoken", "dragon", "x")
	eq(G.vows[1].status, "broken", "attacking without a word breaks I WILL TALK TO ANYONE")
	game.vow_event("kill", "slime", "x")
	eq(G.vows[0].status, "broken")
	eq(G.pendingBreaks.size(), 3)
	game.vow_event("kill", "slime", "x")
	eq(G.pendingBreaks.size(), 3, "a broken vow breaks once")
	await game.flush_breaks()
	eq(G.pendingBreaks.size(), 0)
	eq(lines().filter(func(t): return t == "...BUT NO ONE IS LEFT TO HOLD YOU TO IT.").size(), 3)
