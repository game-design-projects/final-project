## What a finished fight teaches and what a level gives (#162): the experience of experience.gd's table, the level it makes, the
## max HP, health and strike a level gives, that the way a fight ended does not change what it taught, that a level takes the
## picture when the moment is free and the log always carries it (a spare's question too), that the run saves and reads its
## experience back (an older save reading as level 1), and that the status row shows the level and the fill toward the next. The test room's own check that a
## fight there teaches nothing is in features_test, which reads the save after a fight there.
## Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/experience_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Experience = preload("res://src/rules/experience.gd")
const Flags = preload("res://src/utils/flags.gd")
const Floors = preload("res://src/rules/floors.gd")
const Flow = preload("res://src/game/flow.gd")
const Hud = preload("res://src/view/hud.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")


func _name() -> String:
	return "experience_test"


func _run() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound", "no-wick"]))
	_numbers()
	await _a_fight()
	_finish()


## The table itself: what a fight is worth, where the levels are, and what each one gives.
func _numbers() -> void:
	var xp: Dictionary = Experience.table().xp
	_check(int(xp.slain) > 0 and Experience.xp_for("slain", false) == Experience.xp_for("spared", false), "a kill and a spare teach the same (%d, %d)" % [Experience.xp_for("slain", false), Experience.xp_for("spared", false)])
	_check(Experience.xp_for("spared", true) == Experience.xp_for("spared", false) + int(xp.champion), "a champion teaches its bonus on top, however the fight ended (%d)" % Experience.xp_for("spared", true))
	_check(Experience.xp_for("fled", false) == 0 and Experience.xp_for("", false) == 0, "and backing out of a fight teaches nothing, so none can be farmed")
	var levels: Array = Experience.levels()
	_check(int(levels[0]) == 0 and levels.size() >= 5 and range(1, levels.size()).all(func(i): return int(levels[i]) > int(levels[i - 1])), "the level table starts at 0 and every level costs more than the one before (%s)" % [levels])
	_check(Experience.level_at(0) == 1 and Experience.level_at(int(levels[1]) - 1) == 1 and Experience.level_at(int(levels[1])) == 2, "level 2 is the first price, and nothing under it is level 2")
	_check(Experience.level_at(int(levels.back())) == levels.size() and Experience.level_at(int(levels.back()) + 500) == levels.size(), "the last price is the top level, however much is learned past it")
	_check(Experience.next_at(1) == int(levels[1]) and Experience.next_at(levels.size()) == -1, "the bar reads the next level's price, and none at the top")
	var from: int = int(levels[1])
	var to: int = int(levels[2])
	_check(is_zero_approx(Experience.frac(from)) and is_equal_approx(Experience.frac((from + to) / 2), 0.5) and is_equal_approx(Experience.frac(int(levels.back())), 1.0), "the fill toward the next level runs 0 to 1, and is full at the top")
	var at: Dictionary = Experience.within((from + to) / 2)
	_check(int(at.into) == (to - from) / 2 and int(at.need) == to - from, "and the level says how far it is in its own numbers (%s)" % [at])
	var top: Dictionary = Experience.within(int(levels.back()))
	_check(int(top.into) == 0 and int(top.need) == 0, "with no next level at the top, its numbers are none")
	_check(Experience.gain(1).values().all(func(v): return int(v) == 0), "the level every run starts at gives nothing")
	_check(int(Experience.gain(2).max_hp) > 0 and int(Experience.gain(2).heal) > 0, "a level gives max HP and the health that comes with it (%s)" % [Experience.gain(2)])
	var every := int(Experience.table().gain.edge_every)
	var each := int(Experience.table().gain.edge)
	var edge_levels := range(2, 2 + every * 3).filter(func(l): return Experience.edge_level(int(l)))
	_check(edge_levels == [2, 2 + every, 2 + every * 2], "the second level hardens every strike, and every %d levels after it (%s)" % [every, edge_levels])
	_check(range(2, 2 + every * 3).all(func(l): return l in edge_levels or int(Experience.gain(int(l)).edge) == 0), "and the levels between give no edge (%s)" % [range(2, 2 + every * 3).map(func(l): return int(Experience.gain(int(l)).edge))])
	_check(Experience.edge(1) == 0 and Experience.edge(2) == each and Experience.edge(int(edge_levels[2])) == each * 3, "and the harder strikes add up (%d, %d, %d)" % [Experience.edge(1), Experience.edge(2), Experience.edge(int(edge_levels[2]))])


