## Checks the features in `Flags.FEATURES` with no window: that each can be switched off, and what each does when it is on.
## Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/features_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Ally = preload("res://src/game/ally.gd")
const Chart = preload("res://src/rules/chart.gd")
const Clans = preload("res://src/rules/clans.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Dance = preload("res://src/rules/minigames/dance.gd")
const Encounter = preload("res://src/game/encounter.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Flags = preload("res://src/utils/flags.gd")
const Floors = preload("res://src/rules/floors.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const DodgeRun = preload("res://src/rules/dodge_run.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const Hints = preload("res://src/rules/hints.gd")
const Flow = preload("res://src/game/flow.gd")
const Gates = preload("res://src/rules/minigames/gates.gd")
const Monster = preload("res://src/rules/monster.gd")
const Overlay = preload("res://src/view/overlay.gd")
const Pace = preload("res://src/rules/pace.gd")
const Practice = preload("res://src/rules/practice.gd")
const ChoicePopup = preload("res://src/view/choice_popup.gd")
const Hud = preload("res://src/view/hud.gd")
const Vignette = preload("res://src/view/vignette.gd")
const Items = preload("res://src/rules/items.gd")
const Kinds = preload("res://src/rules/kinds.gd")
const Lore = preload("res://src/rules/lore.gd")
const JevMind = preload("res://src/mind/jev_mind.gd")
const Keepsakes = preload("res://src/rules/keepsakes.gd")
const KeepsakeStage = preload("res://src/game/stages/keepsake.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const Skills = preload("res://src/rules/skills.gd")
const Social = preload("res://src/rules/social.gd")
const Lords = preload("res://src/rules/lords.gd")
const Requests = preload("res://src/rules/requests.gd")
const Roaming = preload("res://src/rules/roaming.gd")
const Reveal = preload("res://src/rules/reveal.gd")
const State = preload("res://src/game/state.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Vision = preload("res://src/rules/vision.gd")
const TestRoom = preload("res://src/rules/test_room.gd")
const Texts = preload("res://src/game/texts.gd")
const Tips = preload("res://src/view/tips.gd")
const Transitions = preload("res://src/game/transitions.gd")

const BASE := ["nosave", "nosound", "no-wick"] # she has a test of her own; every other check starts alone


func _name() -> String:
	return "features_test"


func _run() -> void:
	_flags()
	await _real_floors()
	await _practice()
	await _practice_wick()
	await _dodges()
	await _recruiting()
	await _story()
	await _tutorial()
	await _mood_cues()
	await _clear_hp()
	await _reveal()
	await _chat()
	await _gate()
	await _branching()
	await _late_decisions()
	await _clans()
	await _hostility()
	await _map_gen()
	await _secrets()
	await _lore()
	await _items()
	await _shop()
	await _lurkers()
	await _npcs()
	await _lords()
	await _roaming()
	await _input_cooldown()
	await _charting()
	await _heavy_strike()
	await _nerve()
	await _mood_attacks()
	await _follow_through()
	await _keepsakes()
	await _skill_combat()
	await _test_room()
	_close_camera()
	_finish()


## A flow on the local rules, with these flags on top of BASE.
func _flow(seed_value: int, words := []) -> Variant:
	_use(words)
	var rng := Rng.new(seed_value)
	return Flow.new(rng, LocalMind.new())


func _use(words := []) -> void:
	var all := PackedStringArray(BASE)
	all.append_array(PackedStringArray(words))
	Flags.set_args(all)


func _flags() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound"])) # without BASE's no-wick
	_check(Flags.FEATURES.keys().all(func(f): return Flags.enabled(f) != Flags.OPT_IN.has(f)), "every feature is on by default, but the opt-in ones")
	_check(Flags.OPT_IN.all(func(f): return Flags.FEATURES.has(f)), "and those are features too")
	for f in Flags.FEATURES:
		if Flags.OPT_IN.has(f):
			_use([f])
			_check(Flags.enabled(f), "naming %s turns it on" % f)
		_use(["no-" + f])
		_check(not Flags.enabled(f), "no-%s turns it off" % f)
		_use([f + "=off"])
		_check(not Flags.enabled(f), "%s=off turns it off" % f)
	_check(not Flags.KNOWN.has("classic"), "there is no switch that turns every feature off at once")
	_use()


## test-room: one hall with every monster there is, each fight its own, and nothing kept.
func _test_room() -> void:
	# who stands in it
	var words := TestRoom.table()
	var room = TestRoom.make(Rng.new(5))
	var plain: Array = room.monsters.filter(func(m): return not m.boss and not m.elite)
	var kinds: Array = plain.map(func(m): return m.kind)
	_check(kinds.size() == Kinds.all().size() and Kinds.all().keys().all(func(id): return kinds.count(id) == 1), "the test room holds one of every kind (%d)" % kinds.size())
	_check(plain.all(func(m): return m.max_hp == roundi(float(Kinds.info(m.kind).hp) * float(Floors.plan(int(Kinds.info(m.kind).depth)).hp_scale))), "each as tough as on its own floor")
	var elites: Array = room.monsters.filter(func(m): return m.elite)
	var clans := {}
	for m in elites:
		clans[m.species] = true
	_check(elites.size() == words.elites.size() and clans.size() == elites.size() and clans.size() == Content.table("encounter").roster.map(func(e): return e.species).reduce(func(seen, sp): return seen if seen.has(sp) else seen + [sp], []).size(), "an elite of every clan (%d)" % elites.size())
	_check(elites.all(func(m): return m.max_hp > roundi(float(Kinds.info(m.kind).hp) * float(Floors.plan(int(Kinds.info(m.kind).depth)).hp_scale))), "tougher than their kind")
	var champions: Array = room.monsters.filter(func(m): return m.boss)
	var named: Array = Content.table("floors").champions
	_check(champions.size() == Floors.run_floors() and range(champions.size()).all(func(i): return champions[i].name == str(named[i].name) and champions[i].max_hp == int(named[i].hp) and champions[i].genres == Kinds.genres_at(i + 1) and TestRoom.depth_of(champions[i]) == i + 1), "and every champion, with its floor's attacks")
	_check(room.monsters.size() == TestRoom.count(), "that is everyone (%d)" % room.monsters.size())
	var names := {}
	var cells := {}
	for m in room.monsters:
		names[m.name] = true
		cells[m.cell] = true
	_check(names.size() == room.monsters.size() and cells.size() == room.monsters.size(), "no two share a name or a cell")
	# every one can be walked up to without fighting anyone else
	var reach := {room.start: true}
	var queue := [room.start]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for dir in FloorMap.DIRS:
			var next: Vector2i = at + dir
			if room.is_open(next) and not reach.has(next) and room.monster_at(next) == null:
				reach[next] = true
				queue.append(next)
	_check(room.monsters.all(func(m): return room.is_open(m.cell) and FloorMap.DIRS.any(func(dir): return reach.has(m.cell + dir))), "everyone can be walked up to without a fight on the way")
	_check(room.is_open(room.start) and reach.has(room.stairs) and room.stairs != room.start and room.monster_at(room.start) == null, "the way out can be walked to")
	_check(room.grid.size() == room.size and room.grid.all(func(row): return row.size() == room.size), "the room is a square floor like any other")
	var again = TestRoom.make(Rng.new(5))
	_check(range(room.monsters.size()).all(func(i): return again.monsters[i].name == room.monsters[i].name and again.monsters[i].traits == room.monsters[i].traits), "the same seed makes the same room")
	# walking in
	Flags.set_args(PackedStringArray(["nosave", "nosound"])) # without BASE's no-wick: she walks in with you
	var flow = Flow.new(Rng.new(5), LocalMind.new())
	var earned := []
	flow.happened.connect(func(n, d): if n == "trophy": earned.append(d.id))
	var replaced := []
	flow.happened.connect(func(n, d): if n == "state_replaced": replaced.append(d.how))
	await flow.test_room()
	var s = flow.state
	var f = s.floor_map
	_check(s.testing and s.stage == "explore" and s.cell == f.start and f.monsters.size() == TestRoom.count(), "the flow opens the test room")
	_check(replaced == ["test"], "and says the state is the test room's")
	_check(s.gold == int(words.gold) and s.hp == s.max_hp and s.has_ally("witch"), "with a purse to bribe with and the friend a run starts with")
	_check(s.banner != null and s.banner.title == str(words.title) and s.lines.any(func(l): return l.text == str(words.line)), "a banner and the log say what it is")
	_check(Hud.log_fits(s.lines, 760.0) == s.lines.size(), "and the line fits a narrow log")
	_check(not flow.autosave_allowed() and flow.close_run(true) == 0 and not flow.coach.active(), "nothing is saved from it, it leaves no embers and it gives no tips")
	_check(State.from_dict(JSON.parse_string(JSON.stringify(s.to_dict()))) != null, "its state reads back, which is how it is put back")
	_check(Floors.toughness_pct(s) == 0 and not Chart.open(s), "the header boasts of no toughness, and no map is drawn for you")
	# the walk
	_check(f.is_open(s.cell + FloorMap.DIRS[s.facing]), "you start facing down an aisle")
	var before: Array = f.monsters.map(func(m): return m.cell)
	for _i in 4:
		await flow.press("up")
	_check(s.cell == f.start + FloorMap.DIRS[0] * 4 and f.monsters.map(func(m): return m.cell) == before and s.hunger == 0.0, "walking, nobody moves and nobody gets hungry")
	s.cell = f.start + FloorMap.DIRS[0]
	await flow.press("left")
	var front = f.monster_at(s.cell + FloorMap.DIRS[s.facing])
	_check(front != null and s.lines.size() == 1 and s.lines[0].text == TestRoom.describe(front), "facing one, the log says who it is: %s" % (s.lines[0].text if not s.lines.is_empty() else ""))
	await flow.press("right")
	_check(s.lines[0].text == str(words.beside) % [Kinds.title(front), Kinds.title(f.monster_at(s.cell + FloorMap.DIRS[1]))], "between two, who is on each side: %s" % s.lines[0].text)
	_check(f.monsters.all(func(m): return Hud.log_fits([State.sys_line(TestRoom.describe(m))], 760.0) == 1), "every such line fits a narrow log")
	# a fight is its own
	var deep = f.monsters.filter(func(m): return m.kind == "cobra")[0]
	var deep_at: Vector2i = deep.cell
	await flow.go("intro", {"foe": deep})
	await flow.go("menu")
	_check(s.depth == int(Kinds.info("cobra").depth) and s.depth > 1, "a fight runs at the pace of the floor its monster is from (B%dF)" % s.depth)
	s.hp = 3
	s.gold = 0
	s.items = ["salve"]
	s.allies = []
	s.banner = null
	await flow.encounter.defeat(deep, "slain")
	var back = f.monster_at(deep_at)
	_check(s.stage == "explore" and back != null and back != deep and back.name == deep.name and back.hp == back.max_hp and f.monsters_left() == TestRoom.count(), "after it, whoever you slew stands in its place again")
	_check(s.hp == s.max_hp and s.gold == int(words.gold) and s.items.is_empty() and s.has_ally("witch") and s.depth == 1, "and the party is as it walked in")
	_check(s.reputation.is_empty() and s.deeds.is_empty() and s.tally.slain == 0, "no clan remembers it, and it is on no tally")
	_check(s.lines.any(func(l): return l.text == str(words.reset)), "the log says the room is as it was")
	_check(s.banner == null, "and no banner says a clan took it badly (%s)" % [s.banner.title if s.banner != null else ""])
	# a champion gives nothing to keep
	var champion = f.monsters.filter(func(m): return m.boss)[1]
	var max_before: int = s.max_hp
	await flow.go("intro", {"foe": champion})
	await flow.go("menu")
	await flow.encounter.defeat(champion, "slain")
	_check(s.stage == "explore" and s.max_hp == max_before and s.keepsakes.is_empty() and s.keepsake_due == "", "a champion slain here leaves no keepsake and no health to keep")
	_check(earned.is_empty() and flow.trophies.earned.is_empty(), "and nothing in the room earns an achievement")
	# falling
	await flow.go("intro", {"foe": f.monsters[0]})
	s.stage = "dodge"
	s.hp = 0
	await flow.go("dead")
	_check(s.menu.size() == 3 and s.menu[1].label == str(words.back), "falling there offers the way back to the room")
	await flow.tick(flow.clock + 60000.0) # the keys are held off for a moment after a fight; that moment has passed
	await flow.press("2")
	_check(s.stage == "explore" and s.testing and s.hp == s.max_hp and f.monsters_left() == TestRoom.count(), "which stands you up in it, whole")
	# the way out
	flow.tick(flow.clock + 60000.0)
	s.cell = f.stairs + FloorMap.DIRS[1]
	s.facing = 3
	await flow.press("up")
	_check(s.stage == "end" and not s.run_over and s.menu.size() == 2 and s.menu[0].label == str(words.stay) and s.menu[1].label == "MAIN MENU", "its stairs are the way out: stay, or the main menu")
	_check(Transitions.DECIDING.has("end") and s.vignette == "stairs", "asked in the middle of the picture, as any stairs")
	await flow.press("1")
	_check(s.stage == "explore" and s.testing, "staying puts you back on the walk")
	var left := []
	flow.happened.connect(func(n, d): if n == "leave": left.append(d.to))
	await flow.go("end")
	await flow.press("2")
	_check(left == ["menu"], "and the other leaves for the main menu")
	# a run started after it is a run
	await flow.new_run()
	_check(not flow.state.testing and flow.autosave_allowed() and flow.state.floor_map.monsters.back().boss, "a run started after it is an ordinary run")
	# the switch
	_use()
	_check(Flags.enabled("test-room") and not Flags.asked("test-room"), "the test room is on the menu by default, and not where the game starts")
	_use(["test-room"])
	_check(Flags.asked("test-room"), "named outright, the game starts in it")
	_use(["no-test-room"])
	_check(not Flags.enabled("test-room") and not Flags.asked("test-room"), "switched off, it is neither")
	_use()


## nerve: a close call and a clean dodge earn it, a hit shakes one out, a strike that lands or a SPARE spends it.
func _nerve() -> void:
	# the rule, on a run alone: stepping off a square in its last moments
	var run = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0)
	var here := Dodge.index(run.soul.x, run.soul.y)
	run.add_hazard(0.0, [here], 1000.0, 300.0, "goo")
	run.move(1, 0, 400.0)
	_check(run.close_calls == 0, "stepping off a square long before it lands is no close call")
	run.move(-1, 0, 500.0)
	run.move(1, 0, 1000.0 - Combat.NERVE_WINDOW_MS + 50.0)
	_check(run.close_calls == 1, "stepping off it in its last moments is one")
	_check(run.update(900.0, Rng.new(1)).any(func(e): return e.type == "nerve"), "and the run says so")
	run.move(-1, 0, 920.0)
	run.move(1, 0, 950.0)
	_check(run.close_calls == 1, "the same hazard gives no second one")
	var plain = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0)
	plain.add_hazard(0.0, [here], 100.0, 300.0, "goo")
	plain.move(1, 0)
	_check(plain.close_calls == 0, "a step with no time given is only a step")
	var wide = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0)
	wide.add_hazard(0.0, [here, here + 1], 1000.0, 300.0, "goo")
	wide.move(1, 0, 900.0)
	_check(wide.close_calls == 0, "stepping onto another of its squares is none")
	wide.add_hazard(0.0, [here + 1], 1000.0, 300.0, "star")
	wide.move(1, 0, 900.0)
	_check(wide.close_calls == 1, "it is one once you are clear of it, and a star to catch is never one")
	var wall = DodgeRun.start("gates", 1.0, false, 0, 0.0, {}, 1.0)
	wall.update(400.0, Rng.new(3))
	var groups := {}
	for h in wall.hazards:
		groups[h.group] = true
	_check(wall.hazards.size() == Dodge.COLS and groups.size() == 1, "the columns of a wall are one thing: one close call for the lot (%d hazards, %d groups)" % [wall.hazards.size(), groups.size()])
	_check(Combat.nerve_damage(2) == 2 * Combat.NERVE_DAMAGE and Combat.nerve_damage(99) == Combat.NERVE_MAX * Combat.NERVE_DAMAGE, "each point adds to a strike, up to the most you can hold")
	_check(is_equal_approx(Combat.nerve_mercy(3), 3 * Combat.NERVE_MERCY), "and to the odds of a SPARE")
	var Texts = load("res://src/game/texts.gd")
	_check(Texts.spare_chance(0.0, Combat.nerve_mercy(5), 5, false).contains("0% → 40%") and Texts.spare_chance(1.0, 1.0, 0, false).contains("100%"), "SPARE preview handles zero and certain probability boundaries")

	# in a fight
	var flow = _flow(81)
	var m = await _at_menu(flow, "rock")
	var s = flow.state
	var heard := []
	flow.happened.connect(func(name, data): if name in ["nerve", "strike"]: heard.append([name, data]))
	m.max_hp = 200
	m.hp = 200
	_check(s.nerve == 0 and s.viewing("nerve"), "a fight starts with none")
	_check(not str(s.menu[0].sub).contains("NERVE"), "with none held FIGHT says nothing about a zero bonus (%s)" % s.menu[0].sub)
	await _into_dodge(flow)
	_end_dodge(flow)
	await flow.tick(flow.clock + 20.0)
	_check(s.stage == "menu" and s.nerve == 1, "a dodge with no hit in it earns a point (%s, %d)" % [s.stage, s.nerve])
	_check(heard.any(func(e): return e[0] == "nerve" and e[1].how == "clean" and e[1].total == 1), "and says so")
	_check(str(s.menu[0].sub).contains("NERVE 1/5: +2 ON HIT"), "FIGHT says what it adds (%s)" % s.menu[0].sub)
	_check(str(s.menu[2].sub).contains("spend 1 Nerve") and str(s.menu[2].sub).contains("→"), "SPARE compares odds before and after spending (%s)" % s.menu[2].sub)
	await _into_dodge(flow)
	here = Dodge.index(s.dodge.soul.x, s.dodge.soul.y)
	s.dodge.hazards = []
	s.dodge.add_hazard(flow.clock, [here], 100.0, 300.0, "goo") # lands within the window whatever the pace
	await flow.press("right")
	await flow.tick(flow.clock + 16.0)
	_check(s.nerve == 2 and heard.any(func(e): return e[0] == "nerve" and e[1].how == "close"), "a close call in the box earns another (%d)" % s.nerve)
	s.dodge.hazards = []
	s.dodge.add_hazard(flow.clock, [Dodge.index(s.dodge.soul.x, s.dodge.soul.y)], 0.0, 300.0, "goo")
	s.dodge.iframes = 0.0
	await flow.tick(flow.clock + 16.0)
	_check(s.nerve == 1 and heard.any(func(e): return e[0] == "nerve" and e[1].how == "lost"), "a hit shakes one out of you (%d)" % s.nerve)
	_end_dodge(flow)
	await flow.tick(flow.clock + 20.0)
	_check(s.stage == "menu" and s.nerve == 1, "and a dodge with a hit in it earns nothing (%d)" % s.nerve)
	# a miss keeps it, a strike that lands spends it
	s.nerve = 3
	await flow.press("1")
	_check(s.stage == "fightbar" and s.hint.contains("3/5 NERVE: +6 ON HIT"), "the strike bar says what is riding on it (%s)" % s.hint)
	await flow.tick(s.bar.t0 + s.bar.dur + 10.0)
	_check(s.nerve == 3 and m.hp == 200, "a miss keeps the nerve (%d)" % s.nerve)
	await _through_dodge(flow)
	s.nerve = 3
	await flow.go("menu")
	await flow.press("1")
	flow.clock = s.bar.t0 + s.bar.dur / 2.0
	await flow.press("confirm")
	var plain_hit: int = Combat.strike(0.5, false, false).damage
	_check(m.hp == 200 - plain_hit - 3 * Combat.NERVE_DAMAGE and s.nerve == 0, "a strike that lands spends it all for a harder hit (%d left)" % m.hp)
	_check(heard.any(func(e): return e[0] == "strike" and e[1].nerve == 3 * Combat.NERVE_DAMAGE), "the strike says how much of it was nerve")
	# SPARE spends it for better odds
	await _through_dodge(flow)
	s.nerve = Combat.NERVE_MAX
	flow.dice.pin(0.99) # refused, whatever the odds: they are what is checked
	var before: float = await flow.encounter.mercy(m)
	await flow.go("menu")
	_check(s.menu[0].sub.contains("NERVE 5/5") and s.menu[2].sub.contains("spend 5 Nerve") and s.menu[2].sub.contains("→"), "menu compares the damage and mercy uses before commitment")
	await flow.press("3")
	var rolled: float = s.mind_rows.filter(func(row): return row.id == "mercy").front().answer
	_check(is_equal_approx(rolled, minf(1.0, before + Combat.nerve_mercy(Combat.NERVE_MAX))) and s.nerve == 0, "SPARE spends it for better odds (%.2f from %.2f)" % [rolled, before])
	flow.dice.unpin()
	# the next fight starts with none
	await _through_dodge(flow)
	s.nerve = 4
	await flow.go("explore")
	await flow.go("intro", {"foe": m})
	_check(s.nerve == 0, "the next fight starts with none (%d)" % s.nerve)

	# without it
	var off = _flow(82, ["no-nerve"])
	var foe = await _at_menu(off, "rock")
	foe.max_hp = 200
	foe.hp = 200
	await _into_dodge(off)
	_end_dodge(off)
	await off.tick(off.clock + 20.0)
	_check(off.state.stage == "menu" and off.state.nerve == 0 and not off.state.viewing("nerve"), "no-nerve: a clean dodge earns nothing, and nothing is shown")
	_check(not off.state.menu[0].sub.contains("NERVE") and not off.state.menu[2].sub.contains("Nerve"), "no-nerve: menu does not mention the disabled resource")
	await _into_dodge(off)
	off.state.dodge.hazards = []
	off.state.dodge.add_hazard(off.clock, [Dodge.index(off.state.dodge.soul.x, off.state.dodge.soul.y)], 100.0, 300.0, "goo")
	await off.press("right")
	await off.tick(off.clock + 16.0)
	_check(off.state.nerve == 0 and off.state.dodge.close_calls == 0, "nor does a close call")
	_use()


## From the fight's menu into its dodge.
func _into_dodge(flow) -> void:
	var s = flow.state
	s.max_hp = 999
	s.hp = 999
	await flow.go("wait", {"pressure": 1.0})
	for i in 60:
		if s.stage == "dodge":
			return
		if s.hint == "ANY KEY CONTINUE":
			await flow.press("confirm")
		await flow.tick(flow.clock + 50.0)


## Call the dodge over at the next tick, with nothing left in the box.
func _end_dodge(flow) -> void:
	flow.state.dodge.hazards = []
	flow.state.dodge.end_t = flow.clock


## mood-attacks: how the foe feels shows in its attack. A friendly one drops hearts, a frightened one falters and breaks off early.
func _mood_attacks() -> void:
	var entry := {"species": "slime", "genre": "bullet", "hp": 18}
	var feels := func(meters: Dictionary) -> String: return Feelings.mood(Monster.given(entry, Vector2i(1, 1), "TEST", ["shy"], meters))
	_check(feels.call({"friendliness": 10.0, "anger": 70.0, "fear": 70.0}) == "angry", "anger comes first")
	_check(feels.call({"friendliness": 90.0, "anger": 10.0, "fear": 70.0}) == "afraid", "then fear")
	_check(feels.call({"friendliness": 90.0, "anger": 10.0, "fear": 10.0}) == "friendly", "then whether it likes you")
	_check(feels.call({"friendliness": 0.0, "anger": 10.0, "fear": 10.0}) == "wary", "and otherwise it is wary")
	# a friendly one drops hearts, on squares nothing is coming for
	var kind = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0, {}, "friendly")
	var rng := Rng.new(5)
	var t := 0.0
	while t < DodgeRun.GIFT_FIRST_MS + 50.0:
		t += 16.0
		kind.update(t, rng)
	var hearts: Array = kind.hazards.filter(func(h): return h.kind == "heart")
	_check(hearts.size() == 1, "a friendly monster's attack drops a heart (%d)" % hearts.size())
	var heart: Dictionary = hearts[0]
	_check(not kind.hazards.any(func(h): return h.kind != "heart" and h.warn < heart.warn and h.cells.has(heart.at)), "on a square nothing was coming for")
	kind.soul = Vector2i(int(heart.at) % Dodge.COLS, int(heart.at) / Dodge.COLS)
	kind.hazards = [heart]
	var caught: Array = kind.update(heart.hit + 10.0, rng)
	_check(caught.any(func(e): return e.type == "heart") and not caught.any(func(e): return e.type == "hurt"), "standing on it catches it, and it never hurts")
	var none = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0)
	t = 0.0
	while t < 3000.0:
		t += 16.0
		none.update(t, Rng.new(5))
	_check(not none.hazards.any(func(h): return h.kind == "heart"), "anyone else's has none")
	# a frightened one falters and breaks off early
	var scared = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0, {}, "afraid")
	var steady = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0)
	_check(is_equal_approx(scared.end_t, steady.end_t * DodgeRun.AFRAID_DURATION), "a frightened monster breaks off early (%.0f ms of %.0f)" % [scared.end_t, steady.end_t])
	for i in 6:
		scared.add_hazard(0.0, [i], 1000.0, 300.0, "goo")
		steady.add_hazard(0.0, [i], 1000.0, 300.0, "goo")
	_check(scared.hazards.size() == 4 and steady.hazards.size() == 6, "and one hazard in three never comes (%d of 6)" % scared.hazards.size())
	scared.add_hazard(0.0, [9], 1000.0, 300.0, "star")
	scared.add_hazard(0.0, [10], 1000.0, 300.0, "star")
	scared.add_hazard(0.0, [11], 1000.0, 300.0, "star")
	_check(scared.hazards.size() == 7, "what is there to be caught always comes")
	_check(Overlay.mood_word(Monster.given(entry, Vector2i(1, 1), "TEST", ["shy"], {"friendliness": 90.0, "anger": 10.0, "fear": 10.0}))[0] == "FRIENDLY", "the word by its name is the same mood")
	_check(Overlay.heart_shape(7.0).size() == 3, "a heart has a shape")

	# in a fight
	var flow = _flow(83)
	var m = await _at_menu(flow)
	var s = flow.state
	var heard := []
	flow.happened.connect(func(name, _data): if name in ["heart", "mercy_changed"]: heard.append(name))
	m.meters = {"friendliness": m.threshold + 1.0, "anger": 0.0, "fear": 0.0}
	await _into_dodge(flow)
	_check(s.dodge.mood == "friendly", "a foe that likes you attacks as a friend (%s)" % s.dodge.mood)
	s.hp = 500
	var here := Dodge.index(s.dodge.soul.x, s.dodge.soul.y)
	s.dodge.hazards = []
	s.dodge.add_hazard(flow.clock, [here], 0.0, 500.0, "heart", {"at": here})
	await flow.tick(flow.clock + 16.0)
	_check(s.hp == 500 + Combat.HEART_HEAL and heard.has("heart"), "a heart caught heals you (%d)" % s.hp)
	_check(is_equal_approx(m.meters.friendliness, m.threshold + 1.0 + Combat.HEART_FRIENDLINESS), "and pleases it (%.0f)" % m.meters.friendliness)
	_end_dodge(flow)
	await flow.tick(flow.clock + 20.0)
	_check(s.stage == "menu" and heard.has("mercy_changed"), "the mercy gauge moves for it, with no deed of yours")
	m.meters = {"friendliness": 0.0, "anger": 0.0, "fear": 90.0}
	await _into_dodge(flow)
	_check(s.dodge.mood == "afraid", "a frightened one attacks as one (%s)" % s.dodge.mood)

	var off = _flow(84, ["no-mood-attacks"])
	var foe = await _at_menu(off)
	foe.meters = {"friendliness": 100.0, "anger": 0.0, "fear": 0.0}
	await _into_dodge(off)
	_check(off.state.dodge.mood == "", "no-mood-attacks: every attack is the plain one")
	_use()


