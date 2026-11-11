extends "res://tools/test_base.gd"

const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Monster = preload("res://src/rules/monster.gd")
const Social = preload("res://src/rules/social.gd")
const State = preload("res://src/game/state.gd")
const Rng = preload("res://src/utils/rng.gd")
const SocialDemo = preload("res://src/game/social_demo.gd")
const Content = preload("res://src/rules/content.gd")
const Network = preload("res://src/network/network.gd")
const JevMind = preload("res://src/mind/jev_mind.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const Words = preload("res://src/mind/words.gd")

func _name() -> String:
	return "social_test"

func _fresh(species := "bandit", traits := ["jumpy"], extra := []) :
	Flags.set_args(PackedStringArray(["nosave", "nosound", "notips", "no-wick"] + extra))
	var flow = Flow.new(Rng.new(7042), LocalMind.new())
	await flow.new_run()
	var s = flow.state
	var m = Monster.given({"species": species, "genre": "bullet", "hp": 80}, s.floor_map.monsters[0].cell, "TEST " + species.to_upper(), traits, {"friendliness": 25.0, "anger": 30.0, "fear": 30.0})
	s.floor_map.monsters[0] = m
	m.mood = {"id": species, "goal": Content.table("moods")[species].goal}
	s.rotate_mini_games = false
	await flow.go("intro", {"foe": m})
	await flow.go("menu")
	return flow

func _popup(flow) -> void:
	flow.state.foe.social.pending = true
	await flow.go("menu")
	_check(flow.state.stage == "social", "pending offer opens only at menu boundary")

func _run() -> void:
	await _without_it()
	await _speech_from_data()
	await _bandits()
	await _slimes()
	await _scheduler()
	await _text()
	await _safe_queue()
	await _offline()
	await _persistence()
	await _other_species()
	await _compatibility()
	await _ui()
	await _demo()
	_finish()

func _bandits() -> void:
	var flow = await _fresh()
	var s = flow.state
	await _popup(flow)
	var before: int = s.gold
	var paid = s.foe
	await flow.press("1")
	_check(s.gold == before - 6 and paid.gone == "spared" and s.stage == "explore", "payment deducts six and ends truce through existing defeat flow")
	_check(paid.social.history.back().choice == "pay", "paid deal remembered")
	flow = await _fresh()
	s = flow.state
	s.gold = 2
	await _popup(flow)
	await flow.press("1")
	_check(s.stage == "social" and s.gold == 2 and not s.foe.social.used, "unaffordable payment stays open without spending action or money")
	await flow.press("2")
	_check(s.stage == "menu" and s.foe.social.opening == 3 and s.foe.social.rounds == 1, "jumpy Bandit bluff yields opening and exactly one held-back turn")
	_check(s.menu[0].sub.contains("OPENING +3"), "combat command reminds player of earned opening")
	var bonus := Social.strike_bonus(s.foe)
	_check(bonus == 3 and Social.strike_bonus(s.foe) == 0, "opening consumed exactly once")
	flow = await _fresh("bandit", ["proud"])
	s = flow.state
	await _popup(flow)
	await flow.press("2")
	_check(s.stage == "wait" and s.foe.social.opening == 0, "same bluff against proud Bandit triggers one stronger attack")
	var wait_pressure: float = flow._stages.wait._pressure
	_check(wait_pressure > flow.mind.pressure(s.foe), "retaliation reaches actual attack windup")
	await flow.tick(flow.clock + 1000)
	await flow.press("confirm")
	_check(s.stage == "dodge" and s.dodge != null, "retaliation enters real dodge once")
	flow = await _fresh()
	s = flow.state
	await _popup(flow)
	await flow.press("3")
	_check(s.stage == "menu" and s.foe.social.opening == 4, "jumpy Bandit challenge gives a larger opening")
	flow = await _fresh("bandit", ["proud"])
	s = flow.state
	await _popup(flow)
	await flow.press("3")
	_check(s.stage == "wait" and s.foe.social.opening == 4, "proud Bandit challenge trades opening for immediate stronger attack")
	flow = await _fresh()
	s = flow.state
	await _popup(flow)
	await flow.press("cancel")
	_check(s.stage == "menu" and s.gold == 8 and s.foe.social.rounds == 0 and s.foe.social.used, "Ignore expires offer without consuming action or gold")
	await flow.go("act")
	await flow.press("cancel")
	_check(s.stage == "menu", "CHECK/back cannot reopen ignored offer")
	flow = await _fresh()
	s = flow.state
	await _popup(flow)
	await flow.press("5")
	_check(s.stage == "menu" and s.foe.social.history.back().choice == "ignore", "mouse/number Ignore follows same expiry path")

func _slimes() -> void:
	var flow = await _fresh("slime", ["shy"])
	var s = flow.state
	await _popup(flow)
	await flow.press("1")
	_check(s.stage == "wait" and s.foe.social.soft_turns == 1, "reassurance changes this actual attack and one subsequent attack")
	flow = await _fresh("slime", ["shy"])
	s = flow.state
	await _popup(flow)
	await flow.press("2")
	_check(s.stage == "menu" and s.foe.social.promise and s.menu[2].gold and s.mind_rows.any(func(row): return row.id == "mercy" and row.answer == 1.0), "promise holds back one turn and exposes mercy opportunity")
	await flow.press("3")
	_check(s.foe.gone == "spared" and s.stage == "ask", "kept promise enables existing recruitment decision")
	flow = await _fresh("slime", ["shy"])
	s = flow.state
	await _popup(flow)
	await flow.press("2")
	await flow.press("1")
	flow.clock = s.bar.t0 + s.bar.dur * 0.5
	await flow.press("confirm")
	_check(s.foe.social.betrayed and not s.foe.social.promise and s.stage == "wait", "actual timed strike breaks promise and cannot pacify retaliation")
	_check(s.foe.social.history.back().choice == "betrayal", "betrayal recorded before combat continues")
	flow = await _fresh("slime", ["shy"])
	s = flow.state
	await _popup(flow)
	await flow.press("3")
	_check(s.stage == "wait" and s.foe.social.opening == 4, "rejection trades a vulnerability for panic attack")

func _scheduler() -> void:
	var flow = await _fresh()
	var s = flow.state
	var a = s.foe
	flow.dice.pin(0.5)
	_check(flow.dice.keyed(1) == 0.5 and flow.dice.keyed(9000) == 0.5, "keyed scheduler draws honour the flow dice pin")
	flow.dice.unpin()
	var b = Monster.from_dict(a.to_dict())
	_check(int(a.social.due) in range(2, 5), "first normal opportunity after two to four resolved turns")
	for i in 12:
		Social.observe(a, s, flow.dice)
		Social.observe(b, s, flow.dice)
		_check(a.social == b.social, "seeded scheduling reproduces opportunity %d" % i)
	Social.ignore(a)
	for i in 30:
		Social.observe(a, s, flow.dice, 1.0)
	_check(not a.social.pending and a.social.history.size() == 1, "at most one offer and no benefit farming")
	flow = await _fresh()
	s = flow.state
	a = s.foe
	a.social.due = 2
	Social.observe(a, s, flow.dice, 0.0)
	_check(not a.social.pending, "no arbitrary first-turn timer popup")
	Social.observe(a, s, flow.dice, 0.0)
	var checked: int = a.social.checked
	Social.observe(a, s, flow.dice, 1.0)
	_check(not a.social.pending and a.social.checked == checked, "failed roll waits configured two-turn cooldown")
	Social.observe(a, s, flow.dice, 1.0)
	_check(a.social.pending, "later plausible opportunity can roll again")
	flow = await _fresh()
	s = flow.state
	a = s.foe
	a.hp = 10
	Social.observe(a, s, flow.dice, 0.0)
	_check(a.social.pending, "important HP change queues urgent opportunity even before normal due turn")
	for stage in ["dodge", "fightbar", "talk", "wait", "intro", "ask", "items", "skills", "explore"]:
		s.stage = stage
		_check(not Social.ready(a, s), "no popup while in " + stage)
	s.stage = "menu"
	_check(Social.ready(a, s), "queued urgent event ready at next safe boundary")
	a.social = {"used": false}
	a.traits = []
	a.mood = {}
	a.hp = a.max_hp
	s.gold = 0
	_check(not Social.eligible(a, s), "Bandit without goal, need, trait or resource has no generic timer event")
	a.mood = {"goal": "earn gold"}
	_check(Social.eligible(a, s), "current mood goal supplies contextual motivation")

func _text() -> void:
	var flow = await _fresh()
	var s = flow.state
	await _popup(flow)
	await flow.press("4")
	await flow.submit_text("You are pretending, I see your bluff")
	_check(s.stage == "social" and not s.social_typing and s.selected == 1 and not s.foe.social.used, "free text previews existing bluff choice without action")
	await flow.press("confirm")
	_check(s.stage == "menu" and s.foe.social.opening == 3, "confirmed custom reply has same bounded outcome")
	flow = await _fresh("slime", ["shy"])
	s = flow.state
	await _popup(flow)
	await flow.press("4")
	await flow.submit_text("I swear I will stay beside you")
	_check(s.selected == 1 and not s.social_typing, "varied promise wording works offline")
	await flow.press("confirm")
	_check(s.foe.social.promise, "custom promise uses real promise rules")
	flow = await _fresh()
	s = flow.state
	await _popup(flow)
	await flow.press("4")
	await flow.submit_text("zxqv 99999 HP")
	_check(s.stage == "social" and s.gold == 8 and s.foe.hp == 80 and not s.foe.social.used, "unmapped free text cannot invent resources")
	await flow.press("cancel")
	_check(not s.social_typing and s.stage == "social", "cancel typing returns to choices without ignoring")

func _persistence() -> void:
	var flow = await _fresh("slime", ["shy"])
	var s = flow.state
	await _popup(flow)
	await flow.press("2")
	Social.hit(s.foe)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var restored = State.from_dict(saved)
	_check(restored != null and restored.floor_map.monsters[0].social.betrayed, "JSON save/load keeps structured promises and betrayals")
	_check(restored.recent_social == "slime", "topic spacing persists through save/load")
	var old: Dictionary = saved.duplicate(true)
	for m in old.floor.monsters:
		m.erase("social")
	old.erase("recentSocial")
	_check(State.from_dict(old).floor_map.monsters[0].social.is_empty(), "old save without social fields still loads")
	saved.floor.monsters[0].social.history = "bad"
	_check(State.from_dict(saved) == null, "invalid social save refused safely")
	await flow.encounter.retry_fight()
	_check(not flow.state.foe.social.used and not flow.state.foe.social.betrayed and flow.state.gold == 8, "retry restores pre-offer resources and memory")
	_check(flow.state.foe.social.rounds == 0, "retry resets schedule deterministically")

func _other_species() -> void:
	var flow = await _fresh("rock", ["patient"])
	var s = flow.state
	s.hp = 10
	s.foe.hp = 60
	await _popup(flow)
	await flow.press("1")
	_check(s.hp == 13 and s.foe.hp == 64 and s.stage == "menu", "Rock rest trades one action for healing both combatants")
	await flow.go("act")
	await flow.press("cancel")
	_check(s.hp == 13, "Rock rest cannot be repeated by revisiting menu")
	flow = await _fresh("rock", ["patient"])
	s = flow.state
	await _popup(flow)
	await flow.press("3")
	_check(s.stage == "wait" and s.foe.social.opening == 5, "Rock exploitation creates actual next-strike bonus and retaliation")
	flow = await _fresh("snake", ["secretive"])
	s = flow.state
	await _popup(flow)
	var gold: int = s.gold
	await flow.press("3")
	_check(s.gold == gold - 2 and s.stage == "wait" and s.lines.any(func(l): return l.text.contains("stairs")), "Snake proof validates payment and reveals actual floor route")
	flow = await _fresh("snake", ["secretive"])
	s = flow.state
	# A spared neighbour standing in the same cell is directly known, rather than an omniscient tally.
	var neighbour = s.floor_map.monsters[1]
	neighbour.cell = s.foe.cell
	neighbour.gone = "spared"
	await _popup(flow)
	_check(s.social_offer.witness, "Snake's evidence comes from a visible spared neighbour")
	await flow.press("2")
	_check(s.lines.any(func(l): return l.text.contains("was a lie")), "Snake catches a lie it can substantiate")
	flow = await _fresh("snake", ["secretive"])
	s = flow.state
	s.floor_map.monsters[1].gone = "spared"
	s.floor_map.monsters[1].cell = s.foe.cell + Vector2i(5, 5)
	await _popup(flow)
	_check(not s.social_offer.witness, "Snake cannot see a distant or hidden act of mercy")
	await flow.press("2")
	_check(s.lines.any(func(l): return l.text.contains("cannot verify")), "unwitnessed lie is not magically detected")
	flow = await _fresh("dragon", ["bored"])
	s = flow.state
	s.foe.boss = true
	await _popup(flow)
	gold = s.gold
	await flow.press("1")
	_check(s.stage == "wait" and s.foe.social.trial == 8 and s.gold == gold, "Dragon trial starts dangerous attack without paying reward upfront")
	await flow.tick(flow.clock + 1000)
	await flow.press("confirm")
	_check(s.stage == "dodge" and s.dodge.genre == "gates", "Dragon challenge overrides rotation with telegraphed WALLS attack")
	await flow.tick(s.dodge.end_t + 1)
	_check(s.stage == "menu" and s.gold == gold + 8 and s.foe.social.opening == 4 and not s.foe.is_gone(), "survived challenge pays once and leaves boss progression intact")
	await flow.tick(flow.clock + 20000)
	_check(s.gold == gold + 8, "idle/menu ticks cannot farm trial reward")
	flow = await _fresh("dragon", ["bored"])
	s = flow.state
	s.foe.hp = 60
	await _popup(flow)
	await flow.press("3")
	_check(s.foe.hp == 66 and s.stage == "menu" and s.foe.social.trial == 0, "flattery costs Dragon recovery rather than free reward")
	flow = await _fresh()
	s = flow.state
	s.foe.boss = true
	await _popup(flow)
	await flow.press("1")
	_check(s.gold == 2 and s.stage == "menu" and not s.foe.is_gone(), "paid truce never bypasses mandatory champion")

func _compatibility() -> void:
	var flow = await _fresh("slime", ["shy"], ["skill-combat"])
	var s = flow.state
	await _popup(flow)
	await flow.press("2")
	_check(s.skill_fight.energy == 2 and not s.skill_fight.turn_over, "social response starts exactly one new skill turn")
	await flow.press("1")
	await flow.press("1")
	_check(s.foe.social.betrayed and s.skill_fight.used == 1, "damage skill breaks promise through same rules as timed strike")
	await flow.press(str(s.menu.size()))
	_check(s.stage == "wait" and s.skill_fight.turn_over, "skills still resolve one enemy attack after betrayal")
	flow = await _fresh("bandit", ["jumpy"], ["no-initiated-dialogue"])
	s = flow.state
	for i in 6:
		await flow.encounter.after_player([], {"pressure": 1.0, "pacified": true})
	_check(s.stage == "menu" and s.social_offer.is_empty(), "explicit feature-off keeps ordinary combat menu")
	await flow.go("act")
	await flow.press(str(s.menu.size()))
	_check(s.stage == "talk", "ordinary TALK remains available")
	await flow.submit_text("Hello friend")
	_check(s.foe.spoke and s.stage in ["wait", "menu"], "ordinary TALK still resolves its own existing action")

func _ui() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "seed=7042", "notips"]))
	var game = load("res://src/gameplay/gameplay.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await game._begin()
	var flow = game.flow
	var s = flow.state
	var m = Monster.given({"species": "bandit", "genre": "chess", "hp": 80}, s.floor_map.monsters[0].cell, "PIP", ["jumpy"], {"friendliness": 20.0, "anger": 20.0, "fear": 40.0})
	s.floor_map.monsters[0] = m
	await flow.exclusive(func(): await flow.go("intro", {"foe": m}))
	await flow.exclusive(func(): await flow.go("menu"))
	await flow.exclusive(func(): await _popup(flow))
	await process_frame
	game._social._process(0.0)
	_check(game._social.visible and game._social._heading.text.contains("STARTED"), "actual gameplay popup visibly attributes monster initiation")
	_check(game._overlay.in_fight() and game._overlay.speech().is_empty(), "battle art remains present without duplicate speech box")
	_check(game._social._buttons.size() == 5 and game._social._buttons[0].visible, "three replies, custom text, and Ignore displayed")
	game._social._buttons[2].mouse_entered.emit()
	_check(s.selected == 2, "mouse hover selects the reply so its tradeoff can be read before committing")
	game._social._buttons[3].pressed.emit()
	await process_frame
	await process_frame
	_check(s.social_typing and game._social._input.visible and game._social._input.has_focus(), "mouse opens focused custom input")
	game._social._input.text = "I call your bluff"
	game._social._send.pressed.emit()
	await process_frame
	_check(not s.social_typing and s.selected == 1 and s.stage == "social", "mouse text preview selects bounded choice without resolving it")
	await flow.tick(flow.clock + 120000)
	_check(s.stage == "social" and s.hp > 0, "two minutes reading does not expire popup or start attack")
	game._social._buttons[1].pressed.emit()
	await process_frame
	_check(s.stage == "menu" and m.social.used, "mouse reply resolves once and returns to correct combat state")
	game.queue_free()
	await process_frame


func _without_it() -> void:
	var flow = await _fresh("bandit", ["jumpy"], ["no-initiated-dialogue"])
	var s = flow.state
	for i in 8:
		await flow.encounter.after_player([], {"pressure": 1.0, "pacified": true})
	_check(not flow.feature("initiated-dialogue"), "no-initiated-dialogue turns the feature off")
	_check(s.stage == "menu" and s.social_offer.is_empty() and s.foe.social.is_empty(), "without it, combat is untouched after eight actions")
	await flow.go("act")
	await flow.press(str(s.menu.size()))
	_check(s.stage == "talk", "without it, TALK is the ordinary one")
	await flow.submit_text("Hello friend")
	_check(s.foe.spoke and s.stage in ["wait", "menu"], "without it, TALK resolves normally")
	# the switch is only at the two places that make social state (intro.gd, encounter.gd): every other use reads that state
	var m = Monster.given({"species": "slime", "genre": "bullet", "hp": 20}, Vector2i.ZERO, "BLANK", ["shy"], {"friendliness": 10.0, "anger": 10.0, "fear": 10.0})
	var gold: int = s.gold
	_check(Social.strike_bonus(m) == 0 and Social.hit(m) == "" and Social.trial_over(m, s) == "" and s.gold == gold, "with no social state a hit gets no bonus, breaks no promise and ends no trial")
	_check(Social.remembered(m) == "" and not Social.promised(m) and not Social.ready(m, s), "remembers nothing, owes no mercy and has nothing to say")
	_check(m.social.is_empty(), "and reading it leaves it empty")
	_check(Social.pressure(m, 1.7) == 1.7 and m.social.get("pressure", 0.0) == 0.0, "an attack keeps its pressure")


## What the monsters say comes from data/social.json, the variants too.
func _speech_from_data() -> void:
	var flow = await _fresh("slime", ["shy"])
	var s = flow.state
	var t: Dictionary = Social.table()
	var m = s.foe
	m.social.promise = true
	_check(Social.remembered(m) == t.lines.remembered_promise, "a promise is remembered in the words of the data")
	var said = flow.encounter.greeting(m)
	_check(said.kind == "say" and said.text == t.lines.remembered_promise, "and said on meeting again (%s)" % said.text)
	m.social.betrayed = true
	_check(Social.remembered(m) == t.lines.remembered_betrayal and not Social.promised(m), "a broken one too, and it owes no mercy")
	_check(str(Social.offer(m, s).speech).begins_with(t.lines.broke_word + " "), "its offer starts by saying so")
	m.social = {}
	m.meters.fear = 60.0
	var scared: Dictionary = Social.offer(m, s)
	_check(scared.goal == t.events.slime.afraid.goal and scared.speech == t.events.slime.afraid.speech, "a frightened slime asks to survive")
	_check(not scared.has("afraid") and not scared.has("warned"), "and the offer carries only what the popup shows")
	m.meters.fear = 10.0
	_check(Social.offer(m, s).speech == t.events.slime.speech, "a calm one asks for company")
	flow = await _fresh("bandit", ["greedy"])
	s = flow.state
	s.foe.heard = {"standing": -20}
	_check(Social.offer(s.foe, s).speech == t.events.bandit.warned, "a bandit whose clan warned it says so")
	s.foe.heard = {}
	_check(Social.offer(s.foe, s).speech == t.events.bandit.speech, "one that heard nothing makes the usual offer")


func _safe_queue() -> void:
	var flow = await _fresh()
	var s = flow.state
	s.foe.hp = 10
	await flow.encounter.after_player([], {"pressure": 1.0, "pacified": false})
	_check(s.stage == "wait" and s.foe.social.pending and s.social_offer.is_empty(), "urgent event queues behind the real attack confirmation")
	await flow.tick(flow.clock + 1000)
	await flow.press("confirm")
	_check(s.stage == "dodge" and s.social_offer.is_empty(), "queued urgent conversation does not interrupt live dodge")
	await flow.tick(flow.clock + 100)
	_check(s.stage == "dodge" and s.foe.social.pending, "active dodge keeps opportunity queued")
	await flow.tick(s.dodge.end_t + 1)
	_check(s.stage == "social" and s.foe.turn == 1, "popup follows completed enemy attack exactly once")
	await flow.press("5")
	_check(s.stage == "menu" and s.foe.turn == 1, "ignoring queued offer does not cause an extra enemy turn")
	flow = await _fresh()
	s = flow.state
	s.foe.social.pending = true
	await flow.press("1")
	_check(s.stage == "fightbar" and s.social_offer.is_empty(), "pending opportunity cannot interrupt timed strike execution")
	await flow.tick(flow.clock + 50)
	_check(s.stage == "fightbar", "timed strike remains active across frames")

func _offline() -> void:
	var flow = await _fresh("slime", ["shy"])
	var s = flow.state
	await _popup(flow)
	var counts := {"n": 0}
	Network.reset()
	Network.transport = func(_url, _body, _headers, _timeout):
		counts.n += 1
		return {"status": 503, "text": "Server not configured"}
	flow.mind = JevMind.new("https://social.invalid", LocalMind.new())
	await flow.press("4")
	await flow.submit_text("zxqv")
	_check(s.stage == "social" and s.social_typing and counts.n == 1 and not s.listening, "unreachable Jev falls back without leaving the dialogue or spending an action")
	await flow.submit_text("zxqv again")
	_check(counts.n == 1 and s.foe.social.words_asked, "unknown rewrites cannot issue unlimited network questions")
	await flow.submit_text("I will not hurt you")
	_check(s.selected == 1 and not s.social_typing, "creative promise wording still previews locally while Jev is down")
	await flow.press("confirm")
	_check(s.stage == "menu" and s.foe.social.promise, "offline fallback commits the same bounded promise")
	Network.transport = Callable()
	Network.reset()


func _finish_attack(flow) -> void:
	if flow.state.stage == "wait":
		await flow.tick(flow.clock + 1000)
		await flow.press("confirm")
	if flow.state.stage == "dodge":
		await flow.tick(flow.state.dodge.end_t + 1)

func _demo() -> void:
	for enabled in [true, false]:
		var args := PackedStringArray(["nosave", "nosound", "notips", "no-wick", "social-demo", "seed=7042"])
		if not enabled:
			args.append("no-initiated-dialogue")
		Flags.set_args(args)
		var flow = Flow.new(Rng.new(7042), LocalMind.new())
		await flow.new_run()
		var counts := {"offers": 0}
		flow.happened.connect(func(name, _data):
			if name == "social_offer": counts.offers += 1)
		await SocialDemo.start(flow)
		_check(not flow.autosave_allowed(), "demo never autosaves its controlled encounters")
		for i in SocialDemo.CAST.size():
			var s = flow.state
			var m = s.foe
			_check(m.name == SocialDemo.CAST[i].name, "demo reaches " + SocialDemo.CAST[i].name)
			await flow.go("menu")
			for action in 2:
				if s.stage != "menu": break
				await flow.press("2") # ACT
				await flow.press("3" if i in [0, 1, 4] else "2") # tricks, bravery or jokes; no paid ordinary ACT truce
				await _finish_attack(flow)
			if enabled:
				_check(s.stage == "social", "demo opportunity appears after real actions for " + m.name)
				await flow.press("2" if i in [2, 3] else ("1" if i == 4 else "3"))
				if i == 0:
					_check(s.stage == "menu", "demo jumpy Bandit hesitates at challenge")
				if i == 1:
					_check(s.stage == "wait", "demo proud Bandit retaliates at the same challenge")
				await _finish_attack(flow)
				if i in [2, 3]:
					await flow.press("3") # SPARE the promised Slime
					if s.stage == "ask": await flow.press("2") # part ways, so party bonuses don't change the demo
			for action in 12:
				if s.foe != m or s.stage == "explore": break
				if s.stage == "menu":
					await flow.press("1")
					flow.clock = s.bar.t0 + s.bar.dur * 0.5
					await flow.press("confirm")
				await _finish_attack(flow)
			_check(m.is_gone(), "demo encounter resolves without stalling: " + m.name)
		_check(counts.offers == (5 if enabled else 0), "demo comparison has five offers enabled and zero when disabled")
