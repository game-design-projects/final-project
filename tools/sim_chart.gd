## How much of a floor is seen by the time the stairs are, and what charting the rest saves (rules/chart.gd), for tuning
## data/floors.json's `chart`. An explorer with no knowledge of the floor walks to the nearest floor it has not seen, looking the way
## it walks, until it stands on the stairs. Per biome and depth, over `seeds=N` floors (8 without it): the share seen when the stairs
## first show, how often instinct charts the floor before that, and the steps to the stairs with and without instinct.
## `at=0.65` tries another share for instinct than the data's.
##   godot --headless --path . -s res://tools/sim_chart.gd -- nosave nosound
extends SceneTree

const Chart = preload("res://src/rules/chart.gd")
const Content = preload("res://src/rules/content.gd")
const Flags = preload("res://src/utils/flags.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Floors = preload("res://src/rules/floors.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")

const MAX_STEPS := 20000


func _init() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray)
	var seeds := maxi(1, int(Flags.value("seeds", "8")))
	var at := float(Flags.value("at", str(Chart.table().instinct_at)))
	print("sim_chart: instinct at %.0f%%, %d floors each" % [at * 100.0, seeds])
	print("biome | depth | size | cells | seen when the stairs show (p25 / median / p75) | instinct first | steps to the stairs: none / with instinct | saved")
	for biome in Content.table("biomes").biomes:
		for depth in range(1, int(Content.table("floors").run_floors) + 1):
			var shares := []
			var plain := []
			var helped := []
			var first := 0
			var cells := 0
			var size := 0
			for i in seeds:
				var blind := _walk(biome, depth, 100 + i, 2.0)
				var guided := _walk(biome, depth, 100 + i, at)
				shares.append(blind.share_at_stairs)
				plain.append(blind.steps)
				helped.append(guided.steps)
				first += int(guided.charted_before_stairs)
				cells = blind.cells
				size = blind.size
			shares.sort()
			var none := _mean(plain)
			var with := _mean(helped)
			print("%s | %d | %d | %d | %.0f%% / %.0f%% / %.0f%% | %d of %d | %.0f / %.0f | %.0f%%" % [biome.id, depth, size, cells, _at(shares, 0.25) * 100.0, _at(shares, 0.5) * 100.0, _at(shares, 0.75) * 100.0, first, seeds, none, with, (1.0 - with / none) * 100.0 if none > 0.0 else 0.0])
	quit(0)


## One floor walked to its stairs. With `instinct_at` above 1 nothing is ever charted. {steps, share_at_stairs, charted_before_stairs, cells, size}
func _walk(biome: Dictionary, depth: int, seed_value: int, instinct_at: float) -> Dictionary:
	var plan: Dictionary = Floors.plan(depth)
	plan.biome = Floors.sized(biome, depth)
	plan.secrets = Floors.secrets(plan.biome)
	plan.boss_at_exit = true
	var s = State.new()
	s.depth = depth
	s.floor_map = FloorGen.generate(Rng.new(seed_value), plan)
	var f = s.floor_map
	s.cell = f.start
	s.facing = f.start_facing()
	s.visited[s.cell] = true
	s.look()
	var out := {"steps": 0, "share_at_stairs": -1.0, "charted_before_stairs": false, "cells": s.reach().size(), "size": f.size}
	var path: Array = []
	while s.cell != f.stairs and out.steps < MAX_STEPS:
		if out.share_at_stairs < 0.0 and s.seen.has(f.stairs):
			out.share_at_stairs = Chart.share(s)
		if s.charted.is_empty() and Chart.share(s) >= instinct_at and Chart.share(s) < 1.0:
			Chart.reveal(s)
			out.charted_before_stairs = out.share_at_stairs < 0.0
			path = []
		var knows: bool = Chart.known(s, f.stairs)
		if path.is_empty() or (knows and path.back() != f.stairs) or (not knows and s.seen.has(path.back())):
			path = _path(s, knows)
		if path.is_empty():
			break
		var next: Vector2i = path.pop_front()
		s.facing = FloorMap.DIRS.find(next - s.cell)
		s.cell = next
		s.visited[next] = true
		s.look()
		out.steps += 1
	if out.share_at_stairs < 0.0:
		out.share_at_stairs = Chart.share(s)
	return out


## The cells to step through to the stairs (when known), or to the nearest floor not seen yet: breadth first over the floor.
func _path(s, to_stairs: bool) -> Array:
	var f = s.floor_map
	var from := {s.cell: s.cell}
	var queue: Array = [s.cell]
	var at := 0
	var goal = null
	while at < queue.size():
		var c: Vector2i = queue[at]
		at += 1
		if (c == f.stairs) if to_stairs else (not s.seen.has(c)):
			goal = c
			break
		for d in FloorMap.DIRS:
			var n: Vector2i = c + d
			if f.is_open(n) and not from.has(n):
				from[n] = c
				queue.append(n)
	if goal == null:
		return []
	var out := []
	var c: Vector2i = goal
	while c != s.cell:
		out.push_front(c)
		c = from[c]
	return out


func _mean(values: Array) -> float:
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / maxi(1, values.size())


func _at(sorted: Array, share: float) -> float:
	return float(sorted[clampi(roundi((sorted.size() - 1) * share), 0, sorted.size() - 1)])
