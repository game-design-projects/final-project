extends "res://tests/test_case.gd"

const Emotions = preload("res://src/rules/emotions.gd")


func test_every_emotion_is_complete():
	eq(Emotions.EMOTIONS.keys(), ["delighted", "amused", "touched", "flattered", "intrigued", "confused", "sad", "offended", "enraged", "terrified"])
	for id in Emotions.EMOTIONS:
		var e: Dictionary = Emotions.EMOTIONS[id]
		for k in ["label", "what", "when", "meters", "effect", "tone"]:
			ok(e.has(k), "%s has %s" % [id, k])
		ok(["good", "odd", "sad", "bad", "fear"].has(e.tone), "%s tone" % id)
		if e.has("cond"):
			ok(e.has("rounds"), "%s: a condition needs its rounds" % id)


func test_pacifying_is_a_set_of_conditions_some_emotion_grants():
	var conds := []
	for id in Emotions.EMOTIONS:
		if Emotions.EMOTIONS[id].has("cond"):
			conds.append(Emotions.EMOTIONS[id].cond)
	eq(Emotions.PACIFYING.keys(), ["charmed", "laughing", "confused"])
	for c in Emotions.PACIFYING:
		ok(conds.has(c), "%s comes from a feeling" % c)
	ok(Emotions.PACIFYING.has("charmed"))
	ok(not Emotions.PACIFYING.has("enraged"))


func test_pitch_levels():
	eq(Emotions.PITCH.keys(), ["great", "success", "close", "fail", "botch"])
	eq(Emotions.PITCH.great.reach, 10)
	eq(Emotions.PITCH.success.words, "a convincing pitch")
	ok(not Emotions.PITCH.close.has("reach"))
