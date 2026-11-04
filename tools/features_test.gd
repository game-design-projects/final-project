## Checks the features in `Flags.FEATURES` with no window: that each can be switched off, and what each does when it is on.
## Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/features_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Flags = preload("res://src/utils/flags.gd")
const Floors = preload("res://src/rules/floors.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const DodgeRun = preload("res://src/rules/dodge_run.gd")
const Flow = preload("res://src/game/flow.gd")
const Gates = preload("res://src/rules/minigames/gates.gd")
const Monster = preload("res://src/rules/monster.gd")
const Overlay = preload("res://src/view/overlay.gd")
const Pace = preload("res://src/rules/pace.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")

const BASE := ["nosave", "nosound"]


func _name() -> String:
	return "features_test"


func _run() -> void:
	_flags()
	await _real_floors()
	await _dodges()
	_finish()


## A flow on the local rules, with these flags on top of BASE.
func _flow(seed_value: int, words := []) -> Variant:
	_use(words)
	var rng := Rng.new(seed_value)
	return Flow.new(rng, LocalMind.new())


func _use(words := []) -> void:
	var all := PackedStringArray(BASE)
	all.append_array(PackedStringArray(words))
	Flags.set_args(all)


func _flags() -> void:
	_use()
	_check(Flags.FEATURES.keys().all(func(f): return Flags.enabled(f)), "every feature is on by default")
	for f in Flags.FEATURES:
		_use(["no-" + f])
		_check(not Flags.enabled(f), "no-%s turns it off" % f)
		_use([f + "=off"])
		_check(not Flags.enabled(f), "%s=off turns it off" % f)
		_use(["classic"])
		_check(not Flags.enabled(f), "classic turns %s off" % f)
		_use(["classic", f])
		_check(Flags.enabled(f), "classic %s brings it back" % f)
	_use()


## Walk the party onto the stairs, as the last step of a floor does.
func _reach_stairs(flow) -> void:
	var s = flow.state
	var stairs: Vector2i = s.floor_map.stairs
	for i in 4:
		var from: Vector2i = stairs - s.floor_map.DIRS[i]
		if s.floor_map.is_open(from):
			s.cell = from
			s.facing = i
			break
	for m in s.floor_map.monsters:
		if m.cell == stairs:
			m.gone = "slain"
	await flow.press("up")


func _real_floors() -> void:
	var flow = _flow(11)
	await flow.new_run()
	var s = flow.state
	s.hp = 5
	s.gold = 3
	s.tally.spared = 2
	var Ally = load("res://src/game/ally.gd")
	s.allies.append(Ally.make("slime", "GLOB", 70.0))
	await _reach_stairs(flow)
	_check(s.stage == "end" and not s.run_over, "the first stairs don't end the run")
	var first_floor = s.floor_map
	await flow.press("1")
	_check(flow.state == s and s.stage == "explore" and s.depth == 2, "GO DOWN goes to B2F (B%dF, %s)" % [s.depth, s.stage])
	_check(s.floor_map != first_floor and s.cell == s.floor_map.start, "on a new floor, at its start")
	_check(s.gold == 3 and s.tally.spared == 2 and s.allies.size() == 1, "gold, the tally and the party came along")
	_check(s.hp == 5 + Floors.rest_heal(), "and the way down rests you a little (%d)" % s.hp)
	_check(s.lines[0].text.begins_with("B2F"), "the log names the floor (%s)" % s.lines[0].text)
	await _reach_stairs(flow)
	await flow.press("1")
	_check(s.depth == 3, "the second stairs lead to B3F")
	var saved: Dictionary = s.to_dict()
	var loaded = State.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(loaded != null and loaded.depth == 3 and loaded.run_seed == s.run_seed, "a save keeps the depth and the run's seed")

	var again = _flow(11)
	await again.new_run()
	await _reach_stairs(again)
	await again.press("1")
	var other = _flow(11)
	await other.new_run()
	other.rng.real() # the fights drew differently
	await _reach_stairs(other)
	await other.press("1")
	_check(again.state.floor_map.grid == other.state.floor_map.grid, "the same seed makes the same B2F, whatever the fights drew")
	var deeper: int = Floors.plan(3).champion.hp
	_check(deeper > Floors.plan(1).champion.hp and Floors.plan(Floors.run_floors()).champion.name == "VEXALITH", "the champions grow up to Vexalith on the last floor")

	s = again.state
	s.depth = Floors.run_floors()
	await _reach_stairs(again)
	_check(s.stage == "end" and s.run_over, "the last floor's stairs end the run")
	var ended = s
	await again.press("1")
	_check(again.state != ended and again.state.depth == 1, "and NEW RUN starts over on B1F")

	var classic = _flow(11, ["classic"])
	await classic.new_run()
	await _reach_stairs(classic)
	_check(classic.state.stage == "end" and classic.state.run_over, "classic: the stairs end the run")
	var kept = classic.state
	await classic.press("1")
	_check(classic.state != kept and classic.state.depth == 1, "classic: NEW FLOOR starts over")
	_use()


func _dodges() -> void:
	var entry := {"species": "bandit", "genre": "chess", "hp": 24}
	var m = Monster.given(entry, Vector2i(1, 1), "TEST", ["jumpy"], {"friendliness": 10.0, "anger": 10.0, "fear": 10.0})
	var base := Pace.of(m, 1, 0.0, 0, false)
	_check(base < 1.0, "a first dodge runs slower than the classic pace (%.2f)" % base)
	_check(Pace.of(m, 4, 0.0, 0, false) > base, "deeper floors run faster")
	_check(Pace.of(m, 1, 3.0, 0, false) < base, "getting hit a lot slows it")
	_check(Pace.of(m, 1, 0.0, 2, false) < base, "allies slow it")
	_check(Pace.of(m, 1, 0.0, 0, true) < base, "EASY DODGE slows it")
	var friend = Monster.given(entry, Vector2i(1, 1), "TEST", ["jumpy"], {"friendliness": 90.0, "anger": 10.0, "fear": 10.0})
	_check(Pace.of(friend, 1, 0.0, 0, false) < base, "a friendlier foe attacks more gently")
	_check(Pace.after_dodge(2.0, 0) == 1.0 and Pace.after_dodge(1.0, 2) == 3.0, "a clean dodge eases the struggle, hits add to it")

	var run_slow = DodgeRun.start("chess", 1.0, false, 0, 0.0, {}, 0.5)
	var run_full = DodgeRun.start("chess", 1.0, false, 0, 0.0, {}, 1.0)
	var slow_rng := Rng.new(3)
	var full_rng := Rng.new(3)
	run_slow.update(400.0, slow_rng)
	run_full.update(400.0, full_rng)
	var slow_warn: float = run_slow.hazards[0].hit - run_slow.hazards[0].warn
	var full_warn: float = run_full.hazards[0].hit - run_full.hazards[0].warn
	_check(slow_warn > full_warn, "a slower dodge warns for longer (%d ms, %d ms)" % [slow_warn, full_warn])
	_check(run_full.end_t > run_slow.end_t, "and is over sooner")
	for g in ["R", "B", "N"]:
		_check(not Overlay.piece_shape(g).is_empty(), "the piece %s has a shape" % g)

	var enc: Dictionary = load("res://src/rules/content.gd").table("encounter")
	_check(enc.genres.keys().all(func(g): return DodgeRun.MINI_GAMES.has(g)), "every attack in the data has a file of its own in rules/minigames")
	_check(enc.genres.keys().all(func(g): return enc.genres[g].has("plain")), "every attack has its rule in plain words")
	var plain: String = enc.genres.chess.plain.to_lower()
	_check(not plain.contains("rook") and not plain.contains("bishop") and not plain.contains("knight"), "the chess rule needs no chess: %s" % plain)
	var rotated: Array = enc.mini_games
	m.turn = 2
	_check(Dodge.genre_on_turn(m, enc.boss.genres, rotated) in rotated, "every third attack is a mini-game")
	m.turn = 1
	_check(Dodge.genre_on_turn(m, enc.boss.genres, rotated) == "chess", "the others are its own")
	m.turn = 2
	_check(Dodge.genre_on_turn(m, enc.boss.genres, []) == "chess", "without the feature it only ever fights its own way")

	var wall = DodgeRun.start("gates", 1.0, false, 0, 0.0, {}, 1.0)
	var r := Rng.new(5)
	wall.update(400.0, r)
	_check(wall.hazards.size() == Dodge.COLS, "a wall is one hazard per column (%d)" % wall.hazards.size())
	var open_rows := 0
	for row in Dodge.ROWS:
		if not wall.hazards[0].cells.has(Dodge.index(Dodge.COLS - 1, row)):
			open_rows += 1
	_check(open_rows == Gates.GAP, "with a gap in it (%d rows)" % open_rows)
	_check(wall.hazards[1].hit > wall.hazards[0].hit, "and it comes in column by column")

	var stars = DodgeRun.start("stars", 1.0, false, 0, 0.0, {}, 1.0)
	var star_rng := Rng.new(6)
	stars.update(400.0, star_rng)
	var star: Dictionary = stars.hazards.filter(func(h): return h.kind == "star")[0]
	stars.soul = Vector2i(star.at % Dodge.COLS, floori(float(star.at) / Dodge.COLS))
	stars.hazards = [star]
	stars.next_t = 1e9
	var got: Array = stars.update(star.hit + 1.0, star_rng)
	_check(got.any(func(e): return e.type == "star"), "standing under a star catches it")
	_check(not got.any(func(e): return e.type == "hurt"), "and it doesn't hurt")
	_check(not stars.update(star.hit + 2.0, star_rng).any(func(e): return e.type == "star"), "a star is caught once")

	var flow = _flow(13)
	await flow.new_run()
	_check(flow.state.rotate_mini_games, "the run rotates mini-games in")
	var classic = _flow(13, ["no-mini-games"])
	await classic.new_run()
	_check(not classic.state.rotate_mini_games, "no-mini-games leaves them out")
	_use()