## One fight on a real floor: what it taught, the level it made, what the level did, what the picture and the log said, the save,
## the status row, and what a champion's news does to the picture when it owns it.
func _a_fight() -> void:
	var flow = Flow.new(Rng.new(51), LocalMind.new())
	await flow.new_run()
	var s = flow.state
	_check(s.xp == 0 and s.level() == 1 and s.strike_edge() == 0, "a run starts at level 1 having learned nothing")
	_check(not s.to_dict().has("xp"), "and saves as it always did")
	var hud := Hud.new()
	hud.part = Hud.Part.STATUS
	hud.state = s
	var row := "".join(hud.status_pieces().map(func(p): return str(p[0])))
	_check(row.begins_with("LVL 1 ") and is_zero_approx(hud.level_frac()), "the status row says LVL 1 with nothing filled (%s)" % row)
	var m = s.floor_map.monsters.filter(func(x): return not x.boss and not x.is_gone()).front()
	await _meet(flow, m)
	var next: int = Experience.next_at(1)
	s.xp = next - 1 # one fight more than the next level takes
	s.hp = 5
	var max_before: int = s.max_hp
	await flow.encounter.defeat(m, "slain")
	var gained: int = Experience.xp_for("slain", false)
	_check(s.xp == next - 1 + gained, "the fight taught %d experience (%d)" % [gained, s.xp])
	_check(s.level() == 2 and s.max_hp == max_before + int(Experience.gain(2).max_hp), "and made level 2: %d more max HP" % int(Experience.gain(2).max_hp))
	_check(s.hp == mini(s.max_hp, 5 + int(Experience.gain(2).heal)), "with the health the level gives back (%d/%d)" % [s.hp, s.max_hp])
	_check(s.banner != null and str(s.banner.title) == "LEVEL 2" and str(s.banner.text).contains("max HP"), "the picture says the level (%s: %s)" % [s.banner.title if s.banner != null else "", s.banner.text if s.banner != null else ""])
	_check(s.lines.any(func(l): return str(l.text).begins_with("You reach LEVEL 2")), "and so does the log, which keeps it as the record")
	# and in front of the verdict, so the last word on a fight is still how it ended
	var said: Array = s.lines.map(func(l): return str(l.text))
	var reached_at := -1
	for i in said.size():
		if said[i].begins_with("You reach LEVEL 2"):
			reached_at = i
	var verdict_at: int = said.find(Texts.VERDICT_SLAIN)
	_check(reached_at >= 0 and verdict_at > reached_at, "in front of the verdict, which still has the last word (%s)" % [said])
	await flow.go("camp")
	_check(s.lines.any(func(l): return str(l.text).begins_with("LEVEL 2: ")), "and sitting down says the level and how far the next is (%s)" % str(s.lines.map(func(l): return l.text)))
	await flow.tick(flow.clock + Flow.AFTER_FIGHT_MS + 1.0) # the keys are held off a moment after a fight
	await flow.press("cancel")
	_check(s.stage == "explore", "the camp is left with Esc")
	_check(row != "" and is_equal_approx(hud.level_frac(), Experience.frac(s.xp)), "the row's fill follows the experience (%d%%)" % roundi(Experience.frac(s.xp) * 100.0))
	hud.state = s
	_check("LVL 2" in "".join(hud.status_pieces().map(func(p): return str(p[0]))), "and it says the level reached")
	var saved: Dictionary = s.to_dict()
	_check(int(saved.get("xp", -1)) == s.xp, "the experience is saved with the run (%s)" % saved.get("xp"))
	var back = State.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(back != null and back.xp == s.xp and back.level() == 2 and back.max_hp == s.max_hp, "and comes back with the level and the max HP it gave")
	var old: Dictionary = s.to_dict()
	old.erase("xp")
	var before = State.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(before != null and before.xp == 0 and before.level() == 1, "a save from before experience reads as level 1")
	# a spare asks to come along, and the question keeps the level the spare made in its log
	var friend = s.floor_map.monsters.filter(func(x): return not x.boss and not x.is_gone()).front()
	await _meet(flow, friend)
	s.xp = Experience.next_at(s.level()) - 1 # one spare more than the next level takes
	await flow.encounter.defeat(friend, "spared")
	_check(s.stage == "ask" and s.lines.any(func(l): return str(l.text).begins_with("You reach LEVEL")), "a spare that asks to come along keeps the level it made in the log before the question (%s)" % s.stage)
	# the harder strike the levels give is in the fight's help, where the party's aid is. The second level is the first that
	# hardens it: level 3 gives none of its own, and the second's is still on every strike.
	s.xp = int(Experience.levels()[2]) # level 3
	_check(s.level() == 3 and int(Experience.gain(3).edge) == 0 and s.strike_edge() == int(Experience.table().gain.edge), "the second level's edge is on every strike, and level 3 adds none (%d, level %d)" % [s.strike_edge(), s.level()])
	s.xp = int(Experience.levels()[1]) # level 2: the first level that hardens every strike
	_check(s.level() == 2 and s.strike_edge() == int(Experience.gain(2).edge) and s.strike_edge() > 0, "a level that hardens every strike is worth %d to it" % s.strike_edge())
	var probe = s.floor_map.monsters.filter(func(x): return not x.boss and not x.is_gone()).front()
	await _meet(flow, probe)
	await flow.go("fightbar", {})
	_check(s.hint.contains("LEVEL +%d" % s.strike_edge()), "the fight's own hint says what the levels add (%s)" % s.hint)
	await flow.go("explore", {"lines": []})
	# a champion's news owns the picture, and what the fight taught is still in the log the walk goes on with
	var boss = s.floor_map.monsters.filter(func(x): return x.boss).front()
	await _meet(flow, boss)
	s.xp = Experience.next_at(s.level()) - 1
	var max_was: int = s.max_hp
	await flow.encounter.defeat(boss, "spared")
	_check(s.banner != null and str(s.banner.text).contains("stronger"), "a champion won over still owns the picture (%s)" % [s.banner.text if s.banner != null else ""])
	var champion_hp: int = int(Floors.boss_reward().max_hp)
	_check(s.max_hp == max_was + champion_hp + int(Experience.gain(s.level()).max_hp), "and the level it made came with its max HP, on top of the champion's (%d, level %d)" % [s.max_hp, s.level()])


## Up to a fight with `m` and into its own menu, the way the other suites do: the intro's line, and any offer it makes, answered
## so the fight is at the command menu.
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
	if s.stage != "menu":
		await flow.go("menu")
	# a run opens with the story's banner (the last door): let it pass, so a level is the moment's own news below
	await flow.tick(flow.clock + Flow.STORY_BANNER_MS + 500.0)
