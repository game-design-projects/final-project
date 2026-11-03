## Saved settings and progress: one JSON object in user://store.json. Autoloaded as `Store`.
## Save slots are separate files (menu/saves); this is for the small things: settings, tutorial seen, best scores.
## With the `nosave` flag nothing is read or written, so scenario runs leave no trace.
extends Node

const Flags = preload("res://src/utils/flags.gd")
const DEFAULT_PATH := "user://store.json"

var _path := DEFAULT_PATH
var _data := {}
var _persist := true


## `path` is only passed by tools that must not touch the player's real store.
func _init(path := DEFAULT_PATH) -> void:
	_path = path
	_persist = not Flags.on("nosave")
	if not _persist:
		print("store: nosave, keeping everything in memory")
		return
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return # first run
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_data = parsed
		print_verbose("store: %d keys from %s" % [_data.size(), _path])
	else:
		push_warning("store: %s is not a JSON object, starting empty" % _path)


## The saved value, or `default` when the key was never saved.
func get_value(key: String, default = null):
	return _data.get(key, default)


func set_value(key: String, value) -> void:
	_data[key] = value
	_save()


func remove(key: String) -> void:
	if _data.erase(key):
		_save()


## Writes beside the file and renames over it, so a crash mid-write can't leave half a store.
func _save() -> void:
	if not _persist:
		return
	var tmp := _path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("store: can't write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(_data))
	f.close()
	var err := DirAccess.rename_absolute(tmp, _path)
	if err != OK:
		push_warning("store: can't replace %s (%s)" % [_path, error_string(err)])
