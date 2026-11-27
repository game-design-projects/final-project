## Save slots: "auto" (the game writes it itself) and 1..SLOTS (the player's). One JSON file each in `dir_path`:
## {version, name, summary, saved_at, seq, state}. A file is written beside its slot and renamed over it, so a crash mid-write
## keeps the old save, and a damaged file shows as a damaged slot rather than raising. With the `nosave` flag the slots are kept in
## memory for the run instead, and nothing is read from or written to `dir_path`.
extends RefCounted

const Flags = preload("res://src/utils/flags.gd")

const SLOTS := 6
const AUTO := "auto"
const VERSION := 2 # 1 was the first game's format; its saves are shown as old and not loaded
const NAME_MAX := 24

## Where the saves live. A test that writes real files points this somewhere else (a scenario run uses `nosave`).
static var dir_path := "user://saves"

## With the `nosave` flag the slots live here, in memory, and the player's saves are neither read nor changed: a scenario
## run can save, list and load as usual, and nothing reaches the disk. slot -> document.
static var _memory := {}


## Whether the slots are kept in memory (the `nosave` flag).
static func in_memory() -> bool:
	return Flags.on("nosave")


static func slots() -> Array:
	var out: Array = [AUTO]
	for i in SLOTS:
		out.append(str(i + 1))
	return out


static func path(slot: String) -> String:
	return "%s/%s.json" % [dir_path, slot]


## "2026-11-03 16:51" in local time, or "" for no time.
static func when(unix: int) -> String:
	if unix <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().bias) * 60)
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]


## Write the game's state into a slot. The slot keeps its name unless `name` says otherwise.
static func write(slot: String, state: Dictionary, summary: String, name := "") -> bool:
	if not slots().has(slot):
		push_warning("saves: no slot '%s'" % slot)
		return false
	if name == "":
		name = _slot_info(slot, _read_doc(slot), false).name
	return _store({"version": VERSION, "name": name, "summary": summary, "saved_at": int(Time.get_unix_time_from_system()), "seq": _next_seq(), "state": var_to_str(state)}, slot)


## What a slot list shows: {slot, empty, corrupt, name, summary, saved_at, seq}. `seq` is the save's number, higher for a
## later save (0 for a save from before saves were numbered).
static func info(slot: String) -> Dictionary:
	return _slot_info(slot, _read_doc(slot))


static func _slot_info(slot: String, doc, check_state := true) -> Dictionary:
	var none := {"slot": slot, "empty": true, "corrupt": false, "name": "", "summary": "", "saved_at": 0, "seq": 0}
	if doc == null:
		return none
	var problem := _doc_problem(doc)
	if problem == "" and check_state and _read_state(doc).is_empty():
		problem = "DAMAGED SAVE"
	if problem != "":
		none.merge({"empty": false, "corrupt": true, "summary": problem}, true)
		return none
	none.merge({"empty": false, "name": str(doc.get("name", "")), "summary": str(doc.get("summary", "")), "saved_at": int(doc.get("saved_at", 0)), "seq": int(doc.get("seq", 0))}, true)
	return none


## The game's state from a slot, or {} when it is empty, damaged or from an incompatible version.
static func read(slot: String) -> Dictionary:
	return _validated_state(_read_doc(slot))


static func _validated_state(doc) -> Dictionary:
	return {} if doc == null or _doc_problem(doc) != "" else _read_state(doc)


static func _doc_problem(doc: Dictionary) -> String:
	var version = doc.get("version", 0)
	if doc.is_empty() or not _is_json_int(version):
		return "DAMAGED SAVE"
	if int(version) != VERSION:
		return "OLD SAVE, NOT COMPATIBLE"
	if not _is_json_int(doc.get("saved_at", 0)) or not _is_json_int(doc.get("seq", 0)):
		return "DAMAGED SAVE"
	return ""


# JSON decodes numbers as floats; the in-memory documents still use ints.
static func _is_json_int(value) -> bool:
	return value is int or (value is float and value >= -9223372036854775808.0 and value < 9223372036854775808.0 and floorf(value) == value)


static func _read_state(doc: Dictionary) -> Dictionary:
	var encoded = doc.get("state")
	if not encoded is String:
		return {}
	var state = str_to_var(encoded) # unlike a script, str_to_var can't build objects
	return state if state is Dictionary else {}


static func list() -> Array:
	return slots().map(func(s): return info(s))


## The newest save that can be read, or {} (what Continue loads).
static func latest() -> Dictionary:
	var best := {}
	for slot in slots():
		var doc = _read_doc(slot)
		var i := _slot_info(slot, doc, false)
		if not i.empty and not i.corrupt and (best.is_empty() or i.seq > best.seq or (i.seq == best.seq and i.saved_at > best.saved_at)):
			if not _read_state(doc).is_empty():
				best = i
	if not best.is_empty():
		print_verbose("saves: latest is %s (seq %d)" % [best.slot, best.seq])
	return best


static func rename(slot: String, name: String) -> bool:
	var doc = _read_doc(slot)
	if doc == null or doc.is_empty():
		return false
	doc.name = name.strip_edges().left(NAME_MAX)
	return _store(doc, slot)


## Copy a readable slot over another (the autosave can be copied from, not onto).
static func copy(from: String, to: String) -> bool:
	if to == AUTO or not slots().has(to):
		return false
	var doc = _read_doc(from)
	if _validated_state(doc).is_empty():
		return false
	return _store(doc, to)


static func delete(slot: String) -> void:
	if in_memory():
		_memory.erase(slot)
		print_verbose("saves: nosave, deleted slot %s from memory" % slot)
		return
	if slots().has(slot) and FileAccess.file_exists(path(slot)):
		DirAccess.remove_absolute(path(slot))
		print("saves: deleted slot %s" % slot)


static func delete_all() -> void:
	for s in slots():
		delete(s)


## null when there is no file, {} when it is damaged, else the document.
static func _read_doc(slot: String):
	if in_memory():
		return _memory.get(slot)
	if not FileAccess.file_exists(path(slot)):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path(slot))) != OK or not json.data is Dictionary or not json.data.has("state"):
		return {}
	return json.data


## The number for the next save: one above every save there is. `saved_at` is the clock's time and only for showing; the
## number is what says which save came last (two can share a second, and a clock can be set back). Read the slots each time
## to count writes by another window, but only use metadata: numbering a write does not need to decode any saved states.
static func _next_seq() -> int:
	var highest := 0
	for slot in slots():
		highest = maxi(highest, _slot_info(slot, _read_doc(slot), false).seq)
	return highest + 1


static func _store(doc: Dictionary, slot: String) -> bool:
	if in_memory():
		_memory[slot] = doc.duplicate(true)
		print_verbose("saves: nosave, kept slot %s in memory (%s)" % [slot, doc.summary])
		return true
	DirAccess.make_dir_recursive_absolute(dir_path)
	var tmp := path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("saves: can't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(doc))
	f.close()
	var err := DirAccess.rename_absolute(tmp, path(slot))
	if err != OK:
		push_warning("saves: can't move %s into place (%s)" % [tmp, error_string(err)])
		return false
	print("saves: wrote slot %s (%s)" % [slot, doc.summary])
	return true
