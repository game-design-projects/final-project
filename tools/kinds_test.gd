## The kinds of monster (data/kinds.json, rules/kinds.gd) and their attacks (rules/minigames/): five kinds to a floor with no kind
## on two floors and every clan on every floor, each kind with its own attack; a generated floor holds one of each of its kinds and
## a champion that fights in all their attacks; a warren keeps to one clan; an old save's monster is its species' own kind; and
## every attack makes hazards, warns the square you stand on in time, never lights the whole box and never walls you in, and is
## the same attack twice on one seed.
##   godot --headless --path . -s res://tools/kinds_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Content = preload("res://src/rules/content.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const DodgeRun = preload("res://src/rules/dodge_run.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const Floors = preload("res://src/rules/floors.gd")
const Kinds = preload("res://src/rules/kinds.gd")
const Monster = preload("res://src/rules/monster.gd")
const Rng = preload("res://src/utils/rng.gd")

const PER_FLOOR := 5
const CLANS := ["slime", "bandit", "snake", "rock"]
const REACT_MS := 300.0 # the least warning the square you stand on gets
const STEP_MS := 200.0 # how fast a person taps an arrow: five steps a second
const TICK_MS := 16.0
const SAME_SEED := 4242 # the seed an attack is played twice on, to see it come out the same
const ROAMS := ["drift", "patrol", "stalk", "still"]


func _name() -> String:
	return "kinds_test"


func _run() -> void:
	_the_table()
	_floors_hold_their_kinds()
	_saves()
	_champion_cycle()
	_every_attack()
	_finish()


# ---------------------------------------------------------------- the table

func _the_table() -> void:
	var genres: Dictionary = Content.table("encounter").genres
	var used_genres := {}
	var floors := Floors.run_floors()
	_check(Kinds.deepest() == floors, "kinds reach down to the last floor (B%dF)" % floors)
	for depth in range(1, floors + 1):
		var here: Array = Kinds.at_depth(depth)
		_check(here.size() == PER_FLOOR, "B%dF has %d kinds (%d)" % [depth, PER_FLOOR, here.size()])
		var clans := {}
		for e in here:
			clans[e.species] = true
		_check(CLANS.all(func(c): return clans.has(c)), "every clan has a kind on B%dF (%s)" % [depth, ", ".join(clans.keys())])
	for id in Kinds.all():
		var k: Dictionary = Kinds.info(id)
		var ok: bool = Content.is_monster(str(k.species)) and genres.has(str(k.genre)) and DodgeRun.MINI_GAMES.has(str(k.genre))
		ok = ok and int(k.hp) > 0 and str(k.title) != "" and Color.html_is_valid(str(k.color)) and int(k.depth) >= 1 and int(k.depth) <= floors
		var roam: Dictionary = k.get("roam", {})
		if not roam.is_empty():
			ok = ok and ROAMS.has(str(roam.kind)) and (roam.kind != "drift" or int(roam.get("every", 0)) > 0) and (roam.kind != "stalk" or (roam.has("sense") and roam.has("keeps_on")))
		_check(ok, "%s: a %s on B%dF fighting in %s, %d HP, colour %s" % [id, k.species, int(k.depth), k.genre, int(k.hp), k.color])
		_check(not used_genres.has(k.genre), "%s has an attack of its own (%s)" % [id, k.genre])
		used_genres[k.genre] = true
	_check(Kinds.base_of("slime") == "slime" and Kinds.base_of("dragon") == "", "a species is its own kind; the Hoard's dragon has none")
	var colours := {}
	for id in Kinds.all():
		colours[str(Kinds.info(id).color).to_lower()] = true
	_check(colours.size() == Kinds.all().size(), "no two kinds share a colour")


# ---------------------------------------------------------------- the floors

func _plan(depth: int, run_seed: int, way := {}) -> Dictionary:
	var plan: Dictionary = Floors.plan(depth, way)
	plan.boss_at_exit = true
	plan.biome = Floors.biome(run_seed, depth)
	plan.secrets = Floors.secrets(plan.biome)
	plan.lurkers = true
	return plan


