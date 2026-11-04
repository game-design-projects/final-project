## Checks the personality slice (flag `personality-slice`) with no window: the fixed fights, what ends the slice, the
## retry, the autosave rule, the seed and the mind. Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/slice_test.gd
extends "res://tools/test_base.gd"

const Allies = preload("res://src/rules/allies.gd")
const Content = preload("res://src/rules/content.gd")
const Dice = preload("res://src/utils/dice.gd")
const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Minds = preload("res://src/mind/minds.gd")
const Monster = preload("res://src/rules/monster.gd")
const Odds = preload("res://src/rules/odds.gd")
const PersonalitySlice = preload("res://src/game/personality_slice.gd")
const Rng = preload("res://src/utils/rng.gd")
const Texts = preload("res://src/game/texts.gd")
const Transitions = preload("res://src/game/transitions.gd")


var _clock := 0.0


func _name() -> String:
	return "slice_test"


func _run() -> void:
	await _random_seed_repeats()
	await _seed_flag()
	await _bad_seed_everywhere()
	await _pending_flag()
	await _mind_is_pinned()
	await _fair_cut_route()
	await _names_do_not_matter()
	await _allies_are_fixed()
	await _flee_judges_before_it_ends()
	_dice_pin()
	await _slice_needs_its_roll()
	_comment_stripper()
	_scan_patterns()
	_no_draw_around_the_dice()
	_seed_offset()
	await _retry_heals()
	await _flee_ends_it()
	_finish()


## A dice that refuses every roll, as if ROLL were not one.
class RefusingDice:
	extends "res://src/utils/dice.gd"

	func pin(_roll: float) -> bool:
		return false


## If the fixed roll cannot be pinned the slice does not start, rather than running with random chances.
func _slice_needs_its_roll() -> void:
	Flags.set_args(PackedStringArray(["personality-slice", "seed=7042"]))
	var rng := Rng.new(7042)
	var flow = Flow.new(rng, Minds.create(rng, "", true))
	await flow.new_run()
	flow.dice = RefusingDice.new(rng)
	print("slice_test: (the ERROR line that follows is the refusal under test)")
	await PersonalitySlice.start(flow)
	_check(not flow.slice_floor and flow.slice_queue.is_empty() and flow.state.stage == "explore", "a slice whose roll cannot be pinned does not start: the run stays an ordinary one")


## A slice on a fresh run: the flow, and ROOK's intro already over, at his menu.
func _start(seed_value := 7042):
	Flags.set_args(PackedStringArray(["personality-slice", "seed=%d" % seed_value]))
	var rng := Rng.new(PersonalitySlice.seed_value())
	var flow = Flow.new(rng, Minds.create(rng, "", true))
	await flow.new_run()
	await PersonalitySlice.start(flow)
	await _to_menu(flow)
	return flow


func _to_menu(flow) -> void:
	for i in 100:
		if flow.state.stage == "menu":
			return
		_clock += 100.0
		await flow.tick(_clock)


func _press(flow, keys: Array) -> void:
	for k in keys:
		await flow.press(str(k))


## The seed a random run prints must be one `seed=N` accepts again (not negative) and must replay the same numbers.
func _random_seed_repeats() -> void:
	var printable := true
	var repeats := true
	for i in 64:
		Flags.set_args(PackedStringArray([])) # without the previous round's seed, or every round would replay the first
		var first := Rng.new()
		Flags.set_args(PackedStringArray(["seed=%d" % first.seed_value])) # what a player does with the printed seed
		var again := Rng.new()
		printable = printable and first.seed_value >= 0 and Rng.flag_seed() == first.seed_value
		repeats = repeats and again.seed_value == first.seed_value and again.real() == first.real()
	Flags.set_args(PackedStringArray([]))
	_check(printable, "every seed a random run prints is one the `seed=N` flag takes back (non-negative, any length)")
	_check(repeats, "a random run's printed seed replays the same run through the flag")


