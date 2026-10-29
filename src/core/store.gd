## The game's localStorage: string keys to string values, kept in user://store.json (IndexedDB on the web).
## Autoloaded as `Store`. `get_item` returns null for a missing key, like localStorage.getItem.
## Tests use `Memory`, the same API without a file.
extends Node

const PATH := "user://store.json"

var _data := {}


func _init() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_data = parsed
	else:
		push_warning("store: %s is not a JSON object, starting empty" % PATH)


func get_item(k: String):
	return _data.get(k)


func set_item(k: String, v) -> void:
	_data[k] = str(v)
	_save()


func remove_item(k: String) -> void:
	if _data.erase(k):
		_save()


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("store: can't write %s (%s)" % [PATH, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(_data))


## In-memory store with the same API, for tests and headless scripts
class Memory:
	extends RefCounted
	var data := {}

	func _init(initial: Dictionary = {}) -> void:
		data = initial.duplicate()

	func get_item(k: String):
		return data.get(k)

	func set_item(k: String, v) -> void:
		data[k] = str(v)

	func remove_item(k: String) -> void:
		data.erase(k)