func _floors_hold_their_kinds() -> void:
	for depth in range(1, Floors.run_floors() + 1):
		var want := {}
		for e in Kinds.at_depth(depth):
			want[e.kind] = true
		for run_seed in [3, 41, 977]:
			var f = FloorGen.generate(Rng.new(Floors.floor_seed(run_seed, depth)), _plan(depth, run_seed))
			var got := {}
			for m in f.monsters:
				if not m.boss:
					got[m.kind] = true
			var champion = f.monsters[-1]
			_check(got.keys().all(func(k): return want.has(k)) and want.keys().all(func(k): return got.has(k)), "B%dF (seed %d) holds its five kinds and no others (%s)" % [depth, run_seed, ", ".join(got.keys())])
			_check(champion.boss and champion.kind == "" and champion.genres == Kinds.genres_at(depth), "B%dF's champion fights in its floor's five attacks (%s)" % [depth, ", ".join(champion.genres)])
			_check(f.monsters.filter(func(m): return not m.boss and m.genre != Kinds.info(m.kind).genre).is_empty(), "every monster on B%dF fights in its kind's attack" % depth)
	var warren_depth := 3
	for species in CLANS:
		var f = FloorGen.generate(Rng.new(5), _plan(warren_depth, 5, {"only_species": species}))
		var others: Array = f.monsters.filter(func(m): return not m.boss)
		var own: Array = Kinds.of_species(species, warren_depth)
		_check(not others.is_empty() and others.all(func(m): return m.species == species), "a %s warren on B%dF is all %ss (%d)" % [species, warren_depth, species, others.size()])
		_check(others.any(func(m): return int(Kinds.info(m.kind).depth) == warren_depth) and own.size() >= 2, "and meets the floor's own kind of it, among %d kinds met so far" % own.size())
	var full = FloorGen.generate(Rng.new(5), _plan(warren_depth, 5))
	var warren = FloorGen.generate(Rng.new(5), _plan(warren_depth, 5, {"only_species": "rock"}))
	_check(warren.monsters.size() == full.monsters.size(), "a warren has as many monsters as the floor would (%d, %d)" % [warren.monsters.size(), full.monsters.size()])


# ---------------------------------------------------------------- saves

func _saves() -> void:
	var m = Monster.make(Rng.new(9), Kinds.line("golem"), Vector2i(2, 3))
	var back = Monster.from_dict(m.to_dict())
	_check(back.kind == "golem" and back.genre == "golem" and back.species == "rock" and back.max_hp == Kinds.info("golem").hp, "a golem saves and loads as a golem")
	var old: Dictionary = m.to_dict()
	old.erase("kind")
	old.genre = "rhythm"
	_check(Monster.from_dict(old).kind == "rock", "a monster saved before kinds loads as its species' own kind")
	old.kind = "nonsense"
	_check(Monster.from_dict(old).kind == "rock", "an unknown kind in a save falls back on the species'")
	var boss = Monster.make(Rng.new(9), {"species": "dragon", "genre": "bounce", "genres": ["bounce", "slither"], "hp": 40, "name": "X", "boss": true}, Vector2i.ZERO)
	var boss_back = Monster.from_dict(boss.to_dict())
	_check(boss_back.kind == "" and boss_back.genres == ["bounce", "slither"], "a champion keeps its attacks through a save")
	var boss_old: Dictionary = boss.to_dict()
	boss_old.erase("genres")
	_check(Monster.from_dict(boss_old).genres.is_empty(), "a champion saved before kinds has no list of its own")
	boss_old.genres = ["bounce", "nope", 3]
	_check(Monster.from_dict(boss_old).genres == ["bounce"], "a champion's saved attacks keep only real ones")
	_check(Kinds.title(m) == "GOLEM" and Kinds.color_of(m) == Kinds.info("golem").color, "a golem is called GOLEM and wears its own colour")
	_check(Kinds.title(boss) == str(Content.species("dragon").label).to_upper(), "a champion is called by its species")
	_check(Kinds.roam(m).get("kind", "") == "still" and Kinds.roam(Monster.make(Rng.new(1), Kinds.line("slime"), Vector2i.ZERO)).is_empty(), "a golem keeps still; a slime goes about as slimes do")
	var tried = Monster.make(Rng.new(2), Kinds.line("rock"), Vector2i.ZERO)
	tried.become_kind("tide")
	_check(tried.kind == "tide" and tried.species == "slime" and tried.genre == "tide" and tried.hp == Kinds.info("tide").hp, "meet= can turn a monster into a kind from another floor")