## One rule for the seed flag in every place that reads it: a whole number of 0 or more, else the fallback.
func _bad_seed_everywhere() -> void:
	Flags.set_args(PackedStringArray(["seed=9"]))
	_check(Rng.new().seed_value == 9, "the Rng takes seed=9")
	Flags.set_args(PackedStringArray(["seed=abc"]))
	_check(Rng.new().seed_value >= 0, "the Rng does not turn seed=abc into a made-up seed 0 silently")
	var a := Rng.new()
	var b := Rng.new()
	_check(a.seed_value != b.seed_value, "seed=abc gives a random seed (two runs differ), as the warning says")
	Flags.set_args(PackedStringArray(["seed=-5"]))
	_check(Rng.new().seed_value >= 0, "seed=-5 gives a random, printable seed")
	for bare in [["seed"], ["seed="]]:
		Flags.set_args(PackedStringArray(bare))
		_check(Rng.flag_seed() == -1, "%s with no number is not a seed" % bare[0])
		_check(PersonalitySlice.seed_value() == PersonalitySlice.DEFAULT_SEED, "%s with no number gives the slice its default seed" % bare[0])
		_check(Rng.new().seed_value != Rng.new().seed_value, "%s with no number gives the game a random seed" % bare[0])
	for big in ["99999999999999999999", "9223372036854775808"]:
		Flags.set_args(PackedStringArray(["seed=" + big]))
		_check(Rng.flag_seed() == -1, "seed=%s is out of range, so it is ignored (not clamped or wrapped)" % big)
	for edge in [["9223372036854775807", 9223372036854775807], ["999999999999999999", 999999999999999999], ["0000000000000000000005", 5], ["0", 0], ["-0", 0]]:
		Flags.set_args(PackedStringArray(["seed=" + edge[0]]))
		_check(Rng.flag_seed() == edge[1], "seed=%s is a seed and is kept as it is" % edge[0])
	Flags.set_args(PackedStringArray([]))


func _seed_flag() -> void:
	Flags.set_args(PackedStringArray([]))
	_check(PersonalitySlice.seed_value() == PersonalitySlice.DEFAULT_SEED, "no seed flag gives the documented seed")
	Flags.set_args(PackedStringArray(["seed=9"]))
	_check(PersonalitySlice.seed_value() == 9, "seed=9 is used")
	Flags.set_args(PackedStringArray(["seed=-5"]))
	_check(PersonalitySlice.seed_value() == PersonalitySlice.DEFAULT_SEED, "a negative seed falls back to the documented one, not to random")
	Flags.set_args(PackedStringArray(["seed=abc"]))
	_check(PersonalitySlice.seed_value() == PersonalitySlice.DEFAULT_SEED, "a seed that is not a number falls back to the documented one")


func _pending_flag() -> void:
	PersonalitySlice.reset() # whatever ran before, the flag has not been used yet
	Flags.set_args(PackedStringArray(["personality-slice"]))
	_check(PersonalitySlice.pending(), "the flag is pending before the slice starts")
	var flow = await _start()
	_check(not PersonalitySlice.pending(), "the flag has been used once the slice started, so the menu comes back after leaving")
	Flags.set_args(PackedStringArray([]))
	_check(not PersonalitySlice.pending(), "no flag, nothing pending")
	_check(flow.state.floor_map.monsters[0].name == "ROOK" and flow.state.floor_map.monsters[1].name == "VEX", "ROOK and VEX are the first two monsters")
	var vex = flow.state.floor_map.monsters[1]
	for foe in PersonalitySlice.FOES:
		_check(Content.table("taste").motives.has(foe.trait), "%s's trait is one the game knows a motive for" % foe.name)
	_check(not vex.clues().is_empty(), "VEX shows at least one clue for his trait")
	var floor_bandit = Monster.make(Rng.new(3), PersonalitySlice.bandit(), Vector2i.ZERO)
	_check(vex.species == floor_bandit.species and vex.genre == floor_bandit.genre and vex.max_hp == floor_bandit.max_hp and vex.threshold == floor_bandit.threshold, "a slice bandit is built like a floor bandit (same roster line)")
	var taste_vex = Monster.given(PersonalitySlice.bandit(), Vector2i.ZERO, "VEX", ["jumpy"], vex.meters)
	_check(taste_vex.taste == vex.taste, "a monster given its traits gets the taste those traits shift, no random part")


