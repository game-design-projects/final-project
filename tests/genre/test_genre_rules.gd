## Genre Halls, the Undertale-style encounter mode: its rules, with no UI. Port of crawler/test/genre-halls.test.js.
extends "res://tests/test_case.gd"

const Rules = preload("res://src/genre/genre_rules.gd")
const Species = preload("res://src/rules/species.gd")
const Emotions = preload("res://src/rules/emotions.gd")
const Render = preload("res://src/view/render.gd")

const ALL := Rules.COLS * Rules.ROWS


func _kinds() -> Array:
	var out := []
	for r in Rules.ROSTER:
		out.append(r.species)
	out.append(Rules.BOSS.species)
	return out


func _monster(species: String, meters := {}) -> Dictionary:
	var m := {"friendliness": 40, "anger": 20, "fear": 10}
	m.merge(meters, true)
	return {"species": species, "hp": 20, "maxHp": 20, "threshold": Species.SPECIES[species].joinThreshold, "taste": {}, "meters": m}


func _sum(d: Dictionary) -> float:
	var s := 0.0
	for k in d:
		s += d[k]
	return s


func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


func _count_unique(cells: Array) -> int:
	var seen := {}
	for k in cells:
		seen[k] = true
	return seen.size()


func test_every_faction_has_its_genre_acts_tastes_charm_and_values_and_every_feeling_named_exists():
	for r in Rules.ROSTER:
		ok(Rules.GENRES.has(r.genre), r.genre)
	for g in Rules.BOSS.genres:
		ok(Rules.GENRES.has(g), g)
	for s in _kinds():
		ok(Species.SPECIES.has(s), s)
		var lines: Dictionary = Species.SPECIES[s].get("lines", {})
		ok(lines.get("converse", []).size() > 0 and lines.get("attack", []).size() > 0, "%s lines" % s)
		ok(Rules.CHARMS.has(s) and Rules.APPROVE.has(s) and Rules.GIBBERISH_NEG.has(s), s)
		for a in Rules.ACTS[s]:
			ok(Rules.AFF[s].has(a.intent), "%s: %s" % [s, a.intent])
	for intent in Rules.AFF.slime:
		ok(Rules.INTENT_WORDS.get(intent, "") != "", intent)
	var named := []
	for table in [Rules.POS, Rules.NEG, Rules.GIBBERISH_NEG]:
		for k in table:
			named.append_array(table[k])
	for f in named:
		ok(Emotions.EMOTIONS.has(f), f)


func test_a_floor_puts_the_stairs_and_every_monster_within_reach_apart_and_the_champion_in_its_hall():
	seed(7)
	for run in 200:
		var map := Rules.gen_floor()
		var reach := {"1,1": true}
		var q := [[1, 1]]
		var head := 0
		while head < q.size():
			var cur: Array = q[head]
			head += 1
			for d in Render.DIRS:
				var nx: int = cur[0] + d[0]
				var ny: int = cur[1] + d[1]
				var k := "%d,%d" % [nx, ny]
				if ny >= 0 and ny < map.grid.size() and nx >= 0 and nx < map.grid[ny].size() and map.grid[ny][nx] == 1 and not reach.has(k):
					reach[k] = true
					q.append([nx, ny])
		var stairs_key := "%d,%d" % [map.stairs.x, map.stairs.y]
		ok(reach.has(stairs_key), "stairs reachable")
		eq(map.monsters.size(), Rules.ROSTER.size() + 1)
		var at := {}
		for m in map.monsters:
			at["%d,%d" % [m.x, m.y]] = true
		eq(at.size(), map.monsters.size(), "one monster per cell")
		ok(not at.has("1,1") and not at.has(stairs_key), "nobody on the start or the stairs")
		for m in map.monsters:
			ok(reach.has("%d,%d" % [m.x, m.y]), "%s reachable" % m.species)
		var boss = null
		for m in map.monsters:
			if m.boss:
				boss = m
				break
		var c: int = map.n / 2
		eq([boss.x, boss.y, boss.species], [c, c, Rules.BOSS.species])
		for m in map.monsters:
			if not m.boss:
				ok(maxi(absi(m.x - c), absi(m.y - c)) > 2, "outside the hall")


func test_roll_odds_only_picks_answers_at_15_percent_or_more_falling_back_to_the_likeliest():
	seed(11)
	for i in 300:
		var p := Rules.softmax({"a": randf() * 4, "b": randf() * 4, "c": randf() * 4, "d": -3})
		ok(p[Rules.roll_odds(p)] >= 0.15)
	eq(Rules.roll_odds({"a": 0.1, "b": 0.12, "c": 0.14}), "c")


