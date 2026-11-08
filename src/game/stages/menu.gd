## The fight's main menu: FIGHT, ACT, SPARE, FLEE.
extends "res://src/game/stages/list_stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const Floors = preload("res://src/rules/floors.gd")
const Odds = preload("res://src/rules/odds.gd")
const Roaming = preload("res://src/rules/roaming.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const FIGHT := 0
const ACT := 1
const SPARE := 2
const FLEE := 3
const HEAVY := "HEAVY" # the two below come and go, so they are picked by name: the four above keep their places
const ITEM := "ITEM"


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	var mercy: float = await flow.mind.mercy(s.foe)
	s.menu = [
		{"label": "FIGHT", "sub": "Time the strike"},
		{"label": "ACT", "sub": "Say or do something"},
		{"label": "SPARE", "sub": Texts.spare_tip(mercy, s.foe.boss) if flow.feature("recruit-step") else "%s chance to accept. %s" % [Combat.chance_label(mercy), Texts.SPARE_TIP], "gold": mercy >= 0.5},
		{"label": "FLEE", "sub": "Champions block the way" if s.foe.boss else ("Back away: costs gold, and it won't forget" if flow.feature("flee-cost") else "Back away")},
	]
	if flow.feature("heavy-strike"):
		var known: bool = s.heavy_known.has(s.foe.species)
		s.menu.append({"label": HEAVY, "sub": Texts.heavy_tip(s.foe, known), "gold": known and Combat.heavy_weakness(s.foe.species) > 1.0})
	if flow.feature("items") and (flow.feature("combat-grid") or not s.items.is_empty()):
		s.menu.append({"label": ITEM, "sub": "%d in your bag" % s.items.size(), "disabled": s.items.is_empty()})
	s.hint = ("ARROWS / WASD CHOOSE · ENTER PICK · 1-%d · I INFO" if flow.feature("combat-grid") else "UP / DOWN CHOOSE · ENTER PICK · 1-%d · I INFO") % s.menu.size()


func handle(flow, key: String) -> void:
	if key.length() == 1 and key >= "1" and key <= "9":
		var index := int(key) - 1
		if index < flow.state.menu.size() and flow.state.menu[index].get("disabled", false):
			return
	if not flow.feature("combat-grid") or not key in ["up", "down", "left", "right"]:
		await super.handle(flow, key)
		return
	var s = flow.state
	var n: int = s.menu.size()
	if n == 0:
		return
	var old: int = s.selected
	var col: int = old % 3
	var row: int = old / 3
	if key == "left" or key == "right":
		var row_size: int = mini(3, n - row * 3)
		var step := -1 if key == "left" else 1
		for offset in range(1, row_size + 1):
			var candidate := row * 3 + posmod(col + step * offset, row_size)
			if not s.menu[candidate].get("disabled", false):
				s.selected = candidate
				break
	else:
		var other: int = old + (3 if row == 0 else -3)
		if other < n and not s.menu[other].get("disabled", false):
			s.selected = other
	if s.selected != old:
		flow.event("menu_move")


func pick(flow, index: int) -> void:
	if flow.state.menu[index].get("disabled", false):
		return
	match index:
		FIGHT:
			await flow.go("fightbar")
		ACT:
			await flow.go("act")
		SPARE:
			await _spare(flow)
		FLEE:
			await _flee(flow)
		_:
			match str(flow.state.menu[index].label):
				HEAVY:
					await flow.go("fightbar", {"heavy": true})
				ITEM:
					await flow.go("items")


func cancel(flow) -> void:
	flow.event("pause_requested")


func _spare(flow) -> void:
	var s = flow.state
	var m = s.foe
	var odds: float = await flow.mind.mercy(m)
	var accepted := Odds.succeeds(flow.dice, odds)
	s.mind_rows = [{"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "answer": odds, "picked": accepted}]
	if accepted:
		flow.encounter.judge("spare")
		await flow.encounter.defeat(m, "spared")
		return
	flow.event("mercy_refused")
	var gentle: bool = flow.feature("recruit-step")
	if not gentle:
		m.meters.anger = clampf(m.meters.anger + Combat.REFUSED_MERCY_ANGER, 0.0, 100.0)
	var pressure: float = await flow.mind.pressure(m)
	var line: String = Texts.not_ready(m, odds) if gentle else Texts.mercy_refused(m, odds)
	await flow.encounter.after_player([State.sys_line(line)], {"pressure": pressure, "pacified": false})


func _flee(flow) -> void:
	var s = flow.state
	var m = s.foe
	if m.boss:
		s.say([State.sys_line(Texts.BOSS_BLOCKS)])
		await flow.go("menu")
		return
	s.tally.fled += 1
	flow.event("sound", {"name": "flee"})
	var costly: bool = flow.feature("flee-cost")
	var dropped := 0
	if costly:
		var cost: Dictionary = Floors.flee_cost()
		dropped = mini(s.gold, int(cost.gold))
		s.gold -= dropped
		m.meters.anger = clampf(m.meters.anger + float(cost.anger), 0.0, 100.0)
		print("menu: backing away from %s cost %d gold; anger now %.0f" % [m.name, dropped, m.meters.anger])
	flow.encounter.judge("flee") # before the slice ends, so an ally's verdict is drawn at the fixed roll too
	flow.end_slice() # a fled slice is over: no second bandit follows
	Roaming.hold(m)
	if not costly:
		m.hp = m.max_hp
	var lines := [State.sys_line(Texts.flee_cost(m, dropped) if costly else Texts.flee(m))]
	for n in flow.encounter.pending_notes:
		lines.append(State.speech(n.who, n.text))
	flow.encounter.pending_notes = []
	flow.encounter.pending_rows = []
	await flow.encounter.leave_fight(lines)
