## Checks the features in `Flags.FEATURES` with no window: that each can be switched off, and what each does when it is on.
## Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/features_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Clans = preload("res://src/rules/clans.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Flags = preload("res://src/utils/flags.gd")
const Floors = preload("res://src/rules/floors.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const DodgeRun = preload("res://src/rules/dodge_run.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const Flow = preload("res://src/game/flow.gd")
const Gates = preload("res://src/rules/minigames/gates.gd")
const Monster = preload("res://src/rules/monster.gd")
const Overlay = preload("res://src/view/overlay.gd")
const Pace = preload("res://src/rules/pace.gd")
const Hud = preload("res://src/view/hud.gd")
const Items = preload("res://src/rules/items.gd")
const JevMind = preload("res://src/mind/jev_mind.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const Requests = preload("res://src/rules/requests.gd")
const Reveal = preload("res://src/rules/reveal.gd")
const State = preload("res://src/game/state.gd")
const Tips = preload("res://src/view/tips.gd")

const BASE := ["nosave", "nosound"]


func _name() -> String:
	return "features_test"


func _run() -> void:
	_flags()
	await _real_floors()
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
	await _clans()
	await _map_gen()
	await _secrets()
	await _items()
	await _shop()
	await _lurkers()
	await _npcs()
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
	_use()
	_check(Flags.FEATURES.keys().all(func(f): return Flags.enabled(f)), "every feature is on by default")
	for f in Flags.FEATURES:
		_use(["no-" + f])
		_check(not Flags.enabled(f), "no-%s turns it off" % f)
		_use([f + "=off"])
		_check(not Flags.enabled(f), "%s=off turns it off" % f)
		_use(["classic"])
		_check(not Flags.enabled(f), "classic turns %s off" % f)
		_use(["classic", f])
		_check(Flags.enabled(f), "classic %s brings it back" % f)
	_use()


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
	var ended = s
	await again.press("1")
	_check(again.state != ended and again.state.depth == 1, "and NEW RUN starts over on B1F")

	var classic = _flow(11, ["classic"])
	await classic.new_run()
	await _reach_stairs(classic)
	_check(classic.state.stage == "end" and classic.state.run_over, "classic: the stairs end the run")
	var kept = classic.state
	await classic.press("1")
	_check(classic.state != kept and classic.state.depth == 1, "classic: NEW FLOOR starts over")
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
	flow = _flow(30, ["no-recruit-step"])
	m = await _at_menu(flow, "bandit")
	await flow.press("2")
	_check(not flow.state.menu.any(func(i): return i.label == "TREAT IT AS AN EQUAL"), "no-recruit-step: the ACTs are the old three")

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

	# switched off, the old way
	flow = _flow(28, ["no-recruit-step"])
	m = await _at_menu(flow)
	_won_over(m)
	await flow.press("3")
	_check(flow.state.stage == "explore" and m.gone == "spared", "no-recruit-step: a spare goes back to rolling by itself")
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
	flow = _flow(32, ["no-story"])
	await flow.new_run()
	_check(flow.state.lines[0].text == "B1F. Find the stairs." and flow.state.floors_of == 0, "no-story: the old opening line")
	_use()


func _tutorial() -> void:
	var flow = _flow(33)
	await flow.new_run()
	var s = flow.state
	s.banner = null
	var shown := []
	flow.happened.connect(func(n, d): if n == "coach": shown.append(d.id))
	var m = s.floor_map.monsters[0]
	await flow.go("intro", {"foe": m})
	await flow.tick(flow.clock + 1000.0)
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
	var later = _flow(34)
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
	flow = _flow(35, ["no-tutorial"])
	await flow.new_run()
	flow.state.banner = null
	await flow.go("intro", {"foe": flow.state.floor_map.monsters[0]})
	await flow.tick(flow.clock + 1000.0)
	_check(flow.state.banner == null, "no-tutorial: no tips")
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
	flow = _flow(38, ["no-mood-cues"])
	m = await _at_menu(flow)
	var quiet := []
	flow.happened.connect(func(n, _d): if n in ["mood", "wants_join"]: quiet.append(n))
	await flow.encounter.decide(m, [{"intent": "kindness", "w": 1.0}], "TEST")
	_check(quiet.is_empty(), "no-mood-cues: no cues")
	_use()
	_check(not Flags.switched_off("show-mind"), "the mind's rows show by default")
	_use(["no-show-mind"])
	_check(Flags.switched_off("show-mind"), "no-show-mind hides them")
	_use(["classic"])
	_check(not Flags.switched_off("show-mind"), "classic leaves them as they were")
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

	# it answers what you did to it
	flow = _flow(42)
	m = await _at_menu(flow)
	s = flow.state
	await flow.encounter.after_player([State.sys_line("x")], {"pacified": false, "pressure": 1.0, "told": true, "feeling": {"tone": "good"}})
	_check(s.lines.any(func(l): return l.kind == "say" and Content.species(m.species).lines.pleased.any(func(p): return l.text.contains(p.left(8)))), "a liked deed gets a pleased line (%s)" % str(s.lines))
	flow = _flow(43, ["no-reveal"])
	m = await _at_menu(flow)
	s = flow.state
	await flow.press("2")
	await flow.press("1")
	_check(s.lines[0].text.contains("likes"), "no-reveal: CHECK tells all at once")
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
	var tips = Tips.new()
	tips.state = s
	s.stage = "menu"
	_check(tips.targets().has("chat"), "the info key can open the talk so far")
	tips.free()
	_use()


func _gate() -> void:
	var spread := {}
	var blocked := 0
	for i in 200:
		var f = FloorGen.generate(Rng.new(i + 1), Floors.plan(1).merged({"boss_at_exit": true}))
		var champion = f.monsters.back()
		if champion.cell == f.stairs and Floors.fights_required(f) >= 1:
			blocked += 1
	_check(blocked == 200, "boss-at-exit: the champion blocks the stairs on every floor (%d of 200)" % blocked)
	for i in 200:
		var f = FloorGen.generate(Rng.new(i + 1), Floors.plan(1))
		var n: int = Floors.fights_required(f)
		spread[n] = spread.get(n, 0) + 1
	print("features_test: fights required with the champion in its hall: %s" % str(spread))
	_check(spread.get(0, 0) > 100, "without it most floors can still be walked with no fight, as they always could")
	var a = FloorGen.generate(Rng.new(5), Floors.plan(1).merged({"boss_at_exit": true}))
	var b = FloorGen.generate(Rng.new(5), Floors.plan(1))
	_check(a.grid == b.grid, "the flag only moves the champion: same seed, same maze")

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
	_check(map.monster_marks().is_empty(), "the map keeps it hidden until seen")
	s.seen[boss.cell] = true
	_check(map.monster_marks().size() == 1, "and shows it after")
	map.free()

	var hp: int = s.max_hp
	s.hp = 5
	await flow.tick(flow.clock + 1000.0)
	await flow.encounter.defeat(boss, "slain")
	_check(s.max_hp == hp + Floors.boss_reward().max_hp and s.hp == 5 + Floors.boss_reward().heal, "beating a champion leaves you stronger (%d/%d)" % [s.hp, s.max_hp])
	_check(s.banner != null and s.banner.text.contains("stronger"), "and says so")
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
	flow = _flow(48, ["no-boss-at-exit"])
	await flow.new_run()
	_check(flow.state.floor_map.monsters.back().cell != flow.state.floor_map.stairs, "no-boss-at-exit: the champion keeps to its hall")
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
	await flow.go("explore", {"lines": []})
	await flow.go("intro", {"foe": later})
	_check(s.stage == "intro" and s.foe == later and is_equal_approx(later.meters.friendliness, friendly), "a monster hears the same news once")
	await flow.tick(flow.clock + 1000.0)
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
	var word_off = _flow(31, ["no-clans"])
	var off_goo = await _at_menu(word_off)
	await word_off.encounter.defeat(off_goo, "slain")
	_check(word_off.state.reputation.is_empty() and word_off.state.deeds.is_empty(), "no-clans: nothing is recorded")
	_use()


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
	var differs := false
	for s in range(1, 20):
		differs = differs or str(Floors.paths(s, 1)) != str(ways)
	_check(differs, "other seeds offer others")
	_check(Floors.paths(77, Floors.run_floors() - 1).is_empty(), "one way leads to the last floor")
	var labels := {}
	for s in range(1, 60):
		for w in Floors.paths(s, 2):
			labels[w.id] = true
	_check(labels.size() == 3, "every kind of way comes up (%s)" % str(labels.keys()))

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

	var flow = _flow(13)
	await flow.new_run()
	_check(flow.state.rotate_mini_games, "the run rotates mini-games in")
	var classic = _flow(13, ["no-mini-games"])
	await classic.new_run()
	_check(not classic.state.rotate_mini_games, "no-mini-games leaves them out")
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
		_check(standing.size() == Content.table("encounter").roster.size() + 1 + maxi(0, (int(biome.size) - 13) / 3), "with more monsters the bigger it is (%d at %d)" % [standing.size(), biome.size])
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
	var plain = _flow(41, ["no-map-gen"])
	await plain.new_run()
	_check(plain.state.floor_map.size == 13 and plain.state.floor_map.biome == "", "no-map-gen: the floor is the 13x13 maze")
	_check(plain.state.palette_id == plain.state.floor_map.seed_value, "in the colours its seed picks")
	_check(not plain.state.floor_map.teleports.is_empty() or not plain.state.floor_map.treasure.is_empty(), "with its secrets, which are a feature of their own")
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
	var hidden = _flow(47, ["no-secrets"])
	await hidden.new_run()
	var h = hidden.state.floor_map
	_check(h.treasure.is_empty() and h.teleports.is_empty() and _cracked_wall(h) == Vector2i(-1, -1), "no-secrets: nothing is hidden")
	_check(not hidden.state.viewing("secrets"), "and the map's legend doesn't speak of it")
	_check(Tips.map_blocks(true).size() == Tips.map_blocks().size() + 2, "with them, the legend names pads and chests")
	_use()


## A fight with the slime, standing at the menu.
func _item_fight(seed_value: int, words := []) -> Variant:
	var flow = _flow(seed_value, words)
	await _at_menu(flow, "slime")
	return flow


func _items() -> void:
	var flow = await _item_fight(51)
	var s = flow.state
	_check(s.menu.size() == 4, "with an empty bag the menu has its four commands")
	s.items = ["sugar", "salve", "whetstone", "smoke"]
	await flow.go("menu")
	_check(s.menu.size() == 5 and s.menu[4].label == "ITEM" and s.menu[0].label == "FIGHT" and s.menu[3].label == "FLEE", "something in the bag adds ITEM, and the others keep their places")
	await flow.press("5")
	_check(s.stage == "items" and s.menu.size() == 4, "ITEM opens the bag (%s)" % s.stage)
	await flow.press("cancel")
	_check(s.stage == "menu" and s.items.size() == 4, "and backing out uses nothing")
	# a gift changes a recruit
	var m = s.foe
	var before: float = await flow.mind.mercy(m)
	await flow.press("5")
	await flow.press("1")
	var after: float = await flow.mind.mercy(m)
	_check(after >= 0.5 and after > before + 0.2, "the gift a monster loves moves it most of the way to mercy (%.2f to %.2f)" % [before, after])
	_check(not s.items.has("sugar"), "and is gone from the bag")
	_check(s.stage in ["wait", "menu"], "and takes your turn (%s)" % s.stage)
	var other = await _item_fight(51)
	other.state.items = ["ring"]
	await other.go("menu")
	var shrug_from: float = await other.mind.mercy(other.state.foe)
	await other.press("5")
	await other.press("1")
	var shrug_to: float = await other.mind.mercy(other.state.foe)
	_check(shrug_to - shrug_from < after - before, "a gift it doesn't care for does much less (%.2f to %.2f)" % [shrug_from, shrug_to])
	# a salve
	var heal = await _item_fight(52)
	heal.state.items = ["salve"]
	heal.state.hp = 3
	await heal.go("menu")
	await heal.press("5")
	await heal.press("1")
	_check(heal.state.hp == 13 and heal.state.items.is_empty(), "a salve heals 10 (%d)" % heal.state.hp)
	_check(heal.state.stage in ["wait", "menu"], "and takes your turn")
	# a whetstone
	var sharp = await _item_fight(53)
	sharp.state.items = ["whetstone"]
	await sharp.go("menu")
	await sharp.press("5")
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
	await away.press("5")
	await away.press("1")
	_check(away.state.stage == "explore" and away.state.gold == gold, "smoke leaves the fight at no cost")
	_check(foe.meters.anger == anger, "and no grudge")
	var champ = await _item_fight(55)
	champ.state.foe.boss = true
	champ.state.items = ["smoke"]
	await champ.go("menu")
	await champ.press("5")
	await champ.press("1")
	_check(champ.state.stage == "menu" and champ.state.items.size() == 1, "not from a champion, and it keeps the smoke")
	# dying gives them back
	var retry = await _item_fight(56)
	retry.state.items = ["salve"]
	retry.state.encounter_start.items = ["salve"]
	retry.state.encounter_start.sharpened = 0
	await retry.go("menu")
	await retry.press("5")
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
	var none = _flow(58, ["no-items"])
	await none.new_run()
	_check(none.state.floor_map.pickups.is_empty() and none.state.floor_map.merchant.is_empty(), "no-items: nothing lies about")
	var slice_like = await _item_fight(59, ["no-items"])
	slice_like.state.items = ["salve"]
	await slice_like.go("menu")
	_check(slice_like.state.menu.size() == 4, "and no ITEM, whatever a save carried")
	_use()


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
	var closed = _flow(61, ["no-shop"])
	await closed.new_run()
	closed.state.foe = null
	await closed.next_floor()
	_check(closed.state.floor_map.merchant.is_empty(), "no-shop: no trader")
	_check(not closed.state.floor_map.pickups.is_empty(), "though things still lie about")
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
	var plain = await _floor_with_lurker(71, ["no-lurkers"])
	_check(plain.state.floor_map.monsters.all(func(o): return not o.lurking), "no-lurkers: nothing stirs")
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
	_check(s.reputation.get(Clans.of(q.species), 0.0) > 0.0, "and its clan thinks better of you")
	_check(s.banner != null and Overlay.banner_fits(s.banner.text), "the banner says so and fits")
	var back = _flow(s.run_seed)
	await back.load_state(saved)
	var bq: Dictionary = back.state.floor_map.quester
	_check(bq.taken and bq.kind == "fetch" and bq.want == q.want and bq.cell == q.cell, "a save keeps the request as it stood")
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
	var off = _flow(100, ["no-npcs"])
	await off.new_run()
	_check(off.state.floor_map.quester.is_empty(), "no-npcs: nobody asks")
	var no_items = _flow(100, ["no-items"])
	var kinds := {}
	for i in 40:
		no_items = _flow(100 + i, ["no-items"])
		await no_items.new_run()
		if not no_items.state.floor_map.quester.is_empty():
			kinds[no_items.state.floor_map.quester.kind] = true
	_check(not kinds.has("fetch") and not kinds.is_empty(), "no-items: nobody asks you to fetch (%s)" % [kinds.keys()])
	_use()
