## What a monster's face shows. A mood is read off its meters, so it changes as they do; the view has a drawing for each. As the halls
## go cold (rules/warmth.gd) faces go blank, one monster at a time, and the champions last.
extends RefCounted

const Content = preload("res://src/rules/content.gd")

const STRONG := 60.0 # a meter this high shows on the face
const HOLLOW_FROM := 0.1 # at or below this warmth every face but a champion's is blank
const HOLLOW_TO := 0.36 # above this warmth no face is
const BOSS_HOLLOW := 0.04


## "angry", "scared", "happy" or "calm".
static func of(m) -> String:
	if m.hunting or m.meters.anger >= STRONG:
		return "angry"
	if m.meters.fear >= STRONG:
		return "scared"
	if m.meters.friendliness >= m.threshold:
		return "happy"
	return "calm"


## Whether this monster's face has gone blank at this warmth. Each one goes at its own point, the same one every time.
static func hollow(m, warmth: float) -> bool:
	if m.boss:
		return warmth <= BOSS_HOLLOW
	var own := float(absi(str(m.name).hash()) % 1000) / 1000.0
	return warmth <= lerpf(HOLLOW_FROM, HOLLOW_TO, own)


## Temporary intentions advance once at action resolution using the game dice.
static func advance(m, dice) -> String:
	var age := int(m.mood.get("age", 0)) + 1
	var due := int(m.mood.get("due", 0))
	if due == 0:
		due = dice.int_between(2, 4)
	m.mood["age"] = age
	m.mood["due"] = due
	var urgent: bool = m.last_intent in ["fight", "threat", "insult", "kindness", "peace", "gold"]
	if age < due and not (urgent and age >= 2):
		return ""
	var next: String = m.species
	if m.hp_fraction() < 0.35 or m.meters.fear >= 55:
		next = "watchful"
	elif m.last_intent in ["fight", "threat", "insult"] or m.meters.anger >= 60:
		next = "watchful" if m.has_trait("jumpy") else "confident"
	elif m.last_intent in ["kindness", "peace"]:
		next = "calm"
	elif m.has_trait("jumpy") or m.has_trait("secretive"):
		next = "watchful" if dice.real() < 0.75 else m.species
	elif m.has_trait("proud"):
		next = "confident" if dice.real() < 0.75 else m.species
	elif m.mood.get("id", "") == m.species:
		next = "calm"
	m.mood.age = 0
	m.mood.due = dice.int_between(2, 4)
	if next == m.mood.get("id", ""):
		return ""
	var entry: Dictionary = Content.table("moods").get(next, {})
	if entry.is_empty():
		return ""
	m.mood["id"] = next
	m.mood["goal"] = entry.goal
	return "%s %s" % [m.name, entry.cue]

static func shift(m, field: String) -> float:
	return float(Content.table("moods").get(m.mood.get("id", ""), {}).get(field, 0.0))
