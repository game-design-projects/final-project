## SAY SOMETHING: type one line (once per fight). The mind reads what it meant, and the monster reacts, may answer a
## question about the floor, or, for a bandit or snake, take a paid truce if the line names money.
extends "res://src/game/stages/stage.gd"

const Content = preload("res://src/rules/content.gd")
const Hints = preload("res://src/rules/hints.gd")
const Odds = preload("res://src/rules/odds.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")
const Words = preload("res://src/mind/words.gd")

const MAX_CHARS := 140
const HEARD_ODDS := 0.12 # an intent this likely counts as part of what was said
const ASKED_ODDS := 0.25 # this likely a question means it was a question
const CASHES_IN := ["bandit", "snake"]


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.menu = []
	s.hint = "TYPE ANYTHING · ENTER SAY IT · ESC NEVER MIND · GOLD OFFERS COST 6 IF ACCEPTED"


func handle(flow, key: String) -> void:
	if key == "cancel":
		await flow.go("act")


## The line the player sent.
func submit(flow, raw: String) -> void:
	var text := raw.strip_edges().left(MAX_CHARS)
	if text == "":
		await flow.go("act")
		return
	await _say(flow, text)


func _say(flow, text: String) -> void:
	var s = flow.state
	var m = s.foe
	m.spoke = true
	var words: Dictionary = await flow.mind.read_words(text)
	var top := Odds.top(words)
	if m.species in CASHES_IN and top == "gold" and Words.mentions_money(text):
		await flow.encounter.offer_cut(m, "YOUR OFFER", words)
		return
	var heard := []
	for intent in words:
		if intent != "other" and words[intent] >= HEARD_ODDS:
			heard.append({"intent": intent, "w": words[intent]})
	if heard.is_empty():
		heard = [{"intent": "question", "w": 0.3}]
	var decision: Dictionary = await flow.encounter.decide(m, heard, "YOUR WORDS", words)
	flow.encounter.judge("" if top == "other" else top)
	var asked: bool = words.get("question", 0.0) >= ASKED_ODDS and top != "gibberish"
	var lines := []
	if asked:
		lines.append(State.sys_line("%s %s is %s." % [Texts.ASKED, m.name, decision.feeling.label]))
	else:
		lines.append(State.sys_line("%s %s" % [Texts.said(text), Texts.foe_feels(m, decision.feeling)]))
	if top == "gibberish":
		lines.append(State.sys_line(Texts.NOT_UNDERSTOOD))
	elif asked:
		if flow.succeeds(Odds.reveal_odds(m)):
			var hint := Hints.answer(s.floor_map, s.cell, m, text).trim_prefix("...")
			lines.append(State.speech(m.name, "%s: %s" % [Texts.reveal_reason(m), hint]))
		else:
			lines.append(State.sys_line(Texts.no_answer(m)))
	await flow.encounter.after_player(lines, decision, not asked)
