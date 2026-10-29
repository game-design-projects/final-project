# Fights, driven through key() like a player: the guided first fight (talk, recruit, the slime joins), a fight won
# with attacks and a spell from CHOOSE MOVES, death saves, talking and recruiting through the talk box, gold,
# running away, a vow made and broken, and the party falling.
extends "res://tests/game/helpers.gd"


func _walk_until_fight(max_steps := 600) -> bool:
	var G: Dictionary = game.G
	var d := -1
	for i in 4:
		if Floors.cell(G.map.grid, 1 + Render.DIRS[i][0], 1 + Render.DIRS[i][1]) == 1:
			d = i
			break
	G.dir = d
	for i in max_steps:
		G.graceSteps = 0
		game.key("fwd" if i % 2 == 0 else "back")
		if G.combat != null:
			return true
	fail("no fight in %d steps" % max_steps)
	return false


func test_guided_first_fight():
	make_game({"seed": 21})
	var G: Dictionary = game.G
	ok(await _walk_until_fight(), "walking finds a fight")
	var c: Dictionary = G.combat
	eq(c.guide, "talk", "a new player's first fight is the lesson")
	eq(c.enemies.size(), 1)
	var slime: Dictionary = c.enemies[0]
	eq(slime.species, "slime")
	saw("^IT HASN'T NOTICED YOU YET\\. YOU ACT FIRST\\.$")
	ok(not logged("WHO MOVES FIRST"), "no initiative roll in the lesson")
	eq(G.mode, "combat")
	ok(game.music.moods.has("battle"))
	ok(game.ach.names().has("fight-start"))
	await settle()
	ok(game.tips.current() == "talkFirst" or game.tips.pending().has("talkFirst"), "the lesson's tip is up or next")
	# Only TALK works
	game.key("f")
	eq(game.ui.count("nudge_dock"), 1, "the locked key shakes the dock")
	eq(game.tips.current(), "talkFirst", "and the lesson's tip insists")
	eq(c.guide, "talk")
	ok(not G.busy)
	game.key("t")
	ok(G.input != null, "TALK opens the talk box")
	eq(G.input.label, "WHAT DO YOU SAY?")
	eq(game.tips_context(), "prompt")
	game.close_input("hello friend")
	eq(game.ui.count("close_input"), 1)
	ok(game.voice.cancels >= 1)
	saw('^YOU: "hello friend"$')
	saw("^HOW WELL ROLF SAYS IT \\(CHARISMA\\): ROLLED \\d+ \\+4 = \\d+\\. [A-Z -]+ DELIVERY: WORDS LAND X[0-9.]+\\.$", "the best talker speaks")
	eq(c.guide, "recruit", "the lesson moves on to recruiting")
	ok(c.spoken.has("slime"))
	ok(c.history.has('The party said: "hello friend"'))
	await settle()
	var turn: Array = sent("/api/group-turn")
	eq(turn.size(), 1)
	var body: Dictionary = turn[0].body
	eq(body.guided, true)
	eq(body.playerAction.type, "talk")
	eq(body.playerAction.message, "hello friend")
	eq(body.round, 1)
	eq(body.events[0], "The party just came face to face with you in a dungeon corridor. You froze, and they haven't attacked.")
	eq(body.monsters[0].id, slime.id)
	eq(c.conversation[0], {"speaker": "Party", "text": "hello friend"})
	if G.prompt == null:
		# Asked: the invitation is a sure yes
		game.key("t")
		eq(game.ui.count("nudge_dock"), 2, "TALK waits now")
		game.key("r")
		ok(G.input != null)
		eq(G.input.label, "ASK %s TO JOIN YOU. ADD WORDS, OR JUST PRESS ENTER:" % slime.name.to_upper())
		game.ui.text = ""
		game.key("enter")
		saw("^YOU ASK %s TO JOIN YOUR PARTY\\.$" % slime.name.to_upper())
		saw("^PERSUASION \\(ROLF\\): ROLLED .*, NEEDED \\d+\\. (AN IRRESISTIBLE PITCH!|A CONVINCING PITCH\\.|BEGINNER'S LUCK: IT LANDS ANYWAY\\.)$")
		await settle()
		eq(sent("/api/group-turn")[-1].body.playerAction.type, "recruit")
		eq(sent("/api/group-turn")[-1].body.playerAction.pitch, "success" if not logged("IRRESISTIBLE") else "great")
	ok(G.prompt != null, "it asks to join")
	eq(G.prompt.text, "%s WANTS TO JOIN. ACCEPT?" % slime.name.to_upper())
	eq(G.prompt.no, null, "in the lesson yes is the only answer")
	game.key("n")
	game.key("escape")
	ok(G.prompt != null, "N and Esc only shake it")
	eq(game.ui.count("nudge_modal"), 2)
	game.key("y")
	await settle()
	saw("^%s JOINS THE PARTY! \\+\\d+ EXPERIENCE FOR WINNING IT OVER\\.$" % slime.name.to_upper())
	eq(G.party.size(), 4)
	var ally: Dictionary = G.party[3]
	eq([ally.kind, ally.species, ally.name, ally.level, ally.cls], ["monster", "slime", slime.name.to_upper(), 1, "SLIME"])
	ok(ally.loyalty >= 0 and ally.loyalty <= 80)
	eq(slime.status, "joined")
	eq(G.combat, null, "the fight is over")
	eq(G.mode, "explore")
	ok(game.music.stings.has("victory"), "a win sounds like one")
	ok(game.ach.names().has("recruit"))
	eq(game.ui.count("reset_vows"), 1)


