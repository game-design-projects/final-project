## Genre Halls (genre_halls.gd): the rules of the Undertale-style encounter mode, with no UI, so they can be tested.
## Each faction attacks in its own genre (chess, shadow, rhythm, goo rain) inside one box with one rule: lit squares hurt.
## Here: the factions and their tastes, the floor, the monster's mind (Jev-shaped questions with local answers), how
## typed words are read, and the box's geometry. genre_halls.gd draws it all and runs the fight.
## Port of crawler/public/genre-rules.js. `clamp` is `clamp_num` here (GDScript has a global clamp).
extends RefCounted

const Render = preload("res://src/view/render.gd")
const Species = preload("res://src/rules/species.gd")
const Emotions = preload("res://src/rules/emotions.gd")
const J = preload("res://src/core/js.gd")


static func rnd(a: int, b: int) -> int:
	return J.rnd(a, b)


static func pick(a: Array):
	return J.pick(a)


static func clamp_num(v, a, b):
	return maxf(a, minf(b, v))


static func sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))


# ---------------------------------------------------------------- factions

const GENRES = {
	"bullet": {"name": "GOO RAIN", "rule": "WATCH WHERE THE GOO WILL LAND"},
	"chess": {"name": "CHESS", "rule": "ROOK: ROW + COLUMN · BISHOP: DIAGONALS · KNIGHT: L-JUMPS"},
	"shadow": {"name": "SHADOW", "rule": "THE LANTERN FLARES. HIDE IN A PILLAR'S SHADOW"},
	"rhythm": {"name": "RHYTHM", "rule": "IT STOMPS ON THE BEAT. MOVE BETWEEN BEATS"},
}

# ACT options per species. Each one is an intent the monster's mind judges, the same intents the chatbox reads.
const ACTS = {
	"slime": [
		{"label": "TELL A JOKE", "intent": "joke"},
		{"label": "OFFER COMFORT", "intent": "kindness"},
		{"label": "CALL IT GROSS", "intent": "insult"},
	],
	"bandit": [
		{"label": "OFFER A FAIR CUT", "intent": "gold"},
		{"label": "SHOW A CLEVER TRICK", "intent": "joke"},
		{"label": "SNEER AT IT", "intent": "insult"},
	],
	"snake": [
		{"label": "PRAISE ITS SCALES", "intent": "flattery"},
		{"label": "PROPOSE A BARGAIN", "intent": "gold"},
		{"label": "HURRY IT ALONG", "intent": "rush"},
	],
	"rock": [
		{"label": "WAIT QUIETLY", "intent": "peace"},
		{"label": "ADMIRE THE OLD STONE", "intent": "flattery"},
		{"label": "BANG ON YOUR SHIELD", "intent": "noise"},
	],
	"dragon": [
		{"label": "FLATTER ITS HOARD", "intent": "flattery"},
		{"label": "STAND YOUR GROUND", "intent": "courage"},
		{"label": "OFFER ONE COPPER", "intent": "cheap"},
	],
}

