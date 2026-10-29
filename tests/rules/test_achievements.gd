## Achievements (src/rules/achievements.gd): the list, once-only unlocks, persistence, counters, secret display,
## a missing or broken store, and that every game event the hooks send unlocks the right one.
extends "res://tests/test_case.gd"

const Ach = preload("res://src/rules/achievements.gd")
const Emotions = preload("res://src/rules/emotions.gd")
const Species = preload("res://src/rules/species.gd")
const StoreScript = preload("res://src/core/store.gd")

var _rigs := []


## Break the rig <-> achievements reference cycle (the callbacks capture the rig) so nothing leaks between tests.
func after_each() -> void:
	for r in _rigs:
		r.ach = null
		r.clear()
	_rigs.clear()


func _utc(y: int, mo: int, d: int, h: int) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": d, "hour": h, "minute": 0, "second": 0})) * 1000


## An achievements instance with a fake clock and a record of what it unlocked.
func _rig(store = null) -> Dictionary:
	var r := {"store": store if store != null else StoreScript.Memory.new(), "t": _utc(2026, 10, 5, 12), "unlocked": []}
	r.ach = Ach.create_achievements({
		"store": r.store,
		"now": func(): return r.t,
		"onUnlock": func(a): r.unlocked.append(a.id),
	})
	_rigs.append(r)
	return r


func _by_id() -> Dictionary:
	var out := {}
	for a in Ach.ACHIEVEMENTS:
		out[a.id] = a
	return out


func test_20_to_30_achievements_each_with_a_unique_id_a_short_all_caps_name_and_line_a_known_glyph_and_group():
	var n: int = Ach.ACHIEVEMENTS.size()
	ok(n >= 20 and n <= 30, "%d" % n)
	eq(_by_id().size(), n)
	var id_re := RegEx.create_from_string("^[a-z0-9_]+$")
	for a in Ach.ACHIEVEMENTS:
		ok(id_re.search(a.id) != null, a.id)
		eq(a.name, a.name.to_upper(), "%s: name is all caps" % a.id)
		eq(a.desc, a.desc.to_upper(), "%s: line is all caps" % a.id)
		ok(a.name.length() <= 17, '%s: name "%s" is too long' % [a.id, a.name])
		ok(a.desc.length() <= 64, '%s: line "%s" is too long (%d)' % [a.id, a.desc, a.desc.length()])
		ok(Ach.GLYPHS.has(a.icon), "%s: glyph %s" % [a.id, a.icon])
		ok(Ach.GROUPS.has(a.group), "%s: group %s" % [a.id, a.group])
	for g in Ach.GLYPHS.values():
		eq(g.size(), 7)
		for row in g:
			match_re(row, "^[#.]{7}$")


func test_the_briefs_moments_are_all_covered():
	var by_id := _by_id()
	for id in ["charmed", "stitches", "peacemaker", "all_talk", "first_friend", "shiny", "mash", "red_carpet", "word_is_bond", "second_chance", "walked_out", "betrayed", "crit_happens", "fail_forward", "still_breathing", "not_today", "deep5", "deep10", "seeing_red", "stand_down", "legendary", "goblin_tax", "so_vain"]:
		ok(by_id.has(id), id)
	ok(Ach.ACHIEVEMENTS.any(func(a): return a.get("secret", false)), "some are secret")
	ok(Ach.ACHIEVEMENTS.any(func(a): return a.has("goal")), "some count up")


func test_the_counters_goals_mirror_the_feelings_and_kinds_in_the_game():
	var by_id := _by_id()
	eq(by_id.empath.values, Emotions.EMOTIONS.keys())
	eq(by_id.empath.goal, Emotions.EMOTIONS.size())
	eq(by_id.menagerie.values, Species.SPECIES.keys())
	eq(by_id.menagerie.goal, Species.SPECIES.size())


