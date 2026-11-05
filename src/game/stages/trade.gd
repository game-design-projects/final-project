## The trader on some floors: what it has, at its price. You walk off when you are done; nothing here takes a turn.
extends "res://src/game/stages/list_stage.gd"

const Items = preload("res://src/rules/items.gd")
const State = preload("res://src/game/state.gd")
const Survival = preload("res://src/rules/survival.gd")

var _selling: Array = [] # the item ids it would buy off you, as listed after its stock


func enter(flow, _args: Dictionary) -> void:
	flow.state.say([State.sys_line(Items.line("hello"))])
	_fill(flow)


func _fill(flow) -> void:
	var s = flow.state
	var stock: Array = s.floor_map.merchant.stock
	s.menu = stock.map(func(id): return {"label": "%s %dG" % [Items.label(id), Items.info(id).price], "sub": str(Items.info(id).sub), "gold": s.gold >= int(Items.info(id).price)})
	_selling = []
	if flow.feature("butcher"):
		for id in s.items:
			if Survival.sell_price(id) > 0 and not _selling.has(id):
				_selling.append(id)
				s.menu.append({"label": "SELL %s %dG" % [Items.label(id), Survival.sell_price(id)], "sub": "It won't ask where you got it."})
	s.menu.append({"label": "LEAVE", "sub": "Back to the walk"})
	s.selected = mini(s.selected, s.menu.size() - 1)
	s.hint = "ENTER BUY · ESC LEAVE · I INFO"


func pick(flow, index: int) -> void:
	var s = flow.state
	var stock: Array = s.floor_map.merchant.stock
	if index >= stock.size() + _selling.size():
		await cancel(flow)
		return
	if index >= stock.size():
		_sell(flow, _selling[index - stock.size()])
		return
	var id: String = stock[index]
	var price := int(Items.info(id).price)
	if s.gold < price:
		s.say([State.sys_line(Items.line("poor") % [Items.label(id), price, s.gold])])
		flow.event("sound", {"name": "bad"})
		return
	if not Items.carry(s, id):
		s.say([State.sys_line(Items.line("bag_full"))])
		flow.event("sound", {"name": "bad"})
		return
	s.gold -= price
	stock.remove_at(index)
	print("trade: bought %s for %d, %d gold left" % [id, price, s.gold])
	s.say([State.sys_line(Items.line("bought") % [Items.label(id), s.gold])])
	flow.event("sound", {"name": "good"})
	_fill(flow)


func _sell(flow, id: String) -> void:
	var s = flow.state
	var price := Survival.sell_price(id)
	s.items.remove_at(s.items.find(id))
	s.gold += price
	print("trade: sold %s for %d, %d gold now" % [id, price, s.gold])
	s.say([State.sys_line(Survival.line("sold") % [Items.label(id), price, s.gold])])
	flow.event("sound", {"name": "good"})
	_fill(flow)


func cancel(flow) -> void:
	await flow.go("explore", {"lines": [State.sys_line(Items.line("bye"))]})
