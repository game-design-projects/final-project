# The recruit flow end to end: the answer to "join us?" agrees with what the log says. Jev is stubbed with canned
# answers (no API calls, no credits). Ported from crawler/test/join.test.js.
extends "res://tests/test_case.gd"

const Enemy = preload("res://src/jev/enemy.gd")
const Jev = preload("res://src/jev/jev.gd")
const Narrate = preload("res://src/rules/narrate.gd")
const Emotions = preload("res://src/rules/emotions.gd")
const Species = preload("res://src/rules/species.gd")

const PARTY := [{"id": "h0", "name": "HORTENSE", "kind": "human", "cls": "G-FIG", "hp": 14, "maxHp": 14}]

var fake: FakeJev


func before_each():
	seed(11)
	Jev.configure_jev("test-key")


func after_each():
	Jev.configure_jev(null)


static func emotion(id: String) -> Dictionary:
	var e: Dictionary = Emotions.EMOTIONS[id].duplicate(true)
	e["id"] = id
	return e


## Answers every question in the request: defaults that keep things calm, plus per-question overrides by suffix.
class FakeJev:
	extends RefCounted
	var overrides: Dictionary
	var last_questions := {}

	func _init(o: Dictionary) -> void:
		overrides = o

	func fetch(_url, _headers, body) -> Dictionary:
		var questions: Dictionary = body["questions"]
		var answers := {}
		for key in questions:
			var q: Dictionary = questions[key]
			var suffix := "__".join((key as String).split("__").slice(1))
			var keys: Array = [] if q["type"] == "score" else (q["criteria"] as Dictionary).keys() if q.get("criteria") != null else []
			var a: Dictionary
			if q["type"] == "noul":
				a = {"noul": 0}
			elif q["type"] == "score":
				a = {"score": 1}
			else:
				a = {"choice": keys[0], "probabilities": _one_hot(keys, keys[0])}
			if overrides.has(suffix):
				var o = overrides[suffix]
				if q["type"] == "noul":
					a = {"noul": o}
				elif q["type"] == "score":
					a = {"score": o}
				elif o is String:
					a = {"choice": o, "probabilities": _one_hot(keys, o)}
				else:
					var best = null
					for k in o:
						if best == null or o[k] > o[best]:
							best = k
					a = {"choice": best, "probabilities": o}
			var full := {"type": q["type"]}
			full.merge(a)
			full["confidence"] = 0.9
			answers[key] = full
		last_questions = questions
		return {"status": 200, "json": {"answers": answers, "usage": {"input_tokens": 1}, "model": "fake"}}

	static func _one_hot(keys: Array, hot) -> Dictionary:
		var p := {}
		for k in keys:
			p[k] = 1 if k == hot else 0
		return p


func stub(overrides: Dictionary) -> void:
	fake = FakeJev.new(overrides)
	Jev.configure_jev("test-key", {"transport": fake})


static func mon(id: String, species: String, name: String, meters: Dictionary, extra := {}) -> Dictionary:
	var m := {
		"id": id, "species": species, "name": name, "traits": Species.SPECIES[species]["traits"].slice(0, 2), "hp": 20, "maxHp": 20,
		"meters": meters, "specialReady": false, "paid": false, "demanded": false, "impressions": [], "formerAlly": false, "grudges": [], "thisRound": [],
	}
	m.merge(extra, true)
	return m


static func recruit(target_id: String, pitch: String) -> Dictionary:
	return {"type": "recruit", "targetId": target_id, "pitch": pitch, "message": null, "delivery": 1.25}


func turn(monsters: Array, player_action: Dictionary) -> Dictionary:
	return await Enemy.group_turn({"monsters": monsters, "party": PARTY.duplicate(true), "round": 1, "playerAction": player_action, "events": [], "conversation": [], "partyGold": 30, "vows": []})


func test_resolve_join_eligible_and_willing_says_yes_with_jevs_reason():
	var r = Enemy.resolve_join({"invited": true, "meters": {"friendliness": 70, "anger": 0}, "threshold": 65, "willing": 0.8, "yesWhy": "gold", "noWhy": "pride"})
	eq(r, {"asked": true, "accepted": true, "moved": false, "reason": "gold"})