func _mind_is_pinned() -> void:
	var rng := Rng.new(1)
	Flags.set_args(PackedStringArray([]))
	var mind = Minds.create(rng, "https://example.invalid", true)
	_check(mind.get_script() == LocalMind, "the slice thinks with the local rules even when a Jev address is saved")
	Flags.set_args(PackedStringArray(["mock"]))
	_check(Minds.create(rng, "", true).get_script() == LocalMind, "the slice thinks with the local rules even with the mock flag")
	_check(Minds.create(rng, "", false).get_script() != LocalMind, "an ordinary game still takes the mock mind")
	Flags.set_args(PackedStringArray([]))


func _fair_cut_route() -> void:
	_check(not Transitions.stages().has("result"), "a fight ends in the log and back to walking: there is no separate result stage")
	var flow = await _start()
	var s = flow.state
	var vex = s.floor_map.monsters[1]
	_check(s.gold == 12 and s.foe.name == "ROOK", "starts with 12 gold against ROOK")
	_check(not flow.autosave_allowed(), "the slice floor may not be autosaved from the first fight on")
	var rook = s.foe
	await _press(flow, [2, 2])
	_check(s.gold == 6 and rook.gone == "spared", "ROOK takes the 6-gold cut and leaves")
	_check(s.stage == "intro" and s.foe == vex, "VEX comes on at once: no CONTINUE screen between the fights")
	_check(s.lines.any(func(l): return l.text == Texts.cut_accepted(rook)), "ROOK's goodbye is still in the log when VEX's fight starts")
	await _to_menu(flow)
	await _press(flow, [2, 2])
	_check(s.gold == 6 and vex.gone == "" and s.stage == "menu", "VEX refuses the cut: the gold stays, he stays, and the menu is back (no attack follows)")
	await _press(flow, [3])
	_check(vex.gone == "spared" and s.allies.size() == 1, "sparing VEX recruits him")
	_check(s.stage == "explore" and not flow.dice.is_pinned() and flow.slice_queue.is_empty(), "the slice is over and the floor is ordinary again, back to walking with no CONTINUE screen")
	_check(s.lines.any(func(l): return l.kind == "sys" and l.text.contains("joins you")), "the log says VEX joined")
	_check(flow.slice_floor and not flow.autosave_allowed(), "the floor stays marked as the playtest floor, so it is never autosaved")
	await flow.new_run()
	_check(not flow.slice_floor and flow.autosave_allowed(), "a new floor is an ordinary one and may be autosaved")


## A monster of the floor that happens to share the next bandit's name must not be taken for him.
func _names_do_not_matter() -> void:
	var flow = await _start()
	var s = flow.state
	var vex = s.floor_map.monsters[1]
	var twin = s.floor_map.monsters[2]
	twin.name = "VEX"
	s.floor_map.monsters[1] = twin
	s.floor_map.monsters[2] = vex
	await _press(flow, [2, 2, 1])
	_check(s.stage == "intro" and s.foe == vex, "the second fight is the slice's VEX even if another monster is called VEX")


## A slice flow with ROOK sent off and VEX spared and recruited, back in the explore stage.
func _with_recruit(seed_value: int):
	var flow = await _start(seed_value)
	await _press(flow, [2, 2]) # ROOK takes the cut and leaves; on to VEX
	await _to_menu(flow)
	await _press(flow, [3]) # VEX is spared and joins: the slice is over, back to walking
	return flow


## An ally's verdict on a deed, whether it leaves and a recruit's starting loyalty are drawn at the fixed roll too, so the
## same actions leave the ally in the same mood for every seed: after sparing, and with loyalty low enough for the leaving
## roll to be drawn. (Fleeing is `_flee_judges_before_it_ends`.)
func _allies_are_fixed() -> void:
	var after_spare := {}
	var after_low := {}
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]:
		var flow = await _with_recruit(seed_value)
		var s = flow.state
		var ally = s.allies[0]
		after_spare[ally.loyalty] = true
		flow.dice.pin(PersonalitySlice.ROLL) # as if the slice were still going
		ally.loyalty = 35.0 # a verdict that lowers it goes under the line, so the leaving roll is drawn
		flow.encounter.judge("spare")
		after_low["%s/%s" % [ally.loyalty, s.allies.size()]] = true
	_check(after_spare.size() == 1, "a recruit's starting loyalty is the same for every seed (%s)" % [after_spare.keys()])
	_check(after_low.size() == 1, "whether a low-loyalty ally leaves, and its loyalty after the verdict, are the same for every seed (%s)" % [after_low.keys()])


