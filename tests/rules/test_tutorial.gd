## Tips (src/rules/tutorial.gd): the hint registry and the once-only / queue / off / reset logic.
extends "res://tests/test_case.gd"

const Tutorial = preload("res://src/rules/tutorial.gd")
const StoreScript = preload("res://src/core/store.gd")

var _rigs := []


## Break the rig <-> tutorial reference cycle (the callbacks capture the rig) so nothing leaks between tests.
func after_each() -> void:
	for r in _rigs:
		r.tips = null
		r.clear()
	_rigs.clear()


## A tutorial with a fake clock, a settable game context, and a record of what it showed and hid.
func _rig(opts := {}) -> Dictionary:
	var r := {"store": opts.get("store", StoreScript.Memory.new()), "ctx": opts.get("ctx", "explore"), "t": 1000, "shown": [], "hidden": [], "nudged": []}
	r.tips = Tutorial.create_tutorial({
		"store": r.store,
		"context": func(): return r.ctx,
		"now": func(): return r.t,
		"show": func(id, _h): r.shown.append(id),
		"hide": func(id): r.hidden.append(id),
		"nudge": func(id): r.nudged.append(id),
	})
	_rigs.append(r)
	return r


func _wait(r: Dictionary, ms: int) -> void:
	r.t += ms
	r.tips.tick()


func test_every_hint_is_one_or_two_short_lines_with_a_known_context():
	for id in Tutorial.HINTS:
		var h: Dictionary = Tutorial.HINTS[id]
		ok(["explore", "combat", "any"].has(h.ctx), "%s: ctx" % id)
		ok(h.lines.size() >= 1 and h.lines.size() <= 2, "%s: 1-2 lines" % id)
		for line in h.lines:
			var visible := ""
			for t in Tutorial.parse_line(line):
				visible += t.text if t.has("text") else " %s " % t.key
			ok(visible.length() <= 46, '%s: "%s" is too long (%d)' % [id, visible, visible.length()])
			eq(line, line.to_upper(), "%s: the UI is all caps" % id)


func test_the_briefs_moments_all_have_a_hint():
	for id in ["move", "map", "stairs", "combat", "target", "feeling", "recruit", "ally", "camp", "levelup", "down", "boss"]:
		ok(Tutorial.HINTS.has(id), id)
	match_re(" ".join(Tutorial.HINTS.combat.lines), "\\{!?T\\}.*TALK", "the first fight teaches that you can talk")


func test_hints_refer_to_controls_by_key_never_by_screen_position():
	var all := []
	for h in Tutorial.HINTS.values():
		all.append_array(h.lines)
	ok(RegEx.create_from_string("\\b(TOP|BOTTOM|LEFT PANEL|RIGHT PANEL|BAR|ABOVE|BELOW|CORNER)\\b").search(" ".join(all)) == null)


func test_parse_line_splits_keycaps_out_of_the_text_with_bang_marking_the_hot_key():
	eq(Tutorial.parse_line("PRESS {!T} TO TALK"), [{"text": "PRESS "}, {"key": "T", "hot": true}, {"text": " TO TALK"}])
	eq(Tutorial.parse_line("{1}{2}"), [{"key": "1", "hot": false}, {"key": "2", "hot": false}])
	eq(Tutorial.parse_line("NO KEYS"), [{"text": "NO KEYS"}])
	eq(Tutorial.parse_line("{!↑} STEP  {←}{→} TURN"), [{"key": "↑", "hot": true}, {"text": " STEP  "}, {"key": "←", "hot": false}, {"key": "→", "hot": false}, {"text": " TURN"}])


func test_a_hint_shows_once_and_stays_seen_across_sessions():
	var store := StoreScript.Memory.new()
	var a := _rig({"store": store})
	eq(a.tips.hint("move"), true)
	eq(a.shown, ["move"])
	eq(a.tips.current(), "move")
	eq(a.tips.hint("move"), false, "already showing")
	_wait(a, Tutorial.GRACE_MS)
	eq(a.tips.dismiss(), true)
	eq(a.tips.hint("move"), false, "already seen")
	eq(JSON.parse_string(store.data[Tutorial.SEEN_KEY]), ["move"])

	var b := _rig({"store": store})
	eq(b.tips.seen("move"), true)
	eq(b.tips.hint("move"), false)
	eq(b.shown, [])