func test_an_achievement_unlocks_once_with_the_time_it_was_earned():
	var r := _rig()
	eq(r.ach.unlock("charmed"), true)
	eq(r.ach.unlock("charmed"), false)
	r.ach.on("feel", {"feeling": "delighted", "species": "slime"})
	eq(r.unlocked, ["charmed"])
	eq(r.ach.has("charmed"), true)
	eq(r.ach.earned_at("charmed"), r.t)
	eq(r.ach.earned_at("stitches"), null)
	eq(r.ach.unlock("nope"), false, "unknown ids are ignored")


func test_unlocks_survive_a_reload_same_store_and_a_new_run_doesnt_forget_them():
	var store := StoreScript.Memory.new()
	var a := _rig(store)
	a.ach.unlock("first_friend")
	var saved = JSON.parse_string(store.data[Ach.ACH_KEY])
	eq(saved.earned.first_friend, a.t)
	eq(saved.v, 1)
	var b := _rig(store)
	eq(b.ach.has("first_friend"), true)
	eq(b.ach.earned_at("first_friend"), a.t)
	eq(b.ach.unlock("first_friend"), false)
	eq(b.unlocked, [])
	eq(b.ach.count(), {"earned": 1, "total": Ach.ACHIEVEMENTS.size()})


func test_counters_count_each_distinct_thing_once_persist_and_unlock_at_the_goal():
	var store := StoreScript.Memory.new()
	var a := _rig(store)
	var feelings: Array = Emotions.EMOTIONS.keys()
	a.ach.on("feel", {"feeling": "confused", "species": "slime"})
	a.ach.on("feel", {"feeling": "confused", "species": "goblin"})
	a.ach.on("feel", {"feeling": "bogus", "species": "goblin"})
	eq(a.ach.progress("empath"), {"n": 1, "goal": feelings.size()})
	var b := _rig(store)
	eq(b.ach.progress("empath"), {"n": 1, "goal": feelings.size()}, "kept across reloads")
	for f in feelings:
		b.ach.on("feel", {"feeling": f, "species": "rock"})
	eq(b.ach.has("empath"), true)
	eq(b.ach.progress("empath"), {"n": feelings.size(), "goal": feelings.size()})

	var species: Array = Species.SPECIES.keys()
	for s in species.slice(0, -1):
		b.ach.on("recruit", {"species": s, "allies": 1})
	eq(b.ach.has("menagerie"), false)
	b.ach.on("recruit", {"species": species[-1], "allies": 1})
	eq(b.ach.has("menagerie"), true)
	eq(b.ach.progress("charmed"), null, "a one-off has no counter")


func test_secret_achievements_read_question_marks_until_earned_the_rest_show_their_line_while_locked():
	var r := _rig()
	var by_id := _by_id()
	var shown := func(id): return r.ach.list().filter(func(x): return x.id == id)[0]
	ok(by_id.so_vain.secret)
	eq(shown.call("so_vain").name, "???")
	eq(shown.call("so_vain").desc, "???")
	eq(shown.call("so_vain").earned, false)
	eq(shown.call("charmed").name, by_id.charmed.name, "not secret: readable while locked")
	r.ach.on("feel", {"feeling": "flattered", "species": "dragon"})
	eq(shown.call("so_vain").name, by_id.so_vain.name)
	eq(shown.call("so_vain").desc, by_id.so_vain.desc)
	eq(shown.call("so_vain").at, r.t)
	eq(shown.call("so_vain").earned, true)
	r.ach.on("feel", {"feeling": "flattered", "species": "goblin"})
	eq(r.unlocked, ["so_vain"], "only a dragon counts")
	var empath: Dictionary = shown.call("empath")
	eq(empath.progress, {"n": 1, "goal": 10})
	eq(shown.call("charmed").progress, null)
	eq(r.ach.list().size(), Ach.ACHIEVEMENTS.size())


