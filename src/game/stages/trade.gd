## The trader on some floors: what it has, at its price. You walk off when you are done; nothing here takes a turn.
extends "res://src/game/stages/list_stage.gd"

const Items = preload("res://src/rules/items.gd")
const State = preload("res://src/game/state.gd")


func enter(flow, _args: Dictionary) -> void:
	flow.state.say([State.sys_line(Items.line("hello"))])
	_fill(flow)


func _fill(flow) -> void:
	var s = flow.state
	var stock: Array = s.floor_map.merchant.stock
	s.menu = stock.map(func(id): return {"label": "%s %dG" % [Items.label(id), Items.info(id).price], "sub": str(Items.info(id).sub), "gold": s.gold >= int(Items.info(id).price)})
	s.menu.append({"label": "LEAVE", "sub": "Back to the walk"})
	s.selected = mini(s.selected, s.menu.size() - 1)
	s.hint = "ENTER BUY · ESC LEAVE · I INFO"


func pick(flow, index: int) -> void:
	var s = flow.state
	var stock: Array = s.floor_map.merchant.stock
	if index >= stock.size():
		await cancel(flow)
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


func cancel(flow) -> void:
	await flow.go("explore", {"lines": [State.sys_line(Items.line("bye"))]})
