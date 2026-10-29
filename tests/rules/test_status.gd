## Party status helpers and readable dice text.
extends "res://tests/test_case.gd"

const Status = preload("res://src/rules/status.gd")
const Dnd = preload("res://src/rules/dnd.gd")


## Draws inside a real _draw(), so a call that only works outside it fails the test.
class Probe:
	extends Node2D
	var calls := Callable()
	var drew := false

	func _draw() -> void:
		calls.call(self)
		drew = true


func _member(hp, max_hp, extra := {}) -> Dictionary:
	var m := {"hp": hp, "maxHp": max_hp, "dead": false, "down": false}
	m.merge(extra, true)
	return m


func test_health_state_goes_healthy_hurt_critical_by_share_of_max_health():
	eq(Status.hp_state(_member(40, 40)).id, "healthy")
	eq(Status.hp_state(_member(30, 40)).id, "healthy")
	eq(Status.hp_state(_member(29, 40)).id, "hurt")
	eq(Status.hp_state(_member(14, 40)).id, "hurt")
	eq(Status.hp_state(_member(13, 40)).id, "critical")
	eq(Status.hp_state(_member(1, 40)).id, "critical")


func test_down_stable_and_dead_beat_the_health_share_and_every_state_has_a_plain_word_and_a_color():
	eq(Status.hp_state(_member(0, 40, {"down": true})).id, "dying")
	eq(Status.hp_state(_member(0, 40, {"down": true, "stable": true})).id, "stable")
	eq(Status.hp_state(_member(12, 40, {"dead": true})).id, "dead")
	for s in [_member(40, 40), _member(20, 40), _member(2, 40), _member(0, 40, {"down": true}), _member(0, 40, {"dead": true})]:
		var st := Status.hp_state(s)
		match_re(st.word, "^[A-Z ]+$")
		match_re(st.color, "(?i)^#[0-9a-f]{6}$")
		ok(st.pct >= 0 and st.pct <= 1)
	eq(Status.hp_state(_member(29, 40)).word, "HURT")
	near(Status.hp_state(_member(10, 40)).pct, 0.25)


func test_a_monster_at_0_hp_that_is_not_flagged_down_still_reads_as_down_never_as_negative_health():
	var st := Status.hp_state({"hp": -5, "maxHp": 20})
	eq(st.pct, 0)


func test_conditions_come_out_as_plain_words_with_colors_in_a_stable_order_unknown_keys_dropped():
	var list := Status.cond_list({"prone": 1, "poisoned": 2, "nonsense": 3, "asleep": 4})
	eq(list.map(func(c): return c.word), ["ASLEEP", "POISONED", "KNOCKED DOWN"])
	for c in list:
		match_re(c.color, "(?i)^#[0-9a-f]{6}$")
		ok(c.tip.length() > 10)
	eq(list[0].id, "asleep")
	eq(Status.cond_list(null), [])
	eq(Status.cond_list({"held": 1, "asleep": 1, "lit": 1}, 2).size(), 2)
	eq(Status.cond_list({"asleep": 0, "held": false}), [], "falsy values are not conditions")


func test_no_condition_word_is_a_cryptic_tag():
	for c in Status.CONDITIONS.values():
		ok(not ["ZZZ", "SAD", "BOUND", "POISON", "HELD", "PRONE"].has(c.word), c.word)


func test_loyalty_reads_as_a_word_that_gets_more_urgent_as_it_drops():
	eq(Status.loyalty_state(90).word, "DEVOTED")
	eq(Status.loyalty_state(60).word, "CONTENT")
	eq(Status.loyalty_state(35).word, "UNEASY")
	eq(Status.loyalty_state(20).word, "RESENTFUL")
	eq(Status.loyalty_state(5).word, "MAY LEAVE")


func test_spell_slots_become_pip_groups_one_per_circle_filled_for_what_is_left():
	var g := Status.slot_groups([3, 0, 2], [4, 3, 2])
	eq(g.map(func(x): return [x.circle, x.left, x.max]), [[1, 3, 4], [2, 0, 3], [3, 2, 2]])
	eq(g[0].pips, [true, true, true, false])
	ok(g.all(func(x): return RegEx.create_from_string("(?i)^#[0-9a-f]{6}$").search(x.color) != null))
	ne(g[0].color, g[1].color)
	eq(Status.slot_groups(null, null), [])
	eq(Status.slot_groups(null, [2])[0].left, 0, "no slots info reads as empty")
	eq(Status.slot_groups([9], [2])[0].left, 2, "never more than the max")


func test_class_words_are_spelled_out_and_facing_and_floor_are_words():
	eq(Status.class_word({"kind": "human", "clsId": "fighter"}), "FIGHTER")
	eq(Status.class_word({"kind": "monster", "species": "goblin"}), "GOBLIN")
	eq(Status.class_word({"kind": "monster", "species": "snake"}), "SNAKE PERSON")
	eq(Status.class_word({"kind": "monster", "species": "newt"}), "NEWT")
	eq(Status.facing_word(0), "NORTH")
	eq(Status.facing_word(3), "WEST")
	eq(Status.facing_word(7), "")
	eq(Status.floor_name(5), "FLOOR 5")
	eq(Status.floor_name(5.0), "FLOOR 5")