func test_unknown_ids_are_ignored_and_a_corrupt_store_doesnt_break_anything():
	var r := _rig({"store": StoreScript.Memory.new({Tutorial.SEEN_KEY: "{not json"})})
	eq(r.tips.hint("nope"), false)
	eq(r.tips.hint("move"), true)
	var s := _rig({"store": StoreScript.Memory.new({Tutorial.SEEN_KEY: '["move", "gone", 7]'})})
	eq(s.tips.seen("move"), true)
	eq(s.tips.seen("gone"), false, "ids that are no longer hints are dropped")


func test_a_key_right_after_a_hint_appears_doesnt_dismiss_it_a_later_one_does():
	var r := _rig()
	r.tips.hint("move")
	r.t += Tutorial.GRACE_MS - 1
	eq(r.tips.dismiss(), false, "inside the grace period (held key, or the key that triggered it)")
	eq(r.tips.current(), "move")
	r.t += 1
	eq(r.tips.dismiss(), true)
	eq(r.tips.current(), null)
	eq(r.hidden, ["move"])


func test_a_forced_dismiss_click_menu_works_immediately():
	var r := _rig()
	r.tips.hint("move")
	eq(r.tips.dismiss({"force": true}), true)
	eq(r.tips.current(), null)


func test_hints_queue_one_at_a_time_with_a_short_breath_between_them():
	var r := _rig()
	r.tips.hint("move")
	r.tips.hint("map")
	eq(r.shown, ["move"])
	eq(r.tips.pending(), ["map"])
	_wait(r, Tutorial.GRACE_MS)
	r.tips.dismiss()
	r.tips.tick()
	eq(r.shown, ["move"], "not straight away")
	_wait(r, Tutorial.GAP_MS)
	eq(r.shown, ["move", "map"])


func test_explore_hints_wait_out_a_fight_combat_hints_wait_out_exploring():
	var r := _rig({"ctx": "combat"})
	r.tips.hint("ally") # you recruit mid-fight, but E only talks to allies outside one
	eq(r.shown, [])
	r.ctx = "explore"
	_wait(r, Tutorial.GAP_MS)
	eq(r.shown, ["ally"])


func test_a_combat_hint_whose_fight_ended_before_it_got_its_turn_is_dropped_and_can_come_back_next_fight():
	var r := _rig({"ctx": "combat"})
	r.tips.hint("combat")
	r.tips.hint("feeling")
	eq(r.tips.pending(), ["feeling"])
	r.ctx = "explore"
	_wait(r, Tutorial.MIN_READ_MS)
	eq(r.tips.current(), null, "the fight hint goes away with the fight")
	eq(r.tips.pending(), [], "its moment passed")
	eq(r.tips.seen("feeling"), false)
	r.ctx = "combat"
	eq(r.tips.hint("feeling"), true)
	_wait(r, Tutorial.GAP_MS)
	eq(r.tips.current(), "feeling")


func test_any_hints_show_in_both_fights_and_exploring():
	var r := _rig({"ctx": "combat"})
	r.tips.hint("levelup")
	eq(r.tips.current(), "levelup")


func test_nothing_shows_during_a_roll_of_fate_or_game_over_a_hint_cut_short_comes_back_after():
	var r := _rig()
	r.tips.hint("stairs")
	r.ctx = "roll"
	_wait(r, 100)
	eq(r.tips.current(), null)
	r.tips.hint("boss")
	_wait(r, Tutorial.GAP_MS)
	eq(r.shown, ["stairs"])
	r.ctx = "explore"
	_wait(r, Tutorial.GAP_MS)
	eq(r.tips.current(), "stairs", "shown for only 100ms, so it gets another go")
	_wait(r, Tutorial.GRACE_MS)
	r.tips.dismiss()
	_wait(r, Tutorial.GAP_MS)
	eq(r.tips.current(), "boss")


