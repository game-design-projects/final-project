extends "res://tests/test_case.gd"

const Saves = preload("res://src/menu/saves.gd")

var root := ""


func before_each() -> void:
	root = "user://test_saves_%d" % Time.get_ticks_usec()
	Saves.dir_override = root


func after_each() -> void:
	Saves.delete_all()
	for f in DirAccess.get_files_at(root) if DirAccess.dir_exists_absolute(root) else PackedStringArray():
		DirAccess.remove_absolute(root + "/" + f)
	DirAccess.remove_absolute(root)
	Saves.dir_override = ""


func _state() -> Dictionary:
	return {"x": 3, "dir": 1, "seen": {14: true, 27: true}, "map": {"grid": [[0, 1], [1, 1]], "n": 2}, "hp": 12.5, "name": "Pear"}


func test_a_state_survives_a_write_and_read() -> void:
	ok(Saves.write(1, _state(), "B1F · HP 12/20"))
	eq(Saves.read(1), _state(), "integer dictionary keys and floats come back as they were")
	eq(Saves.info(1).summary, "B1F · HP 12/20")
	ok(Saves.info(1).saved_at > 0)


func test_empty_slots_and_listing() -> void:
	var l := Saves.list()
	eq(l.size(), Saves.SLOTS + 1, "auto plus the manual slots")
	eq(l[0].slot, "auto")
	ok(l.all(func(i): return i.empty), "nothing saved yet")
	eq(Saves.read(2), {})
	eq(Saves.latest(), {})
	ok(not Saves.write(99, _state()), "no such slot")


func test_latest_is_the_newest_readable_save() -> void:
	Saves.write(2, _state(), "older")
	# make slot 3 newer by writing it with a later time
	Saves.write(3, _state(), "newer")
	var doc = JSON.parse_string(FileAccess.get_file_as_string(Saves.path(3)))
	doc.saved_at = int(doc.saved_at) + 100
	var f := FileAccess.open(Saves.path(3), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	eq(Saves.latest().slot, "3")
	Saves.delete(3)
	eq(Saves.latest().slot, "2")


func test_a_damaged_file_is_shown_as_corrupt_not_loaded() -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(Saves.path(4), FileAccess.WRITE)
	f.store_string("{this is not json")
	f.close()
	ok(Saves.info(4).corrupt)
	eq(Saves.read(4), {})
	eq(Saves.latest(), {}, "Continue skips it")


func test_copy_rename_delete() -> void:
	Saves.write(1, _state(), "first", "Pear's run")
	ok(Saves.copy(1, 5))
	eq(Saves.read(5), _state())
	eq(Saves.info(5).name, "Pear's run")
	ok(not Saves.copy(1, 1), "not onto itself")
	ok(not Saves.copy(2, 3), "nothing to copy")
	ok(Saves.rename(5, "  Backup  "))
	eq(Saves.info(5).name, "Backup")
	eq(Saves.read(5), _state(), "renaming leaves the state alone")
	ok(Saves.delete(5))
	ok(Saves.info(5).empty)
	ok(not Saves.delete(5), "already gone")


func test_overwriting_keeps_the_name_and_leaves_no_temp_file() -> void:
	Saves.write(1, _state(), "a", "Mine")
	Saves.write(1, {"x": 9}, "b")
	eq(Saves.info(1).name, "Mine")
	eq(Saves.read(1), {"x": 9})
	ok(not FileAccess.file_exists(Saves.path(1) + ".tmp"))