## follow-through: with friends, a strike that lands leaves the line running, and a press on each friend's mark is that friend's strike.
func _follow_through() -> void:
	var flow = _flow(85)
	var m = await _at_menu(flow, "rock")
	var s = flow.state
	var heard := []
	flow.happened.connect(func(name, data): if name == "follow": heard.append(data))
	m.max_hp = 400
	m.hp = 400
	# alone: as it always was
	await flow.press("1")
	_check(s.bar.marks.is_empty(), "alone there are no marks on the bar")
	var ticks := []
	var on_sweep := func(name, data): if name == "sweep": ticks.append(int(data.step))
	flow.happened.connect(on_sweep)
	for part in range(1, 11):
		await flow.tick(s.bar.t0 + s.bar.dur * part * 0.05)
	_check(ticks == [1, 2, 3, 4], "the line is heard crossing each part of the bar, a step higher to the middle (%s)" % [ticks])
	flow.happened.disconnect(on_sweep)
	flow.clock = s.bar.t0 + s.bar.dur / 2.0
	await flow.press("confirm")
	_check(s.stage != "fightbar" and s.bar == null, "and the strike ends the bar at once (%s)" % s.stage)
	await _through_dodge(flow)
	# with two friends, and Wick, who is no one's strike
	s.allies = [Ally.make("witch", "WICK", 75.0), Ally.make("slime", "GLOP", 60.0), Ally.make("snake", "HISS", 60.0)]
	await flow.press("1")
	_check(s.bar.marks.size() == 2 and s.bar.marks[0].who == "GLOP" and s.bar.marks[1].who == "HISS", "each friend in the party has a mark, in order (%s)" % [s.bar.marks.map(func(k): return k.who)])
	_check(s.hint.contains("FRIEND"), "and the hint says to press again (%s)" % s.hint)
	var hp: int = m.hp
	flow.clock = s.bar.t0 + s.bar.dur * 0.5
	await flow.press("confirm")
	var mine: int = hp - m.hp
	_check(s.stage == "fightbar" and s.bar != null and is_equal_approx(s.bar.struck, 0.5) and mine > 0, "your strike lands and the line runs on (%s, %d)" % [s.stage, mine])
	flow.clock = s.bar.t0 + s.bar.dur * 0.51
	await flow.press("confirm")
	_check(s.bar.marks[0].state == "" and m.hp == hp - mine, "a press right on top of the first is a slip of the finger, and does nothing")
	flow.clock = s.bar.t0 + s.bar.dur * Combat.FOLLOW_MARKS[0]
	await flow.press("confirm")
	_check(s.bar.marks[0].state == "hit" and m.hp == hp - mine - Combat.FOLLOW_DAMAGE, "the next press, on the first mark, is that friend's strike (%d)" % m.hp)
	_check(heard.size() == 1 and heard[0].who == "GLOP" and heard[0].species == "slime" and heard[0].damage == Combat.FOLLOW_DAMAGE, "and the game says whose")
	flow.clock = s.bar.t0 + s.bar.dur * (Combat.FOLLOW_MARKS[1] + Combat.FOLLOW_EDGE * 0.9)
	await flow.press("confirm")
	_check(s.bar != null and s.bar.marks[1].state == "hit" and m.hp == hp - mine - 2 * Combat.FOLLOW_DAMAGE, "and the one after, anywhere on the second mark, the second friend's")
	await flow.tick(flow.clock + 16.0)
	_check(s.stage != "fightbar" and s.bar == null, "with every mark settled the strike is over (%s)" % s.stage)
	_check(s.lines.any(func(l): return str(l.text).contains("GLOP and HISS follow through: %d more" % (2 * Combat.FOLLOW_DAMAGE))), "the log says who followed (%s)" % str(s.lines.map(func(l): return l.text)))
	_check(Texts.followed(["A", "B", "C"], 9) == "A, B and C follow through: 9 more. " and Texts.followed(["A"], 3) == "A follows through: 3 more. " and Texts.followed([], 0) == "", "however many of them it was")
	# a press off the mark loses that friend's moment, and a mark the line leaves behind is lost too
	await _through_dodge(flow)
	await flow.press("1")
	hp = m.hp
	flow.clock = s.bar.t0 + s.bar.dur * 0.5
	await flow.press("confirm")
	mine = hp - m.hp
	flow.clock = s.bar.t0 + s.bar.dur * (Combat.FOLLOW_MARKS[0] - Combat.FOLLOW_EDGE - 0.01)
	await flow.press("confirm")
	_check(s.bar != null and s.bar.marks[0].state == "lost" and s.bar.marks[1].state == "" and m.hp == hp - mine, "a press off the mark loses that friend's moment")
	await flow.tick(s.bar.t0 + s.bar.dur * (Combat.FOLLOW_MARKS[1] + Combat.FOLLOW_EDGE + 0.01))
	_check(s.stage != "fightbar" and m.hp == hp - mine, "a mark the line leaves behind is lost, and with none left the strike is over (%s)" % s.stage)
	# not pressing at all costs nothing: the end of the bar ends the strike
	await _through_dodge(flow)
	await flow.press("1")
	hp = m.hp
	flow.clock = s.bar.t0 + s.bar.dur * 0.5
	await flow.press("confirm")
	mine = hp - m.hp
	await flow.tick(s.bar.t0 + s.bar.dur * 0.6)
	_check(s.stage == "fightbar", "the line runs on to the marks")
	await flow.tick(s.bar.t0 + s.bar.dur + 10.0)
	_check(s.stage != "fightbar" and m.hp == hp - mine, "and not pressing at all costs nothing (%s)" % s.stage)
	# three marks at most, each further along and clear of the one before
	var marks: Array = Combat.FOLLOW_MARKS
	_check(marks.size() == Combat.PARTY_MAX and marks[0] - Combat.FOLLOW_EDGE > 0.5 + Combat.CRIT_EDGE and marks[-1] + Combat.FOLLOW_EDGE <= 1.0, "a mark for each of a full party, all past the middle and on the bar")
	_check(range(1, marks.size()).all(func(i): return marks[i] - marks[i - 1] >= Combat.FOLLOW_EDGE * 2.0), "and no two overlap")
	# a HEAVY blow is too quick for them
	await _through_dodge(flow)
	await flow.press("5")
	_check(s.bar.heavy and s.bar.marks.is_empty(), "a HEAVY blow has no marks")
	flow.clock = s.bar.t0 + s.bar.dur / 2.0
	await flow.press("confirm")
	_check(s.stage != "fightbar", "and ends at once (%s)" % s.stage)
	# a strike that fells it ends at once
	await _through_dodge(flow)
	m.hp = 1
	await flow.press("1")
	flow.clock = s.bar.t0 + s.bar.dur * 0.5
	await flow.press("confirm")
	_check(m.is_gone() and s.bar == null and s.stage != "fightbar", "a strike that fells it doesn't wait for the friends (%s)" % s.stage)

	var off = _flow(86, ["no-follow-through"])
	var foe = await _at_menu(off, "rock")
	foe.max_hp = 400
	foe.hp = 400
	off.state.allies = [Ally.make("slime", "GLOP", 60.0), Ally.make("snake", "HISS", 60.0)]
	await off.go("menu")
	await off.press("1")
	_check(off.state.bar.marks.is_empty(), "no-follow-through: no marks")
	off.clock = off.state.bar.t0 + off.state.bar.dur / 2.0
	await off.press("confirm")
	_check(off.state.stage != "fightbar" and off.state.bar == null, "and a strike ends the bar at once, as it did")
	_use()


## Into a fight with `m` on the run as it stands (`_at_menu` starts a new run), up to the menu.
func _meet(flow, m) -> void:
	var s = flow.state
	if s.stage != "explore":
		await flow.go("explore", {"lines": []})
	await flow.go("intro", {"foe": m})
	await flow.tick(flow.clock + 1000.0)
	if s.stage == "intro" and s.hint == "ANY KEY CONTINUE":
		await flow.press("confirm")
	if s.stage == "social":
		await flow.press("cancel")


## A stage that is deciding (Transitions.DECIDING) has its choices over the middle of the picture and not in the dock:
## `cards` of them cards with what they do, `plain` of them small buttons, with the moving picture `art` over them.
## The card that ends a run has a row for what the run earned, between what it says and its choices.
func _the_run_says_what_it_earned(s) -> void:
	var achievements = load("res://src/rules/achievements.gd")
	var cards: Array = ["door", "quiet"].map(func(id): return achievements.card(str(id), {str(id): 0}))
	for frame in [Vector2(936, 392), Vector2(1400, 600), Vector2(480, 206)]:
		var popup := ChoicePopup.new()
		popup.state = s
		popup.size = frame
		_check(not popup._layout().badges.has_area(), "the end at %s: no row with nothing to show" % frame)
		popup.badges = cards
		var plan: Dictionary = popup._layout()
		var row: Rect2 = plan.badges
		var rects: Array[Rect2] = popup.choice_rects()
		_check(row.has_area() and Rect2(Vector2.ZERO, frame).encloses(row), "the end at %s: what the run earned has a row on the card (%s)" % [frame, row])
		_check(not row.intersects(plan.ask) and rects.all(func(r): return r.has_area() and not r.intersects(row)) and (not plan.art.has_area() or not plan.art.intersects(row)), "the end at %s: on nothing else" % frame)
		s.run_over = false
		_check(not popup._layout().badges.has_area(), "the end at %s: and only on the card that ends the run" % frame)
		s.run_over = true
		popup.free()


func _choices_over_the_picture(s, art: String, cards: int, plain: int) -> void:
	var where := "%s (%s)" % [s.stage, art]
	_check(Transitions.DECIDING.has(s.stage) and Transitions.WALK.has(s.stage), "%s: the choice is the whole moment" % where)
	_check(s.vignette == art and Vignette.KNOWN.has(art), "%s: the stage says what it has stopped at, and there is a picture of it (%s)" % [where, s.vignette])
	var asked: Array = ChoicePopup.asked(s)
	_check(not asked.is_empty() and asked[-1] == s.lines[-1], "%s: what is asked is said with the choices" % where)
	var dock := Hud.new()
	dock.part = Hud.Part.DOCK
	dock.state = s
	dock.size = Vector2(1136, 200)
	_check(dock.command_rects().is_empty() and dock._log_lines().size() == s.lines.size() - asked.size(), "%s: the dock keeps the lines before the question and no commands" % where)
	dock.free()
	for frame in [Vector2(936, 392), Vector2(1400, 600), Vector2(480, 206)]:
		var popup := ChoicePopup.new()
		popup.state = s
		popup.size = frame
		var rects: Array[Rect2] = popup.choice_rects()
		var plan: Dictionary = popup._layout()
		var whole := Rect2(Vector2.ZERO, frame)
		var all_in: bool = rects.size() == s.menu.size() and rects.all(func(r): return r.has_area() and whole.encloses(r))
		var apart := true
		for a in rects.size():
			for b in range(a + 1, rects.size()):
				apart = apart and not rects[a].intersects(rects[b])
		_check(all_in and apart, "%s at %s: every choice has its own place inside the picture" % [where, frame])
		var tall: Array = rects.filter(func(r): return r.size.y > ChoicePopup.PLAIN_H + 1.0)
		_check(tall.size() == cards and rects.size() - tall.size() == plain, "%s at %s: %d cards that say what they do and %d plain (%d, %d)" % [where, frame, cards, plain, tall.size(), rects.size() - tall.size()])
		var box: Rect2 = rects[0]
		for r in rects:
			box = box.merge(r)
		box = box.merge(plan.ask)
		if plan.art.has_area():
			box = box.merge(plan.art)
		_check(absf(box.get_center().x - frame.x / 2.0) < 2.0 and box.position.y >= 0.0 and box.end.y <= frame.y and absf(box.get_center().y - frame.y / 2.0) < frame.y * 0.12, "%s at %s: the question and its choices sit in the middle (%s)" % [where, frame, box])
		_check(not plan.art.has_area() or (whole.encloses(plan.art) and rects.all(func(r): return not r.intersects(plan.art)) and not plan.art.intersects(plan.ask)), "%s at %s: the moving picture is over them, on nothing" % [where, frame])
		var top := INF
		for r in rects:
			top = minf(top, r.position.y)
		_check(plan.ask.has_area() and top - plan.ask.end.y >= ChoicePopup.GAP - 0.5, "%s at %s: the first row of choices clears the question by the gap the layout counts (%.1f)" % [where, frame, top - plan.ask.end.y])
		if frame.y >= 392.0:
			_check(plan.art.has_area(), "%s at %s: and it is there when the picture has the room" % [where, frame])
		var got := [-1]
		popup.picked.connect(func(i): got[0] = i)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = rects[-1].get_center()
		popup._gui_input(click)
		_check(got[0] == rects.size() - 1, "%s at %s: a click on a choice picks it (%d)" % [where, frame, got[0]])
		popup.free()


## keepsakes: a champion out of your way leaves three, of which you take one for the rest of the run.
func _keepsakes() -> void:
	# what is offered
	var all: Array = Keepsakes.ids()
	_check(all.size() == 9 and all.all(func(id): return Keepsakes.name_of(id) != "" and Keepsakes.text_of(id) != ""), "nine keepsakes, each with a name and what it does")
	_check(all.all(func(id): return Overlay.banner_fits(KeepsakeStage.sentence(Keepsakes.text_of(id)))), "and what each does fits the banner")
	var first: Array = Keepsakes.offer(11, 1, [])
	_check(first.size() == Keepsakes.OFFERED and first == Keepsakes.offer(11, 1, []), "three are offered, the same three for the same run and floor (%s)" % [first])
	_check(first[0] != first[1] and first[1] != first[2] and first[0] != first[2], "no two alike")
	_check(range(1, 30).any(func(i): return Keepsakes.offer(11 + i, 1, []) != first) and range(2, 6).any(func(d): return Keepsakes.offer(11, d, []) != first), "another run or another floor offers others")
	_check(Keepsakes.offer(11, 1, first).all(func(id): return not first.has(id)), "one already held is never offered again")
	_check(Keepsakes.offer(11, 1, all.slice(0, 7)).size() == 2 and Keepsakes.offer(11, 1, all).is_empty(), "with few left fewer are offered, and with none left none")
	_check(range(40).all(func(i): return Keepsakes.offer(i, 1, [], false).all(func(id): return not Keepsakes.NEEDS_NERVE.has(id))), "a game without nerve is never offered the ones that feed it")
	_check(Transitions.allowed("fightbar", "keepsake") and Transitions.allowed("ask", "keepsake") and Transitions.allowed("keepsake", "explore") and not Transitions.allowed("explore", "keepsake"), "the choice comes at the end of a fight and nowhere else")
	_check(Transitions.WALK.has("keepsake") and Transitions.DECIDING.has("keepsake"), "it is made on the floor, the fight behind you, and it is the whole moment: its cards go over the picture")
	var named := {}
	var naming := RegEx.create_from_string('vignette = (?:"(\\w+)" if .* else )?"(\\w+)"')
	for file in DirAccess.get_files_at("res://src/game/stages"):
		if file.ends_with(".gd"):
			for found in naming.search_all(FileAccess.get_file_as_string("res://src/game/stages/" + file)):
				for group in [1, 2]:
					if found.get_string(group) != "":
						named[found.get_string(group)] = file
	_check(named.size() >= 6 and named.keys().all(func(id): return Vignette.KNOWN.has(id)) and Vignette.KNOWN.all(func(id): return named.has(id)), "every moving picture a stage names is one there is, and every one there is is named (%s)" % [named.keys()])

	# a champion slain leaves them
	var flow = _flow(86)
	await flow.new_run()
	var s = flow.state
	var took := []
	var paused := [0]
	flow.happened.connect(func(name, data):
		if name == "keepsake":
			took.append(data.id)
		if name == "pause_requested":
			paused[0] += 1)
	_check(not s.to_dict().has("keepsakes"), "a run with none saves as it always did")
	var boss = s.floor_map.monsters.filter(func(x): return x.boss).front()
	await _meet(flow, boss)
	await flow.encounter.defeat(boss, "slain")
	var offered: Array = Keepsakes.offer(s.run_seed, s.depth, [])
	_check(s.stage == "keepsake" and s.foe == null and s.keepsake_due == "", "a champion slain leaves keepsakes before the walk goes on (%s)" % s.stage)
	_check(s.menu.map(func(item): return item.label) == offered.map(func(id): return Keepsakes.name_of(id)) and s.menu.all(func(item): return str(item.sub).ends_with(".")), "the three of this run and floor, each saying what it does (%s)" % [s.menu])
	_check(s.lines.any(func(l): return str(l.text).contains(boss.name) and str(l.text).contains("keepsakes")), "the log says who left them (%s)" % str(s.lines.map(func(l): return l.text)))
	_choices_over_the_picture(s, "keepsakes", 3, 0)
	_check(s.banner != null and str(s.banner.text).contains("stronger"), "and the picture still says the champion made you stronger")
	await flow.press("confirm")
	_check(s.stage == "keepsake" and s.keepsakes.is_empty(), "a key still down from the fight takes nothing")
	await flow.tick(flow.clock + Flow.AFTER_FIGHT_MS + 1.0)
	await flow.press("confirm")
	_check(s.stage == "keepsake" and s.keepsakes.is_empty(), "nor one pressed a moment later: there is time to read")
	await flow.tick(flow.clock + Flow.BEFORE_KEEPSAKE_MS)
	await flow.press("cancel")
	_check(s.stage == "keepsake" and paused[0] == 1, "Esc is the pause menu, and the choice waits")
	await flow.press("right")
	_check(s.selected == 1, "the arrows move along them")
	var max_before: int = s.max_hp
	await flow.press("confirm")
	var mine: String = offered[1]
	_check(s.stage == "explore" and s.keepsakes == [mine] and took == [mine], "Enter takes the picked one and the walk goes on (%s, %s)" % [s.stage, s.keepsakes])
	_check(s.banner != null and s.banner.title == Keepsakes.name_of(mine) and s.lines.any(func(l): return str(l.text).begins_with("You take the %s" % Keepsakes.name_of(mine))), "the picture and the log say which")
	_check(s.max_hp == max_before + (Keepsakes.EMBER_MAX_HP if mine == "ember_heart" else 0), "(only the ember heart changes your health)")

	# kept in a save, down the stairs, and never offered twice
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var back = State.from_dict(saved)
	_check(back != null and back.keepsakes == [mine] and back.max_hp == s.max_hp, "a save keeps them")
	var odd: Dictionary = saved.duplicate(true)
	odd.keepsakes = ["nonsense", mine, mine, 7.0]
	_check(State.from_dict(odd).keepsakes == [mine], "and only the ones there are, once each")
	odd.keepsakes = "all of them"
	_check(State.from_dict(odd).keepsakes.is_empty(), "(a save that says something else about them holds none)")
	await flow.tick(flow.clock + 1000.0)
	await flow.go("camp")
	_check(s.lines.any(func(l): return str(l.text) == "You carry the %s." % Keepsakes.name_of(mine)), "sitting down says what you carry (%s)" % str(s.lines.map(func(l): return l.text)))
	await flow.press("cancel")
	await flow.next_floor()
	_check(s.keepsakes == [mine] and s.depth == 2, "they come down the stairs with you")
	var boss2 = s.floor_map.monsters.filter(func(x): return x.boss).front()
	var other = s.floor_map.monsters.filter(func(x): return not x.boss).front()
	await _meet(flow, boss2)
	flow.fight_queue = [other]
	await flow.encounter.defeat(boss2, "spared", false)
	_check(s.stage == "keepsake" and s.menu.size() == 3 and s.menu.all(func(item): return item.label != Keepsakes.name_of(mine)), "the next champion, spared, leaves three others (%s)" % [s.menu.map(func(item): return item.label)])
	await flow.tick(flow.clock + Flow.BEFORE_KEEPSAKE_MS + 1.0)
	await flow.press("3")
	_check(s.keepsakes.size() == 2 and s.stage == "intro" and s.foe == other, "a digit takes one too, and a fight that was queued comes after the choice (%s)" % s.stage)
	_check(Keepsakes.held_words(s) == "%s and the %s" % [Keepsakes.name_of(s.keepsakes[0]), Keepsakes.name_of(s.keepsakes[1])], "(two are named as two)")

	# a champion won over at the ask stage leaves them as well
	var kind = _flow(87)
	await kind.new_run()
	var ks = kind.state
	var kboss = ks.floor_map.monsters.filter(func(x): return x.boss).front()
	await _meet(kind, kboss)
	_won_over(kboss)
	await kind.encounter.defeat(kboss, "spared")
	_check(ks.stage == "ask" and ks.keepsake_due == kboss.name, "a champion spared asks its question first (%s)" % ks.stage)
	await kind.press(str(ks.menu.size())) # GO IN PEACE
	_check(ks.stage == "keepsake", "and its keepsakes come after the answer (%s)" % ks.stage)

	# none where there is nothing to use one on, and none with the feature off
	for how in ["last", "practice", "off"]:
		var none = _flow(88, ["no-keepsakes"] if how == "off" else [])
		await none.new_run()
		var ns = none.state
		var nboss = ns.floor_map.monsters.filter(func(x): return x.boss).front()
		await _meet(none, nboss)
		if how == "last":
			ns.depth = Floors.run_floors()
		ns.practice = how == "practice"
		await none.encounter.defeat(nboss, "slain")
		_check(ns.stage == "explore" and ns.keepsake_due == "" and ns.keepsakes.is_empty(), "no keepsake: %s (%s)" % [how, ns.stage])
		ns.practice = false
		if how == "off":
			_check(await none.load_state(saved) and none.state.keepsakes.is_empty(), "and a save made with keepsakes is played without them")
	_use()

	# what each one does
	var f = _flow(89, ["no-initiated-dialogue"]) # so no strike carries a bonus the last one earned
	var m = await _at_menu(f, "rock")
	var fs = f.state
	var struck := []
	var winds := [0]
	f.happened.connect(func(name, data):
		if name == "strike":
			struck.append(data)
		if name == "second_wind":
			winds[0] += 1)
	m.max_hp = 900
	m.hp = 900
	var strike := func(x: float) -> Dictionary:
		fs.nerve = 0
		await f.press("1")
		f.clock = fs.bar.t0 + fs.bar.dur * x
		await f.press("confirm")
		await _through_dodge(f)
		return struck[-1]
	var off_middle: float = 0.5 + Combat.CRIT_EDGE * 0.75 # outside the perfect mark, inside one twice as wide
	var plain: Dictionary = await strike.call(0.5)
	var near: Dictionary = await strike.call(off_middle)
	_check(plain.crit and not near.crit and near.damage < plain.damage, "(without keepsakes: the middle is perfect, a little off is not)")
	Keepsakes.take(fs, "sharp_tooth")
	await f.press("1")
	_check(fs.hint.contains("TOOTH +%d" % Keepsakes.TOOTH_DAMAGE), "the sharp tooth shows on the strike bar (%s)" % fs.hint)
	f.clock = fs.bar.t0 + fs.bar.dur * 0.5
	fs.nerve = 0
	await f.press("confirm")
	await _through_dodge(f)
	_check(struck[-1].damage == plain.damage + Keepsakes.TOOTH_DAMAGE, "and every strike that lands does that much more (%d, %d)" % [struck[-1].damage, plain.damage])
	fs.keepsakes = []
	Keepsakes.take(fs, "steady_hand")
	var steady: Dictionary = await strike.call(off_middle)
	_check(steady.crit and steady.damage == plain.damage, "the steady hand makes a strike a little off the middle perfect (%s)" % [steady])
	var far: Dictionary = await strike.call(0.5 + Combat.CRIT_EDGE * 1.25)
	_check(not far.crit, "but not one off the wider mark")
	fs.keepsakes = []
	var hp_was: int = fs.max_hp
	fs.max_hp = 20
	fs.hp = 7
	Keepsakes.take(fs, "ember_heart")
	Keepsakes.take(fs, "ember_heart")
	_check(fs.max_hp == 20 + Keepsakes.EMBER_MAX_HP and fs.hp == fs.max_hp and fs.keepsakes == ["ember_heart"], "the ember heart is more health and all of it back, once (%d/%d)" % [fs.hp, fs.max_hp])
	fs.max_hp = hp_was
	fs.keepsakes = []
	await _into_dodge(f)
	var bare: int = fs.dodge.guard
	_check(is_equal_approx(fs.dodge.nerve_window, Combat.NERVE_WINDOW_MS), "(without keepsakes a close call is as close as ever)")
	_end_dodge(f)
	await _through_dodge(f)
	fs.keepsakes = ["thick_hide", "quick_feet", "second_wind"]
	await _into_dodge(f)
	_check(fs.dodge.guard == bare + Keepsakes.THICK_GUARD, "the thick hide takes one off every hit")
	_check(is_equal_approx(fs.dodge.nerve_window, Combat.NERVE_WINDOW_MS * Keepsakes.QUICK_WINDOW), "quick feet make a close call of a step from further out")
	var early: float = Combat.NERVE_WINDOW_MS * 1.25 # too early for a close call without quick feet
	for quick in [false, true]:
		var run = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0)
		if quick:
			run.nerve_window = Combat.NERVE_WINDOW_MS * Keepsakes.QUICK_WINDOW
		run.add_hazard(0.0, [Dodge.index(run.soul.x, run.soul.y)], 1000.0, 300.0, "goo")
		run.move(1, 0, 1000.0 - early)
		_check(run.close_calls == (1 if quick else 0), "a step %d ms before it lands is %s" % [roundi(early), "a close call with quick feet" if quick else "none without"])
	# the second wind: the hit that would fell you leaves you standing, once a fight
	var box = fs.dodge
	box.hazards = []
	box.next_t = f.clock + 1e7
	box.end_t = f.clock + 1e7
	box.mood = ""
	box.add_hazard(f.clock, [Dodge.index(box.soul.x, box.soul.y)], 0.0, 1e6, "goo")
	fs.hp = 2
	await f.tick(f.clock + 20.0)
	_check(fs.hp == 1 and fs.stage == "dodge" and winds[0] == 1 and fs.second_wind_used, "second wind: the hit that would fell you leaves you on 1 HP (%d, %s)" % [fs.hp, fs.stage])
	await f.tick(f.clock + DodgeRun.SAFE_SNAKE_MS + 100.0)
	_check(fs.stage == "dead" and winds[0] == 1, "but only once a fight (%s)" % fs.stage)
	await f.go("intro", {"foe": m})
	_check(not fs.second_wind_used, "and the next fight has it again")
	_check(fs.nerve == 0, "(no deep breath, no nerve to start with)")

	# deep breath, open hand, lucky coin
	for with_nerve in [true, false]:
		var d = _flow(90, [] if with_nerve else ["no-nerve"])
		await d.new_run()
		d.state.keepsakes = ["deep_breath"]
		await _meet(d, d.state.floor_map.monsters.filter(func(x): return not x.boss).front())
		_check(d.state.nerve == (Keepsakes.DEEP_NERVE if with_nerve else 0), "deep breath: a fight starts with %d nerve%s" % [d.state.nerve, "" if with_nerve else " in a game without it"])
	_use()
	var o = _flow(91)
	var om = await _at_menu(o)
	var os = o.state
	om.meters.friendliness = 30.0
	var closed: float = await o.encounter.mercy(om)
	os.keepsakes = ["open_hand"]
	var open: float = await o.encounter.mercy(om)
	_check(closed < 1.0 - Keepsakes.OPEN_MERCY and is_equal_approx(open, closed + Keepsakes.OPEN_MERCY), "the open hand makes mercy likelier (%.2f, %.2f)" % [closed, open])
	_won_over(om)
	_check(await o.encounter.mercy(om) <= 1.0, "never past certain")
	os.reputation[Clans.of(om.species)] = -Clans.STANDING_MAX
	_check(Clans.enraged(os, om) and await o.encounter.mercy(om) == 0.0, "and an enraged clan still takes none")
	os.reputation = {}
	os.keepsakes = ["lucky_coin"]
	_check(Keepsakes.gold(os, 10) == 15 and Keepsakes.gold(os, 5) == 8 and Keepsakes.gold(State.new(), 10) == 10, "the lucky coin makes gold worth half as much again")
	var gold: int = os.gold
	om.purse = 10
	await o.encounter.defeat(om, "slain")
	_check(os.gold == gold + 15, "a purse is worth that to you (%d)" % (os.gold - gold))
	_use()


