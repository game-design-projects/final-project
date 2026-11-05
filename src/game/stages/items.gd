## ITEM: the bag, in a fight. A salve or a gift takes your turn, a whetstone doesn't, and smoke ends the fight.
extends "res://src/game/stages/list_stage.gd"

const Encounter = preload("res://src/game/encounter.gd")
const Items = preload("res://src/rules/items.gd")
const State = preload("res://src/game/state.gd")
const Survival = preload("res://src/rules/survival.gd")
const Texts = preload("res://src/game/texts.gd")


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.menu = s.items.map(func(id): return {"label": Items.label(id), "sub": str(Items.info(id).sub)})
	s.hint = "ENTER USE · ESC BACK · I INFO"


func pick(flow, index: int) -> void:
	var s = flow.state
	var m = s.foe
	var id: String = s.items[index]
	var item: Dictionary = Items.info(id)
	var what := Items.label(id)
	match str(item.kind):
		"heal":
			s.items.remove_at(index)
			var healed: int = mini(s.max_hp - s.hp, int(item.amount))
			s.hp += healed
			flow.event("sound", {"name": "good"})
			print("items: %s healed %d" % [id, healed])
			var pressure: float = await flow.mind.pressure(m)
			await flow.encounter.after_player([State.sys_line(Items.line("healed") % [what, healed])], {"pressure": pressure, "pacified": false})
		"food":
			var healed := Survival.eat(s, index)
			flow.event("sound", {"name": "good"})
			var pressure: float = await flow.mind.pressure(m)
			await flow.encounter.after_player([State.sys_line(Survival.line("ate") % [what, healed])], {"pressure": pressure, "pacified": false})
		"sharpen":
			s.items.remove_at(index)
			s.sharpened += int(item.amount)
			flow.event("sound", {"name": "good"})
			print("items: sharpened by %d" % item.amount)
			s.say([State.sys_line(Items.line("sharpened") % [what, item.amount])])
			await flow.go("menu")
		"escape":
			if m.boss:
				s.say([State.sys_line(Texts.BOSS_BLOCKS)])
				await flow.go("menu")
				return
			s.items.remove_at(index)
			await flow.encounter.slip_away(m, Items.line("escaped") % [what, m.name])
		"gift":
			s.items.remove_at(index)
			var loved := Items.give(m, id)
			var decision: Dictionary = await flow.encounter.decide(m, [{"intent": "kindness", "w": 1.0}], "YOU GAVE %s" % what)
			flow.encounter.judge("kindness")
			flow.event("sound", {"name": "good" if loved else "odd"})
			var line: String = Items.line("gift") % [what, m.name]
			if loved:
				line += " " + Items.line("loved")
			await flow.encounter.after_player([State.sys_line("%s %s" % [line, Texts.foe_feels(m, decision.feeling)])], decision)


func cancel(flow) -> void:
	await flow.go("menu")