func test_a_feeling_is_a_full_distribution_over_the_ten_feelings_for_deeds_and_for_words():
	seed(13)
	var acts := [
		"fight",
		[{"intent": "joke", "w": 1}],
		[{"intent": "insult", "w": 0.6}, {"intent": "gibberish", "w": 0.4}],
	]
	for act in acts:
		var a = Rules.ask_feeling(_monster("slime"), act)
		eq(a.type, "choice")
		eq(_sorted_keys(a.probabilities), _sorted_keys(Emotions.EMOTIONS))
		ok(absf(_sum(a.probabilities) - 1.0) < 1e-9)
		ok(Emotions.EMOTIONS.has(a.choice))
	# A slime loves a joke and hates an insult
	var joke = Rules.ask_feeling(_monster("slime"), [{"intent": "joke", "w": 1}]).probabilities
	var insult = Rules.ask_feeling(_monster("slime"), [{"intent": "insult", "w": 1}]).probabilities
	ok(joke.amused + joke.delighted > insult.amused + insult.delighted)
	ok(insult.offended + insult.enraged > joke.offended + joke.enraged)


func test_mercy_grows_with_friendliness_and_shrinks_with_anger_pressure_is_a_0_3_level():
	var mercy := func(meters: Dictionary) -> float: return Rules.ask_mercy(_monster("rock", meters)).noul
	ok(mercy.call({"friendliness": 80}) > mercy.call({"friendliness": 40}))
	ok(mercy.call({"anger": 80}) < mercy.call({"anger": 10}))
	for meters in [{"anger": 0, "friendliness": 100}, {"anger": 100, "friendliness": 0}, {}]:
		var p = Rules.ask_pressure(_monster("dragon", meters))
		ok(p.score >= 0 and p.score <= 3)
		ok(absf(_sum(p.probabilities) - 1.0) < 1e-9)
	ok(Rules.ask_pressure(_monster("dragon", {"anger": 100, "friendliness": 0})).score > Rules.ask_pressure(_monster("dragon", {"anger": 0, "friendliness": 100})).score)


func test_typed_words_are_read_by_intent_and_a_keyboard_mash_is_nonsense():
	eq(Rules.read_words("you are so beautiful and strong").choice, "flattery")
	eq(Rules.read_words("I can offer gold, a fair share of the loot").choice, "gold")
	eq(Rules.read_words("where are the stairs?").choice, "question")
	eq(Rules.read_words("asdfgh qwrtzp").choice, "gibberish")
	ok(Rules.gibberish_odds("hello friend") < 0.2)
	var p = Rules.read_words("knock knock, a joke for you").probabilities
	ok(absf(_sum(p) - 1.0) < 1e-9)


func test_every_chess_piece_and_every_stomp_leaves_a_safe_square_wherever_you_stand():
	for r in Rules.ROWS:
		for c in Rules.COLS:
			var o := {"c": c, "r": r}
			for cells in [Rules.rook_cells(o), Rules.bishop_cells(o), Rules.knight_cells(o)]:
				ok(cells.all(func(k): return k >= 0 and k < ALL), "inside the box")
				ok(_count_unique(cells) < ALL)
			for i in Rules.STOMPS.size():
				ok(_count_unique(Rules.STOMPS[i].call(o)) < ALL, "stomp %d" % i)
	# Pieces hit what they should: a rook its row and column, a knight its L-jumps and its own square
	eq(_count_unique(Rules.rook_cells({"c": 0, "r": 3})), Rules.COLS + Rules.ROWS - 1)
	ok(Rules.knight_cells({"c": 3, "r": 3}).has(Rules.idx(4, 5)) and Rules.knight_cells({"c": 3, "r": 3}).has(Rules.idx(3, 3)))
	ok(Rules.bishop_cells({"c": 0, "r": 0}).has(Rules.idx(6, 6)))
	ok(not Rules.in_box(-1, 0) and not Rules.in_box(Rules.COLS, 0) and Rules.in_box(0, Rules.ROWS - 1))


func test_wherever_the_lantern_swings_some_pillars_shadow_is_there_to_hide_in():
	var blocked := {}
	for k in Rules.PILLARS:
		blocked[k] = true
	for intensity in [0.8, 1.0, 1.4, 1.8]:
		for step in 201:
			var ms := step * 40.0
			var L := Rules.lantern_at(ms, intensity)
			var hide := 0
			for r in Rules.ROWS:
				for c in Rules.COLS:
					if not blocked.has(Rules.idx(c, r)) and Rules.shaded(L, c, r, blocked):
						hide += 1
			ok(hide > 0, "no shadow at %d ms, intensity %s" % [ms, intensity])
