## What the player can change, kept in the Store one key each. A missing or damaged value falls back to its default, so an
## old file never breaks a new build. `set_value` checks, saves and applies at once; `apply` also runs when a scene starts.
extends RefCounted

const Mix = preload("res://src/audio/mix.gd")

## key -> default. The kind of value is the kind of the default.
const DEFAULTS := {
	"window_mode": "windowed", # windowed | maximized | fullscreen
	"vsync": true,
	"fps_cap": 0, # 0 = no cap
	"crt": true, # the glow and scanlines over the picture
	"calm": false, # softer flashes and no colour split when something hits
	"shake": true, # the battle screen shakes when something hits
	"easy": false, # slower dodges
	"tips": true, # the first-time tips
	"text_size": "normal", # the log and the speech box
	"seen_tips": [], # the tips already shown
	"sfx": true,
	"sfx_volume": 5, # 0..VOLUME_MAX, for the music too
}
const OPTIONS := {
	"window_mode": ["windowed", "maximized", "fullscreen"],
	"fps_cap": [0, 30, 60, 120, 144],
	"text_size": ["normal", "large"],
}
const VOLUME_MAX := 10
## Where the game before the rewrite kept every setting, as one JSON string. Read once, moved to the keys below, and removed.
const OLD_KEY := "donjon.settings"
const LABELS := {
	"window_mode": {"windowed": "WINDOWED", "maximized": "MAXIMIZED", "fullscreen": "FULLSCREEN"},
	"fps_cap": {0: "NO CAP", 30: "30", 60: "60", 120: "120", 144: "144"},
	"text_size": {"normal": "NORMAL", "large": "LARGE"},
}


static var _migrated := false


## The saved value if it is valid, else the default.
static func get_value(key: String):
	_migrate_old()
	var v = Store.get_value(key, DEFAULTS[key])
	return v if valid(key, v) else DEFAULTS[key]


## The first read of the settings takes in what the old game left under `donjon.settings`: each valid value whose key is not
## set yet moves to its own key, and the old string is removed (or a Reset would bring its values back).
static func _migrate_old() -> void:
	if _migrated:
		return
	_migrated = true
	var text = Store.get_value(OLD_KEY)
	if text == null:
		return
	var json := JSON.new()
	if json.parse(str(text)) == OK and json.data is Dictionary:
		var moved := 0
		for key in DEFAULTS:
			if json.data.has(key) and Store.get_value(key) == null and valid(key, json.data[key]):
				Store.set_value(key, int(json.data[key]) if DEFAULTS[key] is int else json.data[key])
				moved += 1
		print("settings: took %d values over from the old '%s'" % [moved, OLD_KEY])
	else:
		push_warning("settings: the old '%s' is not a JSON object, dropped" % OLD_KEY)
	Store.remove(OLD_KEY)


## Read the old string again on the next read (a test puts one in the Store).
static func forget_migration() -> void:
	_migrated = false


static func valid(key: String, v) -> bool:
	if not DEFAULTS.has(key):
		return false
	if OPTIONS.has(key):
		return OPTIONS[key].has(int(v) if DEFAULTS[key] is int and (v is int or v is float) else v)
	if key == "sfx_volume":
		return (v is int or v is float) and int(v) >= 0 and int(v) <= VOLUME_MAX
	return typeof(v) == typeof(DEFAULTS[key])


## Check, keep, save and apply one setting. False for an unknown key or a bad value.
static func set_value(key: String, v) -> bool:
	if not valid(key, v):
		push_warning("settings: ignored %s = %s" % [key, v])
		return false
	Store.set_value(key, int(v) if DEFAULTS[key] is int else v)
	print("settings: %s = %s" % [key, v])
	apply()
	return true


## The next (dir = 1) or previous (-1) value of a setting: the following option, a flipped switch, a volume step.
static func cycled(key: String, dir := 1):
	var v = get_value(key)
	if DEFAULTS[key] is bool:
		return not v
	if OPTIONS.has(key):
		return OPTIONS[key][posmod(OPTIONS[key].find(v) + dir, OPTIONS[key].size())]
	return clampi(int(v) + dir, 0, VOLUME_MAX)


static func reset() -> void:
	for key in DEFAULTS:
		Store.remove(key)
	print("settings: back to the defaults")
	apply()


static func label(key: String) -> String:
	var v = get_value(key)
	if LABELS.has(key):
		return LABELS[key].get(v, str(v))
	if key == "sfx_volume":
		return "%d / %d" % [int(v), VOLUME_MAX]
	if v is bool:
		return "ON" if v else "OFF"
	return str(v)


## Put the settings to work: the window, the frame rate, the volumes. A headless run has no window to change.
static func apply() -> void:
	Mix.set_levels(get_value("sfx"), float(get_value("sfx_volume")) / VOLUME_MAX)
	Engine.max_fps = int(get_value("fps_cap"))
	if DisplayServer.get_name() == "headless":
		return
	match get_value("window_mode"):
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"maximized":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
