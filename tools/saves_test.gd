## Checks the save slots with no window, in a folder of their own: the round trip, rename, copy and delete, and that the
## `nosave` flag keeps all of it away from saved data (reading, writing, renaming, copying and deleting).
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
	assert(Saves.dir_path != "user://saves", "saves_test: refusing to run on the player's saves")
	if Saves.dir_path == "user://saves":
		_check(false, "the test's folder replaced the player's save folder, so it did not run")
		_finish()
		return
	Flags.set_args(PackedStringArray([]))
	_round_trip()
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
	Saves.delete_all()
	_check(Saves.list().all(func(i): return i.empty), "nosave: delete all clears the memory")
	Flags.set_args(PackedStringArray([]))
	_check(FileAccess.file_exists(Saves.path("1")) and Saves.info("1").name == "my run" and Saves.info("3").empty, "nosave: the save on disk was not renamed or deleted, and the memory is not on the disk")


func _cleanup() -> void:
	Flags.set_args(PackedStringArray([]))
	Saves.delete_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))
