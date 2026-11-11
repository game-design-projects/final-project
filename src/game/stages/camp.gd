## Sitting down between fights: eat what is in the bag, share a roast with someone, or make a roast of someone. Nothing here takes a
## turn, and no monster moves while you sit. Butchering asks once more, with NO picked first.
extends "res://src/game/stages/list_stage.gd"

const Items = preload("res://src/rules/items.gd")
const State = preload("res://src/game/state.gd")
const Survival = preload("res://src/rules/survival.gd")

var _acts: Array = [] # what each line of the menu does: [what, on what]
var _asking = null # the ally about to be butchered, while it asks


func enter(flow, _args: Dictionary) -> void:
	_asking = null
	flow.state.say([State.sys_line(Survival.line("camp"))])
	_fill(flow)


func _fill(flow) -> void:
	var s = flow.state
	s.menu = []
	_acts = []
	if _asking != null:
		s.say([State.sys_line(Survival.line("ask") % _asking.name)])
		_add(s, "NO", "Leave it be", ["cancel", null])
		_add(s, "YES", "It won't see it coming", ["butcher", _asking])
	else:
		_add_food(flow)
		_add_party(flow)
		_add(s, "LEAVE", "Back to the walk", ["leave", null])
	s.selected = mini(s.selected, s.menu.size() - 1)
	s.hint = "ENTER PICK · ESC LEAVE · I INFO"


func _add(s, label: String, sub: String, act: Array) -> void:
	s.menu.append({"label": label, "sub": sub})
	_acts.append(act)


func _add_food(flow) -> void:
	var s = flow.state
	var offered := {}
	for i in s.items.size():
		var id: String = s.items[i]
		if str(Items.info(id).kind) == "food" and not offered.has(id):
			offered[id] = true
			_add(s, "EAT %s" % Items.label(id), str(Items.info(id).sub), ["eat", id])


func _add_party(flow) -> void:
	var s = flow.state
	if s.items.has(Survival.ROAST):
		for a in s.allies:
			_add(s, "FEED %s" % a.name, "It would like that. It won't ask what it is.", ["feed", a])
	for a in s.allies:
		_add(s, "BUTCHER %s" % a.name, "Food for days. The others may notice.", ["ask", a])


func pick(flow, index: int) -> void:
	var s = flow.state
	var act: Array = _acts[index]
	match act[0]:
		"eat":
			var healed := Survival.eat(s, s.items.find(act[1]))
			s.say([State.sys_line(Survival.line("ate") % [Items.label(act[1]), healed])])
			flow.event("sound", {"name": "good"})
		"feed":
			_feed(flow, act[1])
		"ask":
			_asking = act[1]
			s.selected = 0
		"butcher":
			_butcher(flow, act[1])
			_asking = null
			s.selected = 0
		"cancel":
			_asking = null
			s.selected = 0
			s.say([State.sys_line(Survival.line("camp"))])
		"leave":
			await cancel(flow)
			return
	_fill(flow)


func _feed(flow, ally) -> void:
	var s = flow.state
	var done := Survival.feed(s, ally, flow.dice)
	var lines := [State.sys_line(Survival.line("fed") % ally.name)]
	flow.event("sound", {"name": "good"})
	if done.found_out:
		lines = [State.sys_line(Survival.line("found_out") % ally.name)]
		_left(flow, ally)
		lines.append_array(_told(done.told))
	s.say(lines)


func _butcher(flow, ally) -> void:
	var s = flow.state
	var done := Survival.butcher(s, ally, flow.dice)
	flow.event("sound", {"name": "slash"})
	flow.event("butchered", {"species": ally.species})
	flow.event("ally_left", {"species": ally.species})
	var made: int = done.made
	var lines := [State.sys_line(Survival.line("butchered") % [ally.name, made, "roast" if made == 1 else "roasts"]) if made > 0 else State.sys_line(Survival.line("no_room"))]
	for w in done.witnesses:
		lines.append(State.sys_line(Survival.line("witness") % w.name))
		_left(flow, w)
	lines.append_array(_told(done.told))
	s.say(lines.slice(0, 2)) # the log has room for two


func _left(flow, ally) -> void:
	flow.event("ally_left", {"species": ally.species})
	flow.event("found_out", {"species": ally.species})


func _told(told: Array) -> Array:
	return [State.sys_line(Survival.line("told") % told[0].name)] if not told.is_empty() else []


## Esc gets you up, or out of the question.
func cancel(flow) -> void:
	if _asking != null:
		_asking = null
		flow.state.selected = 0
		_fill(flow)
		return
	await flow.go("explore", {"lines": [State.sys_line(Survival.line("leave"))]})