func test_fight_won_with_attacks_spells_and_death_saves():
	make_game({"tips": false, "seed": 33, "handler": taming("attack")})
	var G: Dictionary = game.G
	for m in G.party:
		m.hp = 100
		m.maxHp = 100
	var hits := []
	game.fx.on("enemy:hit", func(p): hits.append(p.dmg))
	game.debug_meet(["goblin"])
	var c: Dictionary = G.combat
	eq(c.guide, null)
	saw("^(A|AN|A VETERAN|A SHINY) HUGE BROWN GOBLIN APPEARS!")
	saw("^IT IS [A-Z]+, .*\\. ARMOR \\d+\\.$")
	saw("^WHO MOVES FIRST: PARTY ROLLED -?\\d+, MONSTERS -?\\d+\\. (YOU|THEY) ACT FIRST!$")
	var goblin: Dictionary = c.enemies[0]
	goblin.hp = 500
	goblin.maxHp = 500
	await settle()
	ok(not G.busy, "the party's turn")
	# QUICK ATTACK: everyone's usual move
	game.key("f")
	ok(G.busy)
	await settle()
	saw("^HORTENSE ATTACKS [A-Z]+: ROLLED ")
	saw("^ROLF ATTACKS [A-Z]+: ROLLED ")
	saw("^EUGENE CASTS FIRE BOLT!$")
	saw("^FIRE BOLT: ")
	ok(game.dice.pops.size() > 0, "dice tumble on the view")
	ok(game.ach.names().has("attack"))
	ok(c.history.any(func(h): return h.begins_with("The party attacked %s" % goblin.name)))
	ok(sent("/api/group-turn").size() >= 1)
	var fight: Dictionary = sent("/api/group-turn")[-1].body
	eq(fight.playerAction.type, "fight")
	eq(fight.playerAction.targetId, goblin.id)
	ok(fight.party[0].has("didThisRound"), "what HORTENSE did goes to Jev")
	ok(not fight.party[0].has("species"), "humans send no species")
	# CHOOSE MOVES: an attack, a blessing, and a spell that never misses
	var slots_before: int = G.party[2].slots[0]
	game.key("c")
	ok(G.menu != null)
	eq(G.menu.title, "WHAT WILL HORTENSE DO? (1 OF 3)")
	eq(G.menu.who, G.party[0])
	eq(G.menu.options.map(func(o): return o.label), ["ATTACK WITH LONGSWORD", "SECOND WIND", "ACTION SURGE"])
	game.key("back")
	eq(G.menu.sel, 1)
	eq(game.ui.count("render_dock"), 1)
	game.key("fwd")
	game.key("enter")
	eq(G.menu.title, "WHAT WILL ROLF DO? (2 OF 3)")
	var rolf_labels: Array = G.menu.options.map(func(o): return o.label)
	eq(rolf_labels, ["ATTACK WITH MACE", "SACRED FLAME", "CURE WOUNDS", "BLESS", "GUIDING BOLT"])
	eq(G.menu.options[1].cost, 0, "a cantrip is free")
	game.key(str(rolf_labels.find("BLESS") + 1))
	eq(G.menu.title, "WHAT WILL EUGENE DO? (3 OF 3)")
	var eugene_labels: Array = G.menu.options.map(func(o): return o.label)
	eq(eugene_labels, ["ATTACK WITH DAGGER", "FIRE BOLT", "MAGIC MISSILE", "BURNING HANDS", "SLEEP"])
	game.key("pick:%d" % eugene_labels.find("MAGIC MISSILE"))
	ok(G.menu == null and G.busy, "the turn plays out")
	await settle()
	saw("^ROLF CASTS BLESS!$")
	saw("^BLESS: THE PARTY GETS \\+1 TO 4 ON ATTACKS AND SAVES THIS FIGHT\\.$")
	ok(c.blessed)
	saw("^EUGENE CASTS MAGIC MISSILE!$")
	saw("^MAGIC MISSILE: [A-Z]+ TAKES \\d+ \\+ \\d+ \\+ \\d+ = \\d+\\.$")
	eq(G.party[2].slots[0], slots_before - 1, "a first-circle slot is spent")
	eq(G.party[1].slots[0], 1, "ROLF's blessing spent one of his two")
	eq(sent("/api/group-turn")[-1].body.playerAction.type, "cast")
	# Bless is used up for this fight: the next menu leaves it out
	game.key("c")
	game.key("enter")
	ok(not G.menu.options.map(func(o): return o.label).has("BLESS"))
	game.key("escape")
	eq(G.menu, null, "Esc cancels the whole turn")
	ok(not G.busy)
	# ROLF falls and rolls death saves at the start of each turn
	var rolf: Dictionary = G.party[1]
	game.damage(rolf, 999)
	ok(rolf.down)
	eq(rolf.hp, 0)
	eq(rolf.saves, {"s": 0, "f": 0})
	saw("^ROLF FALLS UNCONSCIOUS! HEAL THEM, OR THEY ROLL TO SURVIVE EACH TURN \\(DEATH SAVES\\)\\.$")
	game.key("f")
	await settle()
	saw("^ROLF'S DEATH SAVE: ", "a death save at the start of the party's turn")
	ok(game.ach.names().has("death-save"))
	eq(rolf.saves.s + rolf.saves.f > 0 or not rolf.down, true, "the save counted")
	# Finish it
	var gold_before: int = G.gold
	var xp_before: int = G.party[0].xp + G.party[0].level * 1000
	ok(await win_fight(), "the fight ends")
	eq(G.combat, null)
	eq(goblin.status, "dead", "the goblin is slain")
	saw("^%s IS SLAIN! \\+\\d+ EXPERIENCE, \\+\\d+ GOLD\\.$" % goblin.name.to_upper())
	ok(G.gold > gold_before)
	ok(G.party[0].xp + G.party[0].level * 1000 > xp_before, "experience")
	ok(game.music.stings.has("victory"))
	if not rolf.dead:
		eq(rolf.down, false, "the fallen come to after the fight")
		ok(rolf.hp >= 1)
	ok(not hits.is_empty(), "every hit told the presentation")
	ok(game.hurt_until.has(goblin.id))
	ok(game.floaters.size() > 0)


