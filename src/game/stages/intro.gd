## A fight begins: the monster says its piece and tells you how it fights. `before` is what
## the log said as the last fight ended (the personality slice goes straight from one fight to the next); only the line that
## says how it ended is kept, because the log holds three lines and the greeting and the fight rule must both show.
## A snapshot is taken so dying can try this fight again.
extends "res://src/game/stages/stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const SocialDemo = preload("res://src/game/social_demo.gd")
const Social = preload("res://src/rules/social.gd")
const Skills = preload("res://src/rules/skills.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

var _ambush := false # it caught you, and strikes first (not on the personality slice)
var _continue_at := 0.0
var _queued := false


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	var m = args.foe
	_ambush = args.get("ambush", false)
	_queued = false
	s.foe = m
	s.skill_fight = Skills.new_fight() if flow.feature("skill-combat") else null
	m.spoke = false
	s.social_offer = {}
	s.social_typing = false
	s.social_note = ""
	if flow.feature("initiated-dialogue"):
		Social.begin(m, s, flow.dice)
		SocialDemo.tune(m)
	s.menu = []
	s.hint = ""
	s.encounter_start = {
		"recent_social": s.recent_social, "foe": m.to_dict(), "gold": s.gold, "tally": s.tally.duplicate(), "items": s.items.duplicate(), "sharpened": s.sharpened,
		"allies": s.allies.map(func(a): return a.to_dict()),
	}
	flow.event("encounter", {"boss": m.boss})
	var rule: String
	if m.boss:
		rule = Texts.BOSS_RULE
		if flow.feature("recruit-step"):
			rule += " " + Texts.BOSS_WINNABLE
	else:
		rule = Texts.fight_rule(Content.table("encounter").genres[m.genre])
	var before: Array = args.get("before", [])
	var ended: Array = before.filter(func(l): return l.kind == "sys").slice(-1) # the verdict of the fight before (the last game line, after the foe's farewell), in the personality slice
	var lines: Array = ended if not ended.is_empty() else before.slice(0, 1)
	var greeting = flow.encounter.greeting(m)
	if greeting != null:
		lines.append(greeting)
		if flow.feature("ambush-prompt"):
			s.hint = "ANY KEY CONTINUE"
	lines.append(State.sys_line(rule))
	s.say(lines)
	var mercy: float = await flow.mind.mercy(m)
	flow.encounter.known_mercy = mercy
	s.mind_rows = [{"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "answer": mercy}]
	_continue_at = flow.clock + (0.0 if flow.on_slice() else flow.DIALOGUE_BUFFER_MS)
	print("intro: %s (%s) %s" % [m.name, m.species, "BOSS" if m.boss else ""])


func tick(flow, _t: float) -> void:
	if _queued and flow.clock >= _continue_at:
		await _continue(flow)
	elif flow.state.hint != "ANY KEY CONTINUE" and flow.stage_ms() >= Combat.INTRO_MS:
		await flow.go("wait" if _ambush else "menu")


func handle(flow, _key: String) -> void:
	if flow.state.hint == "ANY KEY CONTINUE":
		if flow.clock < _continue_at:
			_queued = true
		else:
			await _continue(flow)


func queue_continue() -> void:
	_queued = true


func _continue(flow) -> void:
	_queued = false
	await flow.go("dodge" if _ambush else "menu", {"pressure": 1.0} if _ambush else {})
