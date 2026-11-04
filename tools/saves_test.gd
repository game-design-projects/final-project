## Checks the save slots with no window, in a folder of their own: the round trip, rename, copy and delete, and that the
## `nosave` flag keeping the slots in memory, off the disk and away from the player's saves.
##   godot --headless --path . -s res://tools/saves_test.gd
extends "res://tools/test_base.gd"

const Flags = preload("res://src/utils/flags.gd")

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


func _cleanup() -> void:
	Flags.set_args(PackedStringArray([]))
	Saves.delete_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))


## A new run of the game: nothing is known of the slots yet.
func _new_run() -> void:
	Saves._seq = 0
	Saves._scanned = false


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
	_new_run() # the game starts again: the numbers come from what is on disk
	Saves.write("4", {"hp": 1}, "HP 1/20")
	_check(Saves.info("4").seq > maxi(before, maxi(Saves.info("2").seq, Saves.info("3").seq)), "a new run numbers its first save above every save on disk")
	_check(Saves.latest().slot == "4", "so it is the newest")
	var now := int(Time.get_unix_time_from_system())
	var future := now + 3600 * 24 * 365
	Saves._store({"version": Saves.VERSION, "name": "", "summary": "from the future", "saved_at": future, "state": var_to_str({})}, "5") # saved when the clock was wrong, before saves were numbered
	_new_run()
	Saves.write("6", {"hp": 1}, "HP 1/20")
	_check(Saves.latest().slot == "6", "a save made after a clock that was set forward is still the newest")
	_check(absi(Saves.info("6").saved_at - now) < 60, "and says the real time, not the future one")
	Saves.delete("5")
	for slot in ["2", "3", "4", "6"]: # slot 1 stays, for the nosave check that follows
		Saves.delete(slot)