func test_roll_text_says_what_was_rolled_with_advantage_in_words_and_the_total():
	eq(Dnd.fmt_roll({"roll": 14, "rolls": [14], "adv": 0}, 5), "ROLLED 14 +5 = 19")
	eq(Dnd.fmt_roll({"roll": 16, "rolls": [13, 16], "adv": 1}, 5), "ROLLED 16 (ADVANTAGE) +5 = 21")
	eq(Dnd.fmt_roll({"roll": 7, "rolls": [7, 15], "adv": -1}, -1), "ROLLED 7 (DISADVANTAGE) -1 = 6")
	eq(Dnd.fmt_roll({"roll": 9, "rolls": [9], "adv": 0}, 0), "ROLLED 9")
	ok(RegEx.create_from_string("D20|ADV→|DIS→").search(Dnd.fmt_roll({"roll": 3, "rolls": [3, 2], "adv": 1}, 2)) == null)


func test_dice_ranges_replace_dice_notation():
	eq(Dnd.dice_range("1d10"), "1-10")
	eq(Dnd.dice_range("8d6"), "8-48")
	eq(Dnd.dice_range("1d4+1"), "2-5")
	eq(Dnd.dice_range("2d4-1"), "1-7")


func test_every_spell_description_is_free_of_dice_notation_and_stat_abbreviations_and_cantrips_grow():
	var bad := RegEx.create_from_string("\\b\\d*D\\d+\\b|\\{|\\b(DEX|WIS|STR|CON|INT|CHA|HP|AC|DC)\\b")
	for k in Dnd.SPELLS:
		var t := Dnd.spell_text(k, 1)
		ok(t.length() > 5, k)
		ok(bad.search(t) == null, "%s: %s" % [k, t])
	match_re(Dnd.spell_text("fire_bolt", 1), "1-10")
	match_re(Dnd.spell_text("fire_bolt", 5), "2-20")
	var a: Array = Dnd.SPELL_TEXT.keys()
	var b: Array = Dnd.SPELLS.keys()
	a.sort()
	b.sort()
	eq(a, b)


func test_every_icon_is_a_7x7_bitmap_and_every_condition_has_one():
	for name in Status.ICONS:
		var rows: Array = Status.ICONS[name]
		eq(rows.size(), 7, name)
		for r in rows:
			match_re(r, "^[.#]{7}$", name)
	for k in Status.CONDITIONS:
		ok(Status.ICONS.has(Status.CONDITIONS[k].icon), "%s has no icon" % k)


func test_an_icon_renders_as_a_crisp_texture_in_its_color_and_unknown_names_fall_back_to_a_dot():
	var tex := Status.icon_texture("heart", "#ff0000")
	eq(tex.get_size(), Vector2(7, 7), "one texel per dot")
	var img := Status.icon_image("heart", "#ff0000")
	var lit := 0
	for y in 7:
		for x in 7:
			var c := img.get_pixel(x, y)
			if Status.ICONS.heart[y][x] == "#":
				lit += 1
				eq(c, Color(1, 0, 0, 1))
			else:
				eq(c.a, 0.0)
	eq(lit, "".join(Status.ICONS.heart).count("#"))
	ok(Status.icon_texture("heart", "#ff0000") == tex, "cached per name and color")
	ok(Status.icon_texture("heart", "#00ff00") != tex)
	ok(Status.icon_texture("nope") == Status.icon_texture("dot"))
	ok(Status.icon_image("heart") == Status.icon_image("heart", "#e8e8e8"), "default color")


func test_menu_highlight_wraps_around_both_ways():
	eq(Status.menu_step(0, -1, 5), 4)
	eq(Status.menu_step(4, 1, 5), 0)
	eq(Status.menu_step(2, 1, 5), 3)
	eq(Status.menu_step(null, 1, 3), 0)


func test_the_party_holds_six_allies_get_whatever_seats_the_adventurers_leave():
	var h := func(dead := false): return {"kind": "human", "dead": dead}
	var a := func(): return {"kind": "monster"}
	eq(Status.PARTY_MAX, 6)
	eq(Status.ally_room([h.call(), h.call(), h.call()]), {"allies": 0, "max": 3, "full": false})
	eq(Status.ally_room([h.call(), h.call(), h.call(), a.call(), a.call()]), {"allies": 2, "max": 3, "full": false})
	eq(Status.ally_room([h.call(), h.call(), h.call(), a.call(), a.call(), a.call()]), {"allies": 3, "max": 3, "full": true})
	eq(Status.ally_room([h.call(), h.call(true), h.call(), a.call()]), {"allies": 1, "max": 3, "full": false}, "a fallen adventurer keeps their seat")


func test_draw_icon_paints_inside_draw_at_any_scale_and_falls_back_to_a_dot():
	var p := Probe.new()
	p.calls = func(item):
		Status.draw_icon(item, "heart", Vector2(4, 4), "#ff0000")
		Status.draw_icon(item, "skull", Vector2(20, 4), Color.WHITE, 3)
		Status.draw_icon(item, "nope", Vector2(50, 4), "#8a8a8a", 2)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(p)
	p.queue_redraw()
	await tree.process_frame
	await tree.process_frame
	ok(p.drew)
	p.queue_free()