func test_a_corrupt_or_foreign_stored_value_never_breaks_it():
	var odd := JSON.stringify({"earned": {"nope": 1, "charmed": "yesterday", "stitches": 5}, "progress": {"empath": "all", "menagerie": ["slime", "slime", "kraken"]}})
	for raw in ["{not json", "[]", "null", "42", '"x"', odd]:
		var store := StoreScript.Memory.new({Ach.ACH_KEY: raw})
		var r := _rig(store)
		eq(r.ach.has("nope"), false, raw)
		eq(r.ach.has("charmed"), false, "%s: a non-numeric date is dropped" % raw)
		ok(r.ach.count().earned <= 1, raw)
		ok(r.ach.progress("empath").n == 0, raw)
		ok(r.ach.progress("menagerie").n <= 1, "%s: duplicates and unknown species are dropped" % raw)
		eq(r.ach.unlock("charmed"), true, raw)
		eq(JSON.parse_string(store.data[Ach.ACH_KEY]).earned.charmed, r.t, "%s: rewritten cleanly" % raw)
	var kept := _rig(StoreScript.Memory.new({Ach.ACH_KEY: JSON.stringify({"earned": {"stitches": 5}})}))
	eq(kept.ach.has("stitches"), true, "good entries survive next to bad ones")


func test_it_works_without_a_store_a_clock_or_callbacks():
	var ach := Ach.create_achievements()
	eq(ach.unlock("charmed"), true)
	eq(ach.has("charmed"), true, "earned for this session")
	ok(ach.earned_at("charmed") > 1.6e12, "the default clock is the epoch in ms")
	ach.on("feel", {"feeling": "sad", "species": "slime"})
	eq(ach.progress("empath").n, 1)


func test_unknown_events_and_events_outside_a_fight_are_ignored():
	var r := _rig()
	r.ach.on("nonsense", {"a": 1})
	r.ach.on("attack")
	r.ach.on("fight-end", {"won": true, "kills": 0})
	r.ach.on("feel")
	eq(r.unlocked, [])


func test_talking_delighted_in_stitches_terrified_a_peaceful_exit():
	var r := _rig()
	r.ach.on("feel", {"feeling": "delighted", "species": "slime"})
	r.ach.on("feel", {"feeling": "amused", "species": "goblin"})
	r.ach.on("feel", {"feeling": "terrified", "species": "bandit"})
	r.ach.on("peace", {"species": "snake"})
	eq(r.unlocked, ["charmed", "stitches", "boo", "peacemaker"])


func test_all_talk_a_fight_won_with_no_attack_and_no_kill_an_attack_a_kill_or_running_away_spoils_it():
	var r := _rig()
	r.ach.on("fight-start")
	r.ach.on("attack")
	r.ach.on("fight-end", {"won": true, "kills": 0})
	r.ach.on("fight-start")
	r.ach.on("fight-end", {"won": true, "kills": 1}) # an ally's opening lightning killed it
	r.ach.on("fight-start")
	r.ach.on("fight-end", {"won": false, "kills": 0}) # fled
	eq(r.unlocked, [])
	r.ach.on("fight-start")
	r.ach.on("fight-end", {"won": true, "kills": 0})
	eq(r.unlocked, ["all_talk"])


func test_recruiting_first_friend_a_shiny_a_champion_three_monster_allies_at_once():
	var r := _rig()
	r.ach.on("recruit", {"species": "slime", "shiny": false, "boss": false, "allies": 1})
	eq(r.unlocked, ["first_friend"])
	r.ach.on("recruit", {"species": "goblin", "shiny": true, "boss": false, "allies": 2})
	r.ach.on("recruit", {"species": "dragon", "shiny": false, "boss": true, "allies": 3})
	eq(r.unlocked, ["first_friend", "shiny", "red_carpet", "mash"])


