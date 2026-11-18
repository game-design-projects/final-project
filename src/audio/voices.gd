## The monsters' recorded voices: every line they can say was rendered ahead (tools/voices) and filed by species and
## the words said (the line without its *stage directions* and {placeholders}) in assets/voices/<bank>/manifest.json.
## A line with no recording is left to the synthesised voice (shout.gd): the text is still shown, so the game never
## depends on a voice existing.
##
## One bank is the game's (BANK). The feature gemini-voices puts the Gemini TTS bank before it: a line is said from the first
## bank that has it, so a bank that is missing, or has only some lines, changes nothing for the rest.
extends RefCounted

const Flags = preload("res://src/utils/flags.gd")

const BANK := "cosyvoice3" # what every build plays
const GEMINI := "gemini" # what the feature gemini-voices plays first
const ROOT := "res://assets/voices/%s/"

static var _banks := {} # bank -> species -> {key -> relative path}; a bank with no manifest is there, and empty
static var _stage := RegEx.create_from_string("\\*[^*]*\\*")
static var _braces := RegEx.create_from_string("\\{[^}]*\\}")
static var _dots := RegEx.create_from_string("\\.{2,}|…")
static var _space_before := RegEx.create_from_string("\\s+([,.!?])")
static var _edges := RegEx.create_from_string("^[\\s,]+|[\\s,]+$")
static var _spaces := RegEx.create_from_string("\\s+")


## The banks a line is looked for in, the first first.
static func banks() -> Array:
	return [GEMINI, BANK] if Flags.enabled("gemini-voices") else [BANK]


## The recording of `text` said by a `species`, or null if there isn't one.
static func find(species: String, text: String):
	var at := where(species, text)
	return load(at.path) if not at.is_empty() else null


## Which bank has `text` said by a `species`, and the file: {bank, path}, or {} when none has it.
static func where(species: String, text: String) -> Dictionary:
	var key := _key(text)
	for bank in banks():
		var path: String = lines(bank).get(species, {}).get(key, "")
		if path != "" and ResourceLoader.exists((ROOT % bank) + path):
			return {"bank": bank, "path": (ROOT % bank) + path}
	return {}


## How many lines a bank has (0 for one that was never rendered).
static func size(bank: String) -> int:
	var n := 0
	for species in lines(bank):
		n += lines(bank)[species].size()
	return n


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


## A bank's lines, species -> {key -> relative path}, read once. The game's own bank missing is worth a warning; the
## Gemini bank missing only means nobody has rendered it yet, and the log says so once.
static func lines(bank: String) -> Dictionary:
	if _banks.has(bank):
		return _banks[bank]
	var out := {}
	_banks[bank] = out
	var f := FileAccess.open((ROOT % bank) + "manifest.json", FileAccess.READ)
	if f == null:
		if bank == BANK:
			push_warning("voices: no manifest, monsters use the synthesised voice")
		else:
			print("voices: the %s bank is not rendered (tools/voices/render.py %s), the %s bank speaks" % [bank, bank, BANK])
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.get("lines") is Dictionary:
		for species in parsed.lines:
			out[species] = {}
			for line in parsed.lines[species]:
				out[species][line] = parsed.lines[species][line] # filed under its key already
	var n := 0
	for species in out:
		n += out[species].size()
	print("voices: the %s bank has %d lines for %d species" % [bank, n, out.size()])
	return out
