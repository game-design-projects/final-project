## SKILLS, with the feature skill-combat: the skills you hold, and END TURN. Each costs energy and some cool down (rules/skills.gd);
## none asks for timing, so what you pick is the whole skill. You may use several in a turn while the energy lasts. The turn ends
## when you say so or nothing is left to use, and then the monster answers it once, for all of it, and attacks.
extends "res://src/game/stages/list_stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const Skills = preload("res://src/rules/skills.gd")
const Social = preload("res://src/rules/social.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")


func enter(flow, _args: Dictionary) -> void:
	_fill(flow)


## The list as it stands: every skill held, greyed out when it can't be used now, and END TURN last.
func _fill(flow) -> void:
	var s = flow.state
	var f: Dictionary = s.skill_fight
	s.menu = s.skills.map(func(id): return {"label": Skills.label(id), "sub": Skills.sub(f, id), "disabled": not Skills.usable(f, id)})
	var end: Dictionary = Skills.table().end_turn
	s.menu.append({"label": str(end.label), "sub": str(end.text)})
	if s.menu[clampi(s.selected, 0, s.menu.size() - 1)].get("disabled", false):
		s.selected = s.menu.find(s.menu.filter(func(c): return not c.get("disabled", false))[0])
	var status := "ENERGY %d/%d" % [f.energy, Skills.energy_per_turn()]
	if int(f.block) > 0:
		status += " · BLOCK %d" % f.block
	if int(f.bruised) > 0:
		status += " · BRUISED %d" % f.bruised
	s.hint = "%s · ENTER USE%s · I INFO" % [status, " · ESC BACK" if int(f.used) == 0 else ""]


func pick(flow, index: int) -> void:
	var s = flow.state
	if index == s.menu.size() - 1:
		await _end_turn(flow)
		return
	if s.menu[index].get("disabled", false):
		return
	var m = s.foe
	var f: Dictionary = s.skill_fight
	var id: String = s.skills[index]
	var attacks: bool = Skills.damage(f, id, m.boss) > 0
	var bonus := 0
	if attacks:
		bonus = Social.strike_bonus(m) + Combat.party_aid(s.party_size()) + s.sharpened + (Combat.HOARD_FIRE_BONUS if s.has_ally("dragon") else 0)
	var did: Dictionary = Skills.use(f, id, m.boss, bonus)
	print("skills: %s on %s: %s, %d energy left" % [id, m.name, did, f.energy])
	var words := []
	if did.damage > 0:
		s.sharpened = 0
		var betrayal := Social.hit(m)
		if betrayal != "":
			words.append(betrayal)
		m.hp = maxi(0, m.hp - did.damage)
		flow.event("strike", {"damage": did.damage, "crit": false})
		Combat.apply_hit_to_mood(m)
		words.append(Skills.line("hit") % [Skills.label(id), did.damage])
		if m.hp <= 0:
			var begging: bool = await flow.encounter.spareable(m)
			flow.encounter.judge("slay_begging" if begging else "slay")
			await flow.encounter.defeat(m, "slain")
			return
	if did.block > 0:
		flow.event("sound", {"name": "buff"}) # "shield" is for a hit soaked in the dodge, which says BLOCKED
		words.append(Skills.line("block") % [Skills.label(id), f.block])
	if did.bruise > 0:
		words.append(Skills.line("bruised") % [m.name, f.bruised])
	s.say([State.sys_line(" ".join(words))])
	if not Skills.any_usable(f, s.skills):
		await _end_turn(flow)
		return
	_fill(flow)


## The turn is over: the monster takes in all of it at once (a hit, if anything hit it) and winds up.
func _end_turn(flow) -> void:
	var s = flow.state
	var m = s.foe
	var f: Dictionary = s.skill_fight
	if int(f.hits) == 0:
		var pressure: float = await flow.mind.pressure(m)
		var said: Array = s.lines.slice(-1) if int(f.used) > 0 else []
		await flow.encounter.after_player(said + [State.sys_line(Skills.line("guarded"))], {"pressure": pressure, "pacified": false})
		return
	var begging: bool = await flow.encounter.spareable(m)
	var decision: Dictionary = await flow.encounter.decide(m, "fight", "YOU HIT IT")
	if m.social.get("betrayed", false):
		decision.pacified = false
	if begging:
		flow.encounter.judge("slay_begging")
	var line := "%s %s" % [Skills.line("turn") % f.dealt, Texts.foe_feels(m, decision.feeling)]
	await flow.encounter.after_player([State.sys_line(line)], decision)


func cancel(flow) -> void:
	if int(flow.state.skill_fight.used) == 0:
		await flow.go("menu")