func test_fail_forward_a_1_while_talking_then_a_monster_joins_or_lets_you_pass_in_that_same_fight():
	var r := _rig()
	r.ach.on("fight-start")
	r.ach.on("recruit", {"species": "slime", "allies": 1})
	r.ach.on("talk-roll", {"roll": 1})
	r.ach.on("fight-start") # a new fight forgets the fumble
	r.ach.on("peace", {"species": "slime"})
	ok(not r.unlocked.has("fail_forward"))
	r.ach.on("talk-roll", {"roll": 1})
	r.ach.on("peace", {"species": "rock"})
	ok(r.unlocked.has("fail_forward"))


func test_dice_a_natural_20_on_an_attack_a_natural_20_while_talking_death_saves():
	var r := _rig()
	r.ach.on("attack-roll", {"roll": 19})
	r.ach.on("talk-roll", {"roll": 19})
	r.ach.on("death-save", {"roll": 15, "stable": false})
	eq(r.unlocked, [])
	r.ach.on("attack-roll", {"roll": 20})
	r.ach.on("talk-roll", {"roll": 20})
	r.ach.on("death-save", {"roll": 12, "stable": true})
	r.ach.on("death-save", {"roll": 20, "stable": false})
	eq(r.unlocked, ["crit_happens", "mic_drop", "still_breathing", "not_today"])


func test_descending_floors_5_and_10_and_a_vow_carried_down_the_stairs():
	var r := _rig()
	r.ach.on("descend", {"floor": 2, "keptVows": 0})
	eq(r.unlocked, [])
	r.ach.on("descend", {"floor": 5, "keptVows": 1})
	eq(r.unlocked, ["deep5", "word_is_bond"])
	r.ach.on("descend", {"floor": 10, "keptVows": 0})
	eq(r.unlocked, ["deep5", "word_is_bond", "deep10"])


func test_champions_and_fate_slain_talked_down_a_legendary_boon():
	var r := _rig()
	r.ach.on("fight-start")
	r.ach.on("attack")
	r.ach.on("fight-end", {"won": true, "kills": 1, "boss": "dead"})
	r.ach.on("peace", {"species": "goblin", "boss": true})
	r.ach.on("boon", {"name": "WHETSTONE", "great": true, "legendary": false})
	r.ach.on("boon", {"name": "PHOENIX FEATHER", "great": true, "legendary": true})
	eq(r.unlocked, ["seeing_red", "peacemaker", "stand_down", "legendary"])


func test_broken_vows_and_unhappy_allies_forgiven_walked_out_betrayed_robbed():
	var r := _rig()
	r.ach.on("vow-broken", {"response": "forgive"})
	r.ach.on("vow-broken", {"response": "steal_gold", "stolen": false}) # caught it: it stays
	eq(r.unlocked, ["second_chance"])
	r.ach.on("vow-broken", {"response": "steal_gold", "stolen": true})
	r.ach.on("ally-decision", {"decision": "stay"})
	r.ach.on("ally-decision", {"decision": "leave_party"})
	r.ach.on("vow-broken", {"response": "attack_party"})
	eq(r.unlocked, ["second_chance", "robbed", "walked_out", "betrayed"])
	var b := _rig()
	b.ach.on("ally-decision", {"decision": "turn_on_party"})
	b.ach.on("vow-broken", {"response": "leave_party"})
	eq(b.unlocked, ["betrayed", "walked_out"])


func test_oddities_paying_a_goblin_not_a_bandit_a_mutiny_losing_the_party():
	var r := _rig()
	r.ach.on("paid", {"species": "bandit", "gold": 20})
	eq(r.unlocked, [])
	r.ach.on("paid", {"species": "goblin", "gold": 20})
	r.ach.on("mutiny", {"species": "goblin"})
	r.ach.on("wipe", {"floor": 3})
	eq(r.unlocked, ["goblin_tax", "mutiny", "permadeath"])


