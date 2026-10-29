# Every spell, skill and monster move once, so each branch of the combat rules runs: the log line it writes and
# what it changes.
extends "res://tests/game/helpers.gd"

const Dnd = preload("res://src/rules/dnd.gd")


## A fight at floor 7 (every spell known) against three sturdy monsters, on the party's turn
func _fight(handler := Callable()) -> Dictionary:
	make_game({"tips": false, "flags": "#floor7", "seed": 101, "handler": handler if handler.is_valid() else taming("defend")})
	var G: Dictionary = game.G
	var group := [game.make_enemy("goblin"), game.make_enemy("bandit"), game.make_enemy("snake")]
	for e in group:
		e.hp = 900
		e.maxHp = 900
	game.encounter(group)
	await settle()
	return G


func test_every_spell():
	var G: Dictionary = await _fight()
	ok(G.combat != null and not G.busy)
	var rolf: Dictionary = G.party[1]
	var eugene: Dictionary = G.party[2]
	eq(eugene.level, 7)
	eq(eugene.maxSlots.size(), 3)
	for m in [rolf, eugene]:
		m.bonusSlots = [9, 9, 9]
		Game.refresh_slots(m, true)
	var hortense: Dictionary = G.party[0]
	hortense.hp = 1
	for key in ["fire_bolt", "magic_missile", "burning_hands", "sleep", "scorching_ray", "hold_monster", "fireball"]:
		var note: String = await game.cast_spell(eugene, key)
		var s: Dictionary = Dnd.SPELLS[key]
		saw("^EUGENE CASTS %s!$" % s.name)
		saw("^%s: " % s.name, key)
		ok(note != "", "%s says what it did" % key)
		ok(game.sfx.played.has(s.sfx))
	ok(G.combat.enemies.any(func(e): return e.cond.has("held") or e.cond.has("asleep")) or logged("RESISTS|NO ONE IS WEAK ENOUGH"), "sleep or hold took (or was resisted)")
	var before: int = hortense.hp
	await game.cast_spell(rolf, "cure_wounds", hortense)
	ok(hortense.hp > before, "CURE WOUNDS heals")
	saw("^CURE WOUNDS: HORTENSE \\+\\d+\\.$")
	await game.cast_spell(rolf, "prayer_of_healing")
	saw("^PRAYER OF HEALING: HORTENSE \\+\\d+ · ROLF \\+\\d+ · EUGENE \\+\\d+\\.$")
	await game.cast_spell(rolf, "bless")
	ok(G.combat.blessed)
	await game.cast_spell(rolf, "sacred_flame")
	await game.cast_spell(rolf, "guiding_bolt")
	await game.cast_spell(rolf, "spirit_guardians")
	saw("^SPIRIT GUARDIANS: .+ (IS HIT|DODGES HALF) \\(ROLLED \\d+, NEEDED \\d+\\): \\d+ DAMAGE")
	eugene.dead = true
	eugene.hp = 0
	var note: String = await game.cast_spell(rolf, "revivify", eugene)
	eq(note, "brought EUGENE back from the dead")
	ok(not eugene.dead)
	ok(G.combat.history.has("EUGENE was brought back from the dead."))
	eq(rolf.slots, [13 - 3, 12 - 1, 12 - 2], "each leveled spell spent a slot of its circle")


func test_skills_and_a_downed_member_back_up():
	var G: Dictionary = await _fight()
	var hortense: Dictionary = G.party[0]
	hortense.hp = 5
	var did: String = await game.act({"m": hortense, "act": "second_wind"})
	ok(did.begins_with("caught a second wind, then "))
	saw("^HORTENSE CATCHES A SECOND WIND!$")
	eq(hortense.uses.second_wind, 0)
	ok(hortense.hp > 5)
	did = await game.act({"m": hortense, "act": "action_surge"})
	saw("^HORTENSE SURGES INTO ACTION!$")
	eq(hortense.uses.action_surge, 0)
	# Fighters at level 5+ swing twice; a surge doubles that to four: a summary line
	saw("^HORTENSE STRIKES \\d+ TIMES: \\d+ HIT( \\(\\d+ CRITICAL\\))? FOR \\d+ DAMAGE\\.$")
	# Knocked down: loses the turn getting up
	hortense.cond.prone = 1
	eq(Game.default_plan(hortense).act, "prone")
	did = await game.act(Game.default_plan(hortense))
	eq(did, "got back up after being knocked down")
	ok(not hortense.cond.has("prone"))
	# Healing a downed member gets them up
	var rolf: Dictionary = G.party[1]
	game.damage(rolf, 999)
	game.heal(rolf, 4)
	ok(not rolf.down)
	eq(rolf.hp, 4)
	saw("^ROLF GETS BACK UP!$")


func test_ally_specials_and_sulks():
	var G: Dictionary = await _fight()
	game.debug_ally("dragon", "Ember")
	var ember: Dictionary = G.party[-1]
	ember.cooldown = 0
	var seen_special := false
	for i in 30:
		ember.cooldown = 0
		var did: String = await game.ally_turn(ember)
		if did.begins_with("used its special attack on "):
			seen_special = true
			break
	ok(seen_special, "a dragon breathes fire every so often")
	saw("^EMBER USES ITS SPECIAL: .+! .+ (IS HIT|DODGES HALF) \\(ROLLED \\d+, NEEDED \\d+\\): \\d+ DAMAGE")
	eq(ember.cooldown, 3)
	ember.mood = {"id": "SULKING", "desc": "sulks"}
	eq(await game.ally_turn(ember), "sulked and refused to fight")
	saw("^EMBER SULKS AND SITS THIS FIGHT OUT\\.$")
	# Its own kind: it won't
	game.debug_ally("goblin", "Snik")
	var snik: Dictionary = G.party[-1]
	G.combat.target = G.combat.enemies[0].id
	eq(await game.weapon_attacks(snik, 1), "refused to fight %s, one of its own kind" % G.combat.enemies[0].name)
	saw("^SNIK WON'T ATTACK ITS OWN KIND\\.$")