## skill-combat: SKILLS in FIGHT's place, energy that comes back every turn, a cooldown, block that soaks hits, bruises that add up.
func _skill_combat() -> void:
	var flow = _flow(70)
	await _at_menu(flow, "rock")
	var s = flow.state
	_check(s.menu[0].label == "FIGHT" and s.skill_fight == null and s.skills.is_empty(), "off unless named: FIGHT as it was")
	_check(not s.to_dict().has("skills"), "and a save says nothing of skills")
	flow = _flow(71, ["skill-combat"])
	var m = await _at_menu(flow, "rock")
	s = flow.state
	var f: Dictionary = s.skill_fight
	_check(s.menu[0].label == "SKILLS" and not s.menu.any(func(c): return c.label == "HEAVY"), "SKILLS takes FIGHT's place, and HEAVY is gone (%s)" % [s.menu.map(func(c): return c.label)])
	_check(s.skills == ["strike", "defend", "slam"] and f.energy == 2, "a run starts with STRIKE, DEFEND and SLAM, and 2 energy")
	await flow.press("1")
	_check(s.stage == "skills" and s.menu.size() == 4 and s.menu[3].label == "END TURN", "SKILLS lists them, and END TURN (%s)" % s.stage)
	_check(s.menu.all(func(c): return not c.get("disabled", false)), "all of them can be used on a fresh turn")
	await flow.press("cancel")
	_check(s.stage == "menu", "ESC goes back while nothing is used yet")
	await flow.press("1")
	var hp: int = m.hp
	await flow.press("3")
	_check(m.hp == hp - 12 and f.bruised == 1, "SLAM: 12 damage, then a bruise (%d -> %d)" % [hp, m.hp])
	_check(f.energy == 0 and s.stage in ["wait", "menu"], "with no energy left the turn is over by itself (%s)" % s.stage)
	await _through_dodge(flow)
	_check(s.stage == "menu" and f.energy == 2, "the next turn gives the energy back (%s, %d)" % [s.stage, f.energy])
	await flow.press("1")
	_check(s.menu[2].get("disabled", false) and s.menu[2].sub.contains("ready in 1 turn"), "SLAM is cooling down for one turn (%s)" % s.menu[2].sub)
	hp = m.hp
	await flow.press("1")
	_check(m.hp == hp - 9 and s.stage == "skills", "STRIKE: 8, and 1 more for the bruise; one energy is left to use")
	await flow.press("cancel")
	_check(s.stage == "skills", "once a skill is used there is no going back to the menu this turn")
	await flow.press("2")
	_check(f.block == 2 and s.stage in ["wait", "menu"], "DEFEND: 2 block, and the turn is over")
	var probe := {"block": 2}
	_check(Skills.soak(probe, 3) == 1 and probe.block == 0 and Skills.soak(probe, 3) == 3, "block soaks a hit and is used up")
	await _through_dodge(flow)
	_check(f.block == 0 and Skills.usable(f, "slam"), "a new turn: the block is gone, and SLAM is ready again")
	await flow.press("1")
	await flow.press("4")
	_check(s.stage in ["wait", "menu"] and f.used == 0, "END TURN with nothing used lets it attack")
	await _through_dodge(flow)
	await flow.press("1")
	m.hp = 3
	var slain: int = s.tally.slain
	await flow.press("1")
	_check(s.stage == "explore" and s.tally.slain == slain + 1 and m.gone == "slain", "a skill that kills ends the fight (%s)" % s.stage)
	_check(Skills.damage(Skills.new_fight(), "strike", true) == roundi(8 * Combat.BOSS_DAMAGE_SCALE), "a champion takes less, as from a strike")
	var held := Skills.start()
	_check(not Skills.learn(held, "strike") and held.size() == 3 and Skills.slots() == 6, "a skill held already isn't learned twice, and three of six slots are free")
	_check(not Skills.learn(held, "nonexistent"), "nor one that doesn't exist")
	_check(not Skills.learn(["defend", "slam", "x", "y", "z", "w"], "strike"), "and full slots take no more")
	# a save keeps them, and one from before the feature starts with the first three
	var saved: Dictionary = s.to_dict()
	_check(saved.skills == ["strike", "defend", "slam"] and State.from_dict(saved).skills == saved.skills, "a save keeps the skills held")
	saved.erase("skills")
	var later = _flow(72, ["skill-combat"])
	await later.load_state(saved)
	_check(later.state.skills == Skills.start(), "a save from before skill-combat starts with the first three")
	for id in Skills.table().skills:
		var sub: String = Skills.sub(Skills.new_fight(), id)
		_check(sub != "" and Skills.label(id) != "", "%s has a name and help" % id)
	_check(Overlay.banner_fits(Content.table("coach").tips.skills), "its tip fits the banner")
	_use()


## Lets the monster's attack play out (with health to spare), up to the menu of the next turn.
func _through_dodge(flow) -> void:
	var s = flow.state
	s.max_hp = 999
	s.hp = 999
	for i in 400:
		if s.stage == "social":
			await flow.press("cancel") # keep the action while testing the underlying skill turn
		if s.stage == "menu":
			return
		if s.stage == "wait" and s.hint == "ANY KEY CONTINUE":
			await flow.press("confirm")
		await flow.tick(flow.clock + 100.0)


## Walk the party onto the stairs, as the last step of a floor does.
func _reach_stairs(flow) -> void:
	var s = flow.state
	var stairs: Vector2i = s.floor_map.stairs
	for i in 4:
		var from: Vector2i = stairs - s.floor_map.DIRS[i]
		if s.floor_map.is_open(from):
			s.cell = from
			s.facing = i
			break
	for m in s.floor_map.monsters:
		if m.cell == stairs:
			m.gone = "slain"
	await flow.press("up")


func _real_floors() -> void:
	var flow = _flow(11)
	await flow.new_run()
	var s = flow.state
	s.hp = 5
	s.gold = 3
	s.tally.spared = 2
	var Ally = load("res://src/game/ally.gd")
	s.allies.append(Ally.make("slime", "GLOB", 70.0))
	await _reach_stairs(flow)
	_check(s.stage == "end" and not s.run_over, "the first stairs don't end the run")
	var first_floor = s.floor_map
	await flow.press("1")
	_check(flow.state == s and s.stage == "explore" and s.depth == 2, "GO DOWN goes to B2F (B%dF, %s)" % [s.depth, s.stage])
	_check(s.floor_map != first_floor and s.cell == s.floor_map.start, "on a new floor, at its start")
	_check(s.gold >= 3 and s.tally.spared == 2 and s.allies.size() == 1, "gold, the tally and the party came along")
	_check(s.hp >= 5 + Floors.rest_heal(), "and the way down rests you a little (%d)" % s.hp)
	_check(s.lines[0].text.begins_with("B2F"), "the log names the floor (%s)" % s.lines[0].text)
	await _reach_stairs(flow)
	await flow.press("1")
	_check(s.depth == 3, "the second stairs lead to B3F")
	var saved: Dictionary = s.to_dict()
	var loaded = State.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(loaded != null and loaded.depth == 3 and loaded.run_seed == s.run_seed, "a save keeps the depth and the run's seed")

	var again = _flow(11)
	await again.new_run()
	await _reach_stairs(again)
	await again.press("1")
	var other = _flow(11)
	await other.new_run()
	other.rng.real() # the fights drew differently
	await _reach_stairs(other)
	await other.press("1")
	_check(again.state.floor_map.grid == other.state.floor_map.grid, "the same seed makes the same B2F, whatever the fights drew")
	var deeper: int = Floors.plan(3).champion.hp
	_check(deeper > Floors.plan(1).champion.hp and Floors.plan(Floors.run_floors()).champion.name == "VEXALITH", "the champions grow up to Vexalith on the last floor")

	s = again.state
	s.depth = Floors.run_floors()
	s.allies.append(load("res://src/game/ally.gd").make("slime", "GLOB", 70.0))
	await _reach_stairs(again)
	_check(s.stage == "end" and s.run_over, "with a friend, the last floor's stairs end the run")
	_the_run_says_what_it_earned(s)
	var ended = s
	await again.press("1")
	_check(again.state != ended and again.state.depth == 1, "and NEW RUN starts over on B1F")
	_use()


## The practice floor before B1F asked for by a first run, and then a run like any other from B1F.
func _practice() -> void:
	var flow = _flow(12)
	await flow.new_run()
	_check(not flow.state.practice and flow.state.floor_map.monsters.back().boss, "a run starts on B1F unless the practice floor is asked for")
	flow = _flow(12)
	await flow.new_run(true)
	var s = flow.state
	var f = s.floor_map
	_check(s.practice and s.depth == 1 and flow.coach.seen.has(flow.PRACTICE_SEEN), "asked for, the run starts on the practice floor, and it counts as seen")
	_check(f.monsters.size() == 1 and not f.monsters[0].boss and f.monsters[0].species == "slime" and f.monsters[0].max_hp == int(Practice.table().foe.hp), "one small slime and no champion")
	_check(f.is_open(f.start) and f.is_open(f.stairs) and f.start != f.stairs, "its start and stairs are open cells")
	_check(f.pickups.size() == 1 and f.pickups[0].item == str(Practice.table().item), "something to pick up on the way")
	_check(s.cell == f.start and f.is_open(f.start + FloorMap.DIRS[s.facing]), "you start facing down the corridor")
	_check(s.lines.any(func(l): return l.text == Practice.line("line")), "the log says where you are")
	_check(Hud.log_fits(s.lines, 760.0) == s.lines.size(), "and it fits a narrow log")
	var saved = State.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	_check(saved != null and saved.practice and saved.floor_map.size == f.size, "a save made on it loads back on it")
	var old: Dictionary = s.to_dict()
	old.erase("practice")
	_check(not State.from_dict(JSON.parse_string(JSON.stringify(old))).practice, "and an old save, with no word of it, is on a real floor")
	var mercy: float = await flow.mind.mercy(f.monsters[0])
	_check(mercy > 0.2 and mercy < 0.5, "the slime is shy, not yet ready to be spared (%.2f)" % mercy)
	var met = _flow(12)
	await met.new_run(true)
	met.state.banner = null
	await met.go("intro", {"foe": met.state.floor_map.monsters[0]})
	_check(met.coach.seen.has("shy") and met.state.banner != null and met.state.banner.text == str(Content.table("coach").tips.shy), "meeting it, a tip says to ACT and SPARE")
	_check(Hud.log_fits([State.sys_line(str(Content.table("coach").tips.shy))], 760.0) == 1, "and the tip is short")
	_use()
	f.monsters[0].gone = "spared" # the fight is any fight's; this is about the way through
	var walked := 0
	while s.stage == "explore" and walked < 40:
		if not f.is_open(s.cell + FloorMap.DIRS[s.facing]):
			await flow.press("right")
		else:
			await flow.press("up")
			walked += 1
	_check(s.stage == "end" and not s.run_over, "the corridor leads to its stairs (%s after %d steps)" % [s.stage, walked])
	_check(s.items.has(str(Practice.table().item)), "picking up what lay on the way")
	_check(s.menu.size() == 2 and s.menu[0].label == "GO DOWN" and s.menu[0].sub == Practice.line("down_sub"), "its stairs offer only the way to B1F")
	s.hp = 3
	await flow.press("1")
	_check(s.stage == "explore" and not s.practice and s.depth == 1 and s.floor_map.monsters.back().boss, "and lead to B1F with its champion")
	_check(s.hp == s.max_hp, "rested")
	var plain = _flow(12)
	await plain.new_run()
	_check(s.floor_map.grid == plain.state.floor_map.grid, "the same B1F the seed makes without it")
	_check(s.lines[0].text.begins_with("B1F"), "and it is named as usual (%s)" % s.lines[0].text)
	for words in [["floor=3"], ["meet=slime"], ["notips"]]:
		flow = _flow(12, words)
		await flow.new_run(true)
		_check(not flow.state.practice and not flow.coach.seen.has(flow.PRACTICE_SEEN), "%s: no practice floor" % " ".join(words))
	_use()


## On the practice floor Wick is the one who teaches: her welcome (after the opening film, the words that follow it), then how to
## walk, then the tips in her voice; on a real floor the tips are tips again.
func _practice_wick() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound"])) # with her: BASE's no-wick is off for this one
	var coach: Dictionary = Content.table("coach")
	var friend := Floors.friend()
	for words in [coach.tips.walk, friend.line_film] + coach.wick.values():
		_check(Overlay.banner_fits(str(words)), "'%s' fits the banner" % words)
	_check(coach.wick.keys().all(func(id): return coach.tips.has(id)), "every tip she words her own way has a plain one too")
	for film in [true, false]:
		var flow = Flow.new(Rng.new(12), LocalMind.new())
		flow.film_seen = film
		await flow.new_run(true)
		var seen := []
		var t: float = flow.clock
		for i in 80:
			t += 250.0
			await flow.tick(t)
			var b = flow.state.banner
			if b != null and (seen.is_empty() or seen.back() != [b.title, b.text]):
				seen.append([b.title, b.text])
		var texts: Array = seen.map(func(x): return x[1])
		var welcome: String = friend.line_film if film else friend.line
		_check(texts.has(welcome), "film seen %s: her welcome is the one that fits (%s)" % [film, texts])
		_check(texts.has(str(coach.wick.walk)) and texts.find(str(coach.wick.walk)) > texts.find(welcome), "then she says how to walk, after her welcome")
		_check(seen.filter(func(x): return x[1] == str(coach.wick.walk)).all(func(x): return x[0] == str(friend.title)), "and it is signed WICK")
		_check(not flow.film_seen, "the film's word is used up")
		flow.state.banner = null
		_check(flow.coach.say("item") and flow.state.banner.title == str(friend.title) and flow.state.banner.text == str(coach.wick.item), "on the practice floor a tip comes from her")
		flow.state.practice = false
		flow.state.banner = null
		_check(flow.coach.say("act") and flow.state.banner.title == "TIP" and flow.state.banner.text == str(coach.tips.act), "and from the next floor it is a tip again")
	var quiet = Flow.new(Rng.new(12), LocalMind.new())
	await quiet.new_run(false)
	var t2: float = quiet.clock
	for i in 80:
		t2 += 250.0
		await quiet.tick(t2)
	_check(not quiet.coach.seen.has("walk"), "off the practice floor she doesn't teach walking")
	_use()


## A fight with a monster that is already won over, at its menu.
func _at_menu(flow, species := "slime") -> Variant:
	await flow.new_run()
	var s = flow.state
	var m = s.floor_map.monsters.filter(func(x): return x.species == species and not x.boss).front()
	if m == null:
		m = s.floor_map.monsters[0]
	await flow.go("intro", {"foe": m})
	await flow.tick(flow.clock + 1000.0)
	if s.stage == "intro" and s.hint == "ANY KEY CONTINUE":
		await flow.press("confirm")
	return m


func _won_over(m) -> void:
	m.meters.friendliness = 100.0
	m.meters.anger = 0.0


func _recruiting() -> void:
	var flow = _flow(21)
	var m = await _at_menu(flow)
	var s = flow.state
	_check(s.stage == "menu", "a fight reaches its menu (%s)" % s.stage)
	_check(s.menu[2].sub.contains("raise the odds"), "SPARE says that ACTs move the odds (%s)" % s.menu[2].sub)
	_won_over(m)
	s.hp = 5
	s.gold = 3
	await flow.press("3")
	_check(s.stage == "ask" and m.gone == "spared", "a SPARE that lands asks you, not a second roll (%s)" % s.stage)
	_check(s.menu[0].label == "COME ALONG" and s.menu[0].sub.contains(Content.table("encounter").charms[m.species].name), "the question says what it brings (%s)" % s.menu[0].sub)
	await flow.press("1")
	_check(s.stage == "explore" and s.allies.size() == 1 and s.tally.recruited == 1, "COME ALONG: it joins, always")
	_check(s.banner != null and s.banner.title.contains("JOINS"), "joining puts a banner up (%s)" % str(s.banner))
	_check(s.hp > 5, "peace heals you a little (%d)" % s.hp)
	_check(s.allies[0].loyalty >= 31.0 and s.allies[0].loyalty <= 100.0, "an ally starts loyal (%.0f)" % s.allies[0].loyalty)

	flow = _flow(22)
	m = await _at_menu(flow)
	s = flow.state
	_won_over(m)
	s.hp = 5
	var gold: int = s.gold
	await flow.press("3")
	await flow.press("2")
	_check(s.stage == "explore" and s.allies.is_empty(), "GO IN PEACE: it does not join")
	_check(s.gold > gold and s.hp > 5, "and leaves a gift (%d gold, %d HP)" % [s.gold - gold, s.hp - 5])

	flow = _flow(23)
	m = await _at_menu(flow)
	s = flow.state
	var Ally = load("res://src/game/ally.gd")
	for i in 3:
		s.allies.append(Ally.make("rock", "R%d" % i, 70.0))
	_won_over(m)
	await flow.press("3")
	_check(s.stage == "ask" and s.menu.size() == 1 and s.menu[0].label == "GO IN PEACE", "a full party can only say goodbye")
	await flow.press("1")
	_check(s.allies.size() == 3, "and stays at three")

	flow = _flow(24)
	m = await _at_menu(flow)
	s = flow.state
	m.meters.friendliness = 0.0
	m.meters.anger = 20.0
	await flow.press("3")
	_check(m.gone == "" and s.stage == "wait", "a refused SPARE goes on with the fight (%s, %s)" % [m.gone, s.stage])
	_check(m.meters.anger == 20.0, "and doesn't anger it (%.0f)" % m.meters.anger)
	_check(s.lines[0].text.contains("isn't ready"), "and says what to do (%s)" % s.lines[0].text)

	# patience pays, and every kind of monster has a way to be befriended
	flow = _flow(30)
	m = await _at_menu(flow)
	var warm: float = m.meters.friendliness
	Feelings.warm_up(m, {"tone": "good"})
	_check(m.meters.friendliness > warm, "a monster you keep talking to warms up")
	warm = m.meters.friendliness
	Feelings.warm_up(m, {"tone": "bad"})
	_check(m.meters.friendliness == warm, "unless the words landed badly")
	m = await _at_menu(flow, "bandit")
	await flow.press("2")
	_check(flow.state.menu.any(func(i): return i.label == "TREAT IT AS AN EQUAL") or m.species != "bandit", "a bandit can be befriended without paying")

	# the mercy link
	flow = _flow(25)
	m = await _at_menu(flow)
	s = flow.state
	var moved := []
	flow.happened.connect(func(n, d): if n == "mercy_changed": moved.append(d))
	await flow.encounter.after_player([State.sys_line("x")], await flow.encounter.decide(m, [{"intent": "kindness", "w": 1.0}], "TEST"))
	_check(moved.size() == 1 and moved[0].to != moved[0].from, "a deed that moves mercy says so (%s)" % str(moved))
	_check(s.lines[0].text.contains("Mercy ") and s.lines[0].text.contains("->"), "in the log too (%s)" % s.lines[0].text)

	# party aid
	_check(Combat.strike(0.75, false, false, 2).damage == Combat.strike(0.75, false, false).damage + 2, "allies add to a strike")
	_check(Combat.party_guard(1) == 0 and Combat.party_guard(2) == 1, "two allies take the edge off a hit")
	flow = _flow(26)
	m = await _at_menu(flow)
	s = flow.state
	s.allies = [Ally.make("rock", "A", 70.0), Ally.make("rock", "B", 70.0)]
	await flow.press("1")
	_check(s.hint.contains("PARTY +2"), "the strike bar names the party's help (%s)" % s.hint)

	# the last door
	flow = _flow(27)
	await flow.new_run()
	s = flow.state
	s.depth = Floors.run_floors()
	await _reach_stairs(flow)
	_check(s.stage == "end" and not s.run_over and s.menu[0].label == "TURN BACK", "alone, the last door stays shut")
	await flow.press("1")
	_check(s.stage == "explore" and s.cell == s.floor_map.stairs, "TURN BACK: back to the floor")
	s.cell = s.floor_map.start
	await _reach_stairs(flow)
	await flow.press("2")
	_check(s.stage == "end" and s.run_over and s.lines[0].who == "THE LONELY WAY OUT", "LEAVE ALONE ends the run, not cleared (%s)" % s.lines[0].who)
	_check(s.menu[0].label == "NEW RUN", "and offers a new run")

	flow = _flow(29, ["no-last-door"])
	await flow.new_run()
	flow.state.depth = Floors.run_floors()
	await _reach_stairs(flow)
	_check(flow.state.run_over, "no-last-door: the last stairs end the run alone")
	_use()