# How much each species likes each kind of words or deeds (-2..2), from its likes and dislikes in species.gd
const AFF = {
	"slime": {"kindness": 2, "joke": 2, "flattery": 0.5, "gold": 0.5, "threat": -1.5, "insult": -2, "peace": 1.5, "join": 1, "question": 0.5, "gibberish": 1, "courage": 0, "cheap": 0, "noise": -1, "rush": -0.5},
	"bandit": {"kindness": 0, "joke": 1.5, "flattery": 1, "gold": 2, "threat": -1, "insult": -2, "peace": 0, "join": 0.5, "question": 0.5, "gibberish": -1, "courage": 0.5, "cheap": -1.5, "noise": -0.5, "rush": 0},
	"snake": {"kindness": 0.5, "joke": 0, "flattery": 2, "gold": 1.5, "threat": -1.5, "insult": -2, "peace": 1, "join": 0.5, "question": 1, "gibberish": -1.5, "courage": 0, "cheap": -1, "noise": -1.5, "rush": -2},
	"rock": {"kindness": 1, "joke": -0.5, "flattery": 1.5, "gold": -1, "threat": -1, "insult": -1, "peace": 2, "join": 0.5, "question": 1, "gibberish": -1, "courage": 0, "cheap": -0.5, "noise": -2, "rush": -1.5},
	"dragon": {"kindness": 0, "joke": 1, "flattery": 2, "gold": 1, "threat": 0, "insult": -2, "peace": 0, "join": 0, "question": 0.5, "gibberish": -1.5, "courage": 1, "cheap": -2, "noise": -1, "rush": -1},
}
# Traits shift those tastes, so two slimes don't want the same thing
const TRAIT_TASTE = {
	"easily startled": {"threat": -1.5, "noise": -1}, "ticklish": {"joke": 1}, "lonely": {"join": 1.5, "kindness": 0.5}, "hungry": {"gold": 1},
	"curious": {"question": 1}, "sleepy": {"peace": 1, "joke": -1}, "shy": {"flattery": -1, "kindness": 0.5},
	"greedy": {"gold": 1}, "charming": {"flattery": 1}, "jumpy": {"threat": -1.5, "noise": -1}, "owes money to someone": {"gold": 1.5},
	"quick-fingered": {"joke": 0.5}, "surprisingly honest about being dishonest": {"insult": 0.5, "flattery": -0.5},
	"patient": {"peace": 1, "rush": -0.5}, "secretive": {"question": -1.5}, "vain about its scales": {"flattery": 1},
	"always bargaining": {"gold": 1}, "holds grudges": {"insult": -1, "threat": -0.5}, "curious about humans": {"question": 1, "kindness": 0.5},
	"cold-blooded": {"kindness": -1}, "half asleep": {"gibberish": 0.5, "noise": -1}, "slow to anger": {"threat": 1, "insult": 0.5},
	"remembers everything": {"question": 1.5}, "ancient": {"flattery": 0.5}, "covered in moss": {"kindness": 0.5},
	"vain": {"flattery": 1}, "bored": {"joke": 1, "peace": -1}, "loves riddles": {"question": 1, "joke": 0.5}, "hoards gold coins": {"gold": 1},
	"old battle scars": {"courage": 1, "threat": 0.5},
}
const POS = {
	"kindness": ["touched", "delighted"], "joke": ["amused", "delighted"], "flattery": ["flattered", "delighted"], "gold": ["delighted", "intrigued"],
	"peace": ["touched", "delighted"], "join": ["touched", "delighted"], "question": ["intrigued"], "courage": ["intrigued", "touched"],
	"gibberish": ["amused", "confused"], "threat": ["intrigued"], "cheap": ["confused"], "noise": ["confused"], "rush": ["confused"], "insult": ["confused"],
}
const NEG = {
	"kindness": ["confused"], "joke": ["confused", "offended"], "flattery": ["confused", "offended"], "gold": ["offended"], "peace": ["confused"],
	"join": ["offended"], "question": ["offended"], "courage": ["enraged"], "threat": ["terrified", "enraged"], "insult": ["offended", "enraged"],
	"cheap": ["offended", "enraged"], "noise": ["enraged", "confused"], "rush": ["offended"], "gibberish": ["offended"],
}
# Nonsense makes each kind mad or sad in its own way
const GIBBERISH_NEG = {"bandit": ["offended"], "snake": ["offended", "enraged"], "rock": ["confused", "sad"], "dragon": ["enraged"], "slime": ["confused"]}

