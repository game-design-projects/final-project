## You reached the stairs. With real floors they lead on down: the log says how the floor went, and you go down or back to the
## main menu. The last floor's stairs end the run, and so do any stairs without the feature: the log sums up your route, and
## then a new run or the main menu. The very last door only opens for someone with a friend (last-door): alone you can turn back
## and look for one, or take the lonely way out, which ends the run without clearing it.
extends "res://src/game/stages/list_stage.gd"

const Floors = preload("res://src/rules/floors.gd")
const Legacy = preload("res://src/rules/legacy.gd")
const Practice = preload("res://src/rules/practice.gd")
const State = preload("res://src/game/state.gd")
const Survival = preload("res://src/rules/survival.gd")
const Texts = preload("res://src/game/texts.gd")

const TURN_BACK := 0
const LEAVE_ALONE := 1

var _at_door := false
var _at_toll := false # the gate that wants someone left at its chain: HOLD IT YOURSELF, then one line per ally, then MAIN MENU
var _ways: Array = [] # the ways down on offer (Floors.paths)


func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.foe = null
	flow.event("stairs")
	s.run_over = not s.practice and (flow.on_slice() or Floors.is_last(s.depth))
	_at_door = false
	_at_toll = false
	_ways = []
	if s.run_over and flow.feature("last-door") and s.allies.is_empty():
		s.run_over = false
		_at_door = true
		s.say([State.sys_line(Texts.DOOR_SHUT), State.sys_line(Texts.DOOR_HINT)])
		s.menu = [{"label": "TURN BACK", "sub": "Find someone who will come with you"}, {"label": "LEAVE ALONE", "sub": "Ends the run, not cleared"}, {"label": "MAIN MENU", "sub": ""}]
		print("end: the Last Door stays shut, no allies")
	elif s.run_over:
		_finish(flow, Texts.ending(s.tally, s.allies))
	elif s.practice:
		s.say([State.sys_line(Practice.line("done"))])
		s.menu = [{"label": "GO DOWN", "sub": Practice.line("down_sub")}, {"label": "MAIN MENU", "sub": ""}]
		print("end: the practice floor done")
	elif flow.feature("toll") and s.depth == int(Floors.toll().depth) and not s.allies.is_empty():
		_ask_toll(flow)
	else:
		_offer_ways(flow, [State.sys_line(Texts.floor_done(s.depth)), State.sys_line(s.summary() + ".")])
	s.hint = "ENTER PICK · ESC MAIN MENU"


func _offer_ways(flow, lines: Array) -> void:
	var s = flow.state
	s.say(lines)
	_ways = Floors.paths(s.run_seed, s.depth) if flow.feature("branching") else []
	s.menu = []
	for way in _ways:
		s.menu.append({"label": way.label, "sub": way.sub})
	if _ways.is_empty():
		s.menu.append({"label": "GO DOWN", "sub": ""})
	s.menu.append({"label": "MAIN MENU", "sub": ""})
	print("end: B%dF done" % s.depth)


func _ask_toll(flow) -> void:
	var s = flow.state
	var toll := Floors.toll()
	_at_toll = true
	s.say([State.sys_line(Texts.floor_done(s.depth)), State.sys_line(toll.ask)])
	s.menu = [{"label": toll.hold_label, "sub": toll.hold_sub % int(toll.hp)}]
	for a in s.allies:
		s.menu.append({"label": toll.leave_label % a.name, "sub": toll.leave_sub})
	s.menu.append({"label": "MAIN MENU", "sub": ""})
	print("end: the gate asks who stays, %d allies" % s.allies.size())


## 0 holds it yourself, the rest leave that ally. The health can't kill you: the choice is what you carry, not whether you live.
func _pay_toll(flow, index: int) -> void:
	var s = flow.state
	var toll := Floors.toll()
	var lines := []
	if index == 0:
		s.hp = maxi(1, s.hp - int(toll.hp))
		flow.event("sound", {"name": "hurt"})
		lines.append(State.sys_line(toll.held % int(toll.hp)))
		print("end: held the chain, HP %d" % s.hp)
	else:
		var ally = s.allies[index - 1]
		s.allies.erase(ally)
		s.left_behind.append(ally.name)
		for other in s.allies:
			other.loyalty = clampf(other.loyalty + float(toll.loyalty), 0.0, 100.0)
		flow.event("ally_left", {"species": ally.species})
		flow.event("sound", {"name": "sad"})
		lines.append(State.sys_line(toll.left % ally.name))
		if not s.allies.is_empty():
			lines.append(State.sys_line(toll.others))
		print("end: left %s at the chain, %d allies" % [ally.name, s.allies.size()])
	_at_toll = false
	s.selected = 0
	_offer_ways(flow, lines)


func _finish(flow, ending: Dictionary, how := "cleared") -> void:
	var s = flow.state
	s.run_over = true
	flow.event("run_ended", {"how": how})
	var embers: int = flow.close_run(how == "cleared")
	var tail: String = ending.tail
	if Survival.ending_note(s) != "":
		tail = Survival.ending_note(s)
	elif flow.feature("toll") and not s.left_behind.is_empty():
		tail = Floors.toll().ending % s.left_behind[-1]
	elif embers > 0:
		tail += " " + Legacy.line("carried") % embers
	s.say([State.speech(ending.route, ending.text), State.sys_line(tail)])
	s.menu = [{"label": "NEW FLOOR" if flow.on_slice() else "NEW RUN", "sub": ""}, {"label": "MAIN MENU", "sub": ""}]
	print("end: %s" % ending.route)


func pick(flow, index: int) -> void:
	if _at_door:
		match index:
			TURN_BACK:
				await flow.go("explore", {"lines": [State.sys_line(Texts.DOOR_HINT)]})
			LEAVE_ALONE:
				_at_door = false
				flow.state.selected = 0
				_finish(flow, Texts.lonely_ending(), "lonely")
			_:
				flow.event("leave", {"to": "menu"})
		return
	if index == flow.state.menu.size() - 1:
		flow.event("leave", {"to": "menu"})
	elif _at_toll:
		_pay_toll(flow, index)
	elif flow.state.run_over:
		await flow.new_run()
	elif index < _ways.size():
		print("end: taking %s" % _ways[index].label)
		await flow.next_floor(_ways[index])
	else:
		await flow.next_floor()


## Esc is the way out: the main menu, as the route screen's Esc always was.
func cancel(flow) -> void:
	flow.event("leave", {"to": "menu"})
