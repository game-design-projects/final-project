## Checks the floors the map generators make, with no window: a thousand floors per generator where every monster and the stairs
## can be walked to, the secrets are where they should be, and the same seed makes the same floor. The chunk library's rules,
## the order of the biomes, and what a big floor costs (generation, sight, mesh, triangles), which it logs. Prints one line per
## check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/map_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Automap = preload("res://src/view/automap.gd")
const Chunks = preload("res://src/rules/maps/chunks.gd")
const Content = preload("res://src/rules/content.gd")
const Decor = preload("res://src/view/decor.gd")
const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Floors = preload("res://src/rules/floors.gd")
const Materials = preload("res://src/view/materials.gd")
const Monster = preload("res://src/rules/monster.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")
const Vision = preload("res://src/rules/vision.gd")

const FLOORS_EACH := 1000
const SAME_SEED_CHECKS := 40


func _name() -> String:
	return "map_test"


func _run() -> void:
	_chunk_library()
	_biome_order()
	for biome in Content.table("biomes").biomes:
		_thousand_floors(biome)
	_generators_differ()
	_classic_is_untouched()
	_save_keeps_the_secrets()
	_sight_is_bounded()
	_map_window()
	_costs()
	_finish()


func _plan(biome: Dictionary, depth: int, boss_at_exit := true) -> Dictionary:
	var plan: Dictionary = Floors.plan(depth)
	plan.biome = Floors.sized(biome, depth)
	plan.secrets = Floors.secrets(plan.biome)
	plan.boss_at_exit = boss_at_exit
	return plan


func _chunk_library() -> void:
	var library := Chunks.library()
	var by_mask := {}
	var bad := []
	for c in library:
		by_mask[c.mask] = by_mask.get(c.mask, 0) + 1
		var problem := Chunks.problem(c)
		if problem != "":
			bad.append("%s: %s" % [c.id, problem])
	_check(bad.is_empty(), "every chunk (with its turns) is 7x7, closed but for the middle of its open sides, and all in one piece %s" % [bad.slice(0, 4)])
	var missing := []
	for mask in range(1, 16):
		if by_mask.get(mask, 0) < 2:
			missing.append(mask)
	_check(missing.is_empty(), "every shape of openings has at least two chunks to pick from (short: %s; %d chunks with turns)" % [missing, library.size()])


func _biome_order() -> void:
	var seen_ids := {}
	var repeats := 0
	for run_seed in 200:
		var last := ""
		for depth in range(1, 6):
			var b: Dictionary = Floors.biome(run_seed, depth)
			seen_ids[b.id] = true
			if b.id == last:
				repeats += 1
			last = b.id
			if Floors.biome(run_seed, depth).id != b.id:
				repeats += 1
	_check(seen_ids.size() >= 3, "there are at least three biomes (%s)" % [seen_ids.keys()])
	_check(repeats == 0, "no floor is the biome of the floor above, and a seed always gives the same order")


## The floor as the walk sees it: open floor, with the pads standing in the way (a pad takes you away). `breaking` goes through
## cracked walls too.
func _walkable(f, breaking := false) -> Dictionary:
	var pads := {}
	for t in f.teleports:
		pads[t.a] = true
		pads[t.b] = true
	var dist := {f.start: 0}
	var queue: Array = [f.start]
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for d in FloorMap.DIRS:
			var next: Vector2i = at + d
			if (f.is_open(next) or (breaking and f.is_cracked(next))) and not dist.has(next) and not pads.has(next):
				dist[next] = dist[at] + 1
				queue.append(next)
	return dist


