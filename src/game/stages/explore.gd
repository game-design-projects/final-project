## Walking the floor. Up and down step forward and back, left and right turn on the spot. Walking into a monster starts
## a fight, walking into a cracked wall breaks it, and reaching the stairs ends the floor. A chest is opened and a pad carries you
## off as soon as you step on it.
extends "res://src/game/stages/stage.gd"

const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Roaming = preload("res://src/rules/roaming.gd")
const Floors = preload("res://src/rules/floors.gd")
const Items = preload("res://src/rules/items.gd")
const State = preload("res://src/game/state.gd")

const SIGHT_AHEAD := 6 # how many cells down a straight line the first-time tips look

const HINT := "UP / DOWN WALK · LEFT / RIGHT TURN · I INFO · ESC MENU"


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	s.foe = null
	s.menu = []
	s.hint = HINT
	if args.has("lines"):
		s.say(args.lines)


func handle(flow, key: String) -> void:
	var s = flow.state
	match key:
		"up":
			await _step(flow, false)
		"down":
			await _step(flow, true)
		"left":
			s.turn(-1)
			_notice(flow)
		"right":
			s.turn(1)
			_notice(flow)
		"cancel":
			flow.event("pause_requested")


func _step(flow, backwards: bool) -> void:
	var s = flow.state
	var heading: int = (s.facing + 2) % 4 if backwards else s.facing
	var next: Vector2i = s.cell + FloorMap.DIRS[heading]
	if s.floor_map.is_cracked(next):
		_break_wall(flow, next)
		return
	if not s.floor_map.is_open(next):
		flow.event("bump")
		return
	var monster = s.floor_map.monster_at(next)
	if monster != null:
		if monster.lurking:
			_stirred(flow, monster)
		await flow.go("intro", {"foe": monster})
		return
	if s.floor_map.merchant_at(next):
		await flow.go("trade")
		return
	if s.floor_map.quester_at(next):
		await flow.go("request")
		return
	s.cell = next
	s.visited[next] = true
	s.look()
	flow.event("step")
	if flow.feature("walk-heal"):
		s.steps += 1
		if s.steps % flow.WALK_HEAL_STEPS == 0 and s.hp < s.max_hp:
			s.hp += 1
	_find_secrets(flow)
	if s.cell == s.floor_map.stairs:
		await flow.go("end")
		return
	if flow.feature("roaming") and await _monsters_move(flow):
		return
	_notice(flow)


## Everybody's turn. True when one of them walked into you, and the fight is on.
func _monsters_move(flow) -> bool:
	var s = flow.state
	var t0 := Time.get_ticks_usec()
	var done := Roaming.turn(s, {"revenge": flow.feature("clans"), "boss_chase": flow.feature("boss-chase")})
	s.spot()
	print_verbose("explore: the monsters' turn took %d us" % (Time.get_ticks_usec() - t0))
	if done.caught != null:
		await flow.go("intro", {"foe": done.caught, "before": [State.sys_line(Roaming.table().caught % done.caught.name)]})
		return true
	if done.noticed.any(func(m): return s.in_sight.has(m.cell)):
		flow.event("sound", {"name": "odd"})
		flow.coach.say("hunted")
	elif done.moved.any(func(m): return s.in_sight.has(m.cell)):
		flow.coach.say("roaming")
	return false


## You walked into what was stirring: now you see what it is.
func _stirred(flow, m) -> void:
	m.lurking = false
	var numbers: Dictionary = Content.table("npcs").lurkers
	flow.announce(m.name, numbers.stirred % ("a " + str(Content.species(m.species).label).to_lower()))
	print("explore: %s was stirring at %s, purse %d" % [m.name, m.cell, m.purse])


func _break_wall(flow, wall: Vector2i) -> void:
	var s = flow.state
	s.floor_map.break_wall(wall)
	s.look()
	s.say([State.sys_line(Floors.secret_line("wall"))])
	print("explore: broke the wall at %s" % wall)
	flow.event("sound", {"name": "hit"})


## What the cell you just stepped on was hiding.
func _find_secrets(flow) -> void:
	var s = flow.state
	var gold: int = s.floor_map.take_treasure(s.cell)
	if gold > 0:
		s.gold += gold
		s.say([State.sys_line(Floors.secret_line("chest") % gold)])
		print("explore: a chest at %s, %d gold" % [s.cell, gold])
		flow.event("sound", {"name": "good"})
	var found: String = s.floor_map.pickup_at(s.cell)
	if found != "":
		var name := Items.label(found)
		if Items.carry(s, found):
			s.floor_map.remove_pickup(s.cell)
			s.say([State.sys_line(Items.line("found") % name)])
			if not flow.coach.say("item"):
				flow.announce(name, str(Items.info(found).sub))
			print("explore: found %s at %s" % [found, s.cell])
			flow.event("sound", {"name": "good"})
		else:
			s.say([State.sys_line(Items.line("full") % name)])
	var there = s.floor_map.pad_partner(s.cell)
	if there != null:
		print("explore: pad from %s to %s" % [s.cell, there])
		s.cell = there
		s.visited[there] = true
		s.look()
		s.say([State.sys_line(Floors.secret_line("pad"))])
		flow.event("sound", {"name": "holy"})


## The first time a cracked wall is right in front of you, or something new is down the line you face, say what it is.
func _notice(flow) -> void:
	var s = flow.state
	if s.floor_map.is_cracked(s.cell + FloorMap.DIRS[s.facing]):
		flow.coach.say("crack")
	var at: Vector2i = s.cell
	for _i in SIGHT_AHEAD:
		at += FloorMap.DIRS[s.facing]
		if not s.floor_map.is_open(at):
			return
		var m = s.floor_map.monster_at(at)
		if m != null and m.lurking:
			flow.coach.say("lurker")
			return
		if s.floor_map.quester_at(at):
			flow.coach.say("request")
			return