func test_resolve_join_eligible_but_unwilling_refuses_with_jevs_reason():
	var r = Enemy.resolve_join({"invited": true, "meters": {"friendliness": 90, "anger": 0}, "threshold": 65, "willing": 0.2, "yesWhy": "gold", "noWhy": "loyal"})
	eq(r, {"asked": true, "accepted": false, "moved": false, "reason": "loyal"})


func test_resolve_join_under_its_bar_it_refuses_even_if_jev_is_keen():
	var r = Enemy.resolve_join({"invited": true, "meters": {"friendliness": 50, "anger": 0}, "threshold": 65, "willing": 0.9, "noWhy": "wants_more"})
	eq(r["accepted"], false)
	eq(r["reason"], "wants_more")


func test_resolve_join_an_angry_or_offended_refusal_gets_an_angry_reason():
	var angry = Enemy.resolve_join({"invited": true, "meters": {"friendliness": 90, "anger": 40}, "threshold": 55, "willing": 0.9, "noWhy": "home"})
	eq(angry["reason"], "still_angry")
	var botched = Enemy.resolve_join({"invited": true, "meters": {"friendliness": 76, "anger": 47}, "threshold": 55, "willing": 0.9, "noWhy": "not_yet", "pitch": "botch"})
	eq(botched["reason"], "bad_pitch")
	# Offended this round: no yes, even with the meters still over the bar
	var offended = Enemy.resolve_join({"invited": true, "meters": {"friendliness": 80, "anger": 20}, "threshold": 55, "willing": 0.9, "emotion": emotion("offended"), "noWhy": "pride"})
	eq([offended["accepted"], offended["reason"]], [false, "pride"])
	var confused = Enemy.resolve_join({"invited": true, "meters": {"friendliness": 80, "anger": 0}, "threshold": 55, "willing": 0.9, "emotion": emotion("confused"), "noWhy": "pride"})
	eq([confused["accepted"], confused["reason"]], [false, "confused"])


func test_resolve_join_an_invalid_or_missing_reason_falls_back_to_one_that_fits():
	eq(Enemy.resolve_join({"invited": true, "meters": {"friendliness": 10, "anger": 0}, "threshold": 55, "noWhy": "confused"})["reason"], "not_yet")
	eq(Enemy.resolve_join({"invited": true, "meters": {"friendliness": 10, "anger": 0}, "threshold": 55})["reason"], "not_yet")
	eq(Enemy.resolve_join({"invited": true, "meters": {"friendliness": 90, "anger": 0}, "threshold": 55, "willing": 1})["reason"], "likes_you")


func test_resolve_join_a_near_even_answer_is_tipped_by_the_action_roll_landing_on_join():
	var base := {"invited": true, "meters": {"friendliness": 70, "anger": 0}, "threshold": 65, "willing": 0.4}
	eq(Enemy.resolve_join(base)["accepted"], false)
	eq(Enemy.resolve_join(base.merged({"rolledJoin": true}, true))["accepted"], true)
	eq(Enemy.resolve_join(base.merged({"willing": 0.1, "rolledJoin": true}, true))["accepted"], false)


func test_resolve_join_uninvited_only_a_touched_or_delighted_monster_over_its_bar_asks_to_come():
	var m := {"friendliness": 80, "anger": 0}
	eq(Enemy.resolve_join({"invited": false, "meters": m, "threshold": 55, "willing": 0.9, "emotion": emotion("amused")}), null)
	eq(
		Enemy.resolve_join({"invited": false, "meters": m, "threshold": 55, "willing": 0.9, "emotion": emotion("touched"), "yesWhy": "grateful"}),
		{"asked": true, "accepted": true, "moved": true, "reason": "grateful"},
	)
	eq(Enemy.resolve_join({"invited": false, "meters": {"friendliness": 40, "anger": 0}, "threshold": 55, "willing": 0.9, "emotion": emotion("touched")}), null)
	eq(Enemy.resolve_join({"invited": true, "meters": m, "threshold": 55, "willing": 1, "room": false}), null)


