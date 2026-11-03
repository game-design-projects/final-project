## FIGHT: a line sweeps along a bar and you stop it near the middle. Too early or too late is a miss; the middle is a
## perfect strike. A hit hurts the monster and sours its mood, and may end the fight.
extends "res://src/game/stages/stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.menu = []
	s.hint = "ENTER STRIKE WHEN THE LINE CROSSES THE MIDDLE"
	s.bar = {"t0": flow.clock, "dur": Combat.bar_ms(s.has_ally("rock"))}


func handle(flow, key: String) -> void:
	if key == "confirm" and flow.state.bar != null:
		await _strike(flow, flow.clock)


func tick(flow, t: float) -> void:
	var bar = flow.state.bar
	if bar != null and (t - bar.t0) / bar.dur >= 1.0:
		await _strike(flow, t) # too late: it swings wide


func _strike(flow, t: float) -> void:
	var s = flow.state
	var m = s.foe
	var x := clampf((t - s.bar.t0) / s.bar.dur, 0.0, 1.0)
	s.bar = null
	var result := Combat.strike(x, m.boss, s.has_ally("dragon"))
	if result.miss:
		flow.event("miss")
		var swung: Dictionary = await flow.encounter.decide(m, "fight", "YOU SWUNG")
		await flow.encounter.after_player([State.sys_line("%s %s is %s." % [Texts.miss(), m.name, swung.feeling.label])], swung)
		return
	m.hp = maxi(0, m.hp - result.damage)
	flow.event("strike", {"damage": result.damage, "crit": result.crit})
	Combat.apply_hit_to_mood(m)
	var begging: bool = await flow.encounter.spareable(m)
	if m.hp <= 0:
		flow.encounter.judge("slay_begging" if begging else "slay")
		await flow.encounter.defeat(m, "slain")
		return
	var decision: Dictionary = await flow.encounter.decide(m, "fight", "YOU HIT IT")
	if begging:
		flow.encounter.judge("slay_begging")
	var line := "%s %s" % [Texts.hit(result.damage, result.crit), Texts.foe_feels(m, decision.feeling)]
	await flow.encounter.after_player([State.sys_line(line)], decision)
