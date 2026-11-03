## Save slots: "auto" (the game writes it itself) and 1..SLOTS (the player's). One JSON file each in `dir_path`:
## {version, name, summary, saved_at, state}. A file is written beside its slot and renamed over it, so a crash mid-write
## keeps the old save, and a damaged file shows as a damaged slot rather than raising.
extends RefCounted

const Flags = preload("res://src/utils/flags.gd")

const SLOTS := 6
const AUTO := "auto"
const VERSION := 2 # 1 was the first game's format; its saves are shown as old and not loaded
const NAME_MAX := 24

## Where the saves live. Tools that must not touch the player's saves point this somewhere else.
static var dir_path := "user://saves"


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
	if Flags.on("nosave"):
		print_verbose("saves: nosave, not writing slot %s" % slot)
		return true
	if name == "":
		name = info(slot).name
	return _store({"version": VERSION, "name": name, "summary": summary, "saved_at": int(Time.get_unix_time_from_system()), "state": var_to_str(state)}, slot)


## What a slot list shows: {slot, empty, corrupt, name, summary, saved_at}.
static func info(slot: String) -> Dictionary:
	var doc = _read_doc(slot)
	var none := {"slot": slot, "empty": true, "corrupt": false, "name": "", "summary": "", "saved_at": 0}
	if doc == null:
		return none
	if doc.is_empty():
		none.merge({"empty": false, "corrupt": true, "summary": "DAMAGED SAVE"}, true)
		return none
	if int(doc.get("version", 0)) != VERSION:
		none.merge({"empty": false, "corrupt": true, "summary": "OLD SAVE, NOT COMPATIBLE"}, true)
		return none
	none.merge({"empty": false, "name": str(doc.get("name", "")), "summary": str(doc.get("summary", "")), "saved_at": int(doc.get("saved_at", 0))}, true)
	return none


## The game's state from a slot, or {} when it is empty, damaged or from a newer version.
static func read(slot: String) -> Dictionary:
	var doc = _read_doc(slot)
	if doc == null or doc.is_empty() or int(doc.get("version", 0)) != VERSION:
		return {}
	var state = str_to_var(str(doc.state)) # unlike a script, str_to_var can't build objects
	return state if state is Dictionary else {}


static func list() -> Array:
	return slots().map(func(s): return info(s))


## The newest save that can be read, or {} (what Continue loads).
static func latest() -> Dictionary:
	var best := {}
	for i in list():
		if not i.empty and not i.corrupt and (best.is_empty() or i.saved_at > best.saved_at):
			best = i
	return best


static func rename(slot: String, name: String) -> bool:
	var doc = _read_doc(slot)
	if doc == null or doc.is_empty():
		return false
	doc.name = name.strip_edges().left(NAME_MAX)
	return _store(doc, slot)


## Copy one slot over another (the autosave can be copied from, not onto).
static func copy(from: String, to: String) -> bool:
	var doc = _read_doc(from)
	if doc == null or doc.is_empty() or to == AUTO or not slots().has(to):
		return false
	return _store(doc, to)


static func delete(slot: String) -> void:
	if slots().has(slot) and FileAccess.file_exists(path(slot)):
		DirAccess.remove_absolute(path(slot))
		print("saves: deleted slot %s" % slot)


static func delete_all() -> void:
	for s in slots():
		delete(s)


## null when there is no file, {} when it is damaged, else the document.
static func _read_doc(slot: String):
	if not FileAccess.file_exists(path(slot)):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path(slot))) != OK or not json.data is Dictionary or not json.data.has("state"):
		return {}
	return json.data


static func _store(doc: Dictionary, slot: String) -> bool:
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