func _story() -> void:
	var flow = _flow(31)
	await flow.new_run()
	var s = flow.state
	_check(s.lines[0].text.contains("Last Door") and s.lines[1].text.contains(Floors.plan(1).champion.name), "a run says why you are here and who holds the floor (%s)" % s.lines[0].text)
	_check(s.banner != null and s.banner.title == "THE LAST DOOR", "and puts it on the picture")
	_check(s.floors_of == Floors.run_floors(), "the header can count the floors")
	_check(Floors.premise().line.begins_with("You "), "it says who you are: %s" % Floors.premise().line)
	var told := ""
	for c in Content.table("floors").champions:
		told += str(c.lore) + " "
	for clan in Content.table("clans").clans.values():
		_check(told.contains(str(clan.name).trim_prefix("The ")) or Floors.premise().line.contains(str(clan.name).trim_prefix("The ")), "and the story knows %s" % clan.name)
	_check(Hud.log_fits(s.lines, 1100.0) == s.lines.size(), "and the log has room for it at the window's width")
	_check(Hud.log_fits(s.lines, 760.0) == s.lines.size(), "and at a narrow one")
	await _reach_stairs(flow)
	await flow.press("1")
	_check(s.lines[0].text.contains(Floors.plan(2).champion.name), "each floor says who holds it (%s)" % s.lines[0].text)
	for depth in range(1, Floors.run_floors() + 1):
		var line: String = flow._arrival()[0].text
		s.depth = depth
		line = flow._arrival()[0].text
		_check(Hud.log_fits([State.sys_line(line)], 760.0) == 1, "B%dF's line fits the log" % depth)
	_use()


func _tutorial() -> void:
	var flow = _flow(33, ["no-heavy-strike"])
	await flow.new_run()
	var s = flow.state
	s.banner = null
	var shown := []
	flow.happened.connect(func(n, d): if n == "coach": shown.append(d.id))
	var m = s.floor_map.monsters[0]
	await flow.go("intro", {"foe": m})
	await flow.tick(flow.clock + 1000.0)
	await flow.press("confirm")
	_check(shown == ["menu"] and s.banner.title == "TIP", "the first menu brings up one tip (%s)" % str(shown))
	await flow.press("2")
	_check(shown == ["menu"], "a tip waits while another is showing")
	flow.clock += 10000.0
	await flow.press("cancel")
	await flow.press("2")
	_check(shown == ["menu", "act"], "and comes up the next time (%s)" % str(shown))
	flow.clock += 10000.0
	await flow.press("cancel")
	_check(shown.count("menu") == 1, "a tip is shown once")
	flow.coach.enabled = false
	flow.clock += 10000.0
	await flow.press("1")
	_check(not shown.has("strike"), "the TIPS setting skips them")
	var later = _flow(34, ["no-heavy-strike"])
	later.coach.seen = {"menu": true}
	await later.new_run()
	later.state.banner = null
	await later.go("intro", {"foe": later.state.floor_map.monsters[0]})
	await later.tick(later.clock + 1000.0)
	_check(later.state.banner == null, "a tip seen in an earlier run stays quiet")
	for id in Content.table("coach").tips:
		_check(Overlay.banner_fits(Content.table("coach").tips[id]), "the tip '%s' fits the banner" % id)
	_check(Overlay.banner_fits(Floors.premise().door) and Overlay.banner_fits(Floors.premise().banner), "and so does the story's")
	for species in Content.table("encounter").charms:
		var charm: Dictionary = Content.table("encounter").charms[species]
		_check(Overlay.banner_fits("%s: %s" % [charm.name, charm.text]), "and %s's charm" % species)
	_check(Pace.opening(0) < Pace.opening(1) and Pace.opening(1) < 1.0 and Pace.opening(5) == 1.0, "the first fights go slower")
	# the menu teaches one more each time it comes up, FLEE last
	flow = _flow(36)
	await flow.new_run()
	flow.state.banner = null
	await flow.go("intro", {"foe": flow.state.floor_map.monsters[0]})
	flow.coach.seen = {"menu": true, "heavy": true, "act": true, "strike": true}
	flow.state.banner = null
	flow.coach._on_stage("menu")
	_check(flow.coach.seen.has("flee"), "FLEE gets a tip too")
	# a foe that meets you with its face already gone (warmth) gets a tip saying why, or it reads like a drawing that lost its eyes
	for slain in [0, 6]:
		flow = _flow(38)
		await flow.new_run()
		flow.state.banner = null
		flow.state.tally.slain = slain
		var plain = flow.state.floor_map.monsters.filter(func(m): return not m.boss)[0]
		await flow.go("intro", {"foe": plain})
		var want: bool = slain > 0
		_check(flow.coach.seen.has("blank") == want, "%d slain: %s" % [slain, "a blank face is explained" if want else "no word of blank faces"])
	# the TIPS setting skips the slow start as well: only the first fights' pace knows about it
	var paces := {}
	for tips in [true, false]:
		flow = _flow(37)
		await flow.new_run()
		flow.coach.enabled = tips
		flow.state.banner = null
		flow.state.foe = flow.state.floor_map.monsters[0]
		flow._stages["dodge"].enter(flow, {})
		paces[tips] = flow.state.dodge.pace
	_check(paces[true] < paces[false], "with TIPS off the first fights aren't slowed (%.2f, %.2f)" % [paces[true], paces[false]])
	flow = _flow(35, ["notips"])
	await flow.new_run()
	flow.state.banner = null
	await flow.go("intro", {"foe": flow.state.floor_map.monsters[0]})
	await flow.tick(flow.clock + 1000.0)
	_check(flow.state.banner == null, "notips: no tips")
	# walking heals
	flow = _flow(36)
	await flow.new_run()
	s = flow.state
	s.hp = 5
	s.steps = 5
	for i in 4:
		if s.floor_map.is_open(s.cell + s.floor_map.DIRS[s.facing]) and s.floor_map.monster_at(s.cell + s.floor_map.DIRS[s.facing]) == null:
			break
		s.turn(1)
	await flow.press("up")
	_check(s.hp == 6, "the sixth step brings a point of health back (%d)" % s.hp)
	_use()


func _mood_cues() -> void:
	var flow = _flow(37)
	var m = await _at_menu(flow)
	var heard := []
	flow.happened.connect(func(n, d): if n in ["mood", "wants_join"]: heard.append(n))
	m.meters.friendliness = 100.0
	m.meters.anger = 0.0
	flow.encounter.known_mercy = 0.1
	await flow.encounter.decide(m, [{"intent": "kindness", "w": 1.0}], "TEST")
	_check(heard == ["mood", "wants_join"], "a deed shows a mood, and crossing into likely mercy calls out (%s)" % str(heard))
	heard.clear()
	await flow.encounter.decide(m, [{"intent": "kindness", "w": 1.0}], "TEST")
	_check(heard == ["mood"], "only when it crosses (%s)" % str(heard))
	var view = Overlay.new()
	view.state = flow.state
	view.clock_ms = 1000.0
	flow.state.mind_rows = [{"id": "mercy", "answer": 0.9}]
	_check(view.bubble().get("text", "") == "WANNA JOIN?", "the bubble asks when mercy is likely (%s)" % str(view.bubble()))
	view.emote("good")
	_check(view.bubble().get("tone", "") == "good", "a deed's mood shows first")
	view.clock_ms = 3000.0
	_check(view.bubble().has("text"), "and then the question comes back")
	flow.state.mind_rows = [{"id": "mercy", "answer": 0.2}]
	_check(view.bubble().is_empty(), "with mercy unlikely there is no bubble")
	view.free()
	_use()


func _clear_hp() -> void:
	var flow = _flow(39)
	var m = await _at_menu(flow)
	var s = flow.state
	var view = Overlay.new()
	view.state = s
	_check(view.foe_bar() == Overlay.HEAD_BAR, "the foe's health sits over its head")
	s.dodge = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {})
	_check(view.foe_bar() != Overlay.HEAD_BAR, "and moves aside for the dodge box")
	s.dodge = null
	_check(Overlay.ghost_after(1.0, 0.5, 0.5) > 0.5 and Overlay.ghost_after(1.0, 0.5, 0.5) < 1.0, "the trail behind the damage catches up slowly")
	_check(Overlay.ghost_after(0.2, 0.5, 0.1) == 0.5, "and doesn't lag behind healing")
	m.meters = {"friendliness": 10.0, "anger": 90.0, "fear": 0.0}
	_check(Overlay.mood_word(m)[0] == "ANGRY", "an angry foe says so")
	m.meters = {"friendliness": 10.0, "anger": 0.0, "fear": 90.0}
	_check(Overlay.mood_word(m)[0] == "AFRAID", "a frightened one too")
	m.meters = {"friendliness": 100.0, "anger": 0.0, "fear": 0.0}
	_check(Overlay.mood_word(m)[0] == "FRIENDLY", "and a friendly one")
	view.free()
	var bar = Hud.new()
	bar.part = Hud.Part.STATUS
	bar.state = s
	bar._process(0.016)
	_check(bar.trend() == 0, "your health bar has no arrow at rest")
	s.hp -= 3
	bar._process(0.016)
	_check(bar.trend() == -1, "an arrow when it drops")
	s.hp += 1
	bar._process(0.016)
	_check(bar.trend() == 1, "the other way when it rises")
	bar._process(2.0)
	_check(bar.trend() == 0, "and it goes away")
	bar.free()
	_use()


func _reveal() -> void:
	var flow = _flow(40)
	var m = await _at_menu(flow)
	var s = flow.state
	var clues: Array = m.clues()
	await flow.press("2")
	await flow.press("1")
	var first: String = s.lines[0].text
	_check(not first.contains("likes") and not first.contains("hates"), "CHECK doesn't give away what it likes (%s)" % first)
	if not clues.is_empty():
		_check(first.contains(clues[0]) and m.checks == 1, "it reads one thing at a time (%s)" % first)
	for i in 8:
		await flow.press("2")
		await flow.press("1")
	_check(s.lines[0].text.contains("read all you can"), "and then says there's no more (%s)" % s.lines[0].text)
	_check(m.known_traits.size() == m.traits.size(), "by then the traits are known")

	flow = _flow(41)
	m = await _at_menu(flow)
	var card: String = Tips.found_text(m)
	_check(card.contains("???") and not m.traits.any(func(t): return card.contains(t)), "at first the card hides its traits (%s)" % card)
	_check(Reveal.learn(m, "kindness", "good") == ["It likes kindness."] or Reveal.found(m, Reveal.LIKES) == ["kindness"], "a liked thing is found by trying")
	_check(Reveal.learn(m, "kindness", "bad").is_empty(), "and only once")
	Reveal.learn(m, "insult", "bad")
	card = Tips.found_text(m)
	_check(card.contains("Likes kindness") and card.contains("Hates insults"), "the card remembers (%s)" % card)
	_check(Reveal.learn(m, "joke", "odd").all(func(t): return not t.contains("likes")), "a puzzled look teaches nothing about its taste")

	var entry := {"species": "snake", "genre": "shadow", "hp": 22}
	var snake = Monster.given(entry, Vector2i(1, 1), "TEST", ["secretive"], {"friendliness": 10.0, "anger": 10.0, "fear": 10.0})
	var taught: Array = Reveal.learn(snake, "question", "bad")
	_check(taught.has("It is secretive."), "a trait that cares about the deed shows itself (%s)" % str(taught))
	var again = Monster.from_dict(JSON.parse_string(JSON.stringify(snake.to_dict())))
	_check(again.known_traits == ["secretive"] and again.tried.has("question"), "and a save keeps what was found")
	for sp in Content.table("species"):
		var spoken: Dictionary = Content.species(sp).lines
		_check(not spoken.get("pleased", []).is_empty() and not spoken.get("stung", []).is_empty(), "%ss answer a deed in their own words" % sp)
		for kind in Encounter.REACTION_LINES.values():
			_check(not spoken.get(kind, []).is_empty(), "%ss have a word for every way a deed lands (%s)" % [sp, kind])

	# it answers what you did to it
	flow = _flow(42)
	m = await _at_menu(flow)
	s = flow.state
	await flow.encounter.after_player([State.sys_line("x")], {"pacified": false, "pressure": 1.0, "told": true, "feeling": {"tone": "good"}})
	_check(s.lines.any(func(l): return l.kind == "say" and Content.species(m.species).lines.pleased.any(func(p): return l.text.contains(p.left(8)))), "a liked deed gets a pleased line (%s)" % str(s.lines))
	await flow.encounter.after_player([State.sys_line("x")], {"pacified": false, "pressure": 1.0, "told": true, "feeling": {"tone": "fear"}})
	_check(s.lines.any(func(l): return l.kind == "say" and Content.species(m.species).lines.scared.any(func(p): return l.text.contains(p.left(8)))), "and a frightening one a scared line")
	_use()


func _chat() -> void:
	var flow = _flow(44)
	var m = await _at_menu(flow, "slime")
	var s = flow.state
	var greeted: int = s.chat.size()
	_check(greeted >= 1 and s.chat[0].who == m.name, "what the foe says goes in the chat (%s)" % str(s.chat))
	await flow.press("2")
	await flow.press(str(s.menu.size()))
	_check(s.stage == "talk" and s.hint.contains("ASK ABOUT THE FLOOR"), "the talk box says what typing is for (%s)" % s.hint)
	var sent := []
	var listening_then := []
	flow.happened.connect(func(n, d):
		if n == "said":
			sent.append(d.text)
			listening_then.append(s.listening))
	await flow.submit_text("you seem kind")
	_check(sent == ["you seem kind"], "a sent line is announced")
	_check(not s.listening, "and the monster stops listening once it has answered")
	_check(s.chat.any(func(c): return c.who == "YOU" and c.text == "you seem kind"), "the chat keeps what you said")
	var count: int = s.chat.size()
	s.say(s.lines)
	_check(s.chat.size() == count, "a line said again isn't kept twice")
	var saved = State.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	_check(saved.chat.size() == count, "a save keeps the talk")
	var damaged: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	damaged.chat = "words"
	_check(State.from_dict(damaged).chat.is_empty(), "and a damaged one is left out")
	for i in State.CHAT_MAX + 5:
		s.add_chat("YOU", "x")
	_check(s.chat.size() == State.CHAT_MAX, "the talk has a limit")

	var view = Overlay.new()
	view.state = s
	s.stage = "menu"
	s.say([State.speech(m.name, "Hello there."), State.sys_line("It waits.")])
	_check(view.speech().get("text", "") == "Hello there.", "the foe's line gets the speech box")
	view.clock_ms = 100000.0
	s.listening = true
	_check(view.bubble().get("text", "").begins_with("."), "while it takes the words in, dots over its head")
	s.listening = false
	view.send_words("hi")
	_check(view.bubble().get("text", "").begins_with("."), "even for a moment when the answer is quick")
	view.clock_ms += 2000.0
	_check(view.bubble().get("text", "") != ".", "and then they go")
	s.stage = "dodge"
	_check(view.speech().is_empty(), "no speech box over a dodge")
	view.free()
	var long_line := "x ".repeat(110)
	_check(Overlay.speech_px(long_line) == Overlay.SPEECH_SIZES[-1], "the longest lines write smaller")
	var body = load("res://src/view/fonts.gd").body()
	for sp in Content.table("species"):
		for kind in Content.species(sp).lines:
			for l in Content.species(sp).lines[kind]:
				var px: int = Overlay.speech_px(l)
				if body.get_multiline_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, Overlay.SPEECH.size.x - 12.0, px).y > Overlay.SPEECH.size.y - 16.0:
					_check(false, "a line doesn't fit the speech box: %s" % l)
	_check(true, "every monster line fits the speech box")
	var hint_line := "It says it might as well tell you: the stairs are that way, past the third turn, and the champion waits beyond."
	_check(body.get_multiline_string_size(hint_line, HORIZONTAL_ALIGNMENT_LEFT, Overlay.SPEECH.size.x - 12.0, Overlay.speech_px(hint_line)).y <= Overlay.SPEECH.size.y - 16.0, "and so does a long answer about the floor")
	# what a monster says about the floor is put together as it speaks: however it comes out, it fits
	var longest := ""
	for seed_n in 30:
		var f = FloorGen.generate(Rng.new(seed_n + 1), Floors.plan(1))
		var asker = f.monsters[0]
		var other = f.monsters[1]
		for q in ["Where are the stairs?", "Where is the champion?", "What does %s want?" % other.name, "Where is %s?" % other.name, "Who holds this floor?", "What are you?"]:
			var said: String = Hints.answer(f, asker.cell, asker, q)
			longest = said if said.length() > longest.length() else longest
			if body.get_multiline_string_size(said, HORIZONTAL_ALIGNMENT_LEFT, Overlay.SPEECH.size.x - 12.0, Overlay.speech_px(said)).y > Overlay.SPEECH.size.y - 16.0:
				_check(false, "an answer doesn't fit the speech box: %s" % said)
	_check(longest != "", "every answer about the floor fits the speech box, the longest: %s" % longest)
	var tips = Tips.new()
	tips.state = s
	s.stage = "menu"
	_check(tips.targets().has("chat"), "the info key can open the talk so far")
	tips.free()
	_use()


## The monster that catches you strikes first; the toll on the third stairs; the text size.
func _late_decisions() -> void:
	# ambush
	var flow = _flow(61)
	await flow.new_run()
	var s = flow.state
	var m = s.floor_map.monsters[0]
	s.floor_map.monsters = [m]
	s.floor_map.merchant = {}
	s.floor_map.quester = {}
	m.species = "snake"
	m.lurking = false
	m.hold = 0
	var d := 0
	while not s.floor_map.is_open(s.cell + FloorMap.DIRS[d]):
		d += 1
	m.cell = s.cell + FloorMap.DIRS[d]
	s.banner = null
	var caught: bool = await flow._stages["explore"]._monsters_move(flow)
	_check(caught and s.stage == "intro" and s.foe == m, "a monster next to you catches you")
	await flow.tick(flow.clock + 5000.0)
	_check(s.stage == "intro" and s.hint == "ANY KEY CONTINUE", "the greeting waits for a key")
	await flow.press("right")
	_check(s.stage == "dodge", "and strikes first (%s)" % s.stage)
	_check(s.lines.any(func(l): return l.text.contains("strikes first")), "and the log says so")
	# the toll
	var toll: Dictionary = Floors.toll()
	flow = _flow(62)
	await flow.new_run()
	s = flow.state
	s.depth = int(toll.depth)
	s.allies = [Ally.make("slime", "GLOP", 60.0), Ally.make("snake", "HISS", 60.0)]
	s.hp = 20
	await _reach_stairs(flow)
	_check(s.stage == "end" and s.menu[0].label == toll.hold_label and s.menu.size() == 4, "the gate asks who stays (%s)" % str(s.menu.map(func(i): return i.label)))
	_choices_over_the_picture(s, "gate", 3, 1)
	_check(Hud.log_fits(s.lines, 760.0) == s.lines.size(), "and the log has room for it")
	await flow.press("2")
	_check(s.allies.size() == 1 and s.allies[0].name == "HISS" and s.left_behind == ["GLOP"], "a friend left at the chain stays there")
	_check(s.allies[0].loyalty == 60.0 + float(toll.loyalty), "and the others saw")
	_check(s.menu[-1].label == "MAIN MENU" and s.menu[0].label != toll.hold_label, "and the way down is open")
	_check(s.vignette == "stairs", "and the picture is the stairs now, not the gate (%s)" % s.vignette)
	_check(State.from_dict(JSON.parse_string(JSON.stringify(s.to_dict()))).left_behind == ["GLOP"], "a save remembers who")
	var ended := {"route": "x", "text": "y", "tail": "z"}
	flow._stages["end"]._finish(flow, ended)
	_check(s.lines[-1].text.contains("GLOP"), "and so does the end of the run (%s)" % s.lines[-1].text)
	_choices_over_the_picture(s, "ending", 0, 2) # a run's end has nothing but buttons: no card to hold the question off them
	flow = _flow(63)
	await flow.new_run()
	s = flow.state
	s.depth = int(toll.depth)
	s.allies = [Ally.make("slime", "GLOP", 60.0)]
	s.hp = 8
	await _reach_stairs(flow)
	await flow.press("1")
	_check(s.allies.size() == 1 and s.left_behind.is_empty() and s.hp == 1, "holding it yourself costs health, and never the last of it (%d)" % s.hp)
	for words in [["no-toll"], []]:
		flow = _flow(64, words)
		await flow.new_run()
		s = flow.state
		s.depth = int(toll.depth) if not words.is_empty() else int(toll.depth) + 1
		s.allies = [Ally.make("slime", "GLOP", 60.0)]
		await _reach_stairs(flow)
		_check(s.menu[0].label != toll.hold_label, "no gate %s" % ("with no-toll" if not words.is_empty() else "on another floor"))
	flow = _flow(65)
	await flow.new_run()
	s = flow.state
	s.depth = int(toll.depth)
	s.allies = []
	await _reach_stairs(flow)
	_check(s.menu[0].label != toll.hold_label, "and none for someone with nobody to leave")
	# text size
	var line := "A short line."
	Overlay.large_text = false
	var normal: int = Overlay.speech_px(line)
	Overlay.large_text = true
	_check(Overlay.speech_px(line) > normal, "a large text size writes speech larger")
	var long_said := "It says it might as well tell you: the stairs are that way, past the third turn, and the champion waits beyond."
	var body: Font = load("res://src/view/fonts.gd").body()
	_check(body.get_multiline_string_size(long_said, HORIZONTAL_ALIGNMENT_LEFT, Overlay.SPEECH.size.x - 12.0, Overlay.speech_px(long_said)).y <= Overlay.SPEECH.size.y - 16.0, "and a long answer still fits")
	Overlay.large_text = false
	var three := [State.sys_line("One line."), State.sys_line("Another line."), State.sys_line("A third line, and it matters.")]
	var one := [State.sys_line("One line.")]
	Hud.large_text = false
	_check(Hud.log_px(one, 1100.0) == Hud.LOG_PX, "the log keeps its size by default")
	Hud.large_text = true
	_check(Hud.log_px(one, 1100.0) > Hud.LOG_PX, "a large text size writes the log larger")
	_check(Hud.log_fits(three, 1100.0, Hud.log_px(three, 1100.0)) == 3, "and never at the cost of a line")
	Hud.large_text = false
	var settings = load("res://src/menu/settings.gd")
	_check(settings.valid("text_size", "large") and not settings.valid("text_size", "huge"), "the setting has two sizes")
	_use()


## The measurement issue #26 asks for: over 1,000 seeds, the fewest monster cells a walk from the start to the stairs
## must enter. With the champion on the stairs that is never zero; with it back in its hall most floors can still be
## walked past, which is the version the plan can still compare. The target is zero floors with no fight and no seed
## unreachable: the stairs are reached through the champion's cell, never around it.
func _gate() -> void:
	const SEEDS := 1000
	var spread := {}
	var blocked := 0
	var unreachable := 0
	for i in SEEDS:
		var f = FloorGen.generate(Rng.new(i), Floors.plan(1).merged({"boss_at_exit": true}))
		var champion = f.monsters.back()
		var n: int = Floors.fights_required(f)
		spread[n] = spread.get(n, 0) + 1
		if n < 0:
			unreachable += 1
		if champion.cell == f.stairs and n >= 1:
			blocked += 1
	print("features_test: fights required with the champion on the stairs: %s" % str(spread))
	_check(unreachable == 0, "the champion at the exit leaves the stairs reachable on every floor (%d unreachable)" % unreachable)
	_check(spread.get(0, 0) == 0, "no floor can be finished without a fight (%d of %d need none)" % [spread.get(0, 0), SEEDS])
	_check(blocked == SEEDS, "the champion holds the stairs on every floor (%d of %d)" % [blocked, SEEDS])
	spread = {}
	for i in SEEDS:
		var f = FloorGen.generate(Rng.new(i), Floors.plan(1))
		var n: int = Floors.fights_required(f)
		spread[n] = spread.get(n, 0) + 1
	print("features_test: fights required with the champion in its hall: %s" % str(spread))
	_check(spread.get(0, 0) > SEEDS / 2, "with the champion back in its hall most floors can still be walked with no fight, as they always could (%d of %d)" % [spread.get(0, 0), SEEDS])
	for seed_value in [0, 1, 5, 42, 999]:
		var a = FloorGen.generate(Rng.new(seed_value), Floors.plan(1).merged({"boss_at_exit": true}))
		var b = FloorGen.generate(Rng.new(seed_value), Floors.plan(1))
		var same: bool = a.grid == b.grid and a.stairs == b.stairs and a.start == b.start and a.monsters.size() == b.monsters.size()
		for j in a.monsters.size() - 1: # the champion is last; only it moves
			same = same and a.monsters[j].cell == b.monsters[j].cell and a.monsters[j].species == b.monsters[j].species
		_check(same and a.monsters.back().cell == a.stairs and b.monsters.back().cell != b.stairs, "seed %d: placing the champion at the exit moves only it" % seed_value)

	var flow = _flow(45)
	await flow.new_run()
	var s = flow.state
	var boss = s.floor_map.monsters.back()
	_check(boss.cell == s.floor_map.stairs, "a run's champion stands on the stairs")
	_check(s.floor_map.is_open(boss.cell), "on an open cell")
	await _step_onto(flow, boss.cell)
	_check(s.stage == "intro" and s.foe == boss and s.cell != s.floor_map.stairs, "walking at the stairs meets it first (%s)" % s.stage)
	var map = load("res://src/view/automap.gd").new()
	map.state = s
	s.seen = {}
	for other in s.floor_map.monsters:
		other.hunting = false # (a hunter shows wherever it is)
		other.last_seen = Vector2i(-1, -1) # (and the others where you last saw them)
	_check(map.monster_marks().is_empty(), "the map keeps it hidden until seen")
	s.seen[boss.cell] = true
	_check(map.monster_marks().size() == 1, "and shows it after")
	map.free()

	var hp: int = s.max_hp
	s.hp = 5
	await flow.tick(flow.clock + 1000.0)
	await flow.press("confirm")
	await flow.encounter.defeat(boss, "slain")
	_check(s.max_hp == hp + Floors.boss_reward().max_hp and s.hp == 5 + Floors.boss_reward().heal, "beating a champion leaves you stronger (%d/%d)" % [s.hp, s.max_hp])
	_check(s.banner != null and s.banner.text.contains("stronger"), "and says so")
	await flow.tick(flow.clock + 1000.0)
	if s.stage == "keepsake": # it left keepsakes (the feature keepsakes has checks of its own)
		await flow.press("1")
	await _step_onto(flow, s.floor_map.stairs)
	_check(s.stage == "end", "with it gone the stairs are open (%s)" % s.stage)

	flow = _flow(46)
	var m = await _at_menu(flow)
	s = flow.state
	m.hp -= 5
	var was_anger: float = m.meters.anger
	var was_hp: int = m.hp
	var gold: int = s.gold
	await flow.press("4")
	_check(s.gold == gold - Floors.flee_cost().gold, "backing away costs gold (%d)" % s.gold)
	_check(m.hp == was_hp and m.meters.anger > was_anger, "the monster keeps its wounds and holds a grudge")
	flow = _flow(47, ["no-flee-cost"])
	m = await _at_menu(flow)
	s = flow.state
	m.hp -= 5
	gold = s.gold
	await flow.press("4")
	_check(s.gold == gold and m.hp == m.max_hp, "no-flee-cost: it costs nothing and heals it, as before")
	_use()


