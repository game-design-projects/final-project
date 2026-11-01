## Every line a monster can say out loud, for rendering a voice bank (tools/voices/render.py):
##   godot --headless --path . -s res://cli/voice_lines.gd -- --out=build/voice-lines.json
## The approved lines of species.gd (lines, broken, reactions), as the Narrator would speak them (tts.gd speakable):
## stage directions dropped, {name} filled with each of the monster's own names. A line whose spoken words name its
## {target} can't be rendered ahead (anyone can be the target) and is listed under "skipped".
## Writes {"species": {species: [{"text", "key"}]}, "skipped": [{species, line}], "count"}; prints a summary.
extends SceneTree

const Species = preload("res://src/rules/species.gd")
const Tts = preload("res://src/audio/tts.gd")

static var _stage := RegEx.create_from_string("\\*[^*]*\\*")


func _initialize() -> void:
	var out_path := "build/voice-lines.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
	var data := collect()
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("can't write %s" % out_path)
		quit(1)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	for sp in data.species:
		print("%-7s %3d lines" % [sp, data.species[sp].size()])
	print("%d lines to render, %d skipped (they name their target) -> %s" % [data.count, data.skipped.size(), out_path])
	quit()


static func collect() -> Dictionary:
	var out := {"species": {}, "skipped": [], "count": 0}
	for sp in Species.SPECIES:
		var d: Dictionary = Species.SPECIES[sp]
		var templates := []
		for k in ["lines", "broken", "reactions"]:
			_walk(d.get(k, {}), templates)
		var seen := {}
		var list := []
		for t in templates:
			var words: String = _stage.sub(t, "", true)
			if Tts.speakable(t) == "":
				continue
			if words.contains("{target}"):
				out.skipped.append({"species": sp, "line": t})
				continue
			var fills: Array = d.names if words.contains("{name}") else [null]
			for name in fills:
				var line: String = Species.fill(t, {"name": name}) if name != null else t
				var key := Tts.line_key(line)
				if key == "" or seen.has(key):
					continue
				seen[key] = true
				list.append({"text": Tts.speakable(line), "key": key})
		out.species[sp] = list
		out.count += list.size()
	return out


static func _walk(v, out: Array) -> void:
	if v is String:
		out.append(v)
	elif v is Array:
		for x in v:
			_walk(x, out)
	elif v is Dictionary:
		for k in v:
			_walk(v[k], out)
