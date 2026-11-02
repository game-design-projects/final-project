## Save slots: "auto" (the game writes it on its own) and 1..SLOTS (the player's). One JSON file per slot in
## `user://saves/` (IndexedDB on the web): {version, name, summary, saved_at, state}, where `state` is the game's
## own dictionary as a Godot variant string (so integer keys and floats survive, and it can't create objects).
## A file is written beside its slot and renamed over it, so a crash mid-write keeps the old save. A damaged file
## shows as a corrupt slot instead of raising. Tests set `dir_override`.
extends RefCounted

const SLOTS := 6
const AUTO := "auto"
const VERSION := 1

static var dir_override := ""


static func dir() -> String:
	return dir_override if dir_override != "" else "user://saves"


static func slots() -> Array:
	var out: Array = [AUTO]
	for i in SLOTS:
		out.append(str(i + 1))
	return out


static func path(slot) -> String:
	return "%s/%s.json" % [dir(), str(slot)]


static func valid_slot(slot) -> bool:
	return slots().has(str(slot))


## Writes `state` into `slot`. `name` defaults to what the slot held before. Returns false if the file can't be written.
static func write(slot, state: Dictionary, summary := "", name := "") -> bool:
	slot = str(slot)
	if not valid_slot(slot):
		push_warning("saves: no slot %s" % slot)
		return false
	if name == "":
		name = str(info(slot).get("name", ""))
	DirAccess.make_dir_recursive_absolute(dir())
	var doc := {
		"version": VERSION,
		"name": name,
		"summary": summary,
		"saved_at": int(Time.get_unix_time_from_system()),
		"state": var_to_str(state),
	}
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
	print("saves: wrote slot %s (%s)" % [slot, summary])
	return true


static func _load_doc(slot) -> Variant:
	var p := path(slot)
	if not FileAccess.file_exists(p):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(p)) != OK:
		return {"corrupt": true}
	var parsed = json.data
	if not parsed is Dictionary or not parsed.has("state") or not parsed.get("version") is float and not parsed.get("version") is int:
		return {"corrupt": true}
	return parsed


## What a slot list shows: {slot, empty, corrupt, name, summary, saved_at}
static func info(slot) -> Dictionary:
	slot = str(slot)
	var doc = _load_doc(slot)
	if doc == null:
		return {"slot": slot, "empty": true, "corrupt": false, "name": "", "summary": "", "saved_at": 0}
	if doc.has("corrupt"):
		return {"slot": slot, "empty": false, "corrupt": true, "name": "", "summary": "DAMAGED SAVE", "saved_at": 0}
	return {
		"slot": slot, "empty": false, "corrupt": false, "name": str(doc.get("name", "")),
		"summary": str(doc.get("summary", "")), "saved_at": int(doc.get("saved_at", 0)),
	}


## The game's state from a slot, or {} when it is empty, damaged or from a newer version
static func read(slot) -> Dictionary:
	var doc = _load_doc(str(slot))
	if doc == null or doc.has("corrupt"):
		return {}
	if int(doc.get("version", 0)) > VERSION:
		push_warning("saves: slot %s is from a newer version" % str(slot))
		return {}
	var state = str_to_var(str(doc.state))
	return state if state is Dictionary else {}


static func list() -> Array:
	return slots().map(func(s): return info(s))


## The slot Continue loads: the newest save that can be read, or {}
static func latest() -> Dictionary:
	var best := {}
	for i in list():
		if i.empty or i.corrupt:
			continue
		if best.is_empty() or i.saved_at > best.saved_at:
			best = i
	return best


static func delete(slot) -> bool:
	if not valid_slot(slot) or not FileAccess.file_exists(path(slot)):
		return false
	print("saves: deleted slot %s" % str(slot))
	return DirAccess.remove_absolute(path(slot)) == OK


static func delete_all() -> void:
	for s in slots():
		delete(s)


## Copies one slot's file to another (replacing it); the copy keeps the name and time of the original
static func copy(from, to) -> bool:
	if not valid_slot(from) or not valid_slot(to) or str(from) == str(to) or not FileAccess.file_exists(path(from)):
		return false
	var text := FileAccess.get_file_as_string(path(from))
	var f := FileAccess.open(path(to), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	print("saves: copied slot %s to %s" % [str(from), str(to)])
	return true


static func rename(slot, name: String) -> bool:
	var doc = _load_doc(str(slot))
	if doc == null or doc.has("corrupt"):
		return false
	doc.name = name.strip_edges().left(24)
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(doc))
	return true


## "2026-11-01 18:30", or "" when never saved
static func when(unix: int) -> String:
	if unix <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().bias) * 60)
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
