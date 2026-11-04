## A fight begins: the monster says its piece and tells you how it fights, then the menu opens by itself. `before` is what
## the log said as the last fight ended (the personality slice goes straight from one fight to the next).
## A snapshot is taken so dying can try this fight again.
extends "res://src/game/stages/stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	var m = args.foe
	s.foe = m
	m.spoke = false
	s.menu = []
	s.hint = ""
	s.encounter_start = {
		"foe": m.to_dict(), "gold": s.gold, "tally": s.tally.duplicate(),
		"allies": s.allies.map(func(a): return a.to_dict()),
	}
	flow.event("encounter", {"boss": m.boss})
	var rule: String
	if m.boss:
		rule = Texts.BOSS_RULE
	else:
		rule = Texts.fight_rule(Content.table("encounter").genres[m.genre])
	var lines: Array = args.get("before", []).duplicate() # what ended the fight before, in the personality slice
	var greeting = flow.encounter.foe_line(m, "converse")
	if greeting != null:
		lines.append(greeting)
	lines.append(State.sys_line(rule))
	s.say(lines)
	var mercy: float = await flow.mind.mercy(m)
	s.mind_rows = [{"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "answer": mercy}]
	print("intro: %s (%s) %s" % [m.name, m.species, "BOSS" if m.boss else ""])


func tick(flow, _t: float) -> void:
	if flow.stage_ms() >= Combat.INTRO_MS:
		await flow.go("menu")
