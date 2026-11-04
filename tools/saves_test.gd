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
	Flags.set_args(PackedStringArray([]))
	_round_trip()
	_nosave_is_untouched()
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


## With the flag on, the player's saves are neither seen nor changed.
func _nosave_is_untouched() -> void:
	Flags.set_args(PackedStringArray(["nosave"]))
	_check(Saves.info("1").empty and Saves.read("1").is_empty() and Saves.latest().is_empty(), "nosave: saved data is not read (every slot looks empty)")
	Saves.write("3", {"hp": 1}, "HP 1/20")
	_check(not FileAccess.file_exists(Saves.path("3")), "nosave: nothing is written")
	Saves.rename("1", "other")
	Saves.copy("1", "4")
	_check(not FileAccess.file_exists(Saves.path("4")), "nosave: nothing is copied")
	Saves.delete("1")
	Saves.delete_all()
	Flags.set_args(PackedStringArray([]))
	_check(FileAccess.file_exists(Saves.path("1")) and Saves.info("1").name == "my run", "nosave: the existing save was not renamed or deleted")


func _cleanup() -> void:
	Flags.set_args(PackedStringArray([]))
	Saves.delete_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))
