## Walking the floor. Up and down step forward and back, left and right turn on the spot. Walking into a monster starts
## a fight, walking into a cracked wall breaks it, and reaching the stairs ends the floor. A chest is opened and a pad carries you
## off as soon as you step on it, and the writing on a wall is read as soon as you step up to it.
extends "res://src/game/stages/stage.gd"

const Chart = preload("res://src/rules/chart.gd")
const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Roaming = preload("res://src/rules/roaming.gd")
const Floors = preload("res://src/rules/floors.gd")
const Items = preload("res://src/rules/items.gd")
const Keepsakes = preload("res://src/rules/keepsakes.gd")
const Lore = preload("res://src/rules/lore.gd")
const State = preload("res://src/game/state.gd")
const Survival = preload("res://src/rules/survival.gd")
const TestRoom = preload("res://src/rules/test_room.gd")
const Envoys = preload("res://src/rules/envoys.gd")

const SIGHT_AHEAD := 6 # how many cells down a straight line the first-time tips look

const HINT := "UP / DOWN WALK · LEFT / RIGHT TURN · ENTER CAMP · M MAP · I INFO · ESC MENU"


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
			_instinct(flow)
			_notice(flow)
		"right":
			s.turn(1)
			_instinct(flow)
			_notice(flow)
		"confirm":
			await flow.go("camp")
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
		if not flow.repeating: # a key held against the wall lunges once, not at every repeat
			flow.event("bump")
		return
	var monster = s.floor_map.monster_at(next)
	if monster != null and s.visiting != "": # in a clan's hall nobody fights: it looks you over (rules/clan_hall.gd)
		s.say([State.sys_line(str(Envoys.table().hall.minion) % monster.name)])
		return
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
	var envoy: Dictionary = s.floor_map.envoy_at(next)
	if not envoy.is_empty(): # a clan's asker, or its lord in its hall (rules/envoys.gd)
		await flow.go("envoy", {"who": envoy})
		return
	s.cell = next
	s.visited[next] = true
	s.look()
	flow.event("step")
	var fed := Survival.heals(s)
	if not s.testing: # nobody gets hungry in the test room
		_get_hungrier(flow)
	s.steps += 1
	if fed and s.steps % flow.WALK_HEAL_STEPS == 0 and s.hp < s.max_hp:
		s.hp += 1
	var found: String = await _find_secrets(flow) # a cell with news of its own keeps the log and the picture: instinct waits for the next step or turn
	if found == "keepsake": # the Hoard's vault takes the stage; the walk goes on from it
		return
	if found == "":
		_instinct(flow)
	var company = s.floor_map.monster_at(s.cell) # a pad can set you down where something already stands (#175)
	if company != null:
		print("explore: a pad puts you down on %s at %s" % [company.name, s.cell])
		await flow.go("intro", {"foe": company})
		return
	if s.cell == s.floor_map.stairs:
		await flow.go("end")
		return
	if flow.feature("roaming") and not s.testing and s.visiting == "" and await _monsters_move(flow): # in the test room everyone keeps their place
		return
	_notice(flow)


func _get_hungrier(flow) -> void:
	var s = flow.state
	var done := Survival.walk(s)
	if done.crossed != "":
		s.say([State.sys_line(Survival.line(done.crossed))])
		flow.event("sound", {"name": "odd"})
		flow.coach.say("hungry")
		print("explore: %s after %d steps" % [done.crossed, s.steps])


## Enough of the floor is seen: the rest of its layout goes onto the map (rules/chart.gd).
func _instinct(flow) -> void:
	var s = flow.state
	if not Chart.instinct_due(s):
		return
	var seen: float = Chart.share(s)
	var cells: int = Chart.reveal(s)
	var words: Dictionary = Chart.table().instinct
	if not flow.banner_up():
		flow.announce(str(words.title), str(words.text))
	s.say([State.sys_line(str(words.line))])
	print("explore: instinct at %.0f%% seen, %d cells charted on B%dF" % [seen * 100.0, cells, s.depth])
	flow.event("charted", {"how": "instinct", "cells": cells})
	flow.event("sound", {"name": "holy"})