func _clans() -> void:
	_check(Clans.of("slime") != "" and Clans.of("bandit") != "" and Clans.of("slime") != Clans.of("bandit"), "the kinds of monster belong to different clans")
	for species in Content.table("species"):
		_check(Clans.of(species) != "", "%s has a clan" % species)
		for kind in ["kin_spared", "kin_slain", "side_spared", "side_slain"]:
			_check(not Content.species(species).lines.get(kind, []).is_empty(), "%s has %s lines" % [species, kind])

	# the test the issue asks for: spare one, and a later one of the same group reacts and starts in another mood
	var flow = _flow(31)
	var goo = await _at_menu(flow)
	var s = flow.state
	var others: Array = s.floor_map.monsters.filter(func(x): return x.species == "slime" and x != goo)
	var later = others[0] if not others.is_empty() else Monster.make(Rng.new(3), Content.table("encounter").roster.filter(func(e): return e.species == "slime")[0], s.cell)
	var calm: float = later.meters.friendliness
	var cross: float = later.meters.anger
	var calm_odds: float = LocalMind.new().mercy(later)
	_check(s.reputation.is_empty() and s.deeds.is_empty(), "a run starts with nothing to answer for")
	_won_over(goo)
	s.selected = 2
	await flow.encounter.defeat(goo, "spared")
	var clan: String = Clans.of("slime")
	_check(s.reputation.get(clan, 0.0) > 0.0, "sparing one raises its clan's opinion (%s)" % str(s.reputation))
	_check(s.deeds.size() == 1 and s.deeds[0].deed == "spared" and s.deeds[0].who == goo.name, "the run records what was done to whom (%s)" % str(s.deeds))
	await flow.go("explore", {"lines": []})
	var seen := []
	flow.happened.connect(func(n, d):
		if n == "word_spread":
			seen.append(d))
	await flow.go("intro", {"foe": later})
	_check(later.meters.friendliness > calm and later.meters.anger <= cross, "the later one starts friendlier (%.0f -> %.0f)" % [calm, later.meters.friendliness])
	_check(LocalMind.new().mercy(later) > calm_odds, "and the local rules give better odds for it")
	var name_said: String = goo.name.left(1) + goo.name.substr(1).to_lower()
	_check(s.lines.any(func(l): return l.kind == "say" and l.text.contains(name_said)), "it says so, by name (%s)" % str(s.lines))
	_check(seen.size() == 1 and seen[0].tone == "good", "the word going round is an event (%s)" % str(seen))
	_check(s.banner != null and Overlay.banner_fits(s.banner.text), "and shows on the picture")
	var card: String = str(Tips.foe_blocks(later, []))
	_check(card.contains(Clans.title(clan)), "the card says what it heard (%s)" % card)

	# heard once: meeting it again changes nothing, trying again after dying starts from the same place
	var friendly: float = later.meters.friendliness
	await flow.tick(flow.clock + 1000.0)
	await flow.press("confirm")
	await flow.go("explore", {"lines": []})
	await flow.go("intro", {"foe": later})
	_check(s.stage == "intro" and s.foe == later and is_equal_approx(later.meters.friendliness, friendly), "a monster hears the same news once")
	await flow.tick(flow.clock + 1000.0)
	await flow.press("confirm")
	await flow.encounter.retry_fight()
	var again = s.foe
	_check(s.stage == "intro" and again != later, "the fight starts over (%s)" % s.stage)
	_check(is_equal_approx(again.meters.friendliness, friendly), "a retried fight starts from the same mood (%.0f, %.0f)" % [again.meters.friendliness, friendly])

	# what it heard goes to Jev, and survives a save
	var jev = JevMind.new("https://example.invalid", LocalMind.new())
	var told: Dictionary = jev._state(again, {})
	_check(told.get("history", {}).get("clan", "") != "" and str(told.history.heard).contains(goo.name), "Jev is told the history (%s)" % str(told))
	var back = State.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	_check(back != null and back.reputation.get(clan, 0.0) == s.reputation[clan] and back.deeds.size() == s.deeds.size(), "reputation and deeds are saved")
	var kept = Monster.from_dict(JSON.parse_string(JSON.stringify(again.to_dict())))
	_check(kept.heard.get("clan", "") == clan, "what a monster heard is saved")
	var old: Dictionary = s.to_dict()
	old.erase("reputation")
	old.erase("deeds")
	var loaded = State.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(loaded != null and loaded.reputation.is_empty(), "a save from before clans still loads")
	var bad: Dictionary = s.to_dict()
	bad.reputation = {clan: "lots"}
	_check(State.from_dict(JSON.parse_string(JSON.stringify(bad))) == null, "a save with a wrong reputation is refused")
	var huge: Dictionary = s.to_dict()
	huge.reputation = {clan: 1e9, "nobody": 5.0}
	var clamped = State.from_dict(JSON.parse_string(JSON.stringify(huge)))
	_check(clamped.reputation[clan] <= Clans.STANDING_MAX and not clamped.reputation.has("nobody"), "reputation out of range is brought back (%s)" % str(clamped.reputation))

	# word spills to the clan's side, the dragon hears a little of everything, killing turns them the other way
	var slain := State.new()
	var victim := Monster.new()
	victim.species = "slime"
	victim.name = "OOZE"
	Clans.record(slain, victim, "slain")
	var side_clans: Array = Clans.side_of(clan)
	_check(side_clans.size() >= 1, "a clan has others on its side")
	_check(slain.reputation[clan] < 0.0 and slain.reputation[side_clans[0]] < 0.0 and slain.reputation[side_clans[0]] > slain.reputation[clan], "killing one hurts its clan most, its side less (%s)" % str(slain.reputation))
	var rival: String = Clans.of("bandit")
	_check(not side_clans.has(rival) and slain.reputation.get(rival, 0.0) == 0.0, "another side doesn't care (%s)" % str(slain.reputation))
	_check(slain.reputation[Clans.of("dragon")] < 0.0, "the dragon hears of everything")
	var grudge = Monster.make(Rng.new(4), Content.table("encounter").roster.filter(func(e): return e.species == "slime")[0], Vector2i.ONE)
	var was_angry: float = grudge.meters.anger
	var was_kind: float = grudge.meters.friendliness
	var heard: Dictionary = Clans.hear(grudge, slain)
	_check(heard.kind == "kin_slain" and heard.who == "OOZE" and heard.tone == "bad", "kin of the slain knows who did it (%s)" % str(heard))
	_check(grudge.meters.anger > was_angry and grudge.meters.friendliness < was_kind, "and starts angrier")
	var on_side = Monster.make(Rng.new(4), Content.table("encounter").roster.filter(func(e): return e.species == side_species(side_clans[0]))[0], Vector2i.ONE)
	_check(Clans.hear(on_side, slain).kind == "side_slain", "its side has heard too")
	var far = Monster.make(Rng.new(4), Content.table("encounter").roster.filter(func(e): return e.species == "bandit")[0], Vector2i.ONE)
	var far_mood: float = far.meters.friendliness
	_check(Clans.hear(far, slain).is_empty() and far.meters.friendliness == far_mood and far.heard.is_empty(), "another side has nothing to say")

	# every sentence fits the banner, and a hated monster can still be won over
	for id in Content.table("clans").clans:
		for tone in ["good", "bad"]:
			for deed in ["spared", "slain"]:
				var text: String = Clans.news({"clan": id, "deed": deed, "who": "WWWWWWWW", "tone": tone})
				_check(Overlay.banner_fits(text), "the news fits the banner: %s" % text)
	_check(Clans.mood(-1000.0).friendliness >= -Clans.MOOD_MAX and Clans.mood(1000.0).friendliness <= Clans.MOOD_MAX, "a clan's opinion only moves a mood so far")
	_use()


## Kills climb a clan through angry, furious and enraged (#77). A furious clan sends elites to the floors made after it got so; an
## enraged one won't take mercy, a cut or an offer; sparing its side or a favour cools it; the header and the cards say why it's harder.
func _hostility() -> void:
	var clan: String = Clans.of("slime")
	var side: String = Clans.side_of(clan)[0]
	var slime_line: Dictionary = Content.table("encounter").roster.filter(func(e): return e.species == "slime")[0]
	var tally := State.new()
	var kill := func(species: String, who: String) -> Array:
		var victim := Monster.new()
		victim.species = species
		victim.name = who
		return Clans.record(tally, victim, "slain")
	_check(Clans.hostility_of(tally, "slime") == "" and Clans.mood_word(0.0) == "CALM", "a run starts with no clan hostile")
	var moved: Array = kill.call("slime", "A")
	_check(Clans.hostility_of(tally, "slime") == "angry" and moved.size() >= 1 and moved[0].clan == clan and moved[0].to == "angry", "one kill: its clan is angry, and the deed says so first (%s)" % str(moved))
	_check(not Clans.sends_elites(tally, "slime"), "and sends no elites yet")
	kill.call("slime", "B")
	_check(Clans.hostility_of(tally, "slime") == "furious" and Clans.sends_elites(tally, "slime"), "two kills: furious, and it sends elites")
	_check(Clans.hostility(float(tally.reputation[side])) == "angry" and not Clans.sends_elites(tally, side_species(side)), "its side is only angry (%s)" % str(tally.reputation))
	_check(not Clans.sends_elites(tally, "bandit") and Clans.hostility_of(tally, "bandit") == "", "another side doesn't care")
	var goo = Monster.make(Rng.new(5), slime_line, Vector2i.ONE)
	_check(not Clans.enraged(tally, goo), "furious still takes mercy")
	kill.call("slime", "C")
	kill.call("slime", "D")
	_check(Clans.enraged(tally, goo) and Clans.mood_word(float(tally.reputation[clan])) == "ENRAGED", "four kills: enraged")
	var rock := Monster.new()
	rock.species = side_species(side)
	rock.name = "R"
	var cooled: Array = Clans.record(tally, rock, "spared")
	_check(not Clans.enraged(tally, goo) and cooled.any(func(c): return c.clan == clan and c.to == "furious"), "sparing one on its side cools it back to furious (%s)" % str(cooled))
	var favoured: Array = Clans.favour(tally, "slime", 30.0)
	_check(favoured.any(func(c): return c.clan == clan and Clans.rank(c.to) < Clans.rank(c.from)), "and a favour to its kind cools it further (%s)" % str(favoured))
	_check(Clans.mood_word(20.0) == "FRIENDLY", "a clan that likes you says so")
	var title_font: Font = load("res://src/view/fonts.gd").title()
	for id in Content.table("clans").clans:
		for change in [{"clan": id, "from": "", "to": "angry"}, {"clan": id, "from": "angry", "to": "furious"}, {"clan": id, "from": "furious", "to": "enraged"}, {"clan": id, "from": "enraged", "to": "furious"}, {"clan": id, "from": "angry", "to": ""}]:
			var words: Dictionary = Clans.moved_words(change)
			_check_quietly(Overlay.banner_fits(words.text) and words.line.contains(Clans.title(id)) and title_font.get_string_size(words.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x <= Overlay.BANNER_W, "%s %s->%s fits the banner: %s / %s" % [id, change.from, change.to, words.title, words.line])
	_check(true, "every move of every clan's hostility fits the banner")

	# a furious clan sends its elites to the next floor: tougher, the champion never, said on arrival, and kept in a save
	var flow = _flow(80, ["no-branching", "no-roaming"])
	await flow.new_run()
	var s = flow.state
	_check(Hud.toughness_tag(s) == "" and s.floor_map.monsters.all(func(m): return not m.elite), "B1F: no toughness to tell, no elites on a fresh run")
	s.reputation[clan] = -40.0
	await _reach_stairs(flow)
	await flow.press("1")
	var slimes: Array = s.floor_map.monsters.filter(func(m): return m.species == "slime" and not m.boss)
	var others: Array = s.floor_map.monsters.filter(func(m): return Clans.of(m.species) != clan and not m.boss)
	var hp_scale: float = Floors.plan(s.depth).hp_scale
	_check(s.depth == 2 and not slimes.is_empty() and slimes.all(func(m): return m.elite), "B2F: every slime is one of the Burrow's elites (%d)" % slimes.size())
	_check(slimes.all(func(m): return m.max_hp == roundi(roundi(float(slime_line.hp) * hp_scale) * float(Clans.elite().hp_scale)) and m.hp == m.max_hp), "with a quarter more health (%s)" % str(slimes.map(func(m): return m.max_hp)))
	_check(others.all(func(m): return not m.elite) and not s.floor_map.monsters.back().elite, "nobody else is, and never the champion")
	_check(s.lines.any(func(l): return l.text.contains("Elites on this floor") and l.text.contains(Clans.title(clan))), "arriving, the log says who sent elites (%s)" % str(s.lines.map(func(l): return l.text)))
	_check(Hud.toughness_tag(s) == "FOES +12% HP ", "the header says how much tougher this floor's monsters are (%s)" % Hud.toughness_tag(s))
	var by_chars := func(t: String) -> float: return float(t.length())
	_check(Hud.header_left("B2F OF 5 ", "FOES +12% HP ", "ELITE GOO RAIN ENCOUNTER", by_chars, 100.0) == ["B2F OF 5 ", "FOES +12% HP ", "ELITE GOO RAIN ENCOUNTER"], "with room, the header says it all")
	_check(Hud.header_left("B2F OF 5 ", "FOES +12% HP ", "ELITE GOO RAIN ENCOUNTER", by_chars, 40.0) == ["B2F OF 5 ", "FOES +12% HP ", "ELITE GOO RAIN"], "narrow, ENCOUNTER goes first")
	_check(Hud.header_left("B2F OF 5 ", "FOES +12% HP ", "THE GENRE HALLS", by_chars, 25.0) == ["B2F OF 5 ", "FOES +12% HP ", ""], "on the walk, then the title, before the toughness")
	_check(Hud.header_left("B2F OF 5 ", "FOES +12% HP ", "ELITE GOO RAIN ENCOUNTER", by_chars, 10.0)[1] == "", "and the toughness last")
	var back = State.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	_check(back != null and back.floor_map.monsters.filter(func(m): return m.elite).size() == slimes.size() and is_equal_approx(back.floor_map.hp_scale, s.floor_map.hp_scale), "a save keeps the elites and the floor's toughness")
	var old: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	old.floor.erase("hpScale")
	for md in old.floor.monsters:
		md.erase("elite")
	var before = State.from_dict(old)
	_check(before != null and before.floor_map.monsters.all(func(m): return not m.elite) and Hud.toughness_tag(before) == "FOES +12% HP ", "a save from before has no elites and its depth still tells the toughness")
	var wrong: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	wrong.floor.monsters[0].elite = "yes"
	_check(State.from_dict(wrong) == null, "a save with a wrong elite is refused")
	var legend := str(Tips.map_blocks(true, s))
	_check(legend.contains("FURIOUS") and legend.contains("+12% HP") and legend.contains("ENRAGED"), "the map's legend says each clan's mood and what makes it harder (%s)" % legend.right(260))

	# an elite steps up: the picture says so, the header and its card too, and its attacks are harder
	var elite = slimes[0]
	await flow.go("intro", {"foe": elite})
	_check(s.banner != null and s.banner.title.contains("ELITE") and Overlay.banner_fits(s.banner.text), "an elite's fight starts with a banner saying so (%s)" % str(s.banner))
	var card := str(Tips.foe_blocks(elite, [], 2, "", false, s))
	_check(card.contains("ELITE") and card.contains("FURIOUS") and card.contains("hits harder"), "its card says it's an elite of a furious clan (%s)" % card)
	var plain = Monster.make(Rng.new(5), slime_line, Vector2i.ONE)
	_check(Pace.of(elite, 2, 0.0, 0, false) > Pace.of(plain, 2, 0.0, 0, false) or Pace.of(plain, 2, 0.0, 0, false) >= Pace.HIGHEST, "it presses faster in the dodge")
	var hard = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0, Clans.elite())
	var soft = DodgeRun.start("bullet", 1.0, false, 0, 0.0, {}, 1.0)
	_check(hard.intensity > soft.intensity, "its attacks run faster (%.2f > %.2f)" % [hard.intensity, soft.intensity])
	for run in [hard, soft]:
		run.hazards = []
		run.add_hazard(0.0, [Dodge.index(run.soul.x, run.soul.y)], 0.0, 500.0, "bullet")
	var hit_hard: Array = hard.update(10.0, Rng.new(1)).filter(func(e): return e.type == "hurt")
	var hit_soft: Array = soft.update(10.0, Rng.new(1)).filter(func(e): return e.type == "hurt")
	_check(not hit_hard.is_empty() and not hit_soft.is_empty() and hit_hard[0].damage == hit_soft[0].damage + int(Clans.elite().damage), "and each hit costs more (%s vs %s)" % [str(hit_hard), str(hit_soft)])

	# enraged: no mercy, no cut, no offer; the champion says so too
	await flow.tick(flow.clock + 1000.0)
	if s.stage == "intro":
		await flow.press("confirm")
	s.reputation[clan] = -80.0
	_won_over(elite)
	await flow.go("menu")
	_check(s.menu[2].get("disabled", false) and str(s.menu[2].sub).begins_with("ENRAGED"), "enraged: SPARE is greyed out and says why (%s)" % str(s.menu[2]))
	s.nerve = 2
	await flow.go("menu")
	_check(str(s.menu[0].sub).contains("NERVE 2/5") and not str(s.menu[0].sub).contains("SPARE"), "enraged: FIGHT still shows the nerve it adds, and no SPARE chance the fight won't take (%s)" % s.menu[0].sub)
	_check(await flow.encounter.mercy(elite) == 0.0, "its odds are none, however friendly it is")
	await flow.press("3")
	_check(s.stage == "menu" and elite.gone == "", "and SPARE does nothing (%s)" % s.stage)
	_check(not Social.eligible(elite, s), "it has nothing to offer you either")
	var decision: Dictionary = await flow.encounter.decide(elite, [{"intent": "kindness", "w": 1.0}], "PAT")
	_check(s.mind_rows.any(func(r): return r.id == "mercy" and float(r.answer) == 0.0), "an ACT can't raise the odds (%s)" % str(decision.get("id", "")))
	var robber = s.floor_map.monsters.filter(func(m): return m.species == "bandit" and not m.boss)
	if robber.is_empty():
		robber = [Monster.make(Rng.new(6), Content.table("encounter").roster.filter(func(e): return e.species == "bandit")[0], s.cell)]
	s.reputation[Clans.of("bandit")] = -80.0
	s.gold = 50
	await flow.go("intro", {"foe": robber[0]})
	_check(s.banner != null and s.banner.title.contains("ENRAGED"), "an enraged clan's fight starts by saying so (%s)" % str(s.banner))
	await flow.tick(flow.clock + 1000.0)
	if s.stage == "intro":
		await flow.press("confirm")
	await flow.go("act")
	_check(s.menu.any(func(c): return str(c.sub).contains("no price will do")), "the cut's help says it won't be taken (%s)" % str(s.menu.map(func(c): return c.sub)))
	await flow.encounter.offer_cut(robber[0], "PAY OFF")
	_check(s.gold == 50 and robber[0].gone == "" and s.stage == "menu", "and no gold changes hands (%d, %s)" % [s.gold, s.stage])
	s.reputation[Clans.of("dragon")] = -80.0
	await flow.go("explore", {"lines": []})
	await flow.go("intro", {"foe": s.floor_map.monsters.back()})
	_check(s.lines.any(func(l): return l.text.contains(str(Clans.no_mercy().boss))), "a champion of an enraged clan can't be won over, and the rule says so")
	await flow.tick(flow.clock + 1000.0)
	if s.stage == "intro":
		await flow.press("confirm")
	await flow.go("explore", {"lines": []})

	# killing one makes the clan's next level news on the picture
	var flow2 = _flow(82, ["no-branching"])
	var goo2 = await _at_menu(flow2)
	var s2 = flow2.state
	s2.reputation[clan] = -20.0
	s2.banner = null # the words about the door are gone by the time a fight is over
	await flow2.encounter.defeat(goo2, "slain")
	_check(s2.banner != null and s2.banner.title == "%s IS FURIOUS" % Clans.title(clan).to_upper(), "the kill that makes a clan furious says so on the picture (%s)" % str(s2.banner))
	var goo3 = await _at_menu(flow2)
	s2 = flow2.state
	s2.reputation[clan] = -60.0
	await flow2.encounter.defeat(goo3, "slain") # the words about the door are still up
	_check(s2.lines.any(func(l): return l.text.contains("enraged")), "with the picture taken, the log says it instead (%s)" % str(s2.lines.map(func(l): return l.text)))
	_use()


## A check that only prints when it fails, for a loop of many.
func _check_quietly(ok: bool, what: String) -> void:
	if not ok:
		_check(false, what)


func side_species(clan: String) -> String:
	for species in Content.table("species"):
		if Clans.of(species) == clan:
			return species
	return ""


func _branching() -> void:
	var ways: Array = Floors.paths(77, 1)
	_check(ways.size() == 2 and ways[0].label != ways[1].label, "the stairs offer two different ways (%s, %s)" % [ways[0].label, ways[1].label])
	_check(ways.all(func(w): return w.sub != ""), "each says what it is")
	_check(str(Floors.paths(77, 1)) == str(ways), "the same seed offers the same ones")
	var market := {}
	for run in 200:
		for w in Floors.paths(run, 1, false):
			_check(not w.get("shop", false), "without traders no way leads to one")
		for w in Floors.paths(run, 1):
			if w.get("shop", false):
				market = w
	_check(not market.is_empty(), "one way down can be a market")
	var market_flow = _flow(77)
	await market_flow.new_run()
	market_flow.state.depth = 4 # not a floor that has a trader anyway
	market_flow._make_floor(market)
	_check(not market_flow.state.floor_map.merchant.is_empty() or not Items.shop_on(4), "and it has a trader")
	var differs := false
	for s in range(1, 20):
		differs = differs or str(Floors.paths(s, 1)) != str(ways)
	_check(differs, "other seeds offer others")
	_check(Floors.paths(77, Floors.run_floors() - 1).is_empty(), "one way leads to the last floor")
	var labels := {}
	for s in range(1, 60):
		for w in Floors.paths(s, 2):
			labels[w.id] = true
	_check(labels.size() == 4, "every kind of way comes up (%s)" % str(labels.keys()))

	var quiet := {"count": 2, "path": 1, "rest": 6}
	var f = FloorGen.generate(Rng.new(5), Floors.plan(2, quiet))
	_check(f.monsters.size() == 3, "a quiet floor has fewer monsters (%d)" % f.monsters.size())
	var steep = FloorGen.generate(Rng.new(5), Floors.plan(2, {"hp_scale": 1.25}))
	var plain = FloorGen.generate(Rng.new(5), Floors.plan(2))
	_check(steep.monsters[0].max_hp > plain.monsters[0].max_hp, "a steep floor's monsters are tougher")
	var den = FloorGen.generate(Rng.new(5), Floors.plan(2, {"only_species": "rock"}))
	_check(den.monsters.slice(0, -1).all(func(m): return m.species == "rock") and den.monsters.back().boss, "a warren is one kind of monster, and its champion")
	_check(den.monsters.back().boss and den.stairs == plain.stairs, "and the same maze from the same seed")

	var flow = _flow(49)
	await flow.new_run()
	var s = flow.state
	await _reach_stairs(flow)
	_check(s.stage == "end" and s.menu.size() == 3 and s.menu[2].label == "MAIN MENU", "the menu lists the two ways and the way out (%s)" % str(s.menu.map(func(i): return i.label)))
	var expect: Array = Floors.paths(s.run_seed, 1)
	s.hp = 1
	var gold: int = s.gold
	await flow.press("2")
	_check(s.depth == 2, "picking one goes down")
	_check(s.hp == mini(s.max_hp, 1 + Floors.rest_heal() + int(expect[1].get("rest", 0))) and s.gold == gold + int(expect[1].get("gold", 0)), "with what it promised (%d HP, %d gold)" % [s.hp, s.gold])
	var other = _flow(49)
	await other.new_run()
	await _reach_stairs(other)
	await other.press("1")
	_check(other.state.floor_map.grid != s.floor_map.grid, "the two ways lead to different floors")
	flow = _flow(50, ["no-branching"])
	await flow.new_run()
	await _reach_stairs(flow)
	_check(flow.state.menu[0].label == "GO DOWN" and flow.state.menu.size() == 2, "no-branching: one stair")
	_use()


## Stand next to `cell`, facing it, and step.
func _step_onto(flow, cell: Vector2i) -> void:
	var s = flow.state
	for i in 4:
		var from: Vector2i = cell - s.floor_map.DIRS[i]
		if s.floor_map.is_open(from) and s.floor_map.monster_at(from) == null:
			s.cell = from
			s.facing = i
			break
	await flow.press("up")