func _champion_cycle() -> void:
	var enc: Dictionary = Content.table("encounter")
	var boss = Monster.make(Rng.new(9), {"species": "dragon", "genre": "spit", "genres": Kinds.genres_at(2), "hp": 40, "name": "X", "boss": true}, Vector2i.ZERO)
	var seen := []
	for turn in PER_FLOOR:
		boss.turn = turn
		seen.append(Dodge.genre_on_turn(boss, enc.boss.genres, []))
	_check(seen == Kinds.genres_at(2), "a champion fights each of its floor's attacks in turn (%s)" % ", ".join(seen))
	boss.genres = []
	boss.turn = 1
	_check(Dodge.genre_on_turn(boss, enc.boss.genres, []) == enc.boss.genres[1], "one with no list of its own uses the old four")


# ---------------------------------------------------------------- the attacks

## Each attack played for a whole dodge at a low and a high pace of intensity, with the soul standing still and with it wandering:
## it makes hazards, keeps its cells in the box, warns your square at least REACT_MS before it hurts, leaves a square you can walk
## to at STEP_MS a step before it lands, never lights every open square at once, never puts a pillar on you and never shuts you
## into fewer than four squares. The high pace is a champion's on B5F with the dodge pressed hard. Then the same attack twice on
## SAME_SEED: a run that drifts with the clock, or leans on something left over from the run before it, can't be played again.
func _every_attack() -> void:
	var genres: Array = DodgeRun.MINI_GAMES.keys()
	genres.sort()
	for g in genres:
		var worst := {"hazards": 0, "outside": 0, "blind": 0, "trapped": 0, "full": 0, "pinned": 0, "boxed": 0}
		for intensity in [1.0, 1.6]:
			for i in 8:
				var r := _play(g, intensity, i, i % 2 == 1)
				for key in worst:
					worst[key] = worst[key] + r[key]
		_check(worst.hazards > 0, "%s makes hazards (%d)" % [g, worst.hazards])
		_check(worst.outside == 0, "%s keeps to the box" % g)
		_check(worst.blind == 0 or g == "gates", "%s warns your square %d ms before it hurts (%d too late)" % [g, REACT_MS, worst.blind])
		_check(worst.trapped == 0, "%s always leaves a way off your square in time at five steps a second (%d didn't)" % [g, worst.trapped])
		_check(worst.full == 0, "%s never lights every open square at once (%d frames did)" % [g, worst.full])
		_check(worst.pinned == 0, "%s never puts a pillar where you stand" % g)
		_check(worst.boxed == 0, "%s never shuts you into fewer than four squares (%d frames did)" % [g, worst.boxed])
		var made := _signature(g)
		_check(not made.is_empty() and made == _signature(g), "%s is the same attack twice on one seed (%d hazards)" % [g, made.size()])