## Everybody's turn. True when one of them walked into you, and the fight is on.
func _monsters_move(flow) -> bool:
	var s = flow.state
	var t0 := Time.get_ticks_usec()
	var done := Roaming.turn(s, {"revenge": true, "boss_chase": true})
	s.spot()
	print_verbose("explore: the monsters' turn took %d us" % (Time.get_ticks_usec() - t0))
	if done.caught != null:
		var said: String = Roaming.table().caught % done.caught.name
		await flow.go("intro", {"foe": done.caught, "ambush": true, "before": [State.sys_line(said + " " + str(Roaming.table().first))]})
		return true
	if done.noticed.any(func(m): return s.in_sight.has(m.cell)):
		flow.event("sound", {"name": "alert"})
		flow.coach.say("hunted")
	elif done.moved.any(func(m): return s.in_sight.has(m.cell)):
		flow.event("sound", {"name": "creep"})
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


## What the cell you just stepped on was hiding, and what the log said of it: "" for nothing, "found" for something, and
## "keepsake" when the Hoard's vault took the stage, so the step stops there and the walk goes on from the choice (#161).
func _find_secrets(flow) -> String:
	var s = flow.state
	var found_any := ""
	var chest: Dictionary = s.floor_map.take_treasure(s.cell)
	if not chest.is_empty():
		if bool(chest.get("vault", false)) and flow.feature("keepsakes") and not s.testing:
			var offered: Array = Keepsakes.offer(s.run_seed, s.depth, s.keepsakes, flow.feature("nerve"), Keepsakes.VAULT_SALT)
			if not offered.is_empty():
				var words: Dictionary = Keepsakes.table().vault
				print("explore: the Hoard's vault at %s, %d keepsakes offered" % [s.cell, offered.size()])
				flow.event("found", {"what": "vault"})
				flow.event("sound", {"name": "good"})
				await flow.go("keepsake", {"offered": offered, "vault": true, "then": "walk", "lines": [State.sys_line(str(words.opened))]})
				return "keepsake"
		var gold: int = Keepsakes.gold(s, int(chest.get("gold", 0)))
		if gold > 0:
			found_any = "found"
			s.gold += gold
			s.say([State.sys_line(Floors.secret_line("chest") % gold)])
			print("explore: a chest at %s, %d gold" % [s.cell, gold])
			flow.event("found", {"what": "chest"})
			flow.event("sound", {"name": "good"})
	var found: String = s.floor_map.pickup_at(s.cell)
	if found != "":
		found_any = "found"
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
	if s.floor_map.lore_at(s.cell) and not s.floor_map.lore.read:
		found_any = "found"
		_read_the_wall(flow)
	var there = s.floor_map.pad_partner(s.cell)
	if there != null:
		found_any = "found"
		print("explore: pad from %s to %s" % [s.cell, there])
		s.cell = there
		s.visited[there] = true
		s.look()
		s.say([State.sys_line(Floors.secret_line("pad"))])
		flow.event("pad", {})
		flow.event("sound", {"name": "holy"})
	return found_any


## The writing on the wall here. Which piece it is depends on the floor and on how the halls feel about you as you read it, so another
## run, kinder or crueller, reads another one here. What has been read on any run is counted in the log.
func _read_the_wall(flow) -> void:
	var s = flow.state
	var piece := Lore.piece(s.depth, Lore.tone(s))
	s.floor_map.lore.read = true
	var again: bool = flow.lore_read.has(piece.id)
	flow.lore_read[piece.id] = true
	var read: int = flow.lore_read.size()
	flow.announce(piece.title, piece.text)
	s.say([State.sys_line(piece.text), State.sys_line(Lore.found_line(read))])
	print("explore: read the writing %s at %s%s, %d of %d over all runs" % [piece.id, s.cell, " again" if again else "", read, Lore.total()])
	flow.event("found", {"what": "lore", "id": piece.id, "read": read, "total": Lore.total()})
	flow.event("sound", {"name": "holy"})


## The first time a cracked wall is right in front of you, or something new is down the line you face, say what it is.
func _notice(flow) -> void:
	var s = flow.state
	if s.testing: # the test room says who you are looking at, or who is at your sides
		var who := TestRoom.ahead(s.floor_map, s.cell, s.facing)
		if who != "":
			s.say([State.sys_line(who)])
		return
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
		if s.floor_map.lore_at(at) and not s.floor_map.lore.read:
			flow.coach.say("lore")
			return
