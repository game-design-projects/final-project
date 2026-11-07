## Checks the save slots with no window, in a folder of their own: the round trip, rename, copy and delete, and that the
## `nosave` flag keeping the slots in memory, off the disk and away from the player's saves.
##   godot --headless --path . -s res://tools/saves_test.gd
extends "res://tools/test_base.gd"

const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")

var Saves = null # loaded when the test runs, like the other scripts that reach the Store autoload
var _dir := ""


func _name() -> String:
	return "saves_test"


func _run() -> void:
	Saves = load("res://src/menu/saves.gd")
	_dir = "user://saves_test_%d" % Time.get_ticks_usec()
	Saves.dir_path = _dir
	# the test deletes saves: it only goes on if its own folder is the one the slots really use
	var redirected: bool = Saves.path("1").begins_with(_dir)
	_check(redirected, "the slots live in the test's own folder, not the player's")
	if not redirected:
		_finish()
		return
	Flags.set_args(PackedStringArray([]))
	_round_trip()
	_numbers_rise()
	_nosave_in_memory()
	await _state_is_checked()
	_cleanup()
	_finish()


func _round_trip() -> void:
	_check(Saves.write("1", {"hp": 7}, "HP 7/20"), "a slot can be written")
	_check(Saves.read("1") == {"hp": 7}, "and read back as it was")
	_check(Saves.info("1").summary == "HP 7/20" and not Saves.info("1").empty, "its summary shows in the slot list")
	_check(Saves.rename("1", "  my run  ") and Saves.info("1").name == "my run", "a slot can be renamed (trimmed)")
	_check(Saves.copy("1", "2") and Saves.read("2") == {"hp": 7}, "a slot can be copied")
	_check(not Saves.copy("1", Saves.AUTO), "nothing is copied onto the autosave")
	Saves.delete("2")
	_check(Saves.info("2").empty, "a slot can be deleted")
	_check(Saves.latest().slot == "1", "Continue offers the newest save")
	Saves.write(Saves.AUTO, {"hp": 9}, "HP 9/20")
	Saves.write("5", {"hp": 8}, "HP 8/20") # the same second as the autosave, and later
	_check(Saves.latest().slot == "5", "of two saves from the same second, Continue offers the later one")
	Saves.write(Saves.AUTO, {"hp": 7}, "HP 7/20") # list order puts the autosave first: only the write order says it is later
	_check(Saves.latest().slot == Saves.AUTO, "and the autosave when it is the later one, though a ranked list would favour the slot")


## With the flag on, saving, listing, renaming, copying and deleting work in memory, and the player's saves are neither seen
## nor changed.
func _nosave_in_memory() -> void:
	Flags.set_args(PackedStringArray(["nosave"]))
	_check(Saves.info("1").empty and Saves.read("1").is_empty() and Saves.latest().is_empty(), "nosave: the saves on disk are not seen (every slot looks empty)")
	_check(Saves.write("3", {"hp": 1}, "HP 1/20") and Saves.read("3") == {"hp": 1}, "nosave: a save is kept for the run and can be loaded")
	_check(not FileAccess.file_exists(Saves.path("3")), "nosave: nothing reaches the disk")
	_check(Saves.rename("3", "temp") and Saves.info("3").name == "temp", "nosave: a slot can be renamed")
	_check(Saves.copy("3", "4") and Saves.read("4") == {"hp": 1} and not FileAccess.file_exists(Saves.path("4")), "nosave: a slot can be copied, in memory")
	Saves.delete("3")
	_check(Saves.info("3").empty and not Saves.info("4").empty, "nosave: a slot can be deleted")
	Saves.write(Saves.AUTO, {"hp": 3}, "HP 3/20")
	Saves.write("6", {"hp": 2}, "HP 2/20") # the same second, and later
	_check(Saves.latest().slot == "6", "nosave: of two saves from the same second, Continue offers the later one")
	Saves.write(Saves.AUTO, {"hp": 4}, "HP 4/20")
	_check(Saves.latest().slot == Saves.AUTO, "nosave: and the autosave when it is the later one")
	Saves.delete_all()
	_check(Saves.list().all(func(i): return i.empty), "nosave: delete all clears the memory")
	Flags.set_args(PackedStringArray([]))
	_check(FileAccess.file_exists(Saves.path("1")) and Saves.info("1").name == "my run" and Saves.info("3").empty, "nosave: the save on disk was not renamed or deleted, and the memory is not on the disk")


