## FIGHT: a line sweeps along a bar and you stop it near the middle. Too early or too late is a miss; the middle is a
## perfect strike. A hit hurts the monster and sours its mood, and may end the fight.
extends "res://src/game/stages/stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	var heavy: bool = args.get("heavy", false)
	s.menu = []
	s.hint = "ENTER STRIKE INSIDE THE RED MARK" if heavy else "ENTER STRIKE WHEN THE LINE CROSSES THE MIDDLE"
	if flow.feature("party-aid") and not s.allies.is_empty():
		s.hint += " · PARTY +%d" % Combat.party_aid(s.allies.size())
	if s.sharpened > 0:
		s.hint += " · WHETTED +%d" % s.sharpened
	s.bar = {"t0": flow.clock, "dur": Combat.bar_ms(s.has_ally("rock")) * (Combat.HEAVY_BAR_SCALE if heavy else 1.0), "heavy": heavy}


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
	var heavy: bool = s.bar.heavy
	s.bar = null
	var aid: int = Combat.party_aid(s.allies.size()) if flow.feature("party-aid") else 0
	var result: Dictionary
	if heavy:
		result = Combat.heavy_strike(x, m.boss, m.species, s.has_ally("dragon"), aid + s.sharpened)
		print("fightbar: heavy strike on %s at %.2f: %s" % [m.species, x, result])
	else:
		result = Combat.strike(x, m.boss, s.has_ally("dragon"), aid + s.sharpened)
	if not result.miss:
		s.sharpened = 0
	if result.miss:
		flow.event("miss")
		var swung: Dictionary = await flow.encounter.decide(m, "fight", "YOU SWUNG")
		if heavy:
			swung.pressure += Combat.HEAVY_MISS_PRESSURE
		await flow.encounter.after_player([State.sys_line("%s %s is %s." % [Texts.HEAVY_MISS if heavy else Texts.miss(), m.name, swung.feeling.label])], swung)
		return
	m.hp = maxi(0, m.hp - result.damage)
	flow.event("strike", {"damage": result.damage, "crit": result.crit or heavy}) # a heavy hit sounds and flashes like a big one
	var found: String = _learn_how_it_takes_it(flow, m) if heavy else ""
	Combat.apply_hit_to_mood(m)
	var begging: bool = await flow.encounter.spareable(m)
	if m.hp <= 0:
		flow.encounter.judge("slay_begging" if begging else "slay")
		await flow.encounter.defeat(m, "slain")
		return
	var decision: Dictionary = await flow.encounter.decide(m, "fight", "YOU HIT IT")
	if begging:
		flow.encounter.judge("slay_begging")
	var line := "%s %s%s" % [Texts.hit(result.damage, result.crit), found, Texts.foe_feels(m, decision.feeling)]
	await flow.encounter.after_player([State.sys_line(line)], decision)


## The first heavy blow to land on a kind of monster shows how it takes them, and the menu says so from then on. The words for
## the log, which reach you if a tip holds the banner ("" when there is nothing to tell).
func _learn_how_it_takes_it(flow, m) -> String:
	var s = flow.state
	if s.heavy_known.has(m.species):
		return ""
	s.heavy_known[m.species] = true
	var weak := Combat.heavy_weakness(m.species)
	print("fightbar: found out how a %s takes a heavy blow (%.2f)" % [m.species, weak])
	if weak == 1.0:
		return ""
	var found := Texts.heavy_found(m, weak)
	if not flow.banner_up():
		flow.announce("YOU FOUND OUT", found)
	return found + " "