# What allies think of what you do. Recruits are passive charms; cross their values and they walk.
const APPROVE = {
	"slime": {"slay": -2, "slay_begging": -3, "spare": 1.5, "flee": 0, "insult": -1, "threat": -1, "kindness": 0.5, "joke": 0.5, "noise": -0.5},
	"bandit": {"slay": 1, "slay_begging": 0.5, "spare": -0.5, "flee": -1, "gold": -1.5, "cheap": 1, "insult": 0.5},
	"snake": {"slay": -0.5, "slay_begging": -2, "spare": 1, "flee": 0, "gold": 1, "rush": -1, "noise": -1.5, "threat": -1},
	"rock": {"slay": -1, "slay_begging": -1.5, "spare": 1, "flee": -1.5, "noise": -2, "rush": -1, "gold": -1, "peace": 1},
	"dragon": {"slay": 1, "slay_begging": 0, "spare": -0.5, "flee": -2.5, "cheap": -1, "courage": 1.5, "insult": 0.5},
}
const CHARMS = {
	"slime": {"name": "BOUNCY", "text": "absorbs the first hit of every fight"},
	"bandit": {"name": "KEEN EYE", "text": "warnings stay lit longer"},
	"snake": {"name": "SLIPPERY", "text": "longer safety after you get hit"},
	"rock": {"name": "STEADY", "text": "the strike bar moves slower"},
	"dragon": {"name": "HOARD-FIRE", "text": "+4 damage on every strike"},
}

const ROSTER = [
	{"species": "slime", "genre": "bullet", "hp": 18},
	{"species": "bandit", "genre": "chess", "hp": 24},
	{"species": "snake", "genre": "shadow", "hp": 22},
	{"species": "rock", "genre": "rhythm", "hp": 30},
]
const BOSS = {"species": "dragon", "genres": ["chess", "shadow", "rhythm", "bullet"], "hp": 56}


# ---------------------------------------------------------------- floor (DONJON's maze carver, smaller)

static func _cell(grid: Array, x: int, y: int) -> int:
	if y < 0 or y >= grid.size():
		return 0
	var row: Array = grid[y]
	if x < 0 or x >= row.size():
		return 0
	return row[x]


@warning_ignore("integer_division")
static func gen_floor() -> Dictionary:
	var n := 13
	var grid := []
	for _y in n:
		var row := []
		row.resize(n)
		row.fill(0)
		grid.append(row)
	var stack := [[1, 1]]
	grid[1][1] = 1
	while not stack.is_empty():
		var top: Array = stack[stack.size() - 1]
		var x: int = top[0]
		var y: int = top[1]
		var nexts := []
		for d in Render.DIRS:
			var nx: int = x + d[0] * 2
			var ny: int = y + d[1] * 2
			if nx > 0 and ny > 0 and nx < n - 1 and ny < n - 1 and not grid[ny][nx]:
				nexts.append([nx, ny, x + d[0], y + d[1]])
		if nexts.is_empty():
			stack.pop_back()
			continue
		var p: Array = pick(nexts)
		grid[p[3]][p[2]] = 1
		grid[p[1]][p[0]] = 1
		stack.append([p[0], p[1]])
	for _i in 12:
		var x := rnd(1, n - 2)
		var y := rnd(1, n - 2)
		if grid[y][x]:
			continue
		if (grid[y][x - 1] and grid[y][x + 1]) or (grid[y - 1][x] and grid[y + 1][x]):
			grid[y][x] = 1
	# The champion's 5x5 hall at the heart of the floor
	var c := n / 2
	for yy in range(c - 2, c + 3):
		for xx in range(c - 2, c + 3):
			grid[yy][xx] = 1
	var in_hall := func(x: int, y: int) -> bool: return absi(x - c) <= 2 and absi(y - c) <= 2
	# Breadth-first from the start; `order` keeps discovery order so equal distances sort like the JS did
	var dist := {"1,1": 0}
	var order := [[1, 1]]
	var q := [[1, 1]]
	var far := [1, 1]
	var head := 0
	while head < q.size():
		var cur: Array = q[head]
		head += 1
		for d in Render.DIRS:
			var nx: int = cur[0] + d[0]
			var ny: int = cur[1] + d[1]
			var k := "%d,%d" % [nx, ny]
			if _cell(grid, nx, ny) and not dist.has(k):
				dist[k] = dist["%d,%d" % [cur[0], cur[1]]] + 1
				q.append([nx, ny])
				order.append([nx, ny])
				if not in_hall.call(nx, ny) and dist[k] > dist["%d,%d" % [far[0], far[1]]]:
					far = [nx, ny]
	# Monsters spread out along the way, nearest first, in roster order
	var cells := []
	for i in order.size():
		var o: Array = order[i]
		var dd: int = dist["%d,%d" % [o[0], o[1]]]
		if dd >= 3 and not in_hall.call(o[0], o[1]) and not (o[0] == far[0] and o[1] == far[1]):
			cells.append([o[0], o[1], dd, i])
	cells.sort_custom(func(a, b): return a[2] < b[2] or (a[2] == b[2] and a[3] < b[3]))
	var monsters := []
	var used := []
	for i in ROSTER.size():
		var r: Dictionary = ROSTER[i]
		var target := floori((float(i + 1) / (ROSTER.size() + 1)) * cells.size())
		var best = null
		for j in cells.size():
			var cc: Array = cells[(target + j) % cells.size()]
			var apart := true
			for u in used:
				if absi(u[0] - cc[0]) + absi(u[1] - cc[1]) <= 2:
					apart = false
					break
			if apart:
				best = [cc[0], cc[1]]
				break
		if best == null:
			best = [cells[target][0], cells[target][1]]
		used.append(best)
		monsters.append(roll_taste(make_monster(r, best[0], best[1])))
	monsters.append(roll_taste(make_monster({"species": BOSS.species, "genre": BOSS.genres[0], "hp": BOSS.hp, "boss": true}, c, c)))
	return {"grid": grid, "n": n, "stairs": {"x": far[0], "y": far[1]}, "monsters": monsters, "boss": {"x": c, "y": c, "defeated": false}}