## A saved state is data from outside: one that is not ours is refused, a wrong value (a cell in a wall, health past the maximum)
## is brought back in range, and neither reaches a script error.
func _state_is_checked() -> void:
	var flow := Flow.new(Rng.new(5), LocalMind.new())
	await flow.new_run()
	flow.state.allies = [load("res://src/game/ally.gd").make("slime", "GLOP", 70.0)]
	var good: Dictionary = flow.state.to_dict()
	var back = State.from_dict(good.duplicate(true))
	_check(back != null and back.cell == flow.state.cell and back.hp == 20 and back.allies.size() == 1 and back.floor_map.monsters.size() == flow.state.floor_map.monsters.size(), "a state written by the game is read back")
	# each change makes the state refused (null), whatever the wrong value is
	var refused := {
		"a cell that is not a pair": func(d): d.cell = "here",
		"a cell with a word in it": func(d): d.cell = [1, "x"],
		"a cell outside the floor": func(d): d.cell = [99, 99],
		"a cell in a wall": func(d): d.cell = [0, 0],
		"no floor": func(d): d.floor = 5,
		"a floor with no rows": func(d): d.floor.grid = "x",
		"a row that is not a row": func(d): d.floor.grid[3] = 7,
		"a row of the wrong length": func(d): d.floor.grid[3] = [1, 1],
		"a floor with no size": func(d): d.floor.size = 0,
		"a floor far too big": func(d): d.floor.size = 5000,
		"a stairs cell in a wall": func(d): d.floor.stairs = [0, 0],
		"monsters that are not a list": func(d): d.floor.monsters = "many",
		"a monster that is not a record": func(d): d.floor.monsters[0] = 3,
		"a monster of no species": func(d): d.floor.monsters[0].species = "dragonfly",
		"a monster outside the floor": func(d): d.floor.monsters[0].cell = [-4, 2],
		"a monster whose traits are a word": func(d): d.floor.monsters[0].traits = "shy",
		"a monster whose meters are a list": func(d): d.floor.monsters[0].meters = [1, 2],
		"health that is a word": func(d): d.hp = "full",
		"health that is a list": func(d): d.hp = [20],
		"health that is not a number": func(d): d.hp = NAN,
		"a maximum that is nothing": func(d): d.maxHp = null,
		"gold that is a record": func(d): d.gold = {},
		"a tally that is a number": func(d): d.tally = 5,
		"a tally of words": func(d): d.tally = {"spared": "lots"},
		"allies that are a word": func(d): d.allies = "GLOP",
		"an ally that is not a record": func(d): d.allies = [3],
		"an ally of no species": func(d): d.allies[0].species = "ghost",
		"an ally whose loyalty is a word": func(d): d.allies[0].loyalty = "high",
		"a facing that is a word": func(d): d.facing = "north",
		"no hp": func(d): d.erase("hp"),
		"no floor key": func(d): d.erase("floor"),
		"no allies key": func(d): d.erase("allies"),
	}
	for what in refused:
		var d: Dictionary = good.duplicate(true)
		refused[what].call(d)
		_check(State.from_dict(d) == null, "a save with %s is refused" % what)
	# each change is kept but brought back in range
	var clamped := {
		"health past the maximum": [func(d): d.hp = 9999, func(s): return s.hp == s.max_hp],
		"no health left": [func(d): d.hp = 0, func(s): return s.hp == 1],
		"negative health": [func(d): d.hp = -40, func(s): return s.hp == 1],
		"a maximum of nothing": [func(d): d.maxHp = 0; d.hp = 5, func(s): return s.max_hp == 1 and s.hp == 1],
		"negative gold": [func(d): d.gold = -3, func(s): return s.gold == 0],
		"a floor far down": [func(d): d.depth = 1000000, func(s): return s.depth >= 1 and s.depth <= State.DEPTH_MAX],
		"a floor above the first": [func(d): d.depth = -2, func(s): return s.depth == 1],
		"a facing past the compass": [func(d): d.facing = 7, func(s): return s.facing == 3],
		"a negative tally": [func(d): d.tally.spared = -4, func(s): return s.tally.spared == 0],
		"a cell given as floats": [func(d): d.cell = [d.cell[0] + 0.0, d.cell[1] + 0.0], func(s): return s.cell == flow.state.cell],
		"loyalty far over": [func(d): d.allies[0].loyalty = 500.0, func(s): return s.allies[0].loyalty == 100.0],
		"loyalty below nothing": [func(d): d.allies[0].loyalty = -9.0, func(s): return s.allies[0].loyalty == 0.0],
		"a party of five": [func(d): d.allies = [d.allies[0], d.allies[0], d.allies[0], d.allies[0], d.allies[0]], func(s): return s.allies.size() == 3],
		"a monster with more health than its maximum": [func(d): d.floor.monsters[0].hp = 9999, func(s): return s.floor_map.monsters[0].hp == s.floor_map.monsters[0].max_hp],
		"a monster meter out of range": [func(d): d.floor.monsters[0].meters.anger = 900.0, func(s): return s.floor_map.monsters[0].meters.anger == 100.0],
		"a monster that is gone for no reason": [func(d): d.floor.monsters[0].gone = "vanished", func(s): return s.floor_map.monsters[0].gone == ""],
		"cells that are not cells in what was seen": [func(d): d.seen = [[1, 1], "x", [2], [999, 999], [1.0, 3.0]]; d.visited = 4, func(s): return s.seen.has(Vector2i(1, 1)) and s.visited.is_empty() or s.visited.has(s.cell)],
	}
	for what in clamped:
		var d: Dictionary = good.duplicate(true)
		clamped[what][0].call(d)
		var got = State.from_dict(d)
		_check(got != null and clamped[what][1].call(got), "a save with %s is read, brought back in range" % what)


