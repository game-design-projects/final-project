## The game's content (monsters, lines, tastes, feelings, words), loaded once from data/*.json.
## Rules and minds read content through here and never open the files, so where it lives can change in one place.
## JSON gives every number as a float: `int(...)` the ones used as counts or keys.
extends RefCounted

const DIR := "res://data/"

static var _tables := {}
static var _fill_re := RegEx.create_from_string("\\{(\\w+)\\}")


## One data file as a Dictionary ("species", "taste", "encounter", "emotions", "words"). Empty (and an error) if it is
## missing or broken, so callers can still run and the log says why.
static func table(name: String) -> Dictionary:
	if _tables.has(name):
		return _tables[name]
	var path := DIR + name + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("content: can't open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("content: %s is not a JSON object" % path)
		return {}
	print_verbose("content: loaded %s" % path)
	_tables[name] = parsed
	return parsed


## One species' entry, e.g. species("slime").label. Empty (and an error) for an id nobody defined.
static func species(id: String) -> Dictionary:
	var all := table("species")
	if not all.has(id):
		push_error("content: no species '%s'" % id)
		return {}
	return all[id]


## "hi {name}" with {"name": "Drip"} -> "hi Drip". A {key} that isn't in vars stays as written.
static func fill(text: String, vars: Dictionary) -> String:
	var out := ""
	var at := 0
	for m in _fill_re.search_all(text):
		out += text.substr(at, m.get_start() - at)
		out += str(vars[m.get_string(1)]) if vars.has(m.get_string(1)) else m.get_string()
		at = m.get_end()
	return out + text.substr(at)
