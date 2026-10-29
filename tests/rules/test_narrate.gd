## Narration helpers: what the player reads instead of the Jev panel.
extends "res://tests/test_case.gd"

const Narrate = preload("res://src/rules/narrate.gd")
const Emotions = preload("res://src/rules/emotions.gd")
const Species = preload("res://src/rules/species.gd")

const WARM = {"friendliness": 80, "anger": 0, "fear": 0}
const WARY = {"friendliness": 50, "anger": 10, "fear": 20}


func test_every_species_has_a_voice_with_every_tell():
	var keys: Array = Narrate.VOICE.slime.keys()
	keys.sort()
	for sp in Species.SPECIES:
		ok(Narrate.VOICE.has(sp), "%s has a voice" % sp)
		var got: Array = Narrate.VOICE[sp].keys()
		got.sort()
		eq(got, keys, "%s has the same tells as the slime" % sp)


func test_reason_options_situational_reasons_only_when_they_can_be_true_code_only_never():
	var bare := Narrate.reason_options(Narrate.JOIN_NO, {})
	ok(not bare.has("loyal") and not bare.has("burned") and not bare.has("confused"))
	ok(bare.has("not_yet") and bare.has("pride"))
	var full := Narrate.reason_options(Narrate.JOIN_NO, {"others": ["Snag"], "formerAlly": true})
	ok(full.has("loyal") and full.has("burned") and not full.has("confused"))
	ok(not Narrate.reason_options(Narrate.JOIN_YES, {"kin": []}).has("kin"))
	ok(Narrate.reason_options(Narrate.JOIN_YES, {"kin": ["GLOP"]}).has("kin"))
	for v in full.values():
		ok(v is String)


func test_mood_a_feelings_tone_wins_otherwise_the_meters():
	eq(Narrate.mood_of(WARY, Emotions.EMOTIONS.touched), "warm")
	eq(Narrate.mood_of(WARM, Emotions.EMOTIONS.offended), "cold")
	eq(Narrate.mood_of(WARM, null), "warm")
	eq(Narrate.mood_of(WARY, null), "wary")
	eq(Narrate.mood_of({"friendliness": 10, "anger": 0, "fear": 0}), "cold")
	eq(Narrate.mood_of({"friendliness": 50, "anger": 0, "fear": 80}), "scared")
	eq(Narrate.mood_of(), "wary", "no meters: friendliness 50, anger 0")


func test_friendly_but_refuses_shows_the_warmth_then_the_reason_naming_who_it_wont_leave():
	var s = Narrate.join_line("goblin", "GRAK", {"asked": true, "accepted": false, "reason": "loyal", "others": ["SNAG"]}, {"meters": WARM})
	eq(s, "Grak grins, showing crooked teeth, but grunts that it won't leave Snag.")


func test_wary_but_accepts_says_it_still_looks_wary_then_why_it_comes_anyway():
	var s = Narrate.join_line("slime", "GLOP", {"asked": true, "accepted": true, "reason": "company"}, {"meters": WARY})
	eq(s, "Glop still quivers a little, but burbles that it won't be alone down here anymore.")


func test_after_a_feeling_line_the_answer_leads_with_a_gesture_and_still_flags_the_contrast():
	var no = Narrate.join_line("goblin", "GRAK", {"asked": true, "accepted": false, "reason": "pride"}, {"meters": WARM, "emotion": Emotions.EMOTIONS.delighted, "afterFeeling": true})
	eq(no, "Still, Grak shakes its big head and grunts that it'll follow no one.")
	var yes = Narrate.join_line("snake", "SSITH", {"asked": true, "accepted": true, "reason": "gold"}, {"meters": WARY, "emotion": Emotions.EMOTIONS.intrigued, "afterFeeling": true})
	eq(yes, "Even so, Ssith uncoils slowly and hisses that it'll take a share of your gold and loot.")


func test_plain_yes_and_plain_no_read_without_a_contrast():
	eq(
		Narrate.join_line("dragon", "VEXALITH", {"asked": true, "accepted": true, "reason": "strength"}, {"meters": WARM}),
		"Vexalith inclines its head and rumbles that it'll follow strength like yours.",
	)
	eq(
		Narrate.join_line("rock", "BOULDER", {"asked": true, "accepted": false, "reason": "still_angry"}, {"meters": {"friendliness": 20, "anger": 50, "fear": 0}}),
		"Boulder does not move and grinds out that it can't forgive what you did. Not yet.",
	)


func test_bandits_are_people_they_not_it():
	var s = Narrate.join_line("bandit", "ROOK", {"asked": true, "accepted": false, "reason": "home"}, {"meters": WARY})
	eq(s, "Rook shakes their head and says that they won't leave their home on this floor.")
	match_re(Narrate.side_line("bandit", "ROOK", "friendly with the party"), "out of them\\.$")


func test_a_monster_moved_to_ask_on_its_own_says_so():
	var s = Narrate.join_line("slime", "GLOP", {"asked": true, "accepted": true, "moved": true, "reason": "likes_you"}, {"meters": WARM})
	eq(s, "Glop wobbles closer and asks to come with you. It can't help liking you.")