func _dodges() -> void:
	var entry := {"species": "bandit", "genre": "chess", "hp": 24}
	var m = Monster.given(entry, Vector2i(1, 1), "TEST", ["jumpy"], {"friendliness": 10.0, "anger": 10.0, "fear": 10.0})
	var base := Pace.of(m, 1, 0.0, 0, false)
	_check(base < 1.0, "a first dodge runs slower than the classic pace (%.2f)" % base)
	_check(Pace.of(m, 4, 0.0, 0, false) > base, "deeper floors run faster")
	_check(Pace.of(m, 1, 3.0, 0, false) < base, "getting hit a lot slows it")
	_check(Pace.of(m, 1, 0.0, 2, false) < base, "allies slow it")
	_check(Pace.of(m, 1, 0.0, 0, true) < base, "EASY DODGE slows it")
	var friend = Monster.given(entry, Vector2i(1, 1), "TEST", ["jumpy"], {"friendliness": 90.0, "anger": 10.0, "fear": 10.0})
	_check(Pace.of(friend, 1, 0.0, 0, false) < base, "a friendlier foe attacks more gently")
	_check(Pace.after_dodge(2.0, 0) == 1.0 and Pace.after_dodge(1.0, 2) == 3.0, "a clean dodge eases the struggle, hits add to it")

	var run_slow = DodgeRun.start("chess", 1.0, false, 0, 0.0, {}, 0.5)
	var run_full = DodgeRun.start("chess", 1.0, false, 0, 0.0, {}, 1.0)
	var slow_rng := Rng.new(3)
	var full_rng := Rng.new(3)
	run_slow.update(400.0, slow_rng)
	run_full.update(400.0, full_rng)
	var slow_warn: float = run_slow.hazards[0].hit - run_slow.hazards[0].warn
	var full_warn: float = run_full.hazards[0].hit - run_full.hazards[0].warn
	_check(slow_warn > full_warn, "a slower dodge warns for longer (%d ms, %d ms)" % [slow_warn, full_warn])
	_check(run_full.end_t > run_slow.end_t, "and is over sooner")
	for g in ["R", "B", "N"]:
		_check(not Overlay.piece_shape(g).is_empty(), "the piece %s has a shape" % g)

	var enc: Dictionary = load("res://src/rules/content.gd").table("encounter")
	_check(enc.genres.keys().all(func(g): return DodgeRun.MINI_GAMES.has(g)), "every attack in the data has a file of its own in rules/minigames")
	_check(enc.genres.keys().all(func(g): return enc.genres[g].has("plain")), "every attack has its rule in plain words")
	var plain: String = enc.genres.chess.plain.to_lower()
	_check(not plain.contains("rook") and not plain.contains("bishop") and not plain.contains("knight"), "the chess rule needs no chess: %s" % plain)
	var rotated: Array = enc.mini_games
	m.turn = 2
	_check(Dodge.genre_on_turn(m, enc.boss.genres, rotated) in rotated, "every third attack is a mini-game")
	m.turn = 1
	_check(Dodge.genre_on_turn(m, enc.boss.genres, rotated) == "chess", "the others are its own")
	m.turn = 2
	_check(Dodge.genre_on_turn(m, enc.boss.genres, []) == "chess", "without the feature it only ever fights its own way")

	var wall = DodgeRun.start("gates", 1.0, false, 0, 0.0, {}, 1.0)
	var r := Rng.new(5)
	wall.update(400.0, r)
	_check(wall.hazards.size() == Dodge.COLS, "a wall is one hazard per column (%d)" % wall.hazards.size())
	var open_rows := 0
	for row in Dodge.ROWS:
		if not wall.hazards[0].cells.has(Dodge.index(Dodge.COLS - 1, row)):
			open_rows += 1
	_check(open_rows == Gates.GAP, "with a gap in it (%d rows)" % open_rows)
	_check(wall.hazards[1].hit > wall.hazards[0].hit, "and it comes in column by column")

	var stars = DodgeRun.start("stars", 1.0, false, 0, 0.0, {}, 1.0)
	var star_rng := Rng.new(6)
	stars.update(400.0, star_rng)
	var star: Dictionary = stars.hazards.filter(func(h): return h.kind == "star")[0]
	stars.soul = Vector2i(star.at % Dodge.COLS, floori(float(star.at) / Dodge.COLS))
	stars.hazards = [star]
	stars.next_t = 1e9
	var got: Array = stars.update(star.hit + 1.0, star_rng)
	_check(got.any(func(e): return e.type == "star"), "standing under a star catches it")
	_check(not got.any(func(e): return e.type == "hurt"), "and it doesn't hurt")
	_check(not stars.update(star.hit + 2.0, star_rng).any(func(e): return e.type == "star"), "a star is caught once")

	var dance = DodgeRun.start("dance", 1.0, false, 0, 0.0, {}, 1.0)
	var dance_rng := Rng.new(8)
	var beats := 0
	var pads := []
	for t in range(10, 2000, 10):
		for e in dance.update(float(t), dance_rng):
			beats += 1 if e.type == "beat" else 0
		for h in dance.hazards:
			if h.kind == "pad" and not pads.has(h):
				pads.append(h)
	_check(beats >= 3 and pads.size() == beats, "the dance has a light for every beat (%d beats, %d lights)" % [beats, pads.size()])
	_check(pads[1].hit - pads[0].hit > 300.0, "a beat apart")
	var away: Vector2i = Vector2i(pads[1].at % Dodge.COLS, floori(float(pads[1].at) / Dodge.COLS)) - Vector2i(pads[0].at % Dodge.COLS, floori(float(pads[0].at) / Dodge.COLS))
	_check(absi(away.x) + absi(away.y) == 1, "a step apart, so you can keep up")
	var on_the_light = DodgeRun.start("dance", 1.0, false, 0, 0.0, {}, 1.0)
	on_the_light.update(10.0, dance_rng)
	var light: Dictionary = on_the_light.hazards[0]
	on_the_light.soul = Vector2i(light.at % Dodge.COLS, floori(float(light.at) / Dodge.COLS))
	on_the_light.hazards = [light]
	var danced: Array = on_the_light.update(light.hit + 1.0, dance_rng)
	_check(danced.any(func(e): return e.type == "star") and not danced.any(func(e): return e.type == "hurt"), "on the light when it lands you heal")
	for pace in [0.6, 1.0]:
		var slow = DodgeRun.start("dance", 1.0, false, 0, 0.0, {}, pace)
		slow.update(10.0, dance_rng)
		var beat_ms: float = Dance.BEAT_MS / sqrt(slow.intensity * pace)
		_check(absf(slow.hazards[0].hit - slow.hazards[0].warn - beat_ms) < 1.0, "the next light is shown one beat ahead at any pace (%.2f)" % pace)

	var flow = _flow(13)
	await flow.new_run()
	_check(flow.state.rotate_mini_games, "the run rotates mini-games in")
	_use()


func _map_gen() -> void:
	var flow = _flow(41)
	await flow.new_run()
	var s = flow.state
	var kinds := {}
	for depth in range(1, Floors.run_floors() + 1):
		var biome: Dictionary = Floors.biome(41, depth)
		_check(s.floor_map.biome == biome.id and s.floor_map.size == int(biome.size), "B%dF is %s at %d (%s at %d)" % [depth, biome.id, biome.size, s.floor_map.biome, s.floor_map.size])
		_check(biome.palettes.map(func(v): return int(v)).has(s.palette_id), "in the colours of its biome")
		var standing: Array = s.floor_map.monsters.filter(func(m): return not m.lurking)
		var kinds_here: int = Content.table("kinds").kinds.values().filter(func(k): return int(k.depth) == depth).size()
		_check(standing.size() == kinds_here + 1 + maxi(0, (int(biome.size) - 13) / 3), "with its %d kinds and more monsters the bigger it is (%d at %d)" % [kinds_here, standing.size(), biome.size])
		kinds[biome.id] = true
		if depth < Floors.run_floors():
			s.foe = null
			await flow.next_floor()
			_check(s.banner != null and s.banner.title == Floors.biome(41, depth + 1).name, "going down names the biome (%s)" % str(s.banner))
			_check(s.lines.any(func(l): return l.text == Floors.biome(41, depth + 1).line), "and the log describes it")
	_check(kinds.size() == 3, "a run goes through all the biomes (%s)" % [kinds.keys()])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var back = _flow(41)
	_check(await back.load_state(saved) and back.state.floor_map.biome == s.floor_map.biome and back.state.floor_map.size == s.floor_map.size, "a big floor saves and loads")
	var again = _flow(41)
	await again.new_run()
	var other = _flow(41)
	await other.new_run()
	_check(JSON.stringify(again.state.floor_map.to_dict()) == JSON.stringify(other.state.floor_map.to_dict()), "the same seed makes the same floor")
	var quiet = FloorGen.generate(Rng.new(5), _with_biome(Floors.plan(5, {"count": 2})))
	_check(quiet.monsters.size() > 3 and quiet.monsters.size() < FloorGen.generate(Rng.new(5), _with_biome(Floors.plan(5))).size, "the quiet stair's two monsters scale with a bigger floor (%d)" % quiet.monsters.size())
	_use()


func _with_biome(plan: Dictionary) -> Dictionary:
	plan.biome = Floors.sized(Content.table("biomes").biomes[1], 5)
	return plan


## Stand next to a cell, facing it.
func _face(s, cell: Vector2i) -> void:
	for i in 4:
		var from: Vector2i = cell - s.floor_map.DIRS[i]
		if s.floor_map.is_open(from) and s.floor_map.pad_partner(from) == null and not s.floor_map.treasure.any(func(t): return t.cell == from):
			s.cell = from
			s.facing = i
			return


func _cracked_wall(f) -> Vector2i:
	for y in f.size:
		for x in f.size:
			if f.is_cracked(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _secrets() -> void:
	var flow = _flow(47)
	var heard := []
	flow.happened.connect(func(name, data): heard.append([name, data]))
	await flow.new_run()
	var s = flow.state
	var f = s.floor_map
	var wall := _cracked_wall(f)
	_check(wall != Vector2i(-1, -1) and not f.is_open(wall), "a floor has a cracked wall, which is a wall")
	var chest: Dictionary = f.treasure.filter(func(t): return absi(t.cell.x - wall.x) + absi(t.cell.y - wall.y) == 1)[0]
	_check(not f.is_open(wall) and not s.seen.has(chest.cell), "with a chest behind it, out of sight")
	s.banner = null
	flow.clock = 100000.0
	flow.coach.seen = {}
	_face(s, wall)
	_check(s.floor_map.is_cracked(s.cell + f.DIRS[s.facing]), "standing in front of it")
	await flow.press("left")
	await flow.press("right")
	_check(s.banner != null and s.banner.text == Content.table("coach").tips.crack, "the first time you face one, a tip says what it is")
	var was: Vector2i = s.cell
	var changes: int = f.changes
	heard.clear()
	await flow.press("up")
	_check(f.is_open(wall) and f.changes == changes + 1, "walking into it breaks it")
	_check(s.cell == was, "and you stay where you are")
	_check(heard.any(func(h): return h[0] == "sound" and h[1].name == "hit"), "with a crash")
	_check(s.lines.any(func(l): return l.text == Floors.secret_line("wall")), "and the log says so")
	_check(s.seen.has(wall), "and the map learns what opened")
	var gold: int = s.gold
	s.cell = wall
	s.facing = f.DIRS.find(chest.cell - wall)
	await flow.press("up")
	_check(s.gold == gold + chest.gold and not f.treasure.has(chest), "stepping on the chest takes its gold (%d)" % chest.gold)
	_check(s.lines.any(func(l): return l.text == Floors.secret_line("chest") % chest.gold), "and says how much")
	var pad: Dictionary = f.teleports[0]
	_face(s, pad.a)
	await flow.press("up")
	_check(s.cell == pad.b, "a pad carries you to its other end (at %s, %s)" % [s.cell, pad.b])
	_check(s.visited.has(pad.b) and s.seen.has(pad.b), "and the map learns where you are")
	_check(s.stage == "explore", "and you are still walking")
	_face(s, pad.b)
	await flow.press("up")
	_check(s.cell == pad.a, "and back")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var back = _flow(47)
	await back.load_state(saved)
	_check(back.state.floor_map.is_open(wall) and back.state.floor_map.treasure.size() == f.treasure.size(), "a broken wall and an emptied chest stay that way in a save")
	var map = load("res://src/view/automap.gd").new()
	map.state = s
	s.cell = pad.a
	s.seen = {pad.a: true}
	_check(map.secret_marks().size() == 1, "the map marks a pad you have seen")
	s.seen = {}
	_check(map.secret_marks().is_empty(), "and only then")
	map.free()
	var decor: Array = load("res://src/view/decor.gd").placements(f)
	_check(not decor.any(func(p): return p.kind == "fissure" and p.cell + f.DIRS[p.side] == wall), "with the wall broken, no fissure is left on it")
	var other = _flow(47)
	await other.new_run()
	var w2 := _cracked_wall(other.state.floor_map)
	var fissures: Array = load("res://src/view/decor.gd").placements(other.state.floor_map).filter(func(p): return p.kind == "fissure" and p.cell + other.state.floor_map.DIRS[p.side] == w2)
	_check(fissures.size() == 2, "a cracked wall always shows a fissure, on both its faces (%d)" % fissures.size())
	var legend: Array = Tips.map_blocks().map(func(b): return str(b.get("left", "")))
	_check(legend.has("PAD") and legend.has("CHEST"), "the legend names pads and chests")
	_use()


func _lore() -> void:
	var t0 := Time.get_ticks_msec()
	# the words: fifteen pieces, five floors by three tones, each fitting the banner
	var title_font: Font = load("res://src/view/fonts.gd").title()
	var ids := {}
	for depth in Lore.depths():
		for tone in Lore.TONES:
			var each := Lore.piece(depth, tone)
			ids[each.id] = true
			_check_quietly(Lore.known(each.id) and Overlay.banner_fits(each.text) and title_font.get_string_size(each.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x <= Overlay.BANNER_W, "the writing %s fits the banner: %s / %s" % [each.id, each.title, each.text])
	_check(Lore.total() == 15 and ids.size() == 15 and Lore.depths().size() == Floors.run_floors(), "there are fifteen pieces of writing, three for each of the %d floors" % Floors.run_floors())
	_check(Lore.piece(Floors.run_floors() + 3, "warm").id == Lore.piece(Floors.run_floors(), "warm").id, "a floor deeper than the last shows the deepest piece")
	var warmth: Array = load("res://src/rules/warmth.gd").table().levels
	var tones := []
	for level in warmth.size():
		tones.append(Lore.tone_of_level(level))
	_check(tones == ["cold", "cold", "wary", "warm", "warm"], "cold and shut halls read the cold writing, wary the wary, kind and beloved the warm (%s)" % [tones])
	_check(not Lore.known("6-warm") and not Lore.known("1-hot") and not Lore.known("1warm"), "and only those are pieces")
	# where it goes: every floor of a run has it, mostly at the end of a corridor, and placing it changes nothing else on the floor
	var floors := 0
	var placed := 0
	var ends := 0
	var same := true
	for seed_value in range(1, 21):
		for depth in [1, 3, 5]:
			var plan := Floors.plan(depth)
			plan.biome = Floors.biome(seed_value, depth)
			plan.secrets = Floors.secrets(plan.biome)
			plan.items = true
			plan.lurkers = true
			plan.request = Requests.due(depth)
			var bare: Dictionary = plan.duplicate()
			plan.lore = true
			var lored = FloorGen.generate(Rng.new(seed_value * 31 + depth), plan)
			var plain = FloorGen.generate(Rng.new(seed_value * 31 + depth), bare)
			floors += 1
			same = same and lored.grid == plain.grid and lored.stairs == plain.stairs and lored.pickups == plain.pickups and lored.treasure == plain.treasure and lored.monsters.map(func(m): return m.cell) == plain.monsters.map(func(m): return m.cell) and plain.lore.is_empty()
			if lored.lore.is_empty():
				continue
			placed += 1
			var c: Vector2i = lored.lore.cell
			var behind: Vector2i = c + FloorMap.DIRS[lored.lore.side]
			_check_quietly(lored.is_open(c) and not lored.is_open(behind) and not lored.is_cracked(behind), "seed %d B%dF: the writing is on a plain wall of an open cell" % [seed_value, depth])
			_check_quietly(lored.monster_at(c) == null and lored.pickup_at(c) == "" and lored.pad_partner(c) == null and not lored.merchant_at(c) and not lored.quester_at(c) and c != lored.stairs and c != lored.start, "seed %d B%dF: and nothing else stands there" % [seed_value, depth])
			var open := FloorMap.DIRS.filter(func(d): return lored.is_open(c + d))
			if open.size() == 1:
				ends += 1
				_check_quietly(lored.lore.side == (FloorMap.DIRS.find(open[0]) + 2) % 4 or lored.is_cracked(c - open[0]), "seed %d B%dF: at a corridor's end, it is the wall you face walking in" % [seed_value, depth])
	_check(placed == floors, "every floor has writing on a wall (%d of %d)" % [placed, floors])
	_check(ends * 4 >= placed * 3, "at the end of a corridor on most of them (%d of %d)" % [ends, placed])
	_check(same, "and placing it changes nothing else a seed makes")
	# reading it
	var flow = _flow(47)
	var heard := []
	flow.happened.connect(func(name, data): heard.append([name, data]))
	await flow.new_run()
	var st = flow.state
	var f = st.floor_map
	_check(not f.lore.is_empty() and not f.lore.read and f.reserved().has(f.lore.cell), "a run's first floor has writing, unread, where no monster may wander")
	var decor: Array = load("res://src/view/decor.gd").placements(f).filter(func(p): return p.cell == f.lore.cell and p.side == f.lore.side)
	_check(decor.size() == 1 and decor[0].kind == "lore", "its wall carries the writing and nothing else")
	var map = load("res://src/view/automap.gd").new()
	map.state = st
	var start_cell: Vector2i = st.cell
	st.cell = f.lore.cell # a big floor's map is a window that follows you
	st.seen = {f.lore.cell: true}
	var marks: Array = map.secret_marks()
	st.cell = start_cell
	_check(marks.size() == 1 and marks[0].color == load("res://src/view/palette.gd").MERCY, "the map marks it in gold once seen")
	st.seen = {}
	_check(map.secret_marks().is_empty(), "and not before")
	st.banner = null
	flow.clock = 100000.0
	flow.coach.seen = {}
	flow.lore_read = {}
	_face(st, f.lore.cell)
	st.floor_map.monsters = st.floor_map.monsters.filter(func(m): return m.boss) # nobody walks up while it is read
	await flow.press("left")
	st.banner = null
	await flow.press("right")
	_check(st.banner != null and st.banner.text == Content.table("coach").tips.lore, "the first time you look down at it, a tip says what it is")
	st.banner = null
	heard.clear()
	var now_tone := Lore.tone(st)
	await flow.press("up")
	var piece := Lore.piece(1, now_tone)
	_check(now_tone == "warm" and st.cell == f.lore.cell and f.lore.read, "stepping up to it reads it; a run starts in warm halls")
	_check(st.banner != null and st.banner.title == piece.title and st.banner.text == piece.text, "its words go up on the picture: %s" % piece.title)
	_check(st.lines.any(func(l): return l.text == piece.text) and st.lines.any(func(l): return l.text == Lore.found_line(1)), "the log keeps them, and counts what has been read over all runs")
	_check(heard.any(func(h): return h[0] == "found" and h[1].what == "lore" and h[1].id == "1-warm" and h[1].read == 1 and h[1].total == 15), "the scene hears what was read, to keep it")
	_check(heard.any(func(h): return h[0] == "sound" and h[1].name == "holy"), "lored a chime")
	_check(flow.lore_read.has("1-warm"), "and the game counts it")
	st.seen = {f.lore.cell: true}
	marks = map.secret_marks()
	_check(marks.size() == 1 and marks[0].color == load("res://src/view/palette.gd").DIM, "on the map it goes grey")
	map.free()
	var achievements = load("res://src/rules/achievements.gd")
	_check(achievements.earned_by("found", {"what": "lore", "id": "1-warm", "read": 1, "total": 15}, st) == ["lore"], "reading writing earns an achievement")
	_check(achievements.earned_by("found", {"what": "lore", "id": "5-cold", "read": 15, "total": 15}, st) == ["lore", "lore_all"], "and reading all of it, another")
	heard.clear()
	_face(st, f.lore.cell)
	await flow.press("up")
	_check(not heard.any(func(h): return h[0] == "found"), "read once, it says nothing the next time you step up to it")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(st.to_dict()))
	var back = _flow(47)
	await back.load_state(saved)
	_check(back.state.floor_map.lore == f.lore, "a save keeps where it is and that it was read")
	var check = load("res://src/game/save_check.gd")
	for wrong in [{"cell": [0, 0], "side": 1, "read": false}, {"cell": saved.floor.lore.cell, "side": 7, "read": false}, {"cell": saved.floor.lore.cell, "side": 1, "read": "yes"}, "here"]:
		var broken: Dictionary = saved.duplicate(true)
		broken.floor.lore = wrong
		_check_quietly(check.problem(broken) != "", "a save lored its writing as %s is turned away" % [wrong])
	# a cruel run, deeper down, reads another piece on the same wall
	f.lore.read = false
	st.tally.slain = 10
	st.depth = 4
	_face(st, f.lore.cell)
	await flow.press("up")
	_check(st.banner != null and st.banner.text == Lore.piece(4, "cold").text and flow.lore_read.size() == 2, "cold halls read the cold piece: %s" % st.banner.title if st.banner != null else "")
	_check(st.lines.any(func(l): return l.text == Lore.found_line(2)), "and the count goes on")
	var legend: Array = Tips.map_blocks().map(func(b): return str(b.get("left", "")))
	_check(legend.has(str(Lore.table().legend.left)), "the map's legend names the writing")
	_check(Practice.make(Rng.new(5)).lore.is_empty(), "the practice landing has none")
	print("features: writing checked in %d ms" % (Time.get_ticks_msec() - t0))
	_use()


## A fight with the slime, standing at the menu.
func _item_fight(seed_value: int, words := []) -> Variant:
	var flow = _flow(seed_value, words)
	await _at_menu(flow, "slime")
	return flow


func _items() -> void:
	var flow = await _item_fight(51)
	var s = flow.state
	_check(s.menu.size() == 6 and s.menu[5].label == "ITEM" and s.menu[5].disabled, "an empty bag leaves ITEM visible and disabled")
	s.selected = 4
	await flow.press("right")
	_check(s.selected == 3, "moving right skips disabled ITEM")
	await flow.press("left")
	_check(s.selected == 4, "moving left skips disabled ITEM")
	s.selected = 2
	await flow.press("down")
	await flow.press("6")
	flow.select(5)
	_check(s.stage == "menu" and s.selected == 2, "down, the digit and pointer selection cannot select disabled ITEM")
	s.items = ["sugar", "salve", "whetstone", "smoke"]
	await flow.go("menu")
	_check(s.menu.size() == 6 and s.menu[5].label == "ITEM" and s.menu[0].label == "FIGHT" and s.menu[3].label == "FLEE" and s.menu[4].label == "HEAVY", "something in the bag adds ITEM, and the others keep their places")
	await flow.press("6")
	_check(s.stage == "items" and s.menu.size() == 4, "ITEM opens the bag (%s)" % s.stage)
	await flow.press("cancel")
	_check(s.stage == "menu" and s.items.size() == 4, "and backing out uses nothing")
	# a gift changes a recruit
	var m = s.foe
	var before: float = await flow.mind.mercy(m)
	await flow.press("6")
	await flow.press("1")
	var after: float = await flow.mind.mercy(m)
	_check(after >= 0.5 and after > before + 0.2, "the gift a monster loves moves it most of the way to mercy (%.2f to %.2f)" % [before, after])
	_check(not s.items.has("sugar"), "and is gone from the bag")
	_check(s.stage in ["wait", "menu"], "and takes your turn (%s)" % s.stage)
	var other = await _item_fight(51)
	other.state.items = ["ring"]
	await other.go("menu")
	var shrug_from: float = await other.mind.mercy(other.state.foe)
	await other.press("6")
	await other.press("1")
	var shrug_to: float = await other.mind.mercy(other.state.foe)
	_check(shrug_to - shrug_from < after - before, "a gift it doesn't care for does much less (%.2f to %.2f)" % [shrug_from, shrug_to])
	# a salve
	var heal = await _item_fight(52)
	heal.state.items = ["salve"]
	heal.state.hp = 3
	await heal.go("menu")
	await heal.press("6")
	await heal.press("1")
	_check(heal.state.hp == 13 and heal.state.items.is_empty(), "a salve heals 10 (%d)" % heal.state.hp)
	_check(heal.state.stage in ["wait", "menu"], "and takes your turn")
	# a whetstone
	var sharp = await _item_fight(53)
	sharp.state.items = ["whetstone"]
	await sharp.go("menu")
	await sharp.press("6")
	await sharp.press("1")
	_check(sharp.state.stage == "menu" and sharp.state.sharpened == 6, "a whetstone is free, and sharpens the next strike")
	sharp.state.foe.hp = 100
	sharp.state.foe.max_hp = 100
	await sharp.press("1")
	_check(sharp.state.hint.contains("WHETTED +6"), "the bar says so")
	sharp.clock = sharp.state.bar.t0 + sharp.state.bar.dur / 2.0
	await sharp.press("confirm")
	_check(sharp.state.foe.hp <= 100 - 14 - 6 + 5, "and the strike hits harder (%d left of 100)" % sharp.state.foe.hp)
	_check(sharp.state.sharpened == 0, "once")
	# smoke
	var away = await _item_fight(54)
	away.state.items = ["smoke"]
	var gold: int = away.state.gold
	var anger: float = away.state.foe.meters.anger
	var foe = away.state.foe
	await away.go("menu")
	await away.press("6")
	await away.press("1")
	_check(away.state.stage == "explore" and away.state.gold == gold, "smoke leaves the fight at no cost")
	_check(foe.meters.anger == anger, "and no grudge")
	var champ = await _item_fight(55)
	champ.state.foe.boss = true
	champ.state.items = ["smoke"]
	await champ.go("menu")
	await champ.press("6")
	await champ.press("1")
	_check(champ.state.stage == "menu" and champ.state.items.size() == 1, "not from a champion, and it keeps the smoke")
	# dying gives them back
	var retry = await _item_fight(56)
	retry.state.items = ["salve"]
	retry.state.encounter_start.items = ["salve"]
	retry.state.encounter_start.sharpened = 0
	await retry.go("menu")
	await retry.press("6")
	await retry.press("1")
	_check(retry.state.items.is_empty(), "(used)")
	retry.state.stage = "dead"
	await retry.encounter.retry_fight()
	_check(retry.state.items == ["salve"], "trying the fight again gives back what it used (%s)" % [retry.state.items])
	# on the floor
	var walk = _flow(57)
	await walk.new_run()
	var ws = walk.state
	var f = ws.floor_map
	_check(f.pickups.size() >= int(Items.table().pickups_per_floor), "a floor has things lying about (%d)" % f.pickups.size())
	var thing: Dictionary = f.pickups[0]
	ws.banner = null
	_face(ws, thing.cell)
	await walk.press("up")
	_check(ws.items == [thing.item] and f.pickup_at(thing.cell) == "", "walking over one picks it up (%s)" % [ws.items])
	_check(ws.banner != null, "and something on the picture says so")
	ws.items = ["salve", "salve", "salve", "salve", "salve", "salve"]
	var left: Dictionary = f.pickups[0]
	_face(ws, left.cell)
	await walk.press("up")
	_check(ws.items.size() == 6 and f.pickup_at(left.cell) == left.item, "a full bag leaves it where it lies")
	ws.items = ["salve"]
	ws.sharpened = 4
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ws.to_dict()))
	saved.items = ["salve", "not a thing", 3]
	var back = _flow(57)
	await back.load_state(saved)
	_check(back.state.items == ["salve"] and back.state.sharpened == 4, "the bag saves, and what isn't an item doesn't load (%s)" % [back.state.items])
	var den: Dictionary = Floors.plan(2, {"only_species": "rock"})
	den.items = true
	_check(FloorGen.generate(Rng.new(5), den).pickups.any(func(p): return p.item == Items.gift_for("rock")), "a kind's own territory has the gift it loves")
	for id in Items.table().items:
		_check(Overlay.banner_fits(str(Items.info(id).sub)), "%s's line fits the banner" % id)
	_use()