func test_a_hint_nobody_dismisses_fades_on_its_own():
	var r := _rig()
	r.tips.hint("move")
	_wait(r, Tutorial.TTL_MS + 1)
	eq(r.tips.current(), null)


func test_turning_tips_off_hides_the_current_one_drops_the_queue_and_persists():
	var store := StoreScript.Memory.new()
	var r := _rig({"store": store})
	r.tips.hint("move")
	r.tips.hint("map")
	r.tips.set_enabled(false)
	eq(r.tips.on(), false)
	eq(r.tips.current(), null)
	eq(r.tips.pending(), [])
	eq(r.tips.hint("stairs"), false)
	eq(store.data[Tutorial.OFF_KEY], "1")
	eq(_rig({"store": store}).tips.on(), false, "remembered")
	r.tips.set_enabled(true)
	eq(r.tips.hint("stairs"), true)
	eq(_rig({"store": store}).tips.on(), true)


func test_reset_forgets_every_seen_hint():
	var store := StoreScript.Memory.new()
	var r := _rig({"store": store})
	r.tips.hint("move")
	r.tips.dismiss({"force": true})
	r.tips.reset()
	eq(r.tips.seen("move"), false)
	eq(JSON.parse_string(store.data[Tutorial.SEEN_KEY]), [])
	_wait(r, Tutorial.GAP_MS)
	eq(r.tips.hint("move"), true)


func test_h_turns_tips_off_h_again_turns_them_back_on_from_the_start_with_no_menu_to_wait_on():
	var r := _rig({"ctx": "combat"})
	var said := []
	var say := func(text, _cls): said.append(text)
	r.tips.hint("combat")
	r.tips.hint("feeling")
	eq(r.tips.toggle(say), false)
	eq(r.tips.on(), false)
	eq(r.tips.current(), null)
	match_re(said[-1], "OFF.*H")

	eq(r.tips.toggle(say), true)
	eq(r.tips.on(), true)
	eq(r.tips.seen("feeling"), false, "back on means from the start")
	eq(r.tips.current(), "combat", "and the reminder for where you are shows right away")
	match_re(said[-1], "FROM THE START")


func test_each_hint_lights_up_the_real_thing_it_talks_about_its_keys_buttons_the_map_the_party():
	eq(Tutorial.focus_of("combat"), ['[data-key="f"]', '[data-key="c"]', '[data-key="e"]', '[data-key="t"]'])
	eq(Tutorial.focus_of("move"), ['[data-key="fwd"]', '[data-key="turnL"]', '[data-key="turnR"]', '[data-key="back"]'])
	ok(Tutorial.focus_of("map").has("#map"))
	ok(Tutorial.focus_of("boss").has("#map"))
	ok(Tutorial.focus_of("down").any(func(s): return s.begins_with("#party")))
	ok(not Tutorial.focus_of("levelup").has('[data-key="c"]'), "C means CAMP outside a fight, so don't light it up there")
	eq(Tutorial.focus_of("nope"), [])


func test_the_key_that_acts_also_clears_the_hint_a_key_the_game_ignores_nudges_it_instead():
	var r := _rig({"ctx": "combat"})
	r.tips.hint("combat")
	_wait(r, Tutorial.GRACE_MS)
	r.tips.ignored("fwd") # trying to walk away mid-fight does nothing
	r.tips.keyed()
	eq(r.tips.current(), "combat", "still there")
	eq(r.nudged, ["combat"])
	r.tips.keyed() # a key the game used
	eq(r.tips.current(), null)


func test_modifier_and_other_non_command_keys_are_never_treated_as_ignored_commands():
	var r := _rig()
	r.tips.hint("move")
	for k in ["shift", "capslock", "tab", "meta"]:
		r.tips.ignored(k)
	eq(r.nudged, [])