# ---- group_turn with a stubbed Jev


func test_a_convincing_pitch_brings_it_up_to_its_bar_so_the_answer_is_its_own_choice():
	stub({"emotion": "intrigued", "would_join": 0.9, "join_yes": "strength", "action": "converse"})
	var out := await turn([mon("e0", "goblin", "Grok", {"friendliness": 40, "anger": 10, "fear": 5})], recruit("e0", "success"))
	var r: Dictionary = out["results"][0]
	ok(fake.last_questions.has("e0__join_yes") and fake.last_questions.has("e0__join_no"), "reasons asked both ways")
	eq(r["action"], "join_party")
	eq([r["join"]["accepted"], r["join"]["reason"]], [true, "strength"])
	var log := Narrate.group_log(r, {"name": "Grok", "species": "goblin"})
	ok(log.any(func(l): return l["text"] == "GROK: " + r["line"]))
	ok(log.any(func(l): return RegEx.create_from_string("follow strength like yours").search(l["text"]) != null))


func test_friendly_but_refuses_no_join_no_attack_and_the_log_says_it_wont_leave_its_brother():
	stub({"emotion": "delighted", "would_join": 0.1, "join_no": "loyal", "action": {"join_party": 0.6, "attack": 0.4}})
	var out := await turn(
		[mon("e0", "goblin", "Grak", {"friendliness": 62, "anger": 5, "fear": 5}), mon("e1", "goblin", "Snag", {"friendliness": 25, "anger": 15, "fear": 5})],
		recruit("e0", "success"),
	)
	var r: Dictionary = out["results"].filter(func(x): return x["id"] == "e0")[0]
	eq(r["action"], "converse")
	eq(r["side"], "friendly with the party")
	eq([r["join"]["accepted"], r["join"]["reason"], r["join"]["others"]], [false, "loyal", ["Snag"]])
	eq(r["spoken"], false, "no cheerful small talk after a refusal")
	var log := Narrate.group_log(r, {"name": "Grak", "species": "goblin", "sideBefore": "friendly with the party"})
	ok(not log.any(func(l): return l["kind"] == "line"))
	eq(log.filter(func(l): return l["kind"] == "join")[0]["text"], "Still, Grak shakes its big head and grunts that it won't leave Snag.")


func test_a_refusal_in_its_own_words_uses_the_species_not_yet_line():
	stub({"would_join": 0.1, "join_no": "wants_more", "action": "converse"})
	var out := await turn([mon("e0", "goblin", "Grok", {"friendliness": 20, "anger": 10, "fear": 5})], recruit("e0", "close"))
	var r: Dictionary = out["results"][0]
	eq([r["action"], r["spoken"], r["line"]], ["converse", true, "Join you? Hmm. What's in it for Grok?"])


func test_wary_but_accepts_the_slime_joins_and_the_log_says_its_still_unsure_and_why_it_comes():
	stub({"emotion": "intrigued", "would_join": 0.7, "join_yes": "company", "action": "converse"})
	var out := await turn([mon("e0", "slime", "Glop", {"friendliness": 45, "anger": 0, "fear": 30})], recruit("e0", "close"))
	var r: Dictionary = out["results"][0]
	eq(r["meters"]["friendliness"], 59)  # 45, +6 for a near miss, +8 intrigued: over the slime's 55, still "wary"
	eq(r["action"], "join_party")
	var log := Narrate.group_log(r, {"name": "Glop", "species": "slime"})
	eq(log.filter(func(l): return l["kind"] == "join")[0]["text"], "Even so, Glop wobbles closer and burbles that it won't be alone down here anymore.")
	var calm := r.duplicate()
	calm["emotion"] = null
	var log2 := Narrate.group_log(calm, {"name": "Glop", "species": "slime"})
	eq(log2.filter(func(l): return l["kind"] == "join")[0]["text"], "Glop still quivers a little, but burbles that it won't be alone down here anymore.")


