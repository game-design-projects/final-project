## Pins the numbers of the rules to what the game before the rewrite did (Genre Halls at 0.5.3, commit 017b551): the strike bands
## and damage, the champion's scale, a monster's mood after a hit, the squares each chess piece lights, the bounds of the odds, what
## the local mind answers for a few fixed monsters, how typed words are read (six "!" are one cue, not two), and what a monster lets
## slip when asked. The expected values were dumped from the old code, so a change here is a change of the rules, on purpose or not.
## Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/rules_test.gd
extends "res://tools/test_base.gd"

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const Hints = preload("res://src/rules/hints.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Monster = preload("res://src/rules/monster.gd")
const Odds = preload("res://src/rules/odds.gd")
const Rng = preload("res://src/utils/rng.gd")
const Words = preload("res://src/mind/words.gd")

const EPS := 0.00001


func _name() -> String:
	return "rules_test"


func _run() -> void:
	_strike_bands()
	_mood_after_a_hit()
	_dodge_cells()
	_odds_bounds()
	_local_mind_numbers()
	_word_reading()
	_hints()
	_finish()


func _near(a: float, b: float, what: String) -> void:
	_check(absf(a - b) <= EPS, "%s (%.6f, expected %.6f)" % [what, a, b])


# ---------------------------------------------------------------- the strike

## x is how far along the bar the line was; off is its distance from the middle, 0..1. Past 0.92 is a miss, under 0.08 a perfect
## strike (14, a champion takes 0.8 of it), else 4 + 8 * (1 - off)^1.2, rounded. The dragon's charm adds 4 to every hit.
func _strike_bands() -> void:
	# x: [plain damage, champion damage, plain with the dragon's charm, champion with it]; null is a miss
	var table := {
		0.0: null, 0.03: null, 0.97: null, 1.0: null,
		0.05: [5, 4, 9, 8], 0.1: [5, 4, 9, 8], 0.2: [7, 5, 11, 9], 0.3: [8, 7, 12, 11], 0.7: [8, 7, 12, 11], 0.95: [5, 4, 9, 8],
		0.5: [14, 11, 18, 15], 0.47: [14, 11, 18, 15], 0.53: [14, 11, 18, 15],
	}
	for x in table:
		var plain := Combat.strike(x, false, false)
		if table[x] == null:
			_check(plain.miss and not plain.crit and plain.damage == 0, "x %.2f is a miss" % x)
			continue
		var want: Array = table[x]
		_check(not plain.miss and plain.crit == (want[0] == 14) and plain.damage == want[0], "x %.2f hits for %d" % [x, want[0]])
		_check(Combat.strike(x, true, false).damage == want[1], "x %.2f hits a champion for %d" % [x, want[1]])
		_check(Combat.strike(x, false, true).damage == want[2], "x %.2f with the dragon's charm hits for %d" % [x, want[2]])
		_check(Combat.strike(x, true, true).damage == want[3], "x %.2f with the charm hits a champion for %d" % [x, want[3]])
	_check(Combat.bar_ms(false) == 1100.0 and Combat.bar_ms(true) == 1500.0, "the strike bar sweeps in 1100 ms, 1500 with the rock's charm")
	_check(Combat.dodge_intensity(0.0, false) == 0.8 and is_equal_approx(Combat.dodge_intensity(3.0, true), 1.55 * 1.2), "dodge intensity is 0.8 + 0.25 * pressure, 1.2 times that for a champion")
	_check(Combat.DODGE_DAMAGE == 3 and Combat.DODGE_DAMAGE_BOSS == 4 and Combat.START_HP == 20 and Combat.START_GOLD == 8 and Combat.CUT_COST == 6, "a dodge hit costs 3 (4 from a champion); you start with 20 health and 8 gold; a cut costs 6")


func _mood_after_a_hit() -> void:
	var m = _monster("slime", ["lonely", "sleepy"], 58.0, 0.0, 20.0)
	Combat.apply_hit_to_mood(m)
	_check(m.meters.friendliness == 50.0 and m.meters.anger == 10.0 and m.meters.fear == 28.0, "a hit takes 8 off friendliness and puts 10 on anger and 8 on fear")
	for i in 20:
		Combat.apply_hit_to_mood(m)
	_check(m.meters.friendliness == 0.0 and m.meters.anger == 100.0 and m.meters.fear == 100.0, "the meters stay within 0..100")


# ---------------------------------------------------------------- the dodge box

func _dodge_cells() -> void:
	# the squares each piece lights from a square, as sets (old code: genre_rules rook_cells, bishop_cells, knight_cells)
	var want := {
		Vector2i(3, 3): {"rook": 13, "bishop": 13, "knight": 9},
		Vector2i(0, 0): {"rook": 13, "bishop": 7, "knight": 3},
		Vector2i(6, 2): {"rook": 13, "bishop": 7, "knight": 5},
	}
	for at in want:
		_check(_unique(Dodge.rook_cells(at)).size() == want[at].rook, "a rook on %s lights %d squares" % [at, want[at].rook])
		_check(_unique(Dodge.bishop_cells(at)).size() == want[at].bishop, "a bishop on %s lights %d squares" % [at, want[at].bishop])
		_check(_unique(Dodge.knight_cells(at)).size() == want[at].knight, "a knight on %s lights %d squares" % [at, want[at].knight])
	_check(_unique(Dodge.rook_cells(Vector2i(6, 2))) == [6, 13, 14, 15, 16, 17, 18, 19, 20, 27, 34, 41, 48], "the rook on (6, 2) lights row 2 and column 6")
	_check(_unique(Dodge.bishop_cells(Vector2i(6, 2))) == [4, 12, 20, 26, 32, 38, 44], "the bishop on (6, 2) lights its two diagonals")
	_check(_unique(Dodge.knight_cells(Vector2i(6, 2))) == [5, 11, 20, 25, 33], "the knight on (6, 2) lights its jumps and its own square")
	_check(_unique(Dodge.bishop_cells(Vector2i(0, 0))).has(Dodge.index(6, 6)) and _unique(Dodge.knight_cells(Vector2i(3, 3))).has(Dodge.index(4, 5)), "a bishop reaches the far corner and a knight jumps one over, two down")
	var every := Dodge.COLS * Dodge.ROWS
	var safe := true
	for r in Dodge.ROWS:
		for c in Dodge.COLS:
			for cells in [Dodge.rook_cells(Vector2i(c, r)), Dodge.bishop_cells(Vector2i(c, r)), Dodge.knight_cells(Vector2i(c, r))]:
				safe = safe and _unique(cells).size() < every
			for n in Dodge.stomp_count():
				safe = safe and _unique(Dodge.stomp_cells(n, Vector2i(c, r))).size() < every
	_check(safe, "every piece and every stomp leaves a safe square wherever you stand")
	_check(Dodge.COLS == 7 and Dodge.ROWS == 7 and Dodge.stomp_count() == 9 and Dodge.PILLARS.size() == 3, "the box is 7 by 7, nine stomps and three pillars")


func _unique(cells: Array) -> Array:
	var seen := {}
	for c in cells:
		seen[c] = true
	var out := seen.keys()
	out.sort()
	return out


# ---------------------------------------------------------------- odds and the local mind

func _odds_bounds() -> void:
	var angry = _monster("bandit", ["proud", "jumpy"], 20.0, 60.0, 10.0)
	var remembers = _monster("rock", ["remembers everything"], 40.0, 5.0, 0.0)
	_near(Odds.cut_odds(angry), 0.12, "a bandit that is angry, proud and jumpy still takes a cut 12% of the time, never less")
	_near(Odds.reveal_odds(angry), 0.12, "a jumpy one answers a question 12% of the time, never less")
	_near(Odds.reveal_odds(remembers), 0.88, "one that remembers everything answers 88% of the time, never more")
	var probs := {"a": 0.8, "b": 0.14, "c": 0.06}
	var dice = load("res://src/utils/dice.gd").new(Rng.new(5))
	var only_a := true
	for i in 200:
		only_a = only_a and Odds.pick_by_odds(dice, probs) == "a"
	_check(Odds.POSSIBLE == 0.15 and only_a, "an answer under 15% never happens when a likelier one exists")
	_check(Odds.top({"x": 0.1, "y": 0.7, "z": 0.2}) == "y" and Odds.top({}) == "", "the top of a spread is its likeliest, of nothing ''")


func _local_mind_numbers() -> void:
	var mind := LocalMind.new()
	var calm = _monster("slime", ["lonely", "sleepy"], 58.0, 0.0, 20.0)
	_near(mind.mercy(calm), 0.523316, "a lonely slime at 58 friendliness accepts mercy at 52%")
	_near(mind.join(calm), 0.702063, "and joins at 70%")
	_near(mind.pressure(calm), 0.266667, "and presses the next dodge at 0.27 of 3")
	_near(Odds.cut_odds(calm), 0.663106, "and takes a cut at 66%")
	_near(Odds.reveal_odds(calm), 0.769236, "it answers a question at 77%")
	var hit: Dictionary = mind.feeling_when_hit(calm)
	_near(hit.sad, 0.205296, "hit, it is sad first (21%)")
	_near(hit.terrified, 0.18576, "then terrified")
	var kind: Dictionary = mind.feeling_when_told(calm, [{"intent": "kindness", "w": 1.0}])
	_near(kind.touched, 0.683278, "told something kind, it is touched (68%)")
	var angry = _monster("bandit", ["proud", "jumpy"], 20.0, 60.0, 10.0)
	_near(mind.mercy(angry), 0.001108, "an angry bandit all but never accepts mercy")
	_near(mind.pressure(angry), 3.0, "and presses at the top of the scale")
	var gold: Dictionary = mind.feeling_when_told(angry, [{"intent": "gold", "w": 1.0}])
	_near(gold.delighted, 0.297288, "offered gold, a bandit is delighted or intrigued (30% each)")
	var scared = _monster("snake", ["secretive", "vain about its scales"], 30.0, 10.0, 60.0, 0.2, "kindness")
	_near(mind.mercy(scared), 0.053826, "a snake low on health and afraid is only a little likelier to accept mercy")
	_near(mind.feeling_when_hit(scared).terrified, 0.81446, "and hit, it is terrified")
	_near(mind.feeling_when_told(scared, [{"intent": "gold", "w": 1.0}]).offended, 0.458932, "gold offends a secretive snake")
	var dragon = _monster("dragon", ["proud"], 10.0, 30.0, 10.0)
	_near(mind.pressure(dragon), 2.4, "the dragon presses at 2.4")
	_near(mind.join(dragon), 0.000052, "and all but never joins")


# ---------------------------------------------------------------- typed words

func _word_reading() -> void:
	var mind := LocalMind.new()
	var reads := {
		"you are so beautiful and strong": "flattery", "I can offer gold, a fair share of the loot": "gold", "where are the stairs?": "question",
		"snake weakness": "question", "asdfgh qwrtzp": "gibberish", "knock knock, a joke for you": "joke", "hello friend": "kindness", "": "gibberish",
	}
	for text in reads:
		_check(Odds.top(mind.read_words(text)) == reads[text], "'%s' reads as %s" % [text, reads[text]])
	_check(Words.gibberish_odds("hello friend") < 0.2, "two plain words are not nonsense")
	var sum := 0.0
	for p in Words.read("knock knock, a joke for you").values():
		sum += p
	_near(sum, 1.0, "what a line may mean adds up to 1")
	# six "!" are one cue (`!{3,}`), not two: the old game read this at 26% noise, not at the cap's 2 x
	_check(Words.cue_counts("hello!!!!!!").noise == 1, "six exclamation marks are one noise cue, not two")
	_check(Words.cue_counts("stop!!! stop!!! stop!!!").noise == 3 and Words.cue_counts("hey!! hey").noise == 0, "three in a row make a cue; two do not")
	_near(Words.read("hello!!!!!!").noise, 0.259251, "six '!' read as 26% noise")
	_near(Words.read("stop!!! stop!!! stop!!!").noise, 0.381243, "three separate shouts read as 38% noise")
	_check(Odds.top(Words.read("hello!!!!!!")) == "noise", "and noise is what 'hello!!!!!!' means")
	_check(Words.mentions_money("I can pay a coin") and not Words.mentions_money("a fair deal") and not Words.mentions_money("hello"), "only gold, coins, pay and money make a line a paid truce")
	_near(Words.gibberish_odds("AAAAAAAA"), 0.97, "a row of one letter is 97% nonsense")
	_near(Words.gibberish_odds(""), 0.95, "nothing at all is 95% nonsense")


# ---------------------------------------------------------------- what a monster lets slip

func _hints() -> void:
	var enc := Content.table("encounter")
	var asker = _monster("slime", ["curious"], 50.0, 0.0, 0.0)
	var rook = _monster("bandit", ["proud"], 40.0, 0.0, 0.0)
	rook.name = "ROOK"
	rook.gone = "spared"
	var vex = _monster("bandit", ["jumpy"], 40.0, 0.0, 0.0)
	vex.name = "VEX"
	var snake = _monster("snake", ["secretive"], 40.0, 0.0, 0.0)
	snake.name = "SSIL"
	var boss = Monster.given({"species": enc.boss.species, "genre": enc.boss.genres[0], "hp": enc.boss.hp, "boss": true}, Vector2i.ZERO, enc.boss.name, ["proud"], {"friendliness": 0.0, "anger": 0.0, "fear": 0.0})
	var f = FloorGen.generate(Rng.new(3))
	f.monsters = [asker, rook, vex, snake, boss]
	var at: Vector2i = f.start
	_check(Hints.answer(f, at, asker, "What does bandit VEX want?").contains("VEX") and not Hints.answer(f, at, asker, "What does bandit VEX want?").contains("gone"), "asked what bandit VEX wants, it names VEX")
	_check(Hints.answer(f, at, asker, "What does the bandit want?").contains("which bandit"), "'the bandit' with two of them asks which")
	_check(Hints.answer(f, at, asker, "ROOK or VEX?").contains("which monster"), "two names ask which monster")
	_check(Hints.answer(f, at, asker, "Where are the stairs or the champion?").contains("one at a time"), "the stairs and the champion are asked one at a time")
	_check(Hints.answer(f, at, asker, "Where are the stairs or the bandit?").contains("one thing at a time"), "so are the stairs and a monster")
	_check(Hints.answer(f, at, asker, "Where is VEX?").contains("ask what VEX wants"), "'where is VEX?' is sent to ask what it wants")
	_check(Hints.answer(f, at, asker, "Are the stairs dangerous?").contains("ask which way"), "the stairs without a where are sent to ask which way")
	_check(Hints.answer(f, at, asker, "What does the champion want?").contains("opening genres"), "the champion is asked about its opening genres")
	_check(Hints.answer(f, at, asker, "What is the champion's opening?").contains("chess"), "its opening starts with chess")
	_check(Hints.answer(f, at, asker, "What does ROOK want?").contains("gone"), "a monster that has gone is said to be gone")
	_check(Hints.answer(f, at, asker, "Who are you?").contains("ask me about the stairs, the champion, or another monster"), "anything else is sent back to the three topics")
	_check(Hints.answer(f, at, asker, "what do I look like").contains("ask me about") , "a question about nothing is sent back too")
	snake.taste = {"flattery": 20.0, "rush": -20.0}
	var one: String = Hints.answer(f, at, asker, "what does the snake want?")
	_check(one.contains("SSIL") and one.contains("being rushed"), "the tip uses the asked monster's own taste (%s)" % one)
	snake.taste = {"flattery": -20.0, "rush": 20.0}
	_check(Hints.answer(f, at, asker, "what does the snake want?").contains("praise"), "and follows it when it changes")
	var step: String = Hints.first_step_toward(f, at, f.stairs)
	var dir: Vector2i = f.DIRS[Hints.COMPASS.find(step)]
	_check(f.is_open(at + dir) and _steps(f, at + dir, f.stairs) < _steps(f, at, f.stairs), "the stairs hint's first step is open and comes closer by the maze route (%s)" % step)
	_check(Hints.answer(f, at, asker, "Where are the stairs?").contains("corridor %s toward the stairs" % step), "'where are the stairs?' says that corridor")
	_check(Hints.answer(f, f.stairs, asker, "stairs").contains("standing on the stairs"), "on the stairs it says so")


## Steps from `a` to `b` through open cells (-1 when there is no way).
func _steps(f, a: Vector2i, b: Vector2i) -> int:
	var dist := {a: 0}
	var queue: Array = [a]
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		if at == b:
			return dist[at]
		for d in f.DIRS:
			var n: Vector2i = at + d
			if f.is_open(n) and not dist.has(n):
				dist[n] = dist[at] + 1
				queue.append(n)
	return -1


## A monster with a given personality, the way the old tests made one: a species, two traits, the meters, how much health is left,
## and what was last done to it.
func _monster(species: String, traits: Array, friendliness: float, anger: float, fear: float, hp_fraction := 1.0, last := ""):
	var entry := {"species": species, "genre": "bullet", "hp": 30}
	var m = Monster.given(entry, Vector2i.ZERO, species.to_upper(), traits, {"friendliness": friendliness, "anger": anger, "fear": fear})
	m.hp = int(30 * hp_fraction)
	m.last_intent = last
	return m
