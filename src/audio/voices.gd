## The monsters' recorded voices: every line they can say was rendered ahead (tools/voices) and filed by species and
## exact line in assets/voices/<engine>/manifest.json. A line with no recording is simply not spoken: the text is
## still shown, so the game never depends on a voice existing.
extends RefCounted

const ENGINE := "cosyvoice3"
const ROOT := "res://assets/voices/%s/"

static var _lines = null # species -> {line -> relative path}


## The recording of `text` said by a `species`, or null if there isn't one.
static func find(species: String, text: String):
	var by_species: Dictionary = _all().get(species, {})
	var path: String = by_species.get(_key(text), "")
	if path == "":
		return null
	var full := (ROOT % ENGINE) + path
	return load(full) if ResourceLoader.exists(full) else null


static func _key(text: String) -> String:
	return text.strip_edges().to_lower()


static func _all() -> Dictionary:
	if _lines == null:
		_lines = {}
		var f := FileAccess.open((ROOT % ENGINE) + "manifest.json", FileAccess.READ)
		if f == null:
			push_warning("voices: no manifest, monsters stay silent")
			return _lines
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and parsed.get("lines") is Dictionary:
			for species in parsed.lines:
				_lines[species] = {}
				for line in parsed.lines[species]:
					_lines[species][_key(line)] = parsed.lines[species][line]
	return _lines