func _cleanup() -> void:
	Flags.set_args(PackedStringArray([]))
	Saves.delete_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))


## Saves are numbered one above the last, whatever the clock says: the newest save is the one written last, a run carries
## on from the highest number on disk, and `saved_at` stays the real time.
func _numbers_rise() -> void:
	var ordered := true
	for i in 40:
		Saves.write(str(1 + i % 3), {"hp": i}, "HP %d/20" % i)
		ordered = ordered and Saves.latest().slot == str(1 + i % 3)
	_check(ordered, "each of 40 saves in a row is the newest when it is written")
	var numbers: Array = Saves.list().filter(func(x): return not x.empty).map(func(x): return x.seq)
	_check(not numbers.is_empty() and numbers.all(func(n): return n > 0), "every save has a number")
	var before: int = Saves.info("1").seq
	Saves.write("4", {"hp": 1}, "HP 1/20")
	_check(Saves.info("4").seq > maxi(before, maxi(Saves.info("2").seq, Saves.info("3").seq)), "a new run numbers its first save above every save on disk")
	_check(Saves.latest().slot == "4", "so it is the newest")
	var now := int(Time.get_unix_time_from_system())
	var future := now + 3600 * 24 * 365
	Saves._store({"version": Saves.VERSION, "name": "", "summary": "from the future", "saved_at": future, "state": var_to_str({})}, "5") # saved when the clock was wrong, before saves were numbered
	Saves.write("6", {"hp": 1}, "HP 1/20")
	_check(Saves.latest().slot == "6", "a save made after a clock that was set forward is still the newest")
	_check(absi(Saves.info("6").saved_at - now) < 60, "and says the real time, not the future one")
	Saves.delete("5")
	# a second window wrote while this one stayed open: this one's next save is still above it
	var other_window: int = Saves.info("6").seq + 7
	Saves._store({"version": Saves.VERSION, "name": "", "summary": "from another window", "saved_at": now, "seq": other_window, "state": var_to_str({})}, "5")
	Saves.write("2", {"hp": 2}, "HP 2/20") # the run's own count is far behind
	_check(Saves.info("2").seq > other_window and Saves.latest().slot == "2", "a save is numbered above one another window wrote meanwhile, so Continue offers the later one")
	Saves.delete("5")
	for slot in ["2", "3", "4", "6"]: # slot 1 stays, for the nosave check that follows
		Saves.delete(slot)