func test_death_saves_fail_and_die():
	make_game({"tips": false})
	var eugene: Dictionary = game.G.party[2]
	game.damage(eugene, 999)
	ok(eugene.down)
	eugene.saves.f = 1
	game.damage(eugene, 3)
	eq(eugene.saves.f, 2)
	saw("^EUGENE IS HIT WHILE DOWN \\(2 OF 3 FAILURES\\)\\.$")
	game.damage(eugene, 3, {"crit": true})
	ok(eugene.dead)
	saw("^EUGENE DIES\\.$")
	eq(eugene.saves.f, 4)
	saw("\\(3 OF 3 FAILURES\\)")


func test_phoenix_cheats_death():
	make_game({"tips": false})
	var hortense: Dictionary = game.G.party[0]
	hortense.phoenix = true
	game.damage(hortense, 999)
	ok(not hortense.down)
	eq(hortense.hp, 6)
	eq(hortense.phoenix, false)
	saw("^HORTENSE FALLS\\.\\.\\. AND RISES AGAIN IN A BURST OF PHOENIX FIRE!$")


func test_talk_and_recruit_through_the_talk_box():
	make_game({"tips": false, "seed": 44, "handler": taming("converse")})
	var G: Dictionary = game.G
	game.debug_meet(["goblin", "slime"])
	var c: Dictionary = G.combat
	eq(c.enemies.size(), 2)
	await settle()
	ok(not G.busy)
	game.key("2")
	eq(c.target, c.enemies[1].id, "2 aims at the second monster")
	var slime: Dictionary = c.enemies[1]
	game.key("t")
	eq(G.input.label, "WHAT DO YOU SAY? (ALL OF THEM HEAR)")
	game.key("q")
	eq(game.ui.count("focus_input"), 1, "a stray key points back at the box")
	game.ui.text = "  hello friend  "
	game.key("enter")
	saw('^YOU: "hello friend"$', "the words are trimmed")
	ok(c.spoken.has("goblin") and c.spoken.has("slime"), "everyone heard it")
	await settle()
	var talk: Dictionary = sent("/api/group-turn")[-1].body
	eq(talk.playerAction.message, "hello friend")
	ok(talk.playerAction.delivery >= 0.5 and talk.playerAction.delivery <= 2)
	eq(talk.monsters.size(), 2)
	ok(c.conversation.any(func(l): return l.speaker == "Party" and l.text == "hello friend"))
	ok(c.conversation.any(func(l): return l.speaker == slime.name), "its answer is part of the conversation")
	ok(c.lastLines.has(slime.id))
	saw("^%s: " % slime.name.to_upper())
	ok(game.narrator.said.size() >= 2, "the monsters' lines are read aloud (if voices are on)")
	# A cancelled invitation does nothing; then one with words
	game.key("r")
	game.key("escape")
	eq(G.input, null)
	ok(not G.busy)
	game.key("r")
	game.close_input("come with us, little one")
	saw('^YOU, TO %s: "come with us, little one"$' % slime.name.to_upper())
	saw("^PERSUASION \\(ROLF\\): ")
	ok(c.history.any(func(h): return h == 'The party asked %s to join them, saying: "come with us, little one".' % slime.name))
	await settle()
	var ask: Dictionary = sent("/api/group-turn")[-1].body.playerAction
	eq([ask.type, ask.targetId, ask.message], ["recruit", slime.id, "come with us, little one"])
	ok(["great", "success", "close", "fail", "botch"].has(ask.pitch))
	# Now it says yes (Jev's answer, pinned here), and the party says yes back
	game.api_handler = func(path: String, body: Dictionary, o: Dictionary) -> Dictionary:
		var res: Dictionary = await JevApi.handle(path, body, o)
		if path == "/api/group-turn":
			for r in res.body.results:
				r.action = "join_party" if r.id == slime.id else "converse"
				r.join = null
		requests.append({"path": path, "body": body, "reply": res})
		return res
	game.key("t")
	game.close_input("please")
	await settle()
	ok(G.prompt != null)
	eq(G.prompt.text, "%s WANTS TO JOIN. ACCEPT?" % slime.name.to_upper())
	eq([G.prompt.yes, G.prompt.no], ["WELCOME IT", "TURN IT AWAY"])
	game.key("enter")
	await settle()
	eq(slime.status, "joined")
	var ally: Dictionary = G.party[-1]
	eq(ally.species, "slime")
	eq(ally.loyalty, mini(80, 50 + J.round_js((slime.meters.friendliness - 55) / 2.0)))
	ok(G.combat != null, "the goblin is still here")
	ok(c.recruits.has(ally.id))
	# The goblin asks too, and is turned away
	game.api_handler = func(path: String, body: Dictionary, o: Dictionary) -> Dictionary:
		var res: Dictionary = await JevApi.handle(path, body, o)
		if path == "/api/group-turn":
			for r in res.body.results:
				r.action = "join_party"
				r.join = null
		return res
	game.key("t")
	game.close_input("you too?")
	await settle()
	ok(G.prompt != null)
	game.key("n")
	await settle()
	saw("^YOU TURN [A-Z]+ AWAY\\. IT WANDERS OFF\\.$")
	eq(c.enemies[0].status, "left")
	eq(G.combat, null, "nobody is left: the fight is won")


