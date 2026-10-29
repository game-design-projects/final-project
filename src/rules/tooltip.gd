## Pixel-art tooltips in place of the system's own: any control with a tip gets a framed, pixel-font note on hover.
## "A · B · C" titles become one line each, and a run of ability scores ("STRENGTH -1 DEXTERITY +2 ...") becomes a
## small table. `tip_model` is the pure part (tested); the popup that shows it lives in src/ui.
extends RefCounted

static var _ability_re := RegEx.create_from_string("\\b(STRENGTH|DEXTERITY|CONSTITUTION|INTELLIGENCE|WISDOM|CHARISMA) ([+-]\\d+)")


## Title text → {lines: [String], stats: [[name, value]]}. Null text reads as empty.
static func tip_model(text) -> Dictionary:
	var lines := []
	var stats := []
	for part: String in ("" if text == null else str(text)).split(" · "):
		var t := part.strip_edges()
		if t == "":
			continue
		var found := _ability_re.search_all(t)
		# A part made only of ability scores becomes the table
		if found.size() >= 2 and _ability_re.sub(t, "", true).strip_edges() == "":
			stats = found.map(func(m: RegExMatch): return [m.get_string(1), int(m.get_string(2))])
		else:
			lines.append(t)
	return {"lines": lines, "stats": stats}
