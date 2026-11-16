## Rockfall: stones drop, some on you, and where one lands it stays for a moment as a rock in your way. A rock never blocks
## the last of your room: at most six at once, and never so many that you are shut into a pocket of fewer than eight squares.
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const EVERY_MS := 520.0
const BIG_SHARE := 0.3 # a 2x2 stone
const AIMED_SHARE := 0.4
const WARN_MS := 800.0
const HIT_MS := 200.0
const STAY_MS := 1400.0 # how long a landed stone blocks its squares
const MAX_BLOCKED := 6
const MIN_ROOM := 8 # the soul's open region never gets smaller than this
const STEPS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func begin(run, _rng: Rng) -> void:
	run.mem = {"pending": [], "stay": {}}
	print_verbose("rockfall: stones every %d ms, they stay %d ms, at most %d blocked" % [EVERY_MS / (run.intensity * run.pace), STAY_MS, MAX_BLOCKED])


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	_expire(run, t)
	_land(run, t)
	if t < run.next_t:
		return
	run.next_t = t + EVERY_MS / (run.intensity * run.pace)
	var big := rng.chance(BIG_SHARE)
	var size := 2 if big else 1
	var cells := []
	for attempt in 6:
		var top := Vector2i.ZERO
		if rng.chance(AIMED_SHARE):
			# on top of the soul: a big stone covers it from any of its four corners
			top = run.soul - (Vector2i(rng.int_range(0, 1), rng.int_range(0, 1)) if big else Vector2i.ZERO)
		else:
			top = Vector2i(rng.int_range(0, Dodge.COLS - size), rng.int_range(0, Dodge.ROWS - size))
		top.x = clampi(top.x, 0, Dodge.COLS - size)
		top.y = clampi(top.y, 0, Dodge.ROWS - size)
		cells = []
		for dy in size:
			for dx in size:
				var k := Dodge.index(top.x + dx, top.y + dy)
				if not run.blocked.has(k):
					cells.append(k)
		if not cells.is_empty():
			break
	if cells.is_empty():
		return
	run.add_hazard(t, cells, WARN_MS, HIT_MS, "rock", {"at": cells[0], "mark": "rock"})
	run.mem.pending.append({"at": run.hazards.back().end, "cells": cells})


## A stone that has landed leaves its squares blocked, unless that would box the soul in.
static func _land(run, t: float) -> void:
	var still := []
	for p in run.mem.pending:
		if t < p.at:
			still.append(p)
			continue
		var add := []
		var here := Dodge.index(run.soul.x, run.soul.y)
		for k in p.cells:
			if k != here and not run.blocked.has(k):
				add.append(k)
		if add.is_empty() or run.blocked.size() + add.size() > MAX_BLOCKED:
			continue
		for k in add:
			run.blocked[k] = true
		if _room(run) < MIN_ROOM:
			for k in add:
				run.blocked.erase(k)
			print_verbose("rockfall: a stone left no room, not blocking")
			continue
		for k in add:
			run.mem.stay[k] = p.at + STAY_MS
		print_verbose("rockfall: %d squares blocked, %d in all" % [add.size(), run.blocked.size()])
	run.mem.pending = still


static func _expire(run, t: float) -> void:
	for k in run.mem.stay.keys():
		if t >= run.mem.stay[k]:
			run.mem.stay.erase(k)
			run.blocked.erase(k)


## How many open squares the soul can walk to, its own included.
static func _room(run) -> int:
	var seen := {Dodge.index(run.soul.x, run.soul.y): true}
	var todo: Array = [run.soul]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in STEPS:
			var n: Vector2i = c + d
			if not Dodge.in_box(n.x, n.y):
				continue
			var k := Dodge.index(n.x, n.y)
			if seen.has(k) or run.blocked.has(k):
				continue
			seen[k] = true
			todo.append(n)
	return seen.size()