func test_give_gold_and_run_away():
	make_game({"tips": false, "seed": 55, "handler": taming("defend")})
	var G: Dictionary = game.G
	game.debug_hostile("bandit")
	var bandit: Dictionary = G.combat.enemies[0]
	await settle()
	game.key("g")
	eq(G.input.label, "GIVE %s HOW MUCH GOLD? (HAVE 30)" % bandit.name.to_upper())
	eq(G.input.numeric, true)
	eq(game.ui.calls.open_input[-1][1], true, "a number box")
	game.close_input("12.9")
	saw("^YOU OFFER %s 12 GOLD\\.$" % bandit.name.to_upper())
	await settle()
	eq(sent("/api/group-turn")[0].body.monsters[0].meters, {"friendliness": 0, "anger": 60, "fear": 0}, "a hostile one")
	var give: Dictionary = sent("/api/group-turn")[-1].body.playerAction
	eq([give.type, give.gold], ["give", 12])
	eq(G.gold, 30, "offering isn't paying: it takes it only if it accepts")
	ok(bandit.cond.has("dodging") or bandit.cond.is_empty(), "it defended (dodging wears off as the round ends)")
	game.key("g")
	game.close_input("lots")
	await settle()
	eq(sent("/api/group-turn").filter(func(r): return r.body.playerAction.type == "give").size(), 1, "not a number: nothing given")
	# Run until it works
	for i in 20:
		if G.combat == null:
			break
		await settle()
		game.key("e")
		await settle()
	eq(G.combat, null, "the party got away")
	saw("^ESCAPE: ROLLED .*, NEEDED 10\\. YOU FLEE!$")
	ok(game.sfx.played.has("flee"))
	eq(bandit.status, "here", "it is still alive and well")
	ok(not game.music.stings.has("victory"), "running away is not a win")


