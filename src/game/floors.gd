## Dungeon generation (game.js "dungeon generation"): how each floor plays, the floor's news, and the maze itself.
## Pure functions of the floor number and the global random source, so tests can seed() them.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Render = preload("res://src/view/render.gd")


## How each floor plays. The first floors are small and simple; every new depth adds something.
static func floor_rules(f: int) -> Dictionary:
	var pool: Dictionary
	if f == 1:
		pool = {"slime": 60, "goblin": 40}
	elif f == 2:
		pool = {"slime": 35, "goblin": 30, "bandit": 20, "snake": 15}
	elif f == 3:
		pool = {"slime": 22, "goblin": 25, "bandit": 18, "snake": 20, "rock": 15}
	else:
		pool = {"slime": 15, "goblin": 22, "bandit": 15, "snake": 18, "rock": 15, "dragon": 15}
	return {
		"size": mini(25, 13 + 2 * f),
		"maxGroup": 1 if f == 1 else (2 if f == 2 else 3),
		"pool": pool,
		"conditions": f >= 3, # special attacks poison, entangle and knock down
		"elite": minf(0.4, 0.12 + 0.04 * (f - 6)) if f >= 6 else 0.0,
		"encounter": 0.06 + 0.01 * mini(f, 10),
		"boss": f % 5 == 0,
	}


const NEWS = {
	1: "FLOOR 1 IS QUIET: SMALL HALLS, LONE SLIMES AND GOBLINS. A GOOD PLACE TO LEARN THE DICE.",
	2: "NEW: MONSTERS NOW ROAM IN PAIRS. BANDITS AND SNAKE PEOPLE LURK HERE.",
	3: "NEW: GROUPS OF THREE, AND ROCK ENTITIES. SPECIAL ATTACKS NOW POISON, ENTANGLE AND KNOCK YOU DOWN.",
	4: "NEW: DRAGONS. THE HALLS GROW WIDER.",
	6: "NEW: VETERAN MONSTERS, TOUGHER AND SHARPER THAN THE REST.",
}


## A key of `table` ({key: weight}), drawn by weight
static func pick_weighted(table: Dictionary) -> String:
	var total := 0.0
	for k in table:
		total += table[k]
	var r := randf() * total
	for k in table:
		r -= table[k]
		if r < 0:
			return k
	return table.keys()[0]


## grid[y][x], or 0 off the grid (JS: grid[y]?.[x])
static func cell(grid: Array, x: int, y: int) -> int:
	if y < 0 or y >= grid.size():
		return 0
	var row: Array = grid[y]
	if x < 0 or x >= row.size():
		return 0
	return row[x]


## A floor: a maze carved on odd cells, knocked through in places, a few small rooms, the stairs at the cell
## farthest from the start, gold scattered on the floor, and on boss floors a 5x5 hall with the champion.
## Returns { grid, n, stairs: {x, y}, gold: {y * n + x: true}, floor, boss }.
static func gen_floor(fl: int) -> Dictionary:
	var rules := floor_rules(fl)
	var N: int = rules.size
	var grid := []
	for i in N:
		var row := []
		row.resize(N)
		row.fill(0)
		grid.append(row)
	# Maze by randomized depth-first carving on odd cells
	var stack := [[1, 1]]
	grid[1][1] = 1
	while not stack.is_empty():
		var top: Array = stack[stack.size() - 1]
		var x: int = top[0]
		var y: int = top[1]
		var next := []
		for d in Render.DIRS:
			var nx: int = x + d[0] * 2
			var ny: int = y + d[1] * 2
			if nx > 0 and ny > 0 and nx < N - 1 and ny < N - 1 and not grid[ny][nx]:
				next.append([nx, ny, x + d[0], y + d[1]])
		if next.is_empty():
			stack.pop_back()
			continue
		var p: Array = J.pick(next)
		grid[p[3]][p[2]] = 1
		grid[p[1]][p[0]] = 1
		stack.append([p[0], p[1]])
	# Knock through some walls so it isn't a perfect maze, and open a few small rooms
	var knocks := J.round_js(28 * pow(N / 21.0, 2))
	for i in knocks:
		var x := J.rnd(1, N - 2)
		var y := J.rnd(1, N - 2)
		if grid[y][x]:
			continue
		if (grid[y][x - 1] and grid[y][x + 1]) or (grid[y - 1][x] and grid[y + 1][x]):
			grid[y][x] = 1
	for r in 2 + floori(N / 10.0):
		var x := J.rnd(1, N - 5) | 1
		var y := J.rnd(1, N - 5) | 1
		for yy in range(y, y + 3):
			for xx in range(x, x + 3):
				grid[yy][xx] = 1
	# Boss floors: a 5x5 hall at the heart of the floor, the champion standing in its center
	var boss = null
	var c := floori(N / 2.0)
	if rules.boss:
		for yy in range(c - 2, c + 3):
			for xx in range(c - 2, c + 3):
				grid[yy][xx] = 1
		boss = {"x": c, "y": c, "species": pick_weighted(rules.pool), "defeated": false, "enemy": null}
	var in_hall := func(x: int, y: int) -> bool: return boss != null and absi(x - c) <= 2 and absi(y - c) <= 2
	# Stairs: the floor cell farthest from the start
	var dist := {"1,1": 0}
	var q := [[1, 1]]
	var far := [1, 1]
	while not q.is_empty():
		var at: Array = q.pop_front()
		var x: int = at[0]
		var y: int = at[1]
		for d in Render.DIRS:
			var k := "%d,%d" % [x + d[0], y + d[1]]
			if cell(grid, x + d[0], y + d[1]) and not dist.has(k):
				dist[k] = dist["%d,%d" % [x, y]] + 1
				q.append([x + d[0], y + d[1]])
				if not in_hall.call(x + d[0], y + d[1]) and dist[k] > dist["%d,%d" % [far[0], far[1]]]:
					far = [x + d[0], y + d[1]]
	var floors := []
	for k in dist:
		var xy: PackedStringArray = k.split(",")
		floors.append([int(xy[0]), int(xy[1])])
	var gold := {}
	while gold.size() < 4 + floori(N / 6.0):
		var p: Array = J.pick(floors)
		var x: int = p[0]
		var y: int = p[1]
		if (x != 1 or y != 1) and (x != far[0] or y != far[1]) and not (boss != null and x == boss.x and y == boss.y):
			gold[y * N + x] = true
	print_verbose("floor %d: %dx%d, %d floor cells, stairs at %d,%d%s" % [fl, N, N, floors.size(), far[0], far[1], ", boss %s" % boss.species if boss else ""])
	return {"grid": grid, "n": N, "stairs": {"x": far[0], "y": far[1]}, "gold": gold, "floor": fl, "boss": boss}
