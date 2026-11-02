## The player's settings: what the settings pages show and what the game reads (display, effects, sound). Kept as one
## JSON string in the Store under `donjon.settings`; a missing or damaged value falls back to the defaults per key, so an
## old file never breaks a new build. `set_value` validates, saves and applies; `apply` is also run once at startup.
## Tests set `store_override` (a Store.Memory) and `apply_enabled = false`.
extends RefCounted

const KEY := "donjon.settings"

const DEFAULTS := {
	"window_mode": "windowed", # windowed | maximized | fullscreen
	"vsync": true,
	"fps_cap": 0, # 0 = no cap
	"crt": true, # the glow / scanline pass over the dungeon view
	"calm": false, # no color splits or flashes on hits
	"shake": true, # the view shakes when something hits
	"sfx": true,
	"sfx_volume": 5, # 0..VOLUME_MAX
}

const OPTIONS := {
	"window_mode": ["windowed", "maximized", "fullscreen"],
	"fps_cap": [0, 30, 60, 120, 144],
	"sfx_volume": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
}
const VOLUME_MAX := 10
const LABELS := {
	"window_mode": {"windowed": "WINDOWED", "maximized": "MAXIMIZED", "fullscreen": "FULLSCREEN"},
	"fps_cap": {0: "NO CAP", 30: "30", 60: "60", 120: "120", 144: "144"},
}

static var store_override = null
## Tests turn this off so changing a setting doesn't change the test runner's window
static var apply_enabled := true
static var _cache = null
static var _fallback_store = null


static func _store():
	if store_override != null:
		return store_override
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var s = (loop as SceneTree).root.get_node_or_null("Store")
		if s != null:
			return s
	if _fallback_store == null:
		_fallback_store = preload("res://src/core/store.gd").Memory.new()
	return _fallback_store


## Every key present and valid: unknown keys dropped, bad values replaced by the default
static func normalize(raw) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	if not raw is Dictionary:
		return out
	for k in DEFAULTS:
		if raw.has(k) and valid(k, raw[k]):
			out[k] = raw[k]
	# JSON gives floats; the options are ints
	for k in ["fps_cap", "sfx_volume"]:
		out[k] = int(out[k])
	return out


static func valid(k: String, v) -> bool:
	if not DEFAULTS.has(k):
		return false
	if OPTIONS.has(k):
		for o in OPTIONS[k]:
			if (v is int or v is float) and (o is int) and int(v) == o and float(v) == float(o):
				return true
			if o is String and v is String and o == v:
				return true
		return false
	return typeof(v) == typeof(DEFAULTS[k])


static func current() -> Dictionary:
	if _cache == null:
		var parsed = null
		var text = _store().get_item(KEY)
		if text != null:
			var json := JSON.new()
			if json.parse(str(text)) == OK:
				parsed = json.data
			else:
				push_warning("settings: %s is not valid JSON, using the defaults" % KEY)
		_cache = normalize(parsed)
	return _cache


static func get_value(k: String):
	return current()[k]


## Validates, keeps, saves and applies one setting. Returns false for an unknown key or invalid value.
static func set_value(k: String, v) -> bool:
	if not valid(k, v):
		push_warning("settings: ignored %s = %s" % [k, str(v)])
		return false
	var d := current()
	d[k] = int(v) if DEFAULTS[k] is int else v
	_save(d)
	print("settings: %s = %s" % [k, str(v)])
	apply(d)
	return true


## The next (dir = 1) or previous (-1) value of a setting that has a list of options, or a toggled bool
static func cycled(k: String, dir := 1):
	var cur = current()[k]
	if DEFAULTS[k] is bool:
		return not cur
	var opts: Array = OPTIONS[k]
	var i := opts.find(cur)
	return opts[posmod(i + dir, opts.size())]


static func reset() -> void:
	_cache = DEFAULTS.duplicate(true)
	_save(_cache)
	print("settings: reset to the defaults")
	apply(_cache)


## Forget what was read (tests, and after the store changes under us). Not `reload`: that is Script's own method
static func forget() -> void:
	_cache = null


static func _save(d: Dictionary) -> void:
	_cache = d
	_store().set_item(KEY, JSON.stringify(d))


static func label(k: String, v) -> String:
	if LABELS.has(k):
		return LABELS[k].get(v, str(v))
	if k == "sfx_volume":
		return "%d / %d" % [int(v), VOLUME_MAX]
	if v is bool:
		return "ON" if v else "OFF"
	return str(v)


## The sound effects' volume as the Sfx class takes it (0..1)
static func sfx_gain(d: Dictionary) -> float:
	if not d.sfx:
		return 0.0
	return float(d.sfx_volume) / float(VOLUME_MAX)


## Put the display settings on the window. A headless run has no window to change.
static func apply(d: Dictionary = {}) -> void:
	if d.is_empty():
		d = current()
	if not apply_enabled or DisplayServer.get_name() == "headless":
		return
	match d.window_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"maximized":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if d.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(d.fps_cap)
