## The fight's main menu: FIGHT, ACT, SPARE, FLEE.
extends "res://src/game/stages/list_stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const Odds = preload("res://src/rules/odds.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const FIGHT := 0
const ACT := 1
const SPARE := 2
const FLEE := 3


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	var mercy: float = await flow.mind.mercy(s.foe)
	s.menu = [
		{"label": "FIGHT", "sub": "Time the strike"},
		{"label": "ACT", "sub": "Say or do something"},
		{"label": "SPARE", "sub": "%s chance to accept. %s" % [Combat.chance_label(mercy), Texts.SPARE_TIP], "gold": mercy >= 0.5},
		{"label": "FLEE", "sub": "Champions block the way" if s.foe.boss else "Back away"},
	]
	s.hint = "UP / DOWN CHOOSE · ENTER PICK · 1-4"


func pick(flow, index: int) -> void:
	match index:
		FIGHT:
			await flow.go("fightbar")
		ACT:
			await flow.go("act")
		SPARE:
			await _spare(flow)
		FLEE:
			await _flee(flow)


func cancel(flow) -> void:
	flow.event("pause_requested")


func _spare(flow) -> void:
	var s = flow.state
	var m = s.foe
	var odds: float = await flow.mind.mercy(m)
	var accepted := Odds.succeeds(flow.rng, odds)
	s.mind_rows = [{"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "answer": odds, "picked": accepted}]
	if accepted:
		flow.encounter.judge("spare")
		await flow.encounter.defeat(m, "spared")
		return
	flow.event("mercy_refused")
	m.meters.anger = clampf(m.meters.anger + Combat.REFUSED_MERCY_ANGER, 0.0, 100.0)
	var pressure: float = await flow.mind.pressure(m)
	await flow.encounter.after_player([State.sys_line(Texts.mercy_refused(m, odds))], {"pressure": pressure, "pacified": false})


func _flee(flow) -> void:
	var s = flow.state
	var m = s.foe
	if m.boss:
		s.say([State.sys_line(Texts.BOSS_BLOCKS)])
		await flow.go("menu")
		return
	s.tally.fled += 1
	flow.event("sound", {"name": "flee"})
	flow.encounter.judge("flee")
	m.hp = m.max_hp
	var lines := [State.sys_line(Texts.flee(m))]
	for n in flow.encounter.pending_notes:
		lines.append(State.speech(n.who, n.text))
	flow.encounter.pending_notes = []
	flow.encounter.pending_rows = []
	await flow.go("explore", {"lines": lines})