func test_flailing_with_no_hint_up_brings_back_the_reminder_for_where_you_are_but_not_too_often():
	var r := _rig({"ctx": "combat"})
	r.tips.hint("combat")
	r.tips.dismiss({"force": true})
	_wait(r, Tutorial.GAP_MS)
	r.tips.ignored("w")
	eq(r.tips.current(), null, "one stray key is fine")
	r.t += 500
	r.tips.ignored("w")
	eq(r.tips.current(), "combat", "two in a row: here's how fighting works again")
	r.tips.dismiss({"force": true})
	_wait(r, Tutorial.GAP_MS)
	r.tips.ignored("x")
	r.tips.ignored("x")
	eq(r.tips.current(), null, "cooling down")
	_wait(r, Tutorial.REMIND_COOLDOWN_MS)
	r.tips.ignored("x")
	r.tips.ignored("x")
	eq(r.tips.current(), "combat")


func test_no_reminders_when_tips_are_off():
	var r := _rig()
	r.tips.set_enabled(false)
	r.tips.ignored("t")
	r.tips.ignored("t")
	eq(r.tips.current(), null)


func test_hints_step_aside_while_a_yes_no_question_is_up_and_come_back_after():
	var r := _rig()
	r.tips.hint("stairs")
	r.ctx = "prompt"
	_wait(r, 100)
	eq(r.tips.current(), null)
	r.ctx = "explore"
	_wait(r, Tutorial.GAP_MS)
	eq(r.tips.current(), "stairs")


func test_defaults_work_without_any_callbacks_store_or_clock():
	var tips := Tutorial.create_tutorial()
	eq(tips.on(), true)
	eq(tips.hint("move"), true)
	eq(tips.current(), "move")
	eq(tips.toggle(), false)


# ---- the guided first fight

func test_the_first_fight_is_a_lesson_t_first_then_r_and_every_other_fight_key_waits():
	eq(Tutorial.guide_allows("talk", "t"), true)
	for k in ["f", "c", "r", "g", "v", "e", "1"]:
		eq(Tutorial.guide_allows("talk", k), false, k)
	eq(Tutorial.guide_allows("recruit", "r"), true)
	for k in ["f", "c", "t", "g", "v", "e"]:
		eq(Tutorial.guide_allows("recruit", k), false, k)
	eq(Tutorial.guide_allows(null, "f"), true, "no lesson, no lock")
	eq(Tutorial.GUIDE.talk.next, "recruit")
	eq(Tutorial.GUIDE.recruit.next, null)
	for step in Tutorial.GUIDE.values():
		ok(Tutorial.HINTS.has(step.hint), step.hint)
		eq(Tutorial.focus_of(step.hint), ['[data-key="%s"]' % step.key], "the tip lights up only the key to press")


func test_only_a_new_players_first_ordinary_fight_on_the_first_floor_is_guided():
	var base := {"floor": 1, "tipsOn": true, "seen": func(_id): return false}
	eq(Tutorial.should_guide(base), true)
	eq(Tutorial.should_guide({"floor": 2, "tipsOn": true, "seen": base.seen}), false)
	eq(Tutorial.should_guide({"floor": 1, "tipsOn": false, "seen": base.seen}), false, "tips off (H): no lesson")
	eq(Tutorial.should_guide({"floor": 1, "tipsOn": true, "seen": func(id): return id == Tutorial.GUIDE.talk.hint}), false, "learned it already")


func test_a_key_held_back_by_the_lesson_keeps_its_tip_up_or_brings_it_back_never_the_generic_reminder():
	var r := _rig({"ctx": "combat"})
	r.tips.hint("talkFirst")
	eq(r.tips.current(), "talkFirst")
	_wait(r, Tutorial.GRACE_MS + 10)
	r.tips.insist("talkFirst") # F pressed: locked
	eq(r.tips.keyed(), false, "the locked key doesn't clear the tip")
	eq(r.nudged, ["talkFirst"])
	r.tips.dismiss({"force": true})
	_wait(r, Tutorial.GAP_MS + 10)
	r.tips.insist("talkFirst")
	r.tips.insist("talkFirst")
	eq(r.tips.current(), "talkFirst", "back up after being clicked away")
	ok(not r.shown.has("combat"), "not the F-QUICK-ATTACK reminder")