static func make_monster(r: Dictionary, x: int, y: int) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[r.species]
	var boss: bool = r.get("boss", false)
	var meters: Dictionary = sp.start.duplicate()
	meters.friendliness = clamp_num(sp.start.friendliness + rnd(-10, 10), 0, 100)
	meters.anger = clamp_num(sp.start.anger + rnd(-5, 10), 0, 100)
	var traits: Array = sp.traits.duplicate()
	traits.shuffle()
	return {
		"species": r.species,
		"genre": r.genre,
		"boss": boss,
		"name": "VEXALITH" if boss else str(pick(sp.names)).to_upper(),
		"x": x,
		"y": y,
		"hp": r.hp,
		"maxHp": r.hp,
		"meters": meters,
		"traits": traits.slice(0, 2),
		"taste": {},
		"spoke": false,
		"threshold": sp.joinThreshold + 5 if boss else sp.joinThreshold,
		"turn": 0,
		"gone": null, # "spared" | "slain"
	}


static func roll_taste(m: Dictionary) -> Dictionary:
	for k in AFF[m.species]:
		m.taste[k] = (randf() - 0.5) * 1.2
	for t in m.traits:
		var shift: Dictionary = TRAIT_TASTE.get(t, {})
		for k in shift:
			m.taste[k] = m.taste.get(k, 0) + shift[k]
	return m


static func aff(m: Dictionary, intent: String) -> float:
	return float(AFF[m.species].get(intent, 0)) + float(m.taste.get(intent, 0))


# ---------------------------------------------------------------- the mind (Jev-shaped questions, local answers)

static func softmax(logits: Dictionary) -> Dictionary:
	var m := -INF
	for k in logits:
		m = maxf(m, logits[k])
	var e := {}
	var s := 0.0
	for k in logits:
		e[k] = exp(logits[k] - m)
		s += e[k]
	var out := {}
	for k in e:
		out[k] = e[k] / s
	return out


