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
const JevMind = preload("res://src/mind/jev_mind.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
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
