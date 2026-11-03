## The rule-based mind: no network, same answer for the same monster. It works out a monster's feelings from its meters,
## its species' tastes, and its traits' motives (data/taste.json), and reads typed words with keyword cues.
## The game plays on this alone, and falls back to it whenever a mind that needs the network can't answer.
extends "res://src/mind/mind.gd"

const Content = preload("res://src/rules/content.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Odds = preload("res://src/rules/odds.gd")
const Words = preload("res://src/mind/words.gd")

const BASE_LOGIT := -1.4 # every feeling starts unlikely; what happened raises some
const MERCY_FEAR_REST := 40.0


func label() -> String:
	return "local"


func read_words(text: String) -> Dictionary:
	return Words.read(text)


func feeling_when_hit(m) -> Dictionary:
	var logits := _base_logits()
	logits.terrified += 0.6 + m.meters.fear / 30.0 + (1.6 if m.hp_fraction() < 0.4 else 0.0)
	logits.enraged += 1.2 + m.meters.anger / 35.0
	logits.sad += 0.4 + m.meters.friendliness / 60.0
	logits.offended += 0.6
	return Odds.softmax(logits)


func feeling_when_told(m, intents: Array) -> Dictionary:
	var taste := Content.table("taste")
	var logits := _base_logits()
	for it in intents:
		var intent: String = it.intent
		var weight: float = it.w
		var liking: float = m.affinity(intent)
		var pool: Array
		if liking >= 0.0:
			pool = taste.feelings_good.get(intent, [])
		elif intent == "gibberish":
			pool = taste.feelings_gibberish.get(m.species, [])
		else:
			pool = taste.feelings_bad.get(intent, [])
		# A liked thing lands harder on a calm monster, a disliked one on an angry monster.
		var anger_effect: float = -m.meters.anger / 50.0 if liking >= 0.0 else m.meters.anger / 50.0
		for feeling in pool:
			logits[feeling] += weight * (1.4 + 1.1 * absf(liking) + anger_effect)
		for t in m.traits:
			var bias: Dictionary = taste.motives.get(t, {}).get("feelings", {}).get(intent, {})
			for feeling in bias:
				logits[feeling] += weight * bias[feeling]
	logits.terrified += m.meters.fear / 60.0
	return Odds.softmax(logits)


func mercy(m) -> float:
	var low: bool = m.hp_fraction() < 0.4
	var fear_push: float = ((m.meters.fear - MERCY_FEAR_REST) / 25.0) * (1.0 if low else 0.3)
	var x: float = (m.meters.friendliness - m.threshold) / 9.0 + fear_push - m.meters.anger / 30.0
	x += m.motive_shift("mercy", m.last_intent)
	return Odds.sigmoid(x)


func join(m) -> float:
	var x: float = (m.meters.friendliness - m.threshold - 4.0) / 7.0 + m.affinity("join") * 0.4
	x += m.motive_shift("join", m.last_intent)
	return Odds.sigmoid(x)


func pressure(m) -> float:
	var raw: float = (m.meters.anger * 1.2 - m.meters.friendliness * 0.5 - m.meters.fear * 0.4 + 45.0) / 30.0
	return clampf(raw + m.motive_shift("pressure", m.last_intent), 0.0, 3.0)


func _base_logits() -> Dictionary:
	var logits := {}
	for id in Feelings.all():
		logits[id] = BASE_LOGIT
	logits.confused += 0.4 # a little muddle is always possible
	return logits