func test_every_join_sentence_is_complete_for_every_species_reason_and_mood():
	var moods := [WARM, WARY, {"friendliness": 10, "anger": 60, "fear": 0}]
	var bad := RegEx.create_from_string("[{}]|undefined|null")
	for sp in Species.SPECIES:
		for pair in [[Narrate.JOIN_YES, true], [Narrate.JOIN_NO, false]]:
			for reason in pair[0]:
				for meters in moods:
					for after_feeling in [false, true]:
						var s = Narrate.join_line(sp, "NAME", {"asked": true, "accepted": pair[1], "reason": reason, "others": ["A", "B"], "kin": ["C"]}, {"meters": meters, "afterFeeling": after_feeling})
						ok(s != null and bad.search(s) == null, "%s/%s: %s" % [sp, reason, s])
						ok(s != null and s.ends_with("."), "%s/%s ends with a period: %s" % [sp, reason, s])
	eq(Narrate.join_line("slime", "X", null), null)
	eq(Narrate.join_line("slime", "X", {"asked": false}), null)


func test_unknown_reasons_fall_back_to_something_that_still_matches_the_outcome():
	match_re(Narrate.join_line("goblin", "G", {"asked": true, "accepted": true, "reason": "??"}, {"meters": WARM}), "can't help liking you")
	match_re(Narrate.join_line("goblin", "G", {"asked": true, "accepted": false, "reason": "??"}, {"meters": WARY}), "know you better")


func test_every_feeling_has_a_visible_tell():
	for id in Emotions.EMOTIONS:
		var s = Narrate.feeling_line("goblin", "GRAK", id)
		ok(s != null and s.begins_with("Grak "), id)
	eq(Narrate.feeling_line("slime", "GLOP", "touched"), "Glop jiggles softly, its blank stare gone gentle. Your words reached it.")
	eq(Narrate.feeling_line("slime", "GLOP", "nope"), null)


func test_tribute_refusals_say_why():
	match_re(Narrate.tribute_line("goblin", "GROK", "too_little"), "far too little")
	match_re(Narrate.tribute_line("goblin", "GROK", "angry"), "no amount of gold")
	match_re(Narrate.tribute_line("bandit", "ROOK", "not_for_sale"), "They can't be bought\\.$")


func test_history_is_retold_to_the_player_in_the_second_person():
	eq(Narrate.second_person("The party killed Drip, an orange slime, while it begged for mercy."), "you killed Drip, an orange slime, while it begged for mercy")
	eq(Narrate.second_person("The party befriended Glop, who joined them."), "you befriended Glop, who joined you")
	eq(Narrate.second_person("Grak offered to join, but the party turned it away."), "grak offered to join, but you turned it away")
	eq(Narrate.second_person("  The party's gold ran out.  "), "your gold ran out")
	eq(Narrate.nice("GRAK"), "Grak")
	eq(Narrate.nice("SNAG TAM"), "Snag Tam")
	eq(Narrate.nice("old shale"), "Old Shale")
	eq(Narrate.nice(null), "")


func test_ally_reactions_a_walk_out_names_the_moment_a_near_walk_out_stays_grumbling():
	var moment := "The party killed Drip while it begged for mercy."
	eq(Narrate.ally_line("slime", "GLOP", {"level": 0, "decision": "leave_party", "picked": "leave_party", "moment": moment}), "Glop can't stomach how you killed Drip while it begged for mercy.")
	match_re(Narrate.ally_line("slime", "GLOP", {"level": 1, "decision": "stay", "picked": "leave_party", "moment": moment}), "but stays\\. For now\\.$")
	match_re(Narrate.ally_line("goblin", "GRAK", {"level": 4, "decision": "stay", "picked": "stay", "moment": "The party attacked Snag."}), "It liked how you attacked Snag\\.$")
	eq(Narrate.ally_line("goblin", "GRAK", {"level": 2, "decision": "stay", "picked": "stay", "moment": moment}), null)
	match_re(Narrate.ally_line("rock", "BOULDER", {"level": 0, "decision": "turn_on_party", "moment": moment}), "won't forgive how you killed")
	eq(Narrate.ally_line("slime", "GLOP", {"level": 0, "decision": "leave_party"}), "Glop has had enough of you.")


func test_talk_and_vow_tells_follow_the_level():
	match_re(Narrate.reaction_tell("goblin", "GRAK", 0), "bares its teeth")
	match_re(Narrate.reaction_tell("goblin", "GRAK", 1), "ears droop")
	eq(Narrate.reaction_tell("goblin", "GRAK", 2), null)
	match_re(Narrate.reaction_tell("goblin", "GRAK", 4), "stands a little closer")
	match_re(Narrate.cant_forgive_line("snake", "SSITH"), "^Ssith lowers its head\\. It'd like to forgive you, but not after this\\.$")