func test_a_disastrous_pitch_to_a_friend_it_refuses_and_says_it_was_the_asking():
	stub({"emotion": "offended", "would_join": 0.9, "join_no": "not_yet", "action": "join_party"})
	var out := await turn([mon("e0", "slime", "Drip", {"friendliness": 90, "anger": 0, "fear": 10})], recruit("e0", "botch"))
	var r: Dictionary = out["results"][0]
	eq(r["action"], "converse")
	eq([r["join"]["accepted"], r["join"]["reason"]], [false, "bad_pitch"])
	var log := Narrate.group_log(r, {"name": "Drip", "species": "slime"})
	eq(log.map(func(l): return l["kind"]), ["feeling", "emotion", "join"])
	ok(RegEx.create_from_string("didn't like how you asked").search(log[-1]["text"]) != null)


func test_touched_monsters_dont_attack_in_the_same_breath():
	stub({"emotion": "touched", "kindness": 3, "action": "attack"})
	var out := await Enemy.group_turn({
		"monsters": [mon("e0", "goblin", "Grak", {"friendliness": 10, "anger": 20, "fear": 0})],
		"party": PARTY.duplicate(true), "round": 1, "playerAction": {"type": "talk", "message": "We're sorry about your brother.", "delivery": 1},
		"events": [], "conversation": [], "partyGold": 0, "vows": [],
	})
	eq(out["results"][0]["action"], "converse")


func test_a_tribute_refusal_carries_its_reason():
	stub({"action": "accept_tribute"})
	var out := await Enemy.group_turn({
		"monsters": [mon("e0", "goblin", "Grok", {"friendliness": 30, "anger": 10, "fear": 0})],
		"party": PARTY.duplicate(true), "round": 1, "playerAction": {"type": "give", "gold": 3, "targetId": "e0"},
		"events": [], "conversation": [], "partyGold": 30, "vows": [],
	})
	eq([out["results"][0]["action"], out["results"][0]["tributeRefusal"]], ["refuse_tribute", "too_little"])


# ---- the guided first fight: talk, then recruit, and it says yes


func test_resolve_join_in_the_guided_first_fight_the_invitation_is_a_sure_yes_unless_theres_no_room():
	var cold := {"invited": true, "meters": {"friendliness": 20, "anger": 40}, "threshold": 55, "willing": 0, "emotion": emotion("offended"), "noWhy": "pride"}
	eq(Enemy.resolve_join(cold)["accepted"], false)
	eq(Enemy.resolve_join(cold.merged({"sure": true, "yesWhy": "company"}, true)), {"asked": true, "accepted": true, "moved": false, "reason": "company"})
	eq(Enemy.resolve_join(cold.merged({"sure": true, "room": false}, true)), null)
	eq(Enemy.resolve_join(cold.merged({"invited": false, "sure": true}, true)), null, "only an actual invitation is sure")


func test_guided_first_fight_the_slime_joins_when_asked_even_if_jev_is_lukewarm():
	stub({"emotion": "intrigued", "would_join": 0.1, "join_no": "not_yet", "action": "converse"})
	var out := await Enemy.group_turn({
		"monsters": [mon("e0", "slime", "Glop", {"friendliness": 40, "anger": 0, "fear": 20})],
		"party": PARTY.duplicate(true), "round": 2, "playerAction": recruit("e0", "success"), "events": [], "conversation": [], "partyGold": 30, "vows": [], "guided": true,
	})
	eq(out["results"][0]["action"], "join_party")
	eq(out["results"][0]["join"]["accepted"], true)


func test_guided_first_fight_it_stays_to_hear_you_out_instead_of_fleeing_or_wandering_off():
	for action in ["flee", "leave_peacefully"]:
		stub({"emotion": "touched", "action": action})
		var out := await Enemy.group_turn({
			"monsters": [mon("e0", "slime", "Glop", {"friendliness": 60, "anger": 0, "fear": 20})],
			"party": PARTY.duplicate(true), "round": 1, "playerAction": {"type": "talk", "message": "Hello there, little one.", "delivery": 1},
			"events": [], "conversation": [], "partyGold": 30, "vows": [], "guided": true,
		})
		ne(out["results"][0]["action"], action, "%s is blocked while guided" % action)