func _thousand_floors(biome: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var problems := {}
	var cracks := 0
	var pads := 0
	var chests := 0
	var worst_us := 0
	for i in FLOORS_EACH:
		var depth := i % 5 + 1
		var one_t0 := Time.get_ticks_usec()
		var f = FloorGen.generate(Rng.new(i * 13 + 1), _plan(biome, depth))
		worst_us = maxi(worst_us, Time.get_ticks_usec() - one_t0)
		var note := func(what: String): problems[what] = problems.get(what, 0) + 1
		if f.size != int(Floors.sized(biome, depth).size):
			note.call("the wrong size")
		var dist := _walkable(f)
		var with_breaking := _walkable(f, true)
		if not dist.has(f.stairs):
			note.call("stairs out of reach")
		elif dist[f.stairs] < f.size:
			note.call("stairs close to the start")
		for m in f.monsters:
			if not dist.has(m.cell):
				note.call("a monster out of reach")
			if not f.is_open(m.cell):
				note.call("a monster in a wall")
			if f.pad_partner(m.cell) != null:
				note.call("a monster on a pad")
		if f.monsters.size() != f.monsters.filter(func(m): return f.monsters.filter(func(o): return o.cell == m.cell).size() == 1).size():
			note.call("two monsters in one cell")
		var open := 0
		var cracked := []
		for y in f.size:
			for x in f.size:
				var c := Vector2i(x, y)
				if f.is_open(c):
					open += 1
					if not dist.has(c) and f.pad_partner(c) == null and not f.treasure.any(func(t): return t.cell == c):
						note.call("open floor out of reach")
				if f.is_cracked(c):
					cracked.append(c)
				if (x == 0 or y == 0 or x == f.size - 1 or y == f.size - 1) and f.grid[y][x] != 0:
					note.call("an edge not solid")
		cracks += cracked.size()
		chests += f.treasure.size()
		pads += f.teleports.size()
		for t in f.treasure:
			if t.gold <= 0 or dist.has(t.cell):
				note.call("a chest out in the open")
			if not with_breaking.has(t.cell):
				note.call("a chest nobody can get to")
			if not cracked.any(func(c): return absi(c.x - t.cell.x) + absi(c.y - t.cell.y) == 1):
				note.call("a chest with no cracked wall to it")
		for c in cracked:
			if not with_breaking.has(c):
				note.call("a cracked wall nobody can walk up to")
		for t in f.teleports:
			for end in [t.a, t.b]:
				if not f.is_open(end) or end == f.stairs or end == f.start:
					note.call("a pad in the wrong place")
				if not FloorMap.DIRS.any(func(d): return dist.has(end + d)):
					note.call("a pad nobody can walk up to")
		if i < SAME_SEED_CHECKS:
			var again = FloorGen.generate(Rng.new(i * 13 + 1), _plan(biome, depth))
			if JSON.stringify(again.to_dict()) != JSON.stringify(f.to_dict()):
				note.call("a seed that makes two floors")
	var ms := (Time.get_ticks_usec() - t0) / 1000
	print("map_test: %s: %d floors in %d ms (worst %d ms), %d cracked walls, %d chests, %d pairs of pads" % [biome.id, FLOORS_EACH, ms, worst_us / 1000, cracks, chests, pads])
	_check(problems.is_empty(), "%s: %d floors, everything in reach and the secrets in place %s" % [biome.id, FLOORS_EACH, problems])
	_check(cracks == chests and chests >= FLOORS_EACH * 0.98, "%s: nearly every floor hides a chest behind a cracked wall (%d walls, %d chests)" % [biome.id, cracks, chests])
	_check(pads >= FLOORS_EACH * 0.9, "%s: nearly every floor has a pair of pads (%d)" % [biome.id, pads])


## How a floor reads at a glance: how much of it is open, and how much of the open floor has open floor on three sides or more
## (a room or a wide tunnel, not a corridor).
func _shape(f) -> Dictionary:
	var open := 0
	var wide := 0
	for y in f.size:
		for x in f.size:
			var c := Vector2i(x, y)
			if not f.is_open(c):
				continue
			open += 1
			if FloorMap.DIRS.filter(func(d): return f.is_open(c + d)).size() >= 3:
				wide += 1
	return {"open": float(open) / (f.size * f.size), "wide": float(wide) / open}


func _generators_differ() -> void:
	var shapes := {}
	for biome in Content.table("biomes").biomes:
		var open := 0.0
		var wide := 0.0
		for i in 40:
			var s := _shape(FloorGen.generate(Rng.new(i + 1), _plan(biome, 3)))
			open += s.open / 40.0
			wide += s.wide / 40.0
		shapes[biome.id] = {"open": snappedf(open, 0.01), "wide": snappedf(wide, 0.01)}
	print("map_test: shapes %s" % [shapes])
	var wides: Array = shapes.values().map(func(s): return s.wide)
	wides.sort()
	_check(wides[1] - wides[0] >= 0.05 and wides[2] - wides[1] >= 0.05, "the generators' floors differ: how much of the floor is wide (%s)" % [wides])


func _classic_is_untouched() -> void:
	# these seeds' floors as they were before the generators came: the grid's md5, and the monsters with the last of them the champion
	var golden := {
		3: ["313a57227267a61edf46faf015ad62cb", Vector2i(11, 11), ["DRIP(11, 1)", "MAGS(10, 5)", "VASHH(5, 11)", "GRANITE(9, 9)", "VEXALITH(6, 6)"]],
		7: ["c30723289c78247d93cad5beda245eab", Vector2i(11, 7), ["WOBBLES(5, 9)", "ROOK(8, 1)", "SSSERA(3, 11)", "BASALT(11, 2)", "VEXALITH(6, 6)"]],
		7042: ["2b3d47566598db18c610e22d0760c229", Vector2i(11, 11), ["WOBBLES(7, 1)", "ROOK(10, 1)", "SSSERA(5, 9)", "BASALT(11, 6)", "VEXALITH(6, 6)"]],
		123456: ["d58cd3ce9c112b41d60249f556861f36", Vector2i(9, 11), ["GLOP(3, 7)", "ROOK(1, 3)", "NYSS(9, 8)", "OMMON(2, 11)", "VEXALITH(6, 6)"]],
	}
	for seed_value in golden:
		var f = FloorGen.generate(Rng.new(seed_value))
		var rows := []
		for r in f.grid:
			rows.append("".join(r.map(func(v): return str(v))))
		var same: bool = "".join(rows).md5_text() == golden[seed_value][0] and f.stairs == golden[seed_value][1]
		_check(same and f.monsters.map(func(m): return "%s%s" % [m.name, m.cell]) == golden[seed_value][2], "seed %d makes the same classic floor as ever" % seed_value)
		_check(f.size == 13 and f.start == Vector2i(1, 1) and f.biome == "" and f.teleports.is_empty() and f.treasure.is_empty(), "13x13, with no biome and no secrets")


func _save_keeps_the_secrets() -> void:
	var biome: Dictionary = Content.table("biomes").biomes[0]
	var s = State.new()
	s.floor_map = FloorGen.generate(Rng.new(11), _plan(biome, 3))
	s.cell = s.floor_map.start
	s.palette_id = 1
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var back = State.from_dict(saved)
	_check(back != null, "a floor with secrets saves and loads")
	if back == null:
		return
	var f = back.floor_map
	_check(f.biome == s.floor_map.biome and f.treasure == s.floor_map.treasure and f.teleports == s.floor_map.teleports, "with its biome, chests and pads")
	var crack: Vector2i = _cracked(f)[0]
	_check(f.is_cracked(crack), "and its cracked wall")
	for bad in [
		func(d): d.floor.treasure = [{"cell": [0, 0], "gold": 5}],
		func(d): d.floor.treasure = [{"cell": [1, 1], "gold": "lots"}],
		func(d): d.floor.treasure = "chest",
		func(d): d.floor.teleports = [{"a": [0, 0], "b": [1, 1]}],
		func(d): d.floor.teleports = [{"a": [1, 1]}],
		func(d): d.floor.biome = 4,
	]:
		var wrong: Dictionary = saved.duplicate(true)
		bad.call(wrong)
		_check(State.from_dict(wrong) == null, "a save with bad secrets is refused (%s)" % State._problem(wrong))
	var old: Dictionary = saved.duplicate(true)
	old.floor.erase("treasure")
	old.floor.erase("teleports")
	old.floor.erase("biome")
	var loaded = State.from_dict(old)
	_check(loaded != null and loaded.floor_map.treasure.is_empty() and loaded.floor_map.biome == "", "a save from before the secrets still loads")


func _cracked(f) -> Array:
	var out := []
	for y in f.size:
		for x in f.size:
			if f.is_cracked(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


func _sight_is_bounded() -> void:
	var f = FloorMap.new()
	f.size = 41
	f.seed_value = 1
	for y in f.size:
		var row := []
		row.resize(f.size)
		row.fill(1)
		f.grid.append(row)
	var seen: Array = Vision.sight(f, Vector2i(20, 20), 0)
	var far := seen.filter(func(c): return absi(c.x - 20) > Vision.RANGE or absi(c.y - 20) > Vision.RANGE)
	_check(far.is_empty() and seen.size() > 50, "sight stops %d cells away (%d cells seen in an open field)" % [Vision.RANGE, seen.size()])


func _map_window() -> void:
	var biome: Dictionary = Content.table("biomes").biomes[1]
	var s = State.new()
	s.floor_map = FloorGen.generate(Rng.new(5), _plan(biome, 5))
	var f = s.floor_map
	var map = Automap.new()
	map.state = s
	_check(map.cell_px() >= 7, "a cell of the largest floor (%d) is still %d pixels on the map" % [f.size, map.cell_px()])
	var bad := 0
	for c in [Vector2i(1, 1), Vector2i(f.size - 2, f.size - 2), Vector2i(f.size / 2, f.size / 2), Vector2i(1, f.size - 2)]:
		s.cell = c
		var o: Vector2i = map.window_origin()
		var cells: int = map.window_cells()
		if c.x < o.x or c.y < o.y or c.x >= o.x + cells or c.y >= o.y + cells or cells * map.cell_px() > Automap.MAP_PX or o.x < 0 or o.y < 0 or o.x + cells > f.size or o.y + cells > f.size:
			bad += 1
	_check(bad == 0, "the map's window stays on the floor and keeps you in it")
	s.cell = Vector2i(1, 1)
	s.seen = {}
	var boss = f.monsters.back()
	boss.cell = Vector2i(f.size - 2, f.size - 2)
	s.seen[boss.cell] = true
	_check(map.monster_marks().is_empty(), "a monster outside the window is not drawn")
	s.cell = boss.cell
	_check(map.monster_marks().size() == 1, "and it is once you are near")
	map.free()


## What the biggest floors cost. Logged for the web build's sake, and held to limits that a change would have to mean.
func _costs() -> void:
	for biome in Content.table("biomes").biomes:
		var f = FloorGen.generate(Rng.new(21), _plan(biome, 5))
		var t0 := Time.get_ticks_usec()
		var mesh: ArrayMesh = DungeonMesh.build(f, Materials.wire(0, Color.WHITE, Color.WHITE), Materials.wire(1, Color.WHITE, Color.WHITE))
		var mesh_ms := (Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		var torches := []
		var decor: Node3D = Decor.build(f, Color.WHITE, Color.WHITE, torches)
		var decor_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var worst_sight := 0.0
		var total_sight := 0.0
		var cells := []
		for y in f.size:
			for x in f.size:
				if f.is_open(Vector2i(x, y)):
					cells.append(Vector2i(x, y))
		var samples := 0
		for i in range(0, cells.size(), maxi(1, cells.size() / 60)):
			t0 = Time.get_ticks_usec()
			Vision.sight(f, cells[i], i % 4)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			worst_sight = maxf(worst_sight, ms)
			total_sight += ms
			samples += 1
		var tris := 0
		for i in mesh.get_surface_count():
			tris += mesh.surface_get_array_index_len(i) / 3
		var prop_tris := 0
		for child in decor.get_children():
			if child is MeshInstance3D:
				for i in child.mesh.get_surface_count():
					prop_tris += child.mesh.surface_get_array_index_len(i) / 3
		print("map_test: cost of %s at %dx%d: mesh %.1f ms, %d tris; decor %.1f ms, %d tris in %d sections, %d torches; sight mean %.2f ms, worst %.2f ms" % [biome.id, f.size, f.size, mesh_ms, tris, decor_ms, prop_tris, decor.get_child_count(), torches.size(), total_sight / samples, worst_sight])
		_check(worst_sight < 16.0, "%s: sight takes less than a frame here (worst %.1f ms)" % [biome.id, worst_sight])
		_check(mesh_ms + decor_ms < 400.0, "%s: building the floor is quick (%.0f ms)" % [biome.id, mesh_ms + decor_ms])
		decor.free()