func test_every_achievement_can_be_earned_through_the_hooks_events():
	var r := _rig()
	var events := [
		["fight-start", null], ["talk-roll", {"roll": 1}], ["talk-roll", {"roll": 20}], ["attack-roll", {"roll": 20}],
	]
	for f in Emotions.EMOTIONS:
		events.append(["feel", {"feeling": f, "species": "dragon"}])
	events.append(["peace", {"species": "rock", "boss": true}])
	var i := 0
	for s in Species.SPECIES:
		events.append(["recruit", {"species": s, "shiny": i == 0, "boss": i == 1, "allies": mini(3, i + 1)}])
		i += 1
	events.append_array([
		["fight-end", {"won": true, "kills": 0, "boss": "dead"}],
		["death-save", {"roll": 20, "stable": false}], ["death-save", {"roll": 10, "stable": true}],
		["descend", {"floor": 10, "keptVows": 1}], ["boon", {"legendary": true}],
		["vow-broken", {"response": "forgive"}], ["vow-broken", {"response": "steal_gold", "stolen": true}],
		["ally-decision", {"decision": "leave_party"}], ["ally-decision", {"decision": "turn_on_party"}],
		["paid", {"species": "goblin"}], ["mutiny", {}], ["wipe", {}],
	])
	for e in events:
		r.ach.on(e[0], e[1])
	var missing := []
	for a in Ach.ACHIEVEMENTS:
		if not r.ach.has(a.id):
			missing.append(a.id)
	eq(missing, [])
	var seen := {}
	for id in r.unlocked:
		seen[id] = true
	eq(seen.size(), r.unlocked.size(), "each fired once")


func test_reset_forgets_everything():
	var store := StoreScript.Memory.new()
	var r := _rig(store)
	r.ach.unlock("charmed")
	r.ach.on("feel", {"feeling": "sad", "species": "slime"})
	r.ach.reset()
	eq(r.ach.count(), {"earned": 0, "total": Ach.ACHIEVEMENTS.size()})
	eq(r.ach.progress("empath").n, 0)
	eq(_rig(store).ach.has("charmed"), false)


func test_the_unlock_callback_gets_the_view_and_the_total_is_counted():
	var got := []
	var ach := Ach.create_achievements({"store": StoreScript.Memory.new(), "onUnlock": func(a): got.append(a)})
	ach.unlock("charmed")
	ach.unlock("goblin_tax")
	eq(got.size(), 2)
	eq(got[0].name, "CHARMER")
	eq(got[0].earned, true)
	eq(got[1].name, "GOBLIN TAX", "the toast shows a secret by its real name once it is earned")
	eq(ach.count(), {"earned": 2, "total": Ach.ACHIEVEMENTS.size()})


func test_dates_colors_and_badges():
	eq(Ach.fmt_date(_utc(2026, 1, 31, 12)), "JAN 31 2026")
	eq(Ach.fmt_date(_utc(2026, 10, 5, 12)), "OCT 5 2026")
	eq(Ach.color_of(_by_id().charmed), Ach.GROUPS.words.color)
	eq(Ach.color_of({"group": "nope"}), "#ffd27a")
	var secret: Dictionary = _by_id().so_vain
	eq(Ach.glyph_of(secret), "secret")
	var earned := secret.duplicate()
	earned.earned = true
	eq(Ach.glyph_of(earned), "mirror")
	eq(Ach.glyph_of(_by_id().charmed), "heart")
	var tex := Ach.badge_texture("trophy", "#ffffff")
	eq(tex.get_size(), Vector2(7, 7))
	ok(Ach.badge_texture("trophy", "#ffffff") == tex, "cached per name and color")
	ok(Ach.badge_texture("nope") == Ach.badge_texture("secret"), "unknown glyphs show the secret one")
	var img := Ach.badge_image("trophy", "#ff0000")
	var lit := 0
	for y in 7:
		for x in 7:
			if Ach.GLYPHS.trophy[y][x] == "#":
				lit += 1
				eq(img.get_pixel(x, y), Color(1, 0, 0, 1))
			else:
				eq(img.get_pixel(x, y).a, 0.0)
	eq(lit, "".join(Ach.GLYPHS.trophy).count("#"))
