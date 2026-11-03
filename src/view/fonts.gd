## The two typefaces of the game (both open-licence, in assets/fonts/): a chunky pixel face for titles and a narrow
## terminal face for everything else. Loaded once; a missing file falls back to the engine's default font.
extends RefCounted

const TITLE := "res://assets/fonts/PressStart2P-Regular.ttf"
const BODY := "res://assets/fonts/VT323-Regular.ttf"

static var _cache := {}


static func title() -> Font:
	return _font(TITLE)


static func body() -> Font:
	return _font(BODY)


static func _font(path: String) -> Font:
	if not _cache.has(path):
		var font: Font = load(path) if ResourceLoader.exists(path) else null
		if font == null:
			push_warning("fonts: %s is missing, using the default font" % path)
			font = ThemeDB.fallback_font
		_cache[path] = font
	return _cache[path]