func _one_move(action: String, tweak := Callable()) -> Dictionary:
	var move := func(path: String, body: Dictionary, o: Dictionary) -> Dictionary:
		var res: Dictionary = await JevApi.handle(path, body, o)
		if path == "/api/group-turn" and res.status == 200:
			for r in res.body.results:
				r.action = "converse"
				r.join = null
				r.emotion = null
			var r0: Dictionary = res.body.results[0]
			r0.action = action
			if tweak.is_valid():
				tweak.call(r0, body)
		return res
	return await _fight(move)


func test_monster_special_with_a_condition():
	var G: Dictionary = await _one_move("special", func(r, body): r.targetId = "h0")
	game.key("t")
	game.close_input("hi")
	await settle()
	var goblin: Dictionary = G.combat.enemies[0] if G.combat != null else {}
	saw("^%s'S SPECIAL! ROLL \\d+\\+ ON STRENGTH TO TAKE HALF AND NOT BE KNOCKED DOWN\\.$" % goblin.get("name", "").to_upper())
	saw("^HORTENSE (MAKES IT|FAILS) \\(ROLLED \\d+\\): \\d+ DAMAGE")
	eq(goblin.cooldown, goblin.recharge, "the special recharges")


func test_monster_turns_on_another():
	var G: Dictionary = await _one_move("attack_monster", func(r, body): r.monsterTargetId = body.monsters[1].id)
	game.key("t")
	game.close_input("fight each other")
	await settle()
	var a: Dictionary = G.combat.enemies[0]
	var b: Dictionary = G.combat.enemies[1]
	saw("^%s TURNS ON %s: ROLLED .* VS ARMOR \\d+\\. (MISS!|\\d+ DAMAGE!)$" % [a.name.to_upper(), b.name.to_upper()])
	ok(b.grudges.has(a.id))
	ok(G.combat.history.has("%s attacked %s." % [a.name, b.name]))
	ok(game.ach.names().has("mutiny"))


func test_monster_takes_gold():
	var G: Dictionary = await _one_move("accept_tribute", func(r, body): r.offer = 7)
	var gold: int = G.gold
	game.key("g")
	game.close_input("7")
	await settle()
	var a: Dictionary = G.combat.enemies[0]
	saw("^%s TAKES 7 GOLD\\.$" % a.name.to_upper())
	eq(G.gold, gold - 7)
	ok(a.paid)
	ok(game.ach.names().has("paid"))


func test_monster_demands_refuses_defends():
	var G: Dictionary = await _one_move("demand_tribute")
	game.key("t")
	game.close_input("well?")
	await settle()
	ok(G.combat.enemies[0].demanded)
	game.queue_free()
	game = null
	G = await _one_move("refuse_tribute")
	game.key("g")
	game.close_input("3")
	await settle()
	ok(G.combat.history.has("%s refused the party's gold." % G.combat.enemies[0].name))
	game.queue_free()
	game = null
	G = await _one_move("defend")
	game.key("t")
	game.close_input("hold")
	await settle()
	ok(game.floaters.any(func(f): return f.text == "DODGING"))


func test_monster_leaves_in_peace():
	var G: Dictionary = await _one_move("leave_peacefully")
	game.key("t")
	game.close_input("go in peace")
	await settle()
	var a: Dictionary = G.combat.enemies[0] if G.combat != null else {}
	saw("^.+ LETS YOU PASS\\. \\+\\d+ EXPERIENCE FOR A PEACEFUL END\\.$")
	ok(game.ach.names().has("peace"))


func test_feelings_have_teeth():
	var G: Dictionary = await _fight()
	var e: Dictionary = G.combat.enemies[0]
	var gold: int = G.gold
	game.show_emotion(e, {"id": "terrified", "label": "TERRIFIED", "tone": "fear", "cond": "frightened", "rounds": 2})
	eq(e.cond.frightened, 2)
	ok(G.gold > gold)
	saw("^%s DROPS \\d+ GOLD IN ITS PANIC!$" % e.name.to_upper())
	ok(game.floaters.any(func(f): return f.text == "TERRIFIED!"))
	ok(game.sfx.played.has("fear"))
	game.end_monster_round()
	eq(e.cond.frightened, 1, "conditions tick down after the monsters act")
	e.cond.held = 1
	game.end_monster_round()
	ok(e.cond.has("held"), "held stays until it saves")
	ok(not e.cond.has("frightened"))


func test_the_monsters_hesitate_when_jev_is_unreachable():
	var down := func(path: String, body: Dictionary, o: Dictionary) -> Dictionary:
		if path == "/api/group-turn":
			return {"status": 500, "body": {"error": "Server error"}}
		return await JevApi.handle(path, body, o)
	var G: Dictionary = await _fight(down)
	game.key("t")
	game.close_input("anyone?")
	await settle()
	saw("^\\(JEV UNREACHABLE: Server error\\. THE MONSTERS HESITATE\\.\\)$")
	ok(G.combat != null and not G.busy, "back to the party's turn")