# DONJON's rule: any answer at 15% or more can happen, in proportion to its probability.
static func roll_odds(probs: Dictionary) -> String:
	var pool := []
	for k in probs:
		if probs[k] >= 0.15:
			pool.append([k, probs[k]])
	if pool.is_empty():
		var top = null
		for k in probs:
			if top == null or probs[k] > top[1]:
				top = [k, probs[k]]
		pool = [top]
	var total := 0.0
	for e in pool:
		total += e[1]
	var r := randf() * total
	for e in pool:
		r -= e[1]
		if r <= 0:
			return e[0]
	return pool[pool.size() - 1][0]


## `act` is "fight", or an Array of { intent, w }: one for an ACT button, a spread for typed words
static func ask_feeling(m: Dictionary, act) -> Dictionary:
	var f: float = m.meters.friendliness
	var anger: float = m.meters.anger
	var fear: float = m.meters.fear
	var logits := {}
	for k in Emotions.EMOTIONS:
		logits[k] = -1.4
	logits.confused += 0.4
	if act is String and act == "fight":
		logits.terrified += 0.6 + fear / 30.0 + (1.6 if float(m.hp) / m.maxHp < 0.4 else 0.0)
		logits.enraged += 1.2 + anger / 35.0
		logits.sad += 0.4 + f / 60.0
		logits.offended += 0.6
	else:
		for it in act:
			var a := aff(m, it.intent)
			var pool: Array
			if a >= 0:
				pool = POS.get(it.intent, [])
			elif it.intent == "gibberish":
				pool = GIBBERISH_NEG.get(m.species, [])
			else:
				pool = NEG.get(it.intent, [])
			for k in pool:
				logits[k] += it.w * (1.4 + 1.1 * absf(a) + (-anger / 50.0 if a >= 0 else anger / 50.0))
		logits.terrified += fear / 60.0
	var probs := softmax(logits)
	return {"type": "choice", "choice": roll_odds(probs), "probabilities": probs}


static func ask_mercy(m: Dictionary) -> Dictionary:
	var f: float = m.meters.friendliness
	var anger: float = m.meters.anger
	var fear: float = m.meters.fear
	var low: bool = float(m.hp) / m.maxHp < 0.4
	var x: float = (f - m.threshold) / 9.0 + ((fear - 40.0) / 25.0) * (1.0 if low else 0.3) - anger / 30.0
	return {"type": "noul", "noul": sigmoid(x)}


static func ask_pressure(m: Dictionary) -> Dictionary:
	var f: float = m.meters.friendliness
	var anger: float = m.meters.anger
	var fear: float = m.meters.fear
	var raw: float = clamp_num((anger * 1.2 - f * 0.5 - fear * 0.4 + 45.0) / 30.0, 0.0, 3.0)
	var levels := []
	var s := 0.0
	for i in 4:
		var v := exp(-pow(i - raw, 2) * 1.6)
		levels.append(v)
		s += v
	var probs := {}
	for i in 4:
		probs[str(i)] = levels[i] / s
	return {"type": "score", "score": raw, "probabilities": probs}


static func apply_feeling(m: Dictionary, id: String) -> Dictionary:
	var em: Dictionary = Emotions.EMOTIONS[id]
	var shift: Dictionary = em.get("meters", {})
	for k in shift:
		m.meters[k] = clamp_num(m.meters.get(k, 0) + shift[k], 0, 100)
	return em


# ---------------------------------------------------------------- reading typed words

# Keyword cues for each intent. Stand-in for Jev reading the words; the real build asks Jev what they meant.
static var CUES := _make_cues()
const COMMON := ["a", "an", "the", "i", "you", "me", "my", "we", "us", "it", "is", "are", "am", "be", "to", "of", "in", "on", "at", "for", "and", "or", "but", "not", "no", "yes", "do", "don't", "can", "will", "want", "like", "with", "your", "our", "this", "that", "here", "there", "so", "just", "very", "hi", "hello", "hey"]
static var _word_re := RegEx.create_from_string("[a-z']+")
static var _vowel_re := RegEx.create_from_string("[aeiouy]")
static var _run_re := RegEx.create_from_string("[^aeiouy']+")
static var _triple_re := RegEx.create_from_string("(.)\\1\\1")
static var _mash_re := RegEx.create_from_string("asdf|qwer|zxcv|jkl|hjk")