## What one attack made for a whole dodge on SAME_SEED, in the order it came: a line a hazard, with its kind, the squares it
## lights and when it warns, hurts and ends.
func _signature(genre: String) -> Array:
	var rng := Rng.new(SAME_SEED)
	var run = DodgeRun.start(genre, 1.0, false, 0, 0.0, {}, 1.0)
	var made: Array = []
	var t := 0.0
	while not run.is_over(t):
		run.update(t, rng)
		for h in run.hazards:
			if h.has("_signed"):
				continue
			h._signed = true
			var cells: Array = h.cells.keys()
			cells.sort()
			made.append("%s warns from %d, hurts from %d, ends %d: %s" % [h.kind, roundi(float(h.warn)), roundi(float(h.hit)), roundi(float(h.end)), str(cells)])
		t += TICK_MS
	return made


func _play(genre: String, intensity: float, i: int, wander: bool) -> Dictionary:
	var out := {"hazards": 0, "outside": 0, "blind": 0, "trapped": 0, "full": 0, "pinned": 0, "boxed": 0}
	var rng := Rng.new(77 + i)
	var walk := Rng.new(500 + i)
	# the last two are a frightened and a friendly foe (DodgeRun mood): hazards that never come, and hearts, must not break it
	var run = DodgeRun.start(genre, (intensity - 0.8) / 0.25, i == 5, i % 3, 0.0, {}, 1.0, {}, ["", "", "", "", "", "", "afraid", "friendly"][i])
	var t := 0.0
	var next_step := 0.0
	while not run.is_over(t):
		run.update(t, rng)
		var here := Dodge.index(run.soul.x, run.soul.y)
		for h in run.hazards:
			if h.has("_checked"):
				continue
			var drawn: float = maxf(h.warn, h.hit - float(h.shows)) if h.has("shows") else h.warn
			if t < drawn:
				continue
			h._checked = true
			out.hazards += 1
			if h.cells.keys().any(func(k): return int(k) < 0 or int(k) >= Dodge.COLS * Dodge.ROWS):
				out.outside += 1
			if h.cells.has(here) and h.hit - t < REACT_MS - TICK_MS and not DodgeRun.CATCHES.has(h.kind):
				out.blind += 1
			if h.cells.has(here) and not DodgeRun.CATCHES.has(h.kind):
				var steps := _escape(run, h)
				if steps < 0 or steps > floori((h.hit - t) / STEP_MS):
					out.trapped += 1
					print("kinds_test: %s at %.2f%s, seed %d: at %s, %d ms after it showed, %d steps out with %d ms to go" % [genre, intensity, " (champion)" if i == 5 else "", i, run.soul, int(t - h.warn), steps, int(h.hit - t)])
		var live := {}
		for h in run.hazards:
			if t >= h.hit and t < h.end and not DodgeRun.CATCHES.has(h.kind):
				live.merge(h.cells)
		var open: int = Dodge.COLS * Dodge.ROWS - run.blocked.size()
		if live.size() >= open:
			out.full += 1
		if run.blocked.has(here):
			out.pinned += 1
		if _reach(run, run.soul) < 4:
			out.boxed += 1
		if wander and t >= next_step:
			next_step = t + 200.0
			var d: Vector2i = walk.pick([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
			run.move(d.x, d.y)
		t += TICK_MS
	return out


## The fewest steps from the soul to a square that nothing hurts while `h` does, or -1.
func _escape(run, h: Dictionary) -> int:
	var dist := {run.soul: 0}
	var queue := [run.soul]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var k := Dodge.index(c.x, c.y)
		# safe from `h` itself and from whatever else lands while `h` does (a wall that stays lit after it is not counted: you
		# only have to be out of it by the time it lands, and the next one says where to go after)
		if not run.hazards.any(func(o): return not DodgeRun.CATCHES.has(o.kind) and o.cells.has(k) and o.hit < minf(h.end, h.hit + STEP_MS) and o.end > h.hit):
			return dist[c]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if Dodge.in_box(n.x, n.y) and not run.blocked.has(Dodge.index(n.x, n.y)) and not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	return -1


## How many open squares the soul can walk to.
func _reach(run, from: Vector2i) -> int:
	var seen := {from: true}
	var queue := [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if Dodge.in_box(n.x, n.y) and not run.blocked.has(Dodge.index(n.x, n.y)) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size()