func test_vow_made_and_broken():
	make_game({"tips": false, "seed": 66, "handler": taming("defend")})
	var G: Dictionary = game.G
	game.debug_ally("slime", "Glop")
	var glop: Dictionary = G.party[3]
	game.key("v")
	ok(G.menu != null, "one ally: straight to the vow")
	eq(G.menu.title, "I...")
	game.key("2")
	eq(G.menu.title, "I WON'T...")
	eq(G.menu.options.map(func(o): return o.label), ["KILL", "TALK TO", "GIVE GOLD TO", "RUN FROM", "BEFRIEND"])
	game.key("1")
	eq(G.menu.title, "I WON'T KILL...")
	game.key("1")
	await settle()
	eq(G.vows.size(), 1)
	var vow: Dictionary = G.vows[0]
	eq([vow.text, vow.will, vow.verb, vow.target, vow.toId, vow.toName, vow.status, vow.floor], ["I WON'T KILL SLIMES", false, "kill", "slime", glop.id, "GLOP", "active", 1])
	saw('^YOU SWEAR TO GLOP: "I WON\'T KILL SLIMES"$')
	saw("^GLOP: ")
	eq(sent("/api/vow")[0].body, {"monster": {"species": "slime", "name": "GLOP", "traits": glop.traits}, "vow": {"text": "i won't kill slimes"}})
	eq(glop.vowFloor, 1)
	eq(game.ui.calls.show_jev[-1][0].kind, "vow")
	game.key("v")
	await settle()
	eq(lines()[-1], "YOU'VE ALREADY SWORN TO GLOP ON THIS FLOOR.")
	# Kill a slime: the vow breaks
	game.debug_meet(["slime"])
	var victim: Dictionary = G.combat.enemies[0]
	ok(await win_fight(), "the fight ends")
	await settle()
	eq(victim.status, "dead")
	eq(vow.status, "broken")
	match_re(vow.brokenHow, "^The party killed %s, an orange slime(, whose last words were \".*\")?\\.$" % victim.name)
	saw('^YOU BROKE YOUR VOW: "I WON\'T KILL SLIMES"$')
	ok(game.sfx.played.has("slash"))
	var broken: Array = sent("/api/vow-broken")
	eq(broken.size(), 1)
	eq(broken[0].body.vow, {"text": "i won't kill slimes"})
	eq(broken[0].body.how, vow.brokenHow)
	var r: Dictionary = broken[0].reply.body
	ok(game.ach.names().has("vow-broken"))
	match r.response:
		"forgive":
			saw("^GLOP STAYS\\. FOR NOW\\.$")
			ok(G.party.has(glop))
		"leave_party":
			saw("^GLOP LEAVES THE PARTY\\.$")
			ok(index_of_party(glop) < 0)
		"steal_gold":
			ok(logged("^GLOP RUNS OFF WITH \\d+ GOLD!$") or logged("^GLOP TRIES TO STEAL YOUR GOLD"))
		"attack_party":
			ok(index_of_party(glop) < 0, "it left the party to fight it")
			saw("^GLOP TURNS ON YOU!$")
	var after: Array = sent("/api/ally-reactions")
	if after.is_empty() or not after[0].body.allies.any(func(a): return a.id == glop.id):
		eq(glop.loyalty, r.loyalty, "the broken vow set its loyalty")
	else:
		eq(after[0].body.allies.filter(func(a): return a.id == glop.id)[0].loyalty, r.loyalty, "it judged the fight with the loyalty the broken vow left")


func index_of_party(m) -> int:
	return Game.index_of(game.G.party, m)