static func _make_cues() -> Dictionary:
	var src := {
		"kindness": "\\b(friend|kind|sorry|love|care|safe|hug|please|thank|nice|gentle|help|cute|okay|ok)\\b",
		"joke": "\\b(joke|haha+|lol|funny|pun|knock|laugh|silly|boop|blorp|bloop)\\b",
		"flattery": "\\b(beautiful|strong|mighty|pretty|shiny|scales?|great|impressive|wise|handsome|magnificent|cool|amazing|majestic|old)\\b",
		"gold": "\\b(gold|coins?|pay|money|cut|share|deal|trade|offer|bargain|loot|treasure)\\b",
		"threat": "\\b(kill|die|destroy|crush|smash|end you|hurt you|slay)\\b",
		"insult": "\\b(stupid|ugly|gross|dumb|idiot|weak|pathetic|slimy|loser|worm|thief|rock-head)\\b",
		"peace": "\\b(peace|stop|truce|calm|quiet|rest|wait|no fight|don't fight|leave)\\b",
		"join": "\\b(join|come with|team|together|party|follow|with us)\\b",
		"question": "\\?|\\b(where|what|who|why|how|stairs|way out|exit|tell me|secret)\\b",
		"rush": "\\b(hurry|quick|faster|now now|move it)\\b",
		"noise": "\\b(loud|bang|scream|yell)\\b|!{3,}",
	}
	var out := {}
	for k in src:
		out[k] = RegEx.create_from_string(src[k])
	return out


static func _count(re: RegEx, s: String) -> int:
	return re.search_all(s).size()


static func gibberish_odds(text: String) -> float:
	var t := text.to_lower().strip_edges()
	var words := []
	for m in _word_re.search_all(t):
		words.append(m.get_string())
	if words.is_empty():
		return 0.95
	var bad := 0
	for w: String in words:
		if COMMON.has(w):
			continue
		var vowels := _count(_vowel_re, w)
		var run := 0
		for m in _run_re.search_all(w):
			run = maxi(run, m.get_string().length())
		if w.length() > 2 and (vowels == 0 or run >= 4 or _triple_re.search(w) != null or _mash_re.search(w) != null or float(vowels) / w.length() < 0.15):
			bad += 1
	var cues := 0
	for k in CUES:
		cues += _count(CUES[k], t)
	return clamp_num(float(bad) / words.size() - cues * 0.15 + (0.2 if words.size() == 1 and cues == 0 else 0.0), 0.02, 0.97)


static func read_words(text: String) -> Dictionary:
	var t := text.to_lower()
	var gib := gibberish_odds(text)
	var logits := {"other": 0.3}
	for k in CUES:
		logits[k] = minf(_count(CUES[k], t), 2) * 1.5 - 0.6
	var p := softmax(logits)
	var probs := {}
	for k in p:
		probs[k] = p[k] * (1.0 - gib)
	probs["gibberish"] = gib
	var top := ""
	var top_p := -INF
	for k in probs:
		if probs[k] > top_p:
			top = k
			top_p = probs[k]
	return {"type": "choice", "choice": top, "probabilities": probs}


const INTENT_WORDS = {
	"kindness": "kindness", "joke": "jokes", "flattery": "praise", "gold": "gold", "threat": "threats", "insult": "insults", "peace": "quiet and peace",
	"join": "company", "question": "questions", "gibberish": "nonsense", "courage": "courage", "cheap": "cheap offers", "noise": "noise", "rush": "being rushed",
}


# ---------------------------------------------------------------- the box: one grid, one rule (lit squares hurt)

const W := 448
const H := 288
const COLS := 7
const ROWS := 7
const CELL := 28
const BX := (W - COLS * CELL) / 2.0
const BY := 82


static func idx(c: int, r: int) -> int:
	return r * COLS + c