func test_reaction_lines_come_from_the_bucket_that_matches_the_score():
	var reactions: Dictionary = Species.SPECIES.goblin.reactions # 3 approve, 2 neutral, 3 disapprove
	# Jev's overall favorite is a happy line, but the score says it hated it
	var probs := {"line_0": 0.7, "line_1": 0.1, "line_5": 0.05, "line_6": 0.1, "line_7": 0.05}
	eq(Narrate.reaction_line_index(probs, reactions, 0), 6)
	eq(Narrate.reaction_line_index(probs, reactions, 4), 0)
	eq(Narrate.reaction_line_index({}, reactions, 2), 3, "no odds: first neutral line")
	eq(Narrate.reaction_line_index(null, reactions, 2), 3)
	var all: Array = reactions.approve + reactions.neutral + reactions.disapprove
	for level in 5:
		var i := Narrate.reaction_line_index(probs, reactions, level)
		var bucket: Array = reactions.approve if level >= 3 else (reactions.neutral if level == 2 else reactions.disapprove)
		ok(bucket.has(all[i]))


func _result(extra := {}) -> Dictionary:
	var r := {
		"action": "converse", "picked": "converse", "blocked": null, "line": "Hur hur.", "spoken": true, "join": null,
		"emotion": null, "meters": WARM, "side": "friendly with the party",
	}
	r.merge(extra, true)
	return r


func test_group_log_a_narrated_refusal_replaces_small_talk_numbers_only_in_debug():
	var em: Dictionary = Emotions.EMOTIONS.delighted.duplicate()
	em["id"] = "delighted"
	em["delta"] = {"friendliness": 20}
	var r := _result({
		"spoken": false, "line": "unused", "emotion": em,
		"join": {"asked": true, "accepted": false, "reason": "loyal", "others": ["SNAG"]},
		"picked": "join_party", "blocked": "it turned the invitation down (loyal)",
	})
	var log := Narrate.group_log(r, {"name": "GRAK", "species": "goblin", "sideBefore": "friendly with the party"})
	eq(log.map(func(l): return l.kind), ["feeling", "emotion", "join"])
	eq(log[1].text, "GRAK IS DELIGHTED: WON'T ATTACK THIS ROUND.")
	eq(log[2].text, "Still, Grak shakes its big head and grunts that it won't leave Snag.")
	var dbg := Narrate.group_log(r, {"name": "GRAK", "species": "goblin", "debug": true})
	var emotion_line: Dictionary = dbg.filter(func(l): return l.kind == "emotion")[0]
	match_re(emotion_line.text, "\\(FRIENDLY \\+20\\)$")
	ok(dbg.any(func(l): return l.kind == "debug"))
	eq(dbg[-1].text, "[DEBUG] JEV PICKED JOIN_PARTY; CODE: it turned the invitation down (loyal)")


func test_group_log_a_joiner_speaks_then_says_why():
	var log := Narrate.group_log(_result({"action": "join_party", "line": "Fine. Grak joins.", "join": {"asked": true, "accepted": true, "reason": "gold"}}), {"name": "GRAK", "species": "goblin"})
	eq(log.map(func(l): return l.text), ["GRAK: Fine. Grak joins.", "Grak shoulders its club and grunts that it'll take a share of your gold and loot."])
	eq(log.map(func(l): return l.cls), ["npc", ""])


func test_group_log_a_change_of_side_is_told_unless_its_action_would_contradict_it():
	var warmed := Narrate.group_log(_result({}), {"name": "GRAK", "species": "goblin", "sideBefore": "undecided about the party"})
	match_re(warmed[-1].text, "the fight has gone out of it")
	var swinging := Narrate.group_log(_result({"action": "attack"}), {"name": "GRAK", "species": "goblin", "sideBefore": "undecided about the party"})
	ok(not swinging.any(func(l): return l.kind == "side"))
	var soured := Narrate.group_log(_result({"side": "hostile to the party", "meters": {"friendliness": 20, "anger": 40, "fear": 0}}), {"name": "GRAK", "species": "goblin", "sideBefore": "undecided about the party"})
	match_re(soured[-1].text, "You've made an enemy")
	var cooled := Narrate.group_log(_result({"side": "undecided about the party", "meters": WARY}), {"name": "GRAK", "species": "goblin", "sideBefore": "hostile to the party"})
	eq(cooled[-1].text, "Grak eyes you sideways, less sure it'd like this fight.")
	var doubting := Narrate.group_log(_result({"side": "undecided about the party", "meters": WARY}), {"name": "GRAK", "species": "goblin", "sideBefore": "friendly with the party"})
	eq(doubting[-1].text, "Grak eyes you sideways, no longer sure of you.")
	# First reply: no side to compare with yet
	ok(not Narrate.group_log(_result({}), {"name": "GRAK", "species": "goblin", "sideBefore": null}).any(func(l): return l.kind == "side"))


func test_group_log_a_refused_tribute_says_why():
	var log := Narrate.group_log(_result({"action": "refuse_tribute", "tributeRefusal": "too_little"}), {"name": "GROK", "species": "goblin"})
	match_re(log[-1].text, "far too little")