func test_vow_in_a_fight_is_sworn_to_the_monster():
	make_game({"tips": false, "seed": 67, "handler": taming("defend")})
	var G: Dictionary = game.G
	game.debug_meet(["goblin"])
	var goblin: Dictionary = G.combat.enemies[0]
	await settle()
	game.key("v")
	game.key("1")
	game.key("4")
	game.key("pick:6")
	await settle()
	eq(G.vows[0].text, "I WILL RUN FROM ANYONE")
	eq(G.vows[0].toId, goblin.id)
	ok(G.combat.vowed)
	ok(G.combat.history.has('The party swore to %s: "i will run from anyone".' % goblin.name))
	ok(goblin.impressions.has('The party swore to you: "i will run from anyone".'))
	game.key("v")
	eq(lines()[-1], "YOU'VE ALREADY SWORN SOMETHING IN THIS FIGHT.")
	goblin.hp = 500
	# Attacking breaks "I WILL RUN": the monster it was sworn to saw it
	game.key("f")
	await settle()
	eq(G.vows[0].status, "broken")
	saw("^%s SAW THAT\\.$" % goblin.name.to_upper())
	eq(sent("/api/vow-broken").size(), 0, "a monster in the fight just remembers")


func test_the_party_falls():
	make_game({"tips": false, "seed": 77, "handler": taming("attack")})
	var G: Dictionary = game.G
	game.debug_hostile("goblin")
	await settle()
	for m in G.party:
		game.damage(m, 999)
	game.key("f")
	await settle()
	eq(G.mode, "over")
	eq(G.combat, null)
	saw("^YOUR PARTY HAS PERISHED ON FLOOR 1\\.$")
	eq(lines()[-1], "DEEPEST FLOOR EVER REACHED: 1. PRESS ENTER FOR A NEW RUN.")
	ok(game.ach.names().has("wipe"))
	eq(game.tips_context(), "off")
	game.key("f")
	eq(game.ui.count("nudge_dock"), 1, "only Enter works")
	game.key("enter")
	ok(not is_same(G, game.G), "a new run")
	eq(game.G.mode, "explore")
	eq(game.G.party.size(), 3)
	eq(game.G.gold, 30)
	eq(game.G.floor, 1)


## The lesson's second step for sure: Jev is pinned to not ask to join after the talk
func test_guided_first_fight_recruit_step():
	var hold := func(path: String, body: Dictionary, o: Dictionary) -> Dictionary:
		var res: Dictionary = await JevApi.handle(path, body, o)
		if path == "/api/group-turn" and body.playerAction.type == "talk":
			for r in res.body.results:
				r.action = "converse"
				r.join = null
		return res
	make_game({"seed": 22, "handler": hold})
	var G: Dictionary = game.G
	ok(await _walk_until_fight(), "walking finds a fight")
	var c: Dictionary = G.combat
	eq(c.guide, "talk")
	var slime: Dictionary = c.enemies[0]
	await settle()
	game.key("t")
	game.close_input("hi there")
	await settle()
	eq(G.prompt, null, "it hasn't asked yet")
	eq(c.guide, "recruit")
	ok(not G.busy)
	game.key("t")
	eq(game.ui.count("nudge_dock"), 1, "TALK waits now")
	eq(game.tips.current(), "recruitNow")
	game.key("r")
	eq(G.input.label, "ASK %s TO JOIN YOU. ADD WORDS, OR JUST PRESS ENTER:" % slime.name.to_upper())
	game.ui.text = ""
	game.key("enter")
	saw("^YOU ASK %s TO JOIN YOUR PARTY\\.$" % slime.name.to_upper())
	saw("^PERSUASION \\(ROLF\\): ROLLED .*, NEEDED \\d+\\. (AN IRRESISTIBLE PITCH!|A CONVINCING PITCH\\.|BEGINNER'S LUCK: IT LANDS ANYWAY\\.)$", "the first invitation always lands")
	ok(c.history.has("The party asked %s to join them." % slime.name))
	await settle()
	var ask: Dictionary = sent("/api/group-turn")[-1].body
	eq(ask.playerAction.type, "recruit")
	ok(["success", "great"].has(ask.playerAction.pitch))
	eq(ask.playerAction.message, null)
	eq(ask.guided, true)
	ok(G.prompt != null, "the guided invitation is a sure yes")
	eq(G.prompt.no, null)
	game.key("y")
	await settle()
	eq(G.party.size(), 4)
	eq(G.party[3].species, "slime")
	eq(G.combat, null)
