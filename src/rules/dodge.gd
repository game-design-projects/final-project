## The dodge box: a 7x7 grid with one rule, lit squares hurt. Each faction lights squares in its own way (chess pieces,
## stomps on the beat, a lantern and pillars). All geometry here is in cells, never pixels; the view scales it.
## A cell is `row * COLS + col`.
extends RefCounted

const COLS := 7
const ROWS := 7

const BISHOP_DIRS := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const KNIGHT_JUMPS := [Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1), Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]

## Three pillars in the shadow box.
const PILLARS := [Vector2i(2, 2), Vector2i(4, 4), Vector2i(5, 1)]

## The lantern circles the box on an ellipse around its centre (in cells).
const LANTERN_RADIUS := Vector2(6.0, 4.2)
const LANTERN_START_ANGLE := 2.4
const LANTERN_SPEED := 0.75 # radians per second at intensity 1
const SHADOW_STEPS := 40


## The attack a monster on this turn fights with: a champion cycles through all of them. With `mini_games` every third turn is
## a mini-game instead.
static func genre_on_turn(m, boss_genres: Array, mini_games: Array) -> String:
	if not mini_games.is_empty() and m.turn % 3 == 2:
		return mini_games[floori(m.turn / 3.0) % mini_games.size()]
	return boss_genres[m.turn % boss_genres.size()] if m.boss else m.genre


static func index(c: int, r: int) -> int:
	return r * COLS + c


static func in_box(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < COLS and r < ROWS


static func row_cells(r: int) -> Array:
	var out := []
	for c in COLS:
		out.append(index(c, r))
	return out


static func col_cells(c: int) -> Array:
	var out := []
	for r in ROWS:
		out.append(index(c, r))
	return out


## Chess. The squares a piece on `at` attacks, its own square included.
static func rook_cells(at: Vector2i) -> Array:
	return row_cells(at.y) + col_cells(at.x)


static func bishop_cells(at: Vector2i) -> Array:
	var out := []
	for d in BISHOP_DIRS:
		for step in 8:
			var c: Vector2i = at + d * step
			if in_box(c.x, c.y):
				out.append(index(c.x, c.y))
	return out


static func knight_cells(at: Vector2i) -> Array:
	var out := []
	for j in KNIGHT_JUMPS:
		var c: Vector2i = at + j
		if in_box(c.x, c.y):
			out.append(index(c.x, c.y))
	out.append(index(at.x, at.y))
	return out


## Rhythm. How many stomp patterns there are; they come in this order, one per beat, and the last one aims at you.
static func stomp_count() -> int:
	return 9


## The squares stomp number `n` (0-based) lights, given where the soul stands.
static func stomp_cells(n: int, soul: Vector2i) -> Array:
	match n % stomp_count():
		0: return _cols([0, 2, 4, 6])
		1: return _cols([1, 3, 5])
		2: return _rows([0, 2, 4, 6])
		3: return _rows([1, 3, 5])
		4: return row_cells(0) + row_cells(ROWS - 1) + col_cells(0) + col_cells(COLS - 1) # the frame
		5: return row_cells(3) + col_cells(3) # the cross
		6: return _checker(0)
		7: return _checker(1)
		_: return rook_cells(soul)


static func _cols(list: Array) -> Array:
	var out := []
	for c in list:
		out.append_array(col_cells(c))
	return out


static func _rows(list: Array) -> Array:
	var out := []
	for r in list:
		out.append_array(row_cells(r))
	return out


static func _checker(parity: int) -> Array:
	var out := []
	for k in COLS * ROWS:
		if ((k % COLS) + floori(float(k) / COLS)) % 2 == parity:
			out.append(k)
	return out


## Shadow. Where the lantern is, in cells, `ms` after the dodge began. `intensity` speeds it up.
static func lantern_at(ms: float, intensity: float) -> Vector2:
	var angle := (ms / 1000.0) * LANTERN_SPEED * intensity + LANTERN_START_ANGLE
	var centre := Vector2(COLS, ROWS) / 2.0
	return centre + Vector2(cos(angle) * LANTERN_RADIUS.x, sin(angle) * LANTERN_RADIUS.y)


## A cell is in shadow when the line from the lantern to its centre crosses a pillar. `blocked` is the set of pillar
## cells in play ({index: true}).
static func in_shadow(lantern: Vector2, c: int, r: int, blocked: Dictionary) -> bool:
	var target := Vector2(c + 0.5, r + 0.5)
	for i in range(1, SHADOW_STEPS):
		var p := lantern + (target - lantern) * (float(i) / SHADOW_STEPS)
		var pc := floori(p.x)
		var pr := floori(p.y)
		if in_box(pc, pr) and blocked.has(index(pc, pr)) and not (pc == c and pr == r):
			return true
	return false


static func pillar_set() -> Dictionary:
	var out := {}
	for p in PILLARS:
		out[index(p.x, p.y)] = true
	return out