## A fight at the menu with `species`, its health raised so nothing ends it by accident.
func _heavy_fight(seed_value: int, species: String, words := []) -> Variant:
	var flow = _flow(seed_value, words)
	var m = await _at_menu(flow, species)
	m.max_hp = 200
	m.hp = 200
	flow.coach.enabled = false
	flow.state.banner = null
	return flow


func _close_camera() -> void:
	_flow(74)
	# how wide you see follows the picture (the scene sets it, as wide as it has made the picture)
	var f = FloorMap.new()
	f.size = 21
	f.grid = []
	for y in 21:
		var row := []
		for x in 21:
			row.append(0 if x == 0 or y == 0 or x == 20 or y == 20 else 1)
		f.grid.append(row)
	var narrow: Array = Vision.sight(f, Vector2i(10, 10), 0)
	Vision.view_tan = Vision.VIEW_TAN * 1.5
	var wide: Array = Vision.sight(f, Vector2i(10, 10), 0)
	Vision.view_tan = Vision.VIEW_TAN
	_check(wide.size() > narrow.size(), "a wider picture takes in more of the floor (%d cells, not %d)" % [wide.size(), narrow.size()])
	_use()


func _heavy_strike() -> void:
	_heavy_trade()
	# on the menu, after the four that keep their places
	var flow = await _heavy_fight(61, "rock")
	var s = flow.state
	var m = s.foe
	_check(s.menu.size() == 6 and s.menu[4].label == "HEAVY" and s.menu[3].label == "FLEE", "HEAVY comes after the other four (%s)" % str(s.menu.map(func(i): return i.label)))
	var plain_dur: float = Combat.bar_ms(false)
	await flow.press("5")
	_check(s.stage == "fightbar" and s.bar.heavy and is_equal_approx(s.bar.dur, plain_dur * Combat.HEAVY_BAR_SCALE), "the line runs faster (%.0f ms)" % s.bar.dur)
	_check(s.hint.contains("MARK"), "and the hint points at the mark (%s)" % s.hint)
	# a landed blow: harder on a rock, and now you know
	flow.clock = s.bar.t0 + s.bar.dur / 2.0
	await flow.press("confirm")
	var landed: Dictionary = Combat.heavy_strike(0.5, false, "rock", false)
	_check(m.hp == 200 - landed.damage and landed.damage > Combat.strike(0.5, false, false).damage, "a heavy blow in the mark hits harder (%d)" % landed.damage)
	_check(s.heavy_known.has("rock"), "the first one shows how the kind takes it")
	_check(s.banner != null and str(s.banner.text).contains("do more"), "and says so (%s)" % str(s.banner))
	_check(s.lines[0].text.contains("do more"), "in the log too, in case a tip holds the banner (%s)" % s.lines[0].text)
	var known = await _heavy_fight(66, "rock")
	known.state.heavy_known = s.heavy_known
	await known.go("menu")
	_check(known.state.menu[4].sub.contains("badly") and known.state.menu[4].get("gold", false), "from then on the menu says it (%s)" % known.state.menu[4].sub)
	var back = State.from_dict(s.to_dict())
	_check(back.heavy_known.has("rock"), "a save keeps what you found out")
	var dict: Dictionary = s.to_dict()
	dict.heavyKnown = ["rock", "nonsense", 3]
	_check(State.from_dict(dict).heavy_known.keys() == ["rock"], "and what isn't a kind of monster doesn't load")
	dict.erase("heavyKnown")
	_check(State.from_dict(dict).heavy_known.is_empty(), "a save from before it knows nothing")
	# a kind that takes it plainly has nothing to announce
	var plain = await _heavy_fight(62, "bandit")
	await plain.press("5")
	plain.clock = plain.state.bar.t0 + plain.state.bar.dur / 2.0
	await plain.press("confirm")
	_check(plain.state.heavy_known.has("bandit") and (plain.state.banner == null or not str(plain.state.banner.text).contains("Heavy")), "a bandit takes it plainly, so nothing is announced")
	# a blow outside the mark misses where FIGHT would have landed, and the next attack presses harder
	var wide := 0.5 + Combat.HEAVY_MISS_EDGE # as far out as twice the edge: off the mark, on the bar
	_check(Combat.heavy_strike(wide, false, "rock", false).miss and not Combat.strike(wide, false, false).miss, "off the mark is a miss, where FIGHT would land")
	var pressures := []
	for label in ["1", "5"]:
		var swing = await _heavy_fight(63, "bandit")
		await swing.press(label)
		swing.clock = swing.state.bar.t0 + swing.state.bar.dur * (0.02 if label == "1" else 0.2)
		await swing.press("confirm")
		_check(swing.state.stage == "wait" and swing.state.foe.hp == 200, "a miss does nothing to it (%s)" % label)
		if swing.state.hint == "ANY KEY CONTINUE":
			await swing.press("confirm")
		swing.clock += Combat.WINDUP_MS + 1.0
		await swing.tick(swing.clock)
		pressures.append(swing.state.dodge.intensity)
	_check(is_equal_approx(pressures[1] - pressures[0], Combat.dodge_intensity(Combat.HEAVY_MISS_PRESSURE, false) - Combat.dodge_intensity(0.0, false)), "a heavy miss leaves you off balance (%.2f against %.2f)" % [pressures[1], pressures[0]])
	# what else adds to a strike adds to this one
	_check(Combat.heavy_strike(0.5, false, "rock", true, 3).damage == landed.damage + Combat.HOARD_FIRE_BONUS + 3, "the charm, allies and a whetstone add to it")
	_check(Combat.heavy_strike(0.5, true, "rock", false).damage < landed.damage, "and a champion takes less, as from any strike")
	# the tip follows the menu's own
	var told = _flow(67)
	told.coach.seen = {"menu": true}
	await told.new_run()
	told.state.banner = null
	await told.go("intro", {"foe": told.state.floor_map.monsters[0]})
	await told.tick(told.clock + 1000.0)
	await told.press("confirm")
	_check(told.coach.seen.has("heavy"), "a tip tells of it once the menu's has been seen")
	# off
	var off = _flow(64, ["no-heavy-strike"])
	await _at_menu(off, "rock")
	_check(off.state.menu.size() == 5 and off.state.menu[4].label == "ITEM" and off.state.menu[4].disabled, "no-heavy-strike: the four commands and disabled ITEM remain")
	_use()


