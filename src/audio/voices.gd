## The monsters' recorded voices: every line they can say was rendered ahead (tools/voices) and filed by species and
## the words said (the line without its *stage directions* and {placeholders}) in assets/voices/<engine>/manifest.json.
## A line with no recording is left to the synthesised voice (shout.gd): the text is still shown, so the game never
## depends on a voice existing.
extends RefCounted

const ENGINE := "cosyvoice3"
const ROOT := "res://assets/voices/%s/"

static var _lines = null # species -> {key -> relative path}
static var _stage := RegEx.create_from_string("\\*[^*]*\\*")
static var _braces := RegEx.create_from_string("\\{[^}]*\\}")
static var _dots := RegEx.create_from_string("\\.{2,}|…")
static var _space_before := RegEx.create_from_string("\\s+([,.!?])")
static var _edges := RegEx.create_from_string("^[\\s,]+|[\\s,]+$")
static var _spaces := RegEx.create_from_string("\\s+")


## The recording of `text` said by a `species`, or null if there isn't one.
static func find(species: String, text: String):
	var by_species: Dictionary = _all().get(species, {})
	var path: String = by_species.get(_key(text), "")
	if path == "":
		return null
	var full := (ROOT % ENGINE) + path
	return load(full) if ResourceLoader.exists(full) else null


## What is worth saying out loud: the words, not the *stage directions* or {placeholders}. "..." is a pause, so a comma.
static func speakable(line) -> String:
	var s := "" if line == null else str(line)
	s = _stage.sub(s, " ", true)
	s = _braces.sub(s, " ", true)
	s = _dots.sub(s, ", ", true)
	s = _space_before.sub(s, "$1", true)
	s = _edges.sub(s, "", true)
	s = _spaces.sub(s, " ", true)
	return s.strip_edges()


## What a rendered line is filed under (tools/voices/render.py files it the same way): the words said, lower case, single spaces.
static func _key(text) -> String:
	return _spaces.sub(speakable(text).to_lower(), " ", true).strip_edges()


static func _all() -> Dictionary:
	if _lines == null:
		_lines = {}
		var f := FileAccess.open((ROOT % ENGINE) + "manifest.json", FileAccess.READ)
		if f == null:
			push_warning("voices: no manifest, monsters use the synthesised voice")
			return _lines
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and parsed.get("lines") is Dictionary:
			for species in parsed.lines:
				_lines[species] = {}
				for line in parsed.lines[species]:
					_lines[species][line] = parsed.lines[species][line] # filed under its key already
	return _lines