## Fleeing judges the deed while the roll is still fixed, and only then ends the slice.
func _flee_judges_before_it_ends() -> void:
	var seen := {}
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var flow = await _with_recruit(seed_value)
		var s = flow.state
		flow.dice.pin(PersonalitySlice.ROLL)
		var foe = s.floor_map.monsters[2]
		await flow.go("intro", {"foe": foe})
		await _to_menu(flow)
		await _press(flow, [4]) # FLEE
		if seed_value == 1:
			_check(not flow.dice.is_pinned(), "fleeing from the third fight ends the slice")
		seen[s.allies[0].loyalty if not s.allies.is_empty() else -1.0] = true
	_check(seen.size() == 1, "after a real flee from a fight the ally's loyalty is the same for every seed (%s)" % [seen.keys()])


func _retry_heals() -> void:
	var flow = await _start()
	var s = flow.state
	s.hp = 0 # the fight was lost
	s.stage = "dead"
	await flow.encounter.retry_fight()
	_check(s.hp == s.max_hp, "trying a fight again starts at full health, so a lost fight cannot loop")
	_check(flow.slice_queue.size() == 1 and flow.dice.is_pinned(), "a retry keeps the slice going")


func _flee_ends_it() -> void:
	var flow = await _start()
	await _press(flow, [4])
	_check(not flow.dice.is_pinned() and flow.slice_queue.is_empty(), "fleeing ends the slice")


## A pinned Dice gives the same draw every time, so the same odds give the same outcome; an unpinned one does not.
func _dice_pin() -> void:
	var dice := Dice.new(Rng.new(5))
	dice.pin(0.5)
	_check(dice.is_pinned() and Odds.succeeds(dice, 0.6) and not Odds.succeeds(dice, 0.4), "a pinned dice draws 0.5 every time: 60% succeeds, 40% does not")
	var odds := {"a": 0.5, "b": 0.5}
	dice.pin(0.1)
	var low := Odds.pick_by_odds(dice, odds)
	dice.pin(0.9)
	_check(low != Odds.pick_by_odds(dice, odds), "pinned low and pinned high pick different keys, and each is repeatable")
	dice.unpin()
	var varied := {}
	for i in 32:
		varied[Allies.start_loyalty(dice)] = true
	_check(not dice.is_pinned() and varied.size() > 1, "an unpinned dice follows the generator (loyalty varies)")
	dice.pin(0.0)
	_check(Allies.start_loyalty(dice) == float(Allies.START_LOYALTY_MIN), "the lowest draw gives the lowest starting loyalty")
	dice.pin(Rng.BELOW_ONE)
	_check(Allies.start_loyalty(dice) == float(Allies.START_LOYALTY_MAX), "the highest draw gives the highest starting loyalty")
	dice.pin(0.25)
	print("slice_test: (the four ERROR lines that follow are the refusals under test)")
	var refused_all := true
	for refused in [1.0, 2.0, -1.0, NAN]: # not rolls: the dice stays as it was (the old -1 means unpinned idiom must not pin it at 0)
		refused_all = refused_all and not dice.pin(refused)
	_check(refused_all and dice.is_pinned() and dice.real() == 0.25, "a roll outside 0 to below 1 (or NaN) is refused and the pin stays")
	var inside := true
	dice.unpin()
	for i in 2000:
		var l := Allies.start_loyalty(dice)
		inside = inside and l >= Allies.START_LOYALTY_MIN and l <= Allies.START_LOYALTY_MAX
	_check(inside, "a recruit's loyalty always lies inside its range")