static func in_box(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < COLS and r < ROWS


static func row_cells(r: int) -> Array:
	var out := []
	for c in COLS:
		out.append(idx(c, r))
	return out


static func col_cells(c: int) -> Array:
	var out := []
	for r in ROWS:
		out.append(idx(c, r))
	return out


# Chess: the squares a piece standing on `o` ({c, r}) attacks, its own square included
static func rook_cells(o: Dictionary) -> Array:
	return row_cells(o.r) + col_cells(o.c)


const DIAGONALS = [[1, 1], [1, -1], [-1, 1], [-1, -1]]


static func bishop_cells(o: Dictionary) -> Array:
	var cells := []
	for e in DIAGONALS:
		for s in 8:
			if in_box(o.c + e[0] * s, o.r + e[1] * s):
				cells.append(idx(o.c + e[0] * s, o.r + e[1] * s))
	return cells


const KNIGHT = [[1, 2], [2, 1], [-1, 2], [-2, 1], [1, -2], [2, -1], [-1, -2], [-2, -1]]


static func knight_cells(o: Dictionary) -> Array:
	var cells := []
	for d in KNIGHT:
		var x: int = o.c + d[0]
		var y: int = o.r + d[1]
		if in_box(x, y):
			cells.append(idx(x, y))
	cells.append(idx(o.c, o.r))
	return cells


# Rhythm: the stomp patterns, in the order the beat walks through them. The last one aims at where you stand.
# Each takes the soul ({c, r}) and returns the lit cells, with repeats like the JS (a Set makes them unique).
static func _stomp_cols(list: Array) -> Array:
	var out := []
	for c in list:
		out.append_array(col_cells(c))
	return out


static func _stomp_rows(list: Array) -> Array:
	var out := []
	for r in list:
		out.append_array(row_cells(r))
	return out


@warning_ignore("integer_division")
static func _stomp_checker(parity: int) -> Array:
	var out := []
	for k in COLS * ROWS:
		if ((k % COLS) + k / COLS) % 2 == parity:
			out.append(k)
	return out


static var STOMPS: Array = [
	func(_soul): return _stomp_cols([0, 2, 4, 6]),
	func(_soul): return _stomp_cols([1, 3, 5]),
	func(_soul): return _stomp_rows([0, 2, 4, 6]),
	func(_soul): return _stomp_rows([1, 3, 5]),
	func(_soul): return row_cells(0) + row_cells(6) + col_cells(0) + col_cells(6),
	func(_soul): return row_cells(3) + col_cells(3),
	func(_soul): return _stomp_checker(0),
	func(_soul): return _stomp_checker(1),
	func(soul): return row_cells(soul.r) + col_cells(soul.c),
]

# Shadow: three pillars, and a lantern circling the box; `ms` is the time since the dodge began.
const PILLARS = [2 * COLS + 2, 4 * COLS + 4, 1 * COLS + 5] # idx(2, 2), idx(4, 4), idx(5, 1)


static func lantern_at(ms: float, intensity: float) -> Dictionary:
	var a := (ms / 1000.0) * 0.75 * intensity + 2.4
	return {"x": W / 2.0 + cos(a) * 168.0, "y": BY + (ROWS * CELL) / 2.0 + sin(a) * 118.0}


## A cell is in shadow when the line from the lantern to its center crosses a pillar. `blocked` is a set ({idx: true}).
static func shaded(L: Dictionary, c: int, r: int, blocked: Dictionary) -> bool:
	var tx: float = BX + (c + 0.5) * CELL
	var ty: float = BY + (r + 0.5) * CELL
	for i in range(1, 40):
		var s := i / 40.0
		var x: float = L.x + (tx - L.x) * s
		var y: float = L.y + (ty - L.y) * s
		var pc := floori((x - BX) / CELL)
		var pr := floori((y - BY) / CELL)
		if in_box(pc, pr) and blocked.has(idx(pc, pr)) and not (pc == c and pr == r):
			return true
	return false
