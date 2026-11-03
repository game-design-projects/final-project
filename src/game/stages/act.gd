## ACT: read the monster for free, do something it reacts to (each species has three), or say one line.
extends "res://src/game/stages/list_stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const CHECK := 0
const CASHES_IN := ["bandit", "snake"] # these two can be paid off


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	var m = s.foe
	var items := [{"label": "CHECK", "sub": "Free: read it"}]
	for a in _acts(m):
		var pays: bool = m.species in CASHES_IN and a.intent == "gold"
		items.append({"label": a.label, "sub": Texts.GOLD_ACT_TIP if pays else ""})
	if m.spoke:
		items.append({"label": "SAY SOMETHING", "sub": "Already spoke this fight"})
	else:
		items.append({"label": "SAY SOMETHING", "sub": "Ask about stairs, the champion or another monster; one line per fight"})
	s.menu = items
	s.hint = "ENTER PICK · ESC BACK"


func pick(flow, index: int) -> void:
	var s = flow.state
	var m = s.foe
	var acts := _acts(m)
	if index == CHECK:
		s.say([State.sys_line(Texts.check(m, m.clues()))])
		await flow.go("menu")
	elif index <= acts.size():
		await _do_act(flow, acts[index - 1])
	elif m.spoke:
		s.say([State.sys_line(Texts.already_spoke())])
		await flow.go("menu")
	else:
		await flow.go("talk")


func cancel(flow) -> void:
	await flow.go("menu")


func _acts(m) -> Array:
	return Content.table("encounter").acts[m.species]


func _do_act(flow, act: Dictionary) -> void:
	var s = flow.state
	var m = s.foe
	if m.species in CASHES_IN and act.intent == "gold":
		await flow.encounter.offer_cut(m, act.label)
		return
	var decision: Dictionary = await flow.encounter.decide(m, [{"intent": act.intent, "w": 1.0}], act.label)
	flow.encounter.judge(act.intent)
	var tone: String = decision.feeling.get("tone", "odd")
	flow.event("sound", {"name": "good" if tone == "good" else ("bad" if tone == "bad" else "odd")})
	var line := "%s %s" % [Texts.you(act.label), Texts.foe_feels(m, decision.feeling)]
	await flow.encounter.after_player([State.sys_line(line)], decision)
