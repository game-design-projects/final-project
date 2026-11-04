## What the player has found out about one monster, little by little: CHECK reads off one thing at a time (a habit, then a
## trait), and trying something on it teaches what it thinks of that, and which trait made it care. Nothing here changes how the
## monster behaves, only what the player is told. What was found is kept on the monster (`checks`, `tried`, `known_traits`).
extends RefCounted

const Content = preload("res://src/rules/content.gd")

const LIKES := "likes"
const HATES := "hates"


## The next thing CHECK can read off `m`, and counts it as read: {clue} or {trait}, or {} when there is nothing left to read.
static func next_piece(m) -> Dictionary:
	var clues: Array = m.clues()
	if m.checks < clues.size():
		m.checks += 1
		return {"clue": clues[m.checks - 1]}
	for t in m.traits:
		if not m.known_traits.has(t):
			m.known_traits.append(t)
			return {"trait": t}
	return {}


## What trying `intent` on `m` taught, as short sentences (empty if nothing new). `tone` is how it landed.
static func learn(m, intent: String, tone: String) -> Array:
	var out := []
	if intent == "" or m.tried.has(intent):
		return out
	var view := _view_of(tone)
	m.tried[intent] = view
	var word: String = Content.table("words").intent_words.get(intent, intent)
	if view == LIKES:
		out.append("It likes %s." % word)
	elif view == HATES:
		out.append("It hates %s." % word)
	var motives: Dictionary = Content.table("taste").motives
	for t in m.traits:
		if not m.known_traits.has(t) and motives.has(t) and motives[t].get("meters", {}).has(intent):
			m.known_traits.append(t)
			out.append("It is %s." % t)
	return out


static func _view_of(tone: String) -> String:
	if tone == "good":
		return LIKES
	return HATES if tone in ["bad", "sad", "fear"] else ""


## The things found to be liked, or hated, in the words the game uses for them.
static func found(m, view: String) -> Array:
	var out := []
	for intent in m.tried:
		if m.tried[intent] == view:
			out.append(Content.table("words").intent_words.get(intent, intent))
	return out