## What a line of code may not do. Interaction chances are drawn through the Flow's dice, which the typed parameters of Odds
## and Allies already insist on; this catches the other way round: a Dice made anywhere but the Flow, a chance rolled
## straight from `flow.rng`, and (in the game's own scripts) a copy of the Flow's rng kept under another name. It cannot
## see `flow.rng` handed on as an argument.
func _offences(path: String, code: String) -> Array:
	var out := []
	if RegEx.create_from_string("Dice\\.new\\s*\\(").search(code) != null:
		out.append("a Dice made outside the flow")
	if RegEx.create_from_string("flow\\.rng\\.(chance|real)\\s*\\(").search(code) != null:
		out.append("a chance from flow.rng")
	if RegEx.create_from_string("=\\s*flow\\.rng\\s*$").search(code) != null:
		out.append("a copy of flow.rng")
	if path.begins_with("res://src/game/") and RegEx.create_from_string("=\\s*rng\\s*$").search(code) != null:
		out.append("a copy of the game's rng")
	return out


func _scan_patterns() -> void:
	var game := "res://src/game/stages/x.gd"
	_check(_offences(game, "var r = rng") == ["a copy of the game's rng"], "the scan catches a bare copy of rng in the game's scripts")
	_check(_offences(game, "\t_rng = rng") == ["a copy of the game's rng"], "and one kept in a member")
	_check(_offences(game, "var r = flow.rng") == ["a copy of flow.rng"], "and a copy of flow.rng")
	_check(_offences(game, "if flow.rng.chance(0.5):") == ["a chance from flow.rng"], "and a chance drawn from it")
	_check(_offences(game, "var d = Dice.new(rng)") == ["a Dice made outside the flow"], "and a second Dice")
	_check(_offences("res://src/rules/floor_gen.gd", "var r = rng").is_empty(), "but a generator outside src/game may name its parameter rng")
	_check(_offences(game, "var r = Rng.new(5)").is_empty(), "and a fresh Rng of its own is not a copy")


## Reads every script under src (comments left out) for what `_offences` lists.
func _no_draw_around_the_dice() -> void:
	var offenders := []
	var stack := ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for sub_dir in DirAccess.get_directories_at(dir):
			stack.append("%s/%s" % [dir, sub_dir])
		for file in DirAccess.get_files_at(dir):
			var path := "%s/%s" % [dir, file]
			if not file.ends_with(".gd") or path == "res://src/game/flow.gd": # the flow makes the dice
				continue
			var found := {}
			for line in FileAccess.get_file_as_string(path).split("\n"):
				var code := _without_comment(line) if line.contains("#") else line
				for what in _offences(path, code):
					if not found.has(what):
						found[what] = true
						offenders.append("%s: %s" % [path, what])
	_check(offenders.is_empty(), "no script under src draws an interaction chance around the flow's dice (%s)" % [offenders])


## The line without a trailing `#` comment (a `#` inside a string stays, and so does a quote escaped with a backslash).
func _without_comment(line: String) -> String:
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				i += 1 # the next character is escaped
			elif c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.left(i)
		i += 1
	return line


## The comment stripper reads strings the way the scan needs: a `#` in a string stays, a string ending in a backslash ends.
func _comment_stripper() -> void:
	_check(_without_comment("var a = 1 # Dice.new(") == "var a = 1 ", "a trailing comment is cut off")
	_check(_without_comment("print(\"#%d\")") == "print(\"#%d\")", "a # inside a string is not a comment")
	_check(_without_comment("var q = \"say \\\" # not a comment\"") == "var q = \"say \\\" # not a comment\"", "an escaped quote does not end the string, so a # after it is still inside it")
	_check(_without_comment("var p = \"C:\\\\\" # Dice.new(x)") == "var p = \"C:\\\\\" ", "a string that ends in an escaped backslash ends, so the comment after it is cut")


## A seed derived from another wraps past the largest seed and stays one the flag takes back.
func _seed_offset() -> void:
	_check(Rng.offset(7, 1000) == 1007, "an offset of a small seed is plain addition")
	var wrapped := Rng.offset(Rng.MAX_SEED, 1000)
	_check(wrapped >= 0 and wrapped == 999, "an offset past the largest seed wraps to a non-negative seed (%d)" % wrapped)
	_check(str(Rng.MAX_SEED) == Rng.INT64_MAX_TEXT, "the text the flag is compared with is the largest seed")
