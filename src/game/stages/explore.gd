## Walking the floor. Up and down step forward and back, left and right turn on the spot. Walking into a monster starts
## a fight, walking into a cracked wall breaks it, and reaching the stairs ends the floor. A chest is opened and a pad carries you
## off as soon as you step on it.
extends "res://src/game/stages/stage.gd"

const FloorMap = preload("res://src/rules/floor_map.gd")
const Floors = preload("res://src/rules/floors.gd")
const State = preload("res://src/game/state.gd")

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
		await flow.go("intro", {"foe": monster})
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
	_notice(flow)


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
	var there = s.floor_map.pad_partner(s.cell)
	if there != null:
		print("explore: pad from %s to %s" % [s.cell, there])
		s.cell = there
		s.visited[there] = true
		s.look()
		s.say([State.sys_line(Floors.secret_line("pad"))])
		flow.event("sound", {"name": "holy"})


## The first time a cracked wall is right in front of you, say what it is.
func _notice(flow) -> void:
	var s = flow.state
	if s.floor_map.is_cracked(s.cell + FloorMap.DIRS[s.facing]):
		flow.coach.say("crack")