## The trade is real: over the same timing, FIGHT and HEAVY compared by the damage you can expect. Timing error is normally spread,
## in ms, since a faster line gives the same hand less room. Steady hands should want it against a rock and never against a slime,
## a bandit should be about even, and an unsteady hand should stay with FIGHT.
func _heavy_trade() -> void:
	# Every species carries its own number for a heavy blow (`data/species.json`, "heavy"); one that didn't would be fought
	# against the plain default without a word.
	var cast: Array = Content.table("species").keys()
	for species in cast:
		var own = Content.species(species).get("heavy")
		_check(own is float and float(own) > 0.0, "%s says how it takes a heavy blow (%s)" % [species, str(own)])
	var weighed: Array = Combat.heavy_species()
	_check(weighed.size() == cast.size(), "every species takes it on a number of its own (%d of %d)" % [weighed.size(), cast.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	var half: float = Combat.bar_ms(false) / 2.0
	var mean := {}
	for error_ms in [50.0, 80.0, 200.0]:
		var row := {"quick": 0.0}
		for species in weighed:
			row[species] = 0.0
		for _i in 4000:
			var e: float = rng.randfn(0.0, error_ms)
			row.quick += Combat.strike(clampf(0.5 + e / half / 2.0, 0.0, 1.0), false, false).damage / 4000.0
			for species in weighed:
				var x := clampf(0.5 + e / (half * Combat.HEAVY_BAR_SCALE) / 2.0, 0.0, 1.0)
				row[species] += Combat.heavy_strike(x, false, species, false).damage / 4000.0
		mean[error_ms] = row
		print("heavy-strike: timing error %.0f ms, damage per swing: FIGHT %.1f, HEAVY %s" % [error_ms, row.quick, ", ".join(weighed.map(func(k): return "%s %.1f" % [k, row[k]]))])
	_check(mean[50.0].rock > mean[50.0].quick * 1.3, "steady hands want it against a rock (%.1f against %.1f)" % [mean[50.0].rock, mean[50.0].quick])
	_check(absf(mean[80.0].bandit - mean[80.0].quick) < mean[80.0].quick * 0.15, "against a bandit it is about even (%.1f against %.1f)" % [mean[80.0].bandit, mean[80.0].quick])
	for error_ms in mean:
		_check(mean[error_ms].slime < mean[error_ms].quick, "against a slime FIGHT is always better (%.0f ms: %.1f against %.1f)" % [error_ms, mean[error_ms].slime, mean[error_ms].quick])
	for species in weighed:
		_check(mean[200.0][species] < mean[200.0].quick, "an unsteady hand stays with FIGHT against a %s (%.1f against %.1f)" % [species, mean[200.0][species], mean[200.0].quick])


func _shop() -> void:
	var flow = _flow(61)
	await flow.new_run()
	var s = flow.state
	_check(not Items.shop_on(1) and s.floor_map.merchant.is_empty(), "the first floor has no trader")
	s.foe = null
	await flow.next_floor()
	var f = s.floor_map
	_check(Items.shop_on(2) and not f.merchant.is_empty(), "the second has")
	s.gold = 8
	s.items = []
	s.banner = null
	_face(s, f.merchant.cell)
	var stood: Vector2i = s.cell
	await flow.press("up")
	_check(s.stage == "trade" and s.cell == stood, "walking into the trader opens the shelf (%s)" % s.stage)
	_check(s.menu.size() == f.merchant.stock.size() + 1 and s.menu[-1].label == "LEAVE", "its stock and a way out")
	var id: String = f.merchant.stock[0]
	var price := int(Items.info(id).price)
	s.gold = price - 1
	await flow.press("1")
	_check(s.items.is_empty() and s.gold == price - 1 and s.lines[0].text.contains("costs"), "too dear: nothing changes, and it says why")
	s.gold = price + 2
	await flow.press("1")
	_check(s.items == [id] and s.gold == 2 and not f.merchant.stock.has(id), "buying takes the gold, and it is off the shelf")
	_check(s.stage == "trade", "and you are still at the shelf")
	s.gold = 99
	s.items = ["salve", "salve", "salve", "salve", "salve", "salve"]
	var shelf: int = f.merchant.stock.size()
	await flow.press("1")
	_check(s.gold == 99 and f.merchant.stock.size() == shelf, "a full bag buys nothing")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	await flow.press("cancel")
	_check(s.stage == "explore" and s.cell == stood, "ESC walks off")
	var back = _flow(61)
	await back.load_state(saved)
	_check(back.state.floor_map.merchant.stock.size() == shelf, "what is sold stays sold in a save")
	_check(f.in_the_way(f.merchant.cell), "routes go round the trader")
	_use()


## A floor of this seed's, on the given depth, with things standing as they do on it.
func _floor_with_lurker(seed_value: int, words := []) -> Variant:
	var flow = _flow(seed_value, words)
	await flow.new_run()
	return flow


func _lurkers() -> void:
	var flow = await _floor_with_lurker(71)
	var s = flow.state
	var f = s.floor_map
	var stirs: Array = f.monsters.filter(func(m): return m.lurking)
	_check(not stirs.is_empty(), "something stirs on the floor (%d)" % stirs.size())
	var m = stirs[0]
	_check(m.purse > 0 and not m.boss, "it has a purse, and it is no champion")
	_check(f.monsters.back().boss, "the champion is still the last in the list")
	_check(Floors.fights_required(f) <= f.monsters.filter(func(o): return not o.lurking).size(), "the walk to the stairs doesn't count on going through one")
	var again = await _floor_with_lurker(71)
	_check(JSON.stringify(again.state.floor_map.to_dict()) == JSON.stringify(f.to_dict()), "the same seed stirs the same way")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var back = _flow(71)
	await back.load_state(saved)
	var kept: Array = back.state.floor_map.monsters.filter(func(o): return o.lurking)
	_check(kept.size() == stirs.size() and kept[0].purse == m.purse, "a save keeps them stirring, with their purses")
	s.banner = null
	_face(s, m.cell)
	var stood: Vector2i = s.cell
	var gold: int = s.gold
	await flow.press("up")
	_check(s.stage == "intro" and s.foe == m and s.cell == stood, "walking into it starts a fight (%s)" % s.stage)
	_check(not m.lurking, "and you see what it was")
	_check(s.banner != null and Overlay.banner_fits(s.banner.text), "the picture says so, and it fits")
	await flow.tick(flow.clock + 5000.0)
	_check(s.encounter_start.foe.lurking == false, "a retried fight is against something you've seen")
	var purse: int = m.purse
	await flow.encounter.defeat(m, "slain")
	_check(s.gold == gold + purse and m.purse == 0, "out of the fight it leaves its purse (%d)" % s.gold)
	var way: Dictionary = Floors.plan(2, {"count": 2})
	way.lurkers = true
	_check(FloorGen.generate(Rng.new(5), way).monsters.all(func(o): return not o.lurking), "a quiet way down is quiet")
	var tips = await _floor_with_lurker(72)
	var ts = tips.state
	_face(ts, ts.floor_map.monsters.filter(func(x): return x.lurking)[0].cell)
	ts.facing = posmod(ts.facing - 1, 4)
	ts.banner = null
	await tips.press("right")
	_check(tips.coach.seen.has("lurker"), "the first one you face gets a tip (%s)" % [tips.coach.seen.keys()])
	_check(Overlay.banner_fits(str(Content.table("coach").tips.lurker)) and Overlay.banner_fits(str(Content.table("coach").tips.request)), "the tips fit the banner")
	_use()


## A floor with someone asking for this, whichever seed from `start` gives one.
func _asking(start: int, kind: String) -> Variant:
	for i in 200:
		var flow = _flow(start + i)
		await flow.new_run()
		if not flow.state.floor_map.quester.is_empty() and flow.state.floor_map.quester.kind == kind:
			return flow
	_check(false, "no seed has someone asking for %s" % kind)
	return null


## The faction lords (#77): each biome's lord asks on the first floor of that biome, its name and title from the data, the run
## remembers it was met, and paying its favour moves its clan by the lord's number.
func _lords() -> void:
	var flow = _flow(7)
	await flow.new_run()
	var q: Dictionary = flow.state.floor_map.quester
	_check(not q.is_empty() and str(q.get("title", "")) != "", "a biome's first floor has its lord asking")
	_check(str(q.species) == "bandit" and str(q.name) == str(Lords.table().lords.crew.name), "the halls' lord is the Crew's (%s, %s)" % [q.get("name", ""), q.get("title", "")])
	var again = _flow(7)
	await again.new_run()
	var bq: Dictionary = again.state.floor_map.quester
	_check(bq.name == q.name and bq.title == q.title and bq.kind == q.kind, "the same seed gives the same lord")
	var clan := str(q.lord)
	var before: float = Clans.standing_of(flow.state, q.species)
	flow.state.hp = maxi(1, flow.state.max_hp - 12) # room for all the health it pays, or the cap swallows it
	var paid: Dictionary = Requests.settle(q, flow.state)
	var pays: Dictionary = Lords.pays()
	_check(paid.gold == int(pays.gold) and paid.healed == int(pays.heal), "a lord pays its own gold and health (%d, %d)" % [paid.gold, paid.healed])
	_check(flow.state.lords_met.has(clan), "and the run remembers it was met")
	_check(is_equal_approx(Clans.standing_of(flow.state, q.species) - before, float(pays.standing)), "its clan moves by the lord's number (%.0f)" % float(pays.standing))
	var old: Dictionary = flow.state.to_dict()
	old.erase("lordsMet")
	old.erase("lordsSworn")
	var back = State.from_dict(old)
	_check(back != null and back.lords_met.is_empty() and back.lords_sworn.is_empty(), "a save from before lords has met none")
	var kept = State.from_dict(flow.state.to_dict())
	_check(kept != null and kept.lords_met == [clan], "and a save keeps the ones met")
	# the second favour, where the biome comes back: the same lord, and paying it swears the clan
	var back_flow = _flow(7)
	await back_flow.new_run()
	back_flow.state.lords_met = [clan]
	back_flow.state.depth = 4
	await back_flow._make_floor()
	var second_q: Dictionary = back_flow.state.floor_map.quester
	_check(not second_q.is_empty() and str(second_q.get("lord", "")) == clan and second_q.get("big", false), "where the biome comes back its lord asks again (%s)" % str(second_q.get("title", "")))
	_check(str(second_q.get("name", "")) == q.name, "the same lord, not another")
	back_flow.state.hp = maxi(1, back_flow.state.max_hp - 12)
	Requests.settle(second_q, back_flow.state)
	_check(back_flow.state.lords_sworn.has(clan), "its second favour swears the clan")
	_check(Clans.mood_word(Clans.standing_of(back_flow.state, second_q.species)) == "FRIENDLY", "which now stands friendly")
	_check(back_flow.state.allies.any(func(a): return str(a.name) == str(second_q.name)), "and the lord comes along while there is room")
	var pact: Dictionary = Lords.pact()
	var clan_name := Clans.title(clan)
	_check(Overlay.banner_fits(str(pact.title) % clan_name.to_upper()) and Overlay.banner_fits(str(pact.line) % clan_name), "the pact's banner fits the picture")
	# no place in the party: the clan opens its warren on the next stairs instead
	var warren_flow = _flow(7)
	await warren_flow.new_run()
	warren_flow.state.allies = [Ally.make("slime", "A", 70.0), Ally.make("rock", "B", 70.0), Ally.make("snake", "C", 70.0)]
	var joined := Requests.swear(warren_flow.state, "crew", {"species": "bandit", "name": "SIRRA"})
	_check(not joined and warren_flow.state.lords_warren.has("crew"), "with no place in the party the lord opens its warren instead")
	var ways: Array = Floors.paths(warren_flow.state.run_seed, 1, true, warren_flow.state.lords_warren)
	_check(ways.size() == 2 and str(ways[0].get("only_species", "")) == "bandit", "the stairs offer its clan's warren first (%s)" % str(ways[0].get("label", "")))
	_check(str(ways[0].label) == "THE BANDIT WARREN", "and say what waits below (%s)" % str(ways[0].label))
	warren_flow.state.allies = []
	var kept_warren = State.from_dict(warren_flow.state.to_dict())
	_check(kept_warren != null and kept_warren.lords_warren == ["crew"], "a save keeps the warren the lord opened")
	Clans.favour(back_flow.state, second_q.species, -200.0)
	_check(Clans.hostility_of(back_flow.state, second_q.species) == "angry", "a sworn clan never falls past angry (%s)" % Clans.hostility_of(back_flow.state, second_q.species))
	# The party has three places for monsters, and the little witch takes none of them: the list of allies is not the party.
	var room_flow = await _lord_again(clan)
	var room_q: Dictionary = room_flow.state.floor_map.quester
	room_flow.state.allies = [Ally.make("witch", "WICK", 75.0), Ally.make("slime", "GLOP", 60.0), Ally.make("rock", "OLD SHALE", 60.0)]
	_check(room_flow.state.party_size() == Combat.PARTY_MAX - 1, "with two monsters along, one place is free (%d of %d)" % [room_flow.state.party_size(), Combat.PARTY_MAX])
	Requests.settle(room_q, room_flow.state)
	_check(room_flow.state.party_size() == Combat.PARTY_MAX and room_flow.state.has_ally(str(room_q.species)), "a sworn lord takes the last place, not the one before it")
	room_flow.event("lord_joined", {"species": str(room_q.species)}) # what the request stage says when it came along
	_check(room_flow.trophies.earned.has("party") and not room_flow.trophies.earned.has("friend"), "filling the table with it is an achievement, though nobody was spared (%s)" % str(room_flow.trophies.earned))
	var full_flow = await _lord_again(clan)
	var full_q: Dictionary = full_flow.state.floor_map.quester
	full_flow.state.allies = [Ally.make("witch", "WICK", 75.0), Ally.make("slime", "GLOP", 60.0), Ally.make("rock", "OLD SHALE", 60.0), Ally.make("snake", "HISS", 60.0)]
	_check(full_flow.state.party_size() == Combat.PARTY_MAX, "three monsters are a full party with her along")
	_check(not Requests.settle(full_q, full_flow.state).joined, "a full party leaves a lord no place")
	_check(full_flow.state.lords_sworn.has(clan), "the clan is sworn even so")
	# The four lords on the first floor of their own biome, over enough seeds to meet every one: its own favour; a fetch
	# names something lying on that floor; a spare names kin; and the lord never stands on a monster.
	var met := {}
	var kinds := {}
	var lost := 0
	for seed_value in range(1, 21):
		flow.state.run_seed = seed_value
		flow.state.lords_met = []
		for depth in range(1, 4):
			flow.state.depth = depth
			flow._make_floor()
			var f = flow.state.floor_map
			var lord_q: Dictionary = f.quester
			if lord_q.is_empty():
				lost += 1
				continue
			var home := str(lord_q.get("lord", ""))
			met[home] = true
			kinds[str(lord_q.kind)] = true
			_check(Lords.table().lords.has(home) and str(lord_q.get("title", "")) != "", "B%dF of seed %d has a lord of the data (%s)" % [depth, seed_value, home])
			if str(lord_q.kind) == "fetch":
				_check(f.pickups.any(func(p): return str(p.item) == str(lord_q.want)), "seed %d B%dF: the lord's fetch lies on the floor (%s)" % [seed_value, depth, lord_q.want])
			else:
				var target = f.monsters[int(lord_q.target)]
				_check(not target.boss and not target.lurking, "the lord names a monster that can be dealt with")
				if str(lord_q.kind) == "spare":
					_check(target.species == str(lord_q.species), "its kin is one of its own (%s)" % target.species)
			_check(f.monsters.all(func(m): return m.cell != lord_q.cell), "seed %d B%dF: the lord does not stand on a monster" % [seed_value, depth])
	_check(lost == 0, "over twenty seeds every first floor of a biome has its lord")
	_check(met.size() == Lords.table().lords.size(), "over twenty seeds every lord asks (%s)" % str(met.keys()))
	_check(kinds.has("fetch") and kinds.has("spare") and kinds.has("rid"), "each kind of favour is asked (%s)" % str(kinds.keys()))
	for home in Lords.table().lords:
		_check(Content.table("clans").clans.has(home) and str(Lords.table().lords[home].title) != "", "the lord of %s names a clan and a title" % home)
	var first: Dictionary = Lords.due("caves", 0, [])
	var second: Dictionary = Lords.due("caves", 0, [first.clan])
	_check(not first.is_empty() and not second.is_empty() and first.clan != second.clan, "the caves' two lords take turns by the floor's seed")
	_check(Lords.due("caves", 0, [first.clan, second.clan]).is_empty(), "a run that has met both caves lords meets none")
	_check(Lords.due("halls", 0, ["crew"]).is_empty(), "a met lord does not ask again")


## A run where the halls come back (depth 4 of seed 7) and `clan`'s lord was met on B1F: its second favour is asking there.
func _lord_again(clan: String) -> Variant:
	var flow = _flow(7)
	await flow.new_run()
	flow.state.lords_met = [clan]
	flow.state.depth = 4
	await flow._make_floor()
	return flow


func _npcs() -> void:
	var t: Dictionary = Requests.table()
	_check(Requests.due(1) and not Requests.due(2), "some floors have someone asking")
	for kind in t.kinds:
		for key in ["ask", "wait", "ready", "thanks", "yes", "give", "sub"]:
			_check(t.kinds[kind].has(key), "%s says %s" % [kind, key])
	# fetching
	var flow = await _asking(100, "fetch")
	var s = flow.state
	var f = s.floor_map
	var q: Dictionary = f.quester
	_check(f.pickups.any(func(p): return p.item == q.want), "what it wants lies on this floor")
	_check(f.in_the_way(q.cell) and f.reserved().has(q.cell), "routes go round it")
	s.banner = null
	_face(s, q.cell)
	var stood: Vector2i = s.cell
	s.gold = 0
	s.hp = 3
	s.items = []
	await flow.press("up")
	_check(s.stage == "request" and s.cell == stood, "walking up to it opens a talk, not a fight (%s)" % s.stage)
	_check(s.foe == null and s.lines[0].kind == "say" and s.lines[0].who == q.name, "it says what it wants")
	_check(s.lines[0].text.contains(Items.label(q.want)), "by name (%s)" % s.lines[0].text)
	_check(s.menu.size() == 2 and s.menu[0].label == t.kinds.fetch.yes, "and you answer")
	_check(s.questers_met.has(q.name), "its name is heard, and kept (%s)" % q.name)
	await flow.press("1")
	_check(s.stage == "explore" and q.taken, "you say you will, and walk on")
	await flow.press("up")
	_check(s.stage == "request" and s.menu.size() == 1, "come back empty-handed and there's only leaving")
	await flow.press("cancel")
	s.items = [q.want]
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	await flow.press("up")
	_check(s.menu[0].label == t.kinds.fetch.give, "with it in the bag you can hand it over")
	await flow.press("1")
	_check(s.stage == "explore" and s.items.is_empty(), "it takes it")
	_check(s.gold == int(t.gold) and s.hp == 3 + int(t.heal), "and pays (%d gold, %d hp)" % [s.gold, s.hp])
	_check(f.quester.is_empty() and not f.in_the_way(stood + f.DIRS[s.facing]), "then it's gone, and so is what stood in the way")
	_check(s.names_met().has(str(q.name).to_upper()), "and its name is still one met, so no later floor takes it")
	_check(s.reputation.get(Clans.of(q.species), 0.0) > 0.0, "and its clan thinks better of you")
	_check(s.banner != null and Overlay.banner_fits(s.banner.text), "the banner says so and fits")
	var back = _flow(s.run_seed)
	await back.load_state(saved)
	var bq: Dictionary = back.state.floor_map.quester
	_check(bq.taken and bq.kind == "fetch" and bq.want == q.want and bq.cell == q.cell, "a save keeps the request as it stood")
	_check(back.state.questers_met.has(q.name), "and the name it heard")
	# sparing
	var kin = await _asking(300, "spare")
	var ks = kin.state
	var kq: Dictionary = ks.floor_map.quester
	var target = ks.floor_map.monsters[kq.target]
	_check(kq.species == target.species and not target.boss, "kin is its own kind")
	_check(Requests.status(kq, ks) == "new", "not yet asked")
	target.gone = "spared"
	_check(Requests.status(kq, ks) == "ready", "spared is done")
	target.gone = "slain"
	_check(Requests.status(kq, ks) == "failed", "killed isn't")
	ks.banner = null
	_face(ks, kq.cell)
	await kin.press("up")
	_check(ks.menu.size() == 1 and ks.lines[0].text.contains(target.name), "it says so and has nothing to offer (%s)" % ks.lines[0].text)
	var before: int = ks.gold
	await kin.press("1")
	_check(ks.floor_map.quester.is_empty() and ks.gold == before, "and it's gone, with nothing paid")
	# getting rid
	var rid = await _asking(500, "rid")
	var rq: Dictionary = rid.state.floor_map.quester
	var whom = rid.state.floor_map.monsters[rq.target]
	whom.gone = "slain"
	_check(Requests.status(rq, rid.state) == "ready", "gone is gone, whichever way")
	# the fights it's about are the same after a retry
	var saves: Dictionary = JSON.parse_string(JSON.stringify(rid.state.to_dict()))
	saves.floor.quester.target = 999
	_check(not State.is_playable(saves), "a request about nobody doesn't load")
	var bare: Dictionary = Floors.plan(2, {})
	bare.request = true
	var kinds := {}
	for i in 40:
		var made = FloorGen.generate(Rng.new(100 + i), bare)
		if not made.quester.is_empty():
			kinds[made.quester.kind] = true
	_check(not kinds.has("fetch") and not kinds.is_empty(), "with nothing lying about, nobody asks you to fetch (%s)" % [kinds.keys()])
	_use()


## A random walk of `steps` steps on the floor as `flow` has it, the monsters' turns in between: where everybody stood after each.
## `problems` collects what should never be. A monster that catches you puts you back at the start.
func _roam(flow, steps: int, rng_seed: int, problems: Dictionary) -> Array:
	var s = flow.state
	var f = s.floor_map
	var rng := Rng.new(rng_seed)
	var path := []
	var note := func(what: String): problems[what] = problems.get(what, 0) + 1
	for _i in steps:
		var ways := []
		for d in f.DIRS:
			var c: Vector2i = s.cell + d
			if f.is_open(c) and f.monster_at(c) == null and not f.in_the_way(c) and c != f.stairs:
				ways.append(c)
		if not ways.is_empty():
			s.cell = rng.pick(ways)
		var before := {}
		for m in f.monsters:
			before[m] = m.cell
		var done := Roaming.turn(s, {"revenge": true, "boss_chase": false})
		var barred: Dictionary = f.reserved()
		for t in f.treasure:
			barred[t.cell] = true
		for m in f.monsters:
			if m.is_gone():
				continue
			if not f.is_open(m.cell):
				note.call("a monster in a wall")
			if m.cell != before[m] and (barred.has(m.cell) or m.cell == f.stairs):
				note.call("a monster on something it may not stand on")
			if absi(m.cell.x - before[m].x) + absi(m.cell.y - before[m].y) > 1:
				note.call("a monster that jumped")
			if m.lurking and m.cell != before[m]:
				note.call("something stirring that moved")
			if m.boss and m.cell != before[m]:
				note.call("a champion that left without boss-chase")
			if f.monsters.any(func(o): return o != m and not o.is_gone() and o.cell == m.cell):
				note.call("two monsters in one cell")
			if m.cell == s.cell:
				note.call("a monster on top of you")
		if done.caught != null:
			s.cell = f.start
			done.caught.hold = 8
		path.append(f.monsters.map(func(m): return m.cell))
	return path


func _roaming() -> void:
	var t: Dictionary = Roaming.table()
	# many seeds: nothing stands where it shouldn't, and the same seed and steps walk the same way, a save or not
	var problems := {}
	var moved := 0
	for i in 12:
		var one = _flow(800 + i)
		await one.new_run()
		var before: Array = one.state.floor_map.monsters.map(func(m): return m.cell)
		var path := _roam(one, 150, i, problems)
		if path[-1] != before:
			moved += 1
		var two = _flow(800 + i)
		await two.new_run()
		_check(path == _roam(two, 150, i, {}), "seed %d: the same seed and steps give the same paths" % (800 + i))
		var three = _flow(800 + i)
		await three.new_run()
		var first := _roam(three, 75, i, {})
		var saved: Dictionary = JSON.parse_string(JSON.stringify(three.state.to_dict()))
		var loaded = _flow(800 + i)
		await loaded.load_state(saved)
		var whole_run = _flow(800 + i)
		await whole_run.new_run()
		var whole := _roam(whole_run, 75, i, {})
		_check(first == whole and saved.floor.steps == 75, "seed %d: (the first half is the same)" % (800 + i))
		_check(_after_load_same(whole_run, loaded), "seed %d: a save and load changes nothing about where they go" % (800 + i))
	_check(problems.is_empty(), "12 seeds, 150 steps each: nothing stands where it shouldn't %s" % [problems])
	_check(moved == 12, "and things did move (%d of 12)" % moved)
	# species: on a floor from pictures rows
	var flow = _flow(860)
	await flow.new_run()
	var s = flow.state
	var f = s.floor_map
	var m = f.monsters.filter(func(o): return not o.lurking and not o.boss)[0]
	f.monsters = [m, f.monsters.back()]
	f.quester = {} # a floor with a request keeps the monster it asks about; this one is down to two and a save must still load
	var bare := func(sp: String):
		m.species = sp
		m.meters = {"friendliness": 0.0, "anger": 0.0, "fear": 0.0}
		m.patrol = []
		m.hold = 0
		m.hunting = false
		s.reputation = {}
	bare.call("rock")
	var at: Vector2i = m.cell
	for _i in 6:
		Roaming.turn(s)
	_check(m.cell == at, "a rock stays where it is")
	bare.call("slime")
	var moves := 0
	for _i in 40:
		var was: Vector2i = m.cell
		var on_even: bool = (f.steps + 1) % 2 == 0
		Roaming.turn(s)
		if m.cell != was:
			moves += 1
			_check(on_even, "a slime moves only every other step")
	_check(moves > 8, "and drifts when it does (%d)" % moves)
	bare.call("bandit")
	var seen_cells := {}
	for _i in 40:
		Roaming.turn(s)
		seen_cells[m.cell] = true
	_check(seen_cells.size() > 3 and m.patrol.size() == 2, "a bandit walks a beat (%d cells)" % seen_cells.size())
	# who is near: put them by the walk from you
	var field: Dictionary = Roaming._field(f, s.cell, Roaming._barred(f))
	var cell_at := func(d: int) -> Vector2i:
		for c in field:
			if field[c] == d:
				return c
		return s.cell
	bare.call("snake")
	var far: int = int(t.species.snake.sense) + int(t.species.snake.keeps_on) + 2
	m.cell = cell_at.call(far)
	var waiting: Vector2i = m.cell
	Roaming.turn(s)
	_check(m.cell == waiting and not m.hunting, "a snake waits while you are far (%d)" % far)
	m.cell = cell_at.call(int(t.species.snake.sense))
	var done := Roaming.turn(s)
	_check(m.hunting and done.noticed == [m] and Roaming._field(f, s.cell, Roaming._barred(f))[m.cell] == int(t.species.snake.sense) - 1, "close by, it comes after you, and you are told")
	_check(Roaming.turn(s).noticed.is_empty(), "(once)")
	# how it feels overrides who it is
	bare.call("rock")
	m.meters.anger = float(t.angry_at)
	m.cell = cell_at.call(3)
	Roaming.turn(s)
	_check(Roaming._field(f, s.cell, Roaming._barred(f))[m.cell] == 2, "an angry monster comes after you, even a rock")
	bare.call("rock")
	m.meters.fear = float(t.afraid_at)
	m.cell = cell_at.call(3)
	Roaming.turn(s)
	_check(Roaming._field(f, s.cell, Roaming._barred(f))[m.cell] >= 3, "a frightened one won't come closer")
	bare.call("rock")
	m.meters.friendliness = float(t.friendly_at)
	m.cell = cell_at.call(1)
	var near_you: Vector2i = m.cell
	_check(Roaming.turn(s).caught == null and m.cell == near_you, "a friendly one comes up and stops short of a fight")
	bare.call("rock")
	s.reputation = {Clans.of("rock"): float(t.revenge_at)}
	m.cell = cell_at.call(int(t.revenge_sense))
	var wronged: Vector2i = m.cell
	Roaming.turn(s, {"revenge": false})
	_check(m.cell == wronged, "with no revenge asked for, a wronged clan's monster takes no notice")
	Roaming.turn(s, {"revenge": true})
	_check(m.cell != wronged and m.hunting, "with it, it comes for you from far off")
	# a whole floor, by the keys
	var walk = _flow(861)
	await walk.new_run()
	var ws = walk.state
	var wf = ws.floor_map
	var foe = wf.monsters.filter(func(o): return not o.lurking and not o.boss)[0]
	wf.monsters = [foe, wf.monsters.back()]
	foe.species = "snake"
	foe.meters = {"friendliness": 0.0, "anger": 0.0, "fear": 0.0}
	var walk_field: Dictionary = Roaming._field(wf, ws.cell, Roaming._barred(wf))
	var open_way := -1
	for i in 4:
		if wf.is_open(ws.cell + wf.DIRS[i]) and not wf.in_the_way(ws.cell + wf.DIRS[i]):
			open_way = i
	ws.facing = open_way
	var steps_before: int = wf.steps
	await walk.press("left")
	await walk.press("right")
	_check(wf.steps == steps_before, "turning gives nobody a turn")
	var wall_way := -1
	for i in 4:
		if not wf.is_open(ws.cell + wf.DIRS[i]) and not wf.is_cracked(ws.cell + wf.DIRS[i]):
			wall_way = i
	if wall_way >= 0:
		ws.facing = wall_way
		await walk.press("up")
		_check(wf.steps == steps_before, "nor does bumping a wall")
	ws.facing = open_way
	var next_cell: Vector2i = ws.cell + wf.DIRS[open_way]
	foe.cell = next_cell + wf.DIRS[open_way]
	if not wf.is_open(foe.cell) or wf.reserved().has(foe.cell) or foe.cell == wf.stairs:
		for d in wf.DIRS:
			if wf.is_open(next_cell + d) and next_cell + d != ws.cell and not wf.reserved().has(next_cell + d) and next_cell + d != wf.stairs:
				foe.cell = next_cell + d
	await walk.press("up")
	_check(ws.stage == "intro" and ws.foe == foe and ws.cell == next_cell, "a step next to a snake, and it walks into you: a fight (%s)" % ws.stage)
	_check(ws.lines[0].text.contains(foe.name) and ws.lines[0].kind == "sys", "and the log says who caught you (%s)" % ws.lines[0].text)
	await walk.tick(walk.clock + 5000.0)
	var frozen: Array = wf.monsters.map(func(o): return o.cell)
	var fight_steps: int = wf.steps
	for _i in 3:
		await walk.tick(walk.clock + 300.0)
	_check(frozen == wf.monsters.map(func(o): return o.cell) and wf.steps == fight_steps, "nobody moves during a fight")
	# backing away
	if ws.stage == "intro":
		await walk.press("confirm")
	while ws.stage != "menu":
		if ws.hint == "ANY KEY CONTINUE":
			await walk.press("confirm")
		await walk.tick(walk.clock + 500.0)
	await walk.press("4")
	_check(ws.stage == "explore" and foe.hold == int(t.flee_hold), "backing out of the fight (%s), it holds still (%d)" % [ws.stage, foe.hold])
	var stood_at: Vector2i = foe.cell
	var free_steps := 0
	for _i in int(t.flee_hold):
		var back_way := -1
		for i in 4:
			var c: Vector2i = ws.cell + wf.DIRS[i]
			if wf.is_open(c) and c != foe.cell and not wf.in_the_way(c) and c != wf.stairs and wf.monster_at(c) == null:
				back_way = i
		ws.facing = back_way
		await walk.press("up")
		if ws.stage == "explore" and foe.cell == stood_at:
			free_steps += 1
	_check(free_steps == int(t.flee_hold), "and doesn't start the same fight for %d steps (%d)" % [int(t.flee_hold), free_steps])
	# the stairs are checked before anybody's turn
	var last = _flow(862)
	await last.new_run()
	var ls = last.state
	var lf = ls.floor_map
	lf.monsters = [lf.monsters.back()]
	lf.monsters[0].gone = "spared"
	_face(ls, lf.stairs)
	var stairs_steps: int = lf.steps
	await last.press("up")
	_check(ls.stage == "end" and lf.steps == stairs_steps, "reaching the stairs ends the walk before anybody moves (%s)" % ls.stage)
	# the champion
	await _champion_moves()
	# off
	var still = _flow(860, ["no-roaming"])
	await still.new_run()
	var sf = still.state.floor_map
	var cells: Array = sf.monsters.map(func(o): return o.cell)
	for i in 4:
		var c: Vector2i = still.state.cell + sf.DIRS[i]
		if sf.is_open(c) and sf.monster_at(c) == null and not sf.in_the_way(c):
			still.state.facing = i
			await still.press("up")
			break
	_check(sf.steps == 0 and cells == sf.monsters.map(func(o): return o.cell), "no-roaming: nobody moves")
	var old: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	old.floor.erase("steps")
	for o in old.floor.monsters:
		for key in ["hold", "patrol", "leg", "hunting", "lastSeen"]:
			o.erase(key)
	var from_old = _flow(860)
	_check(await from_old.load_state(old), "a save from before this loads")
	for damage in [func(d): d.floor.steps = "x", func(d): d.floor.monsters[0].hold = "x", func(d): d.floor.monsters[0].patrol = [[0, 0], [0, 0]], func(d): d.floor.monsters[0].lastSeen = "x"]:
		var bad: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
		damage.call(bad)
		_check(not State.is_playable(bad), "a damaged save doesn't load")
	for tip in ["roaming", "hunted"]:
		_check(Overlay.banner_fits(str(Content.table("coach").tips[tip])), "the %s tip fits the banner" % tip)
	_use()


## Whether two runs are at the same place and go on the same way: 40 more steps from each.
func _after_load_same(a, b) -> bool:
	return _roam(a, 40, 9, {}) == _roam(b, 40, 9, {})


func _champion_moves() -> void:
	var held = _flow(870)
	await held.new_run()
	var hs = held.state
	var boss = hs.floor_map.monsters.back()
	hs.seen[boss.cell] = true
	var post: Vector2i = boss.cell
	for _i in 5:
		Roaming.turn(hs, {"boss_chase": true})
	_check(post == hs.floor_map.stairs and boss.cell == post, "with boss-at-exit, a champion holds the stairs, boss-chase or not")
	var free = _flow(870)
	await free.new_run()
	var fs = free.state
	var open_plan: Dictionary = Floors.plan(1)
	open_plan.boss_at_exit = false # a floor whose champion keeps to its hall
	fs.floor_map = FloorGen.generate(Rng.new(870), open_plan)
	fs.cell = fs.floor_map.start
	fs.seen = {}
	var ff = fs.floor_map
	var chaser = ff.monsters.back()
	var hall: Vector2i = chaser.cell
	Roaming.turn(fs, {"boss_chase": true})
	_check(chaser.cell == hall, "unseen, it stays in its hall")
	Roaming.turn(fs, {"boss_chase": false})
	fs.seen[hall] = true
	Roaming.turn(fs, {"boss_chase": false})
	_check(chaser.cell == hall, "with the chase off, it stays even once seen")
	Roaming.turn(fs, {"boss_chase": true})
	_check(chaser.cell != hall and chaser.hunting, "seen, with boss-chase, it comes after you")


## The rest of a floor goes onto the map late on (rules/chart.gd): by instinct once enough of it is seen, or from a monster that is
## out of the way and was carrying a map. (map_test checks the rules; this is the game doing it.)
func _charting() -> void:
	var Chart = load("res://src/rules/chart.gd")
	var flow = _flow(880)
	await flow.new_run()
	var s = flow.state
	var heard := []
	flow.happened.connect(func(name, d):
		if name == "charted":
			heard.append(d))
	var at := float(Chart.table().instinct_at)
	var cells: Array = s.reach().keys()
	await flow.press("right")
	_check(s.charted.is_empty() and heard.is_empty(), "with little of the floor seen (%.0f%%), nothing is charted" % (Chart.share(s) * 100.0))
	for i in ceili(cells.size() * at):
		s.seen[cells[i]] = true
	await flow.tick(flow.clock + 60000.0) # the run's own banner has gone: instinct doesn't talk over another banner
	await flow.press("left")
	var words: Dictionary = Chart.table().instinct
	_check(not s.charted.is_empty() and heard.size() == 1 and heard[0].how == "instinct" and int(heard[0].cells) == s.charted.size(), "at %.0f%% seen, instinct charts the rest (%d cells)" % [at * 100.0, s.charted.size()])
	_check(s.banner != null and s.banner.title == str(words.title) and s.lines.any(func(l): return l.text == str(words.line)), "and says so on the picture and in the log")
	_check(Chart.known(s, s.floor_map.stairs), "the stairs are on the map")
	await flow.press("right")
	_check(heard.size() == 1, "once a floor")
	await flow.new_run()
	s = flow.state
	_check(s.charted.is_empty(), "a new floor starts with nothing charted")
	# a monster's map: one that fled keeps it, one out of the way that rolled it hands it over
	var pair: Array = _map_carriers(Chart, flow)
	var carrier = pair[0]
	var other = pair[1]
	_check(carrier != null and other != null, "on this floor one monster carries a map and another is there to flee from (%d monsters)" % s.floor_map.monsters.size())
	if carrier == null or other == null:
		return
	await flow.go("intro", {"foe": other})
	await flow.go("menu")
	await flow.encounter.leave_fight([])
	_check(s.charted.is_empty() and heard.size() == 1, "a monster you left standing keeps its map")
	await flow.go("intro", {"foe": carrier})
	await flow.go("menu")
	carrier.gone = "spared"
	var ended := [State.sys_line("It falls."), State.sys_line("It is over."), State.sys_line("A friend has something to say.")]
	flow.announce("A PURSE", "something else holds the picture")
	await flow.encounter.leave_fight(ended)
	_check(not s.charted.is_empty() and heard.size() == 2 and heard[1].how == "map", "one out of the way hands its map over (%d cells charted)" % s.charted.size())
	_check(s.stage == "explore" and s.lines.any(func(l): return str(l.text).contains(carrier.name) and str(l.text).contains("map")), "and the log says who was carrying it")
	_check(s.banner.title == "A PURSE" and s.lines.size() == ended.size() + 1 and str(s.lines[0].text).contains(carrier.name) and str(s.lines[0].text).contains("map"), "with another banner on the picture the log says it first, where the lines the log cuts can't take it")
	_check(Chart.known(s, s.floor_map.stairs) and not Chart.instinct_due(s), "the stairs are on the map, and instinct has nothing left to add")
	# the same with the picture free: the banner says it, and the log's line comes after how the fight ended
	await flow.new_run()
	s = flow.state
	carrier = _map_carriers(Chart, flow)[0]
	_check(carrier != null, "the same floor again has the same carrier")
	if carrier == null:
		return
	await flow.go("intro", {"foe": carrier})
	await flow.go("menu")
	carrier.gone = "slain"
	s.banner = null
	await flow.encounter.leave_fight([State.sys_line("It falls.")])
	_check(s.banner != null and s.banner.title == str(Chart.table().map.title) and s.lines.size() == 2 and str(s.lines[1].text).contains(carrier.name) and str(s.lines[1].text).contains("map"), "with the picture free a banner says it, and the log's line comes last")
	# a step onto a cell with news of its own (an item, a chest, the writing, a pad): that news keeps the log and the picture, and
	# instinct waits for the next step or turn instead of being said nowhere
	await flow.new_run()
	s = flow.state
	var f = s.floor_map
	var ahead := -1
	for i in 4:
		var c: Vector2i = s.cell + f.DIRS[i]
		if f.is_open(c) and not f.in_the_way(c) and f.monster_at(c) == null and c != f.stairs and f.pickup_at(c) == "" and not f.lore_at(c) and not f.treasure.any(func(t): return t.cell == c):
			ahead = i
			break
	_check(ahead >= 0, "the start has a plain cell beside it to put an item on")
	if ahead < 0:
		return
	var item_cell: Vector2i = s.cell + f.DIRS[ahead]
	f.pickups.append({"cell": item_cell, "item": "salve"})
	s.facing = ahead
	cells = s.reach().keys()
	for i in ceili(cells.size() * at):
		s.seen[cells[i]] = true
	for _i in 2: # the run's own banners have gone
		await flow.tick(flow.clock + 60000.0)
	heard.clear()
	await flow.press("up")
	_check(s.cell == item_cell and s.items.has("salve") and s.charted.is_empty() and heard.is_empty() and s.banner != null and s.banner.title != str(words.title), "stepping onto an item with instinct due, the item has the log and the picture, and instinct waits (%s)" % s.lines.map(func(l): return l.text))
	await flow.tick(flow.clock + 60000.0)
	await flow.press("left")
	_check(not s.charted.is_empty() and heard.size() == 1 and heard[0].how == "instinct" and s.banner.title == str(words.title) and s.lines.any(func(l): return l.text == str(words.line)), "and at the next turn it charts the floor, on the picture and in the log")


## For `_charting`: sees just under the share where instinct would chart the floor, then finds the first of the floor's monsters that
## would hand a map over if put out of the way now, and the first that would not. [carrier, other], null for one the floor hasn't got.
func _map_carriers(Chart, flow) -> Array:
	var s = flow.state
	var cells: Array = s.reach().keys()
	for i in ceili(cells.size() * float(Chart.table().instinct_at)) - 1:
		s.seen[cells[i]] = true
	var carrier = null
	var other = null
	for m in s.floor_map.monsters:
		if m.boss:
			continue
		m.gone = "spared"
		var has: bool = Chart.drops(s, m, flow.dice)
		m.gone = ""
		if has and carrier == null:
			carrier = m
		elif other == null:
			other = m
	return [carrier, other]


## What a fight's end does to keys, without the scene. (gameplay_test presses real keys.)
func _input_cooldown() -> void:
	var flow = _flow(880)
	await flow.new_run()
	var s = flow.state
	var m = s.floor_map.monsters[0]
	s.foe = m
	await flow.go("intro", {"foe": m})
	await flow.go("menu")
	m.gone = "spared"
	await flow.encounter.leave_fight([])
	var stood: Vector2i = s.cell
	await flow.press("up")
	_check(s.cell == stood, "a key just after a fight does nothing (%s)" % s.cell)
	await flow.tick(flow.clock + Flow.AFTER_FIGHT_MS + 1.0)
	await flow.press("up", true)
	_check(s.cell == stood, "a key still held does nothing after that either")
	await flow.press("up")
	_check(s.cell != stood, "a fresh press walks")
	var moved_to: Vector2i = s.cell
	await flow.press("left", true)
	_check(s.cell == moved_to, "(a held turn doesn't step)")
	var hurried = _flow(881)
	await hurried.new_run()
	await hurried.press("up")
	_check(hurried.state.cell != hurried.state.floor_map.start or hurried.state.stage != "explore", "keys work as ever before any fight")
	_use()

