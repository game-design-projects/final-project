## Decider's readout, without the model: the prompt rows a System One request becomes, and what the option-letter
## probabilities that come back mean. Decider (github.com/Mapika/decider, Apache 2.0) is the open-weight System One
## model the monsters run on; this is a port of decider-ai 1.10.0's decider/systemone.py (render_state, render_question,
## plan_rows, assemble, format_answer, the confidence formulas) and decider/prompt.py (the state-first plain layout,
## one question per row, isolated Score levels: what the released checkpoints use). The model itself runs in llama.cpp
## (local.gd); nothing here does I/O. tests/jev/golden/decider/ holds what Decider's own code makes of every golden
## request (tools/decider_golden.py), which this file must reproduce byte for byte.
## Load it with `const Decider = preload("res://src/jev/decider.gd")`.
extends RefCounted

const U = preload("res://src/jev/util.gd")

const LETTERS := "ABCDEFGHIJ"
## Up to this many options a question is written "(A) .. (J)" in one string (tokenized as one piece); above it, each label
## is its own token between "\n(" and ") text" (decider's "wide" rendering)
const NARROW := 10
## Labels A..Z. Decider goes on to 255 with two-letter labels that are single tokens; the game never asks more than 11
const MAX_OPTIONS := 26
const MAX_LEVELS := 10
## Arrays at least this long get each element's position written in ({"_index": i, ...}), as decider does
const ANNOTATE_MIN := 8
const ISOLATED := "%s\nProposed answer: %s\nDoes the proposed answer fit?"
const NOUL_WITHOUT_INSTRUCTIONS := "Which answer fits the context?"

## The checkpoints the game knows, by GGUF file name, pinned to one Hugging Face revision. `temperatures` are each
## model's decider_config.json temperature_by_type, except noul: the config's 0.05 is tuned for a benchmark's band rule,
## and the game reads noul as a calibrated probability, so it uses the noul temperature fitted on Decider's own rows
## (the config's noul_temperature_note).
const MODELS := {
	"decider-4b-v3-Q4_K_M.gguf": {
		"id": "decider-4b-v3", "repo": "Mapika/decider-4b-GGUF", "revision": "d3a78581751d518bbfa9e871a6d84059554d53c5",
		"bytes": 2708804000, "sha256": "fc6e32a39ca74a4201f7a7b2393bde16b83b7c26957465f257ca75c5c3fc3b3a",
		"temperatures": {"choice": 2.098, "noul": 2.795, "score": 3.152},
	},
	"decider-2b-v12-Q4_K_M.gguf": {
		"id": "decider-2b-v12", "repo": "Mapika/decider-2b-GGUF", "revision": "0df001b8fe4e5298c5dd45d875d3795fcdaea0ab",
		"bytes": 1274396192, "sha256": "e6d3a7534a3abc3a723f8263dc694b86f533214a5bf761474113c66d44018340",
		"temperatures": {"choice": 2.465, "noul": 3.185, "score": 2.833},
	},
}
const DEFAULT_MODEL := "decider-4b-v3-Q4_K_M.gguf"


## The MODELS entry for a GGUF path (by file name), or {}
static func model_for(path: String) -> Dictionary:
	return MODELS.get(path.replace("\\", "/").get_file(), {})


## Where a model downloads from
static func model_url(file: String) -> String:
	var m: Dictionary = MODELS[file]
	return "https://huggingface.co/%s/resolve/%s/%s" % [m["repo"], m["revision"], file]


# ---------------------------------------------------------------- text, as Python's json.dumps writes it

## json.dumps(v, ensure_ascii=False): ", " and ": " separators, keys in insertion order, non-ASCII kept as it is.
## Whole floats print as ints: GDScript reads JSON numbers as floats, Python reads "7" as an int.
static func py_json(v) -> String:
	if v == null:
		return "null"
	if v is bool:
		return "true" if v else "false"
	if v is int:
		return str(v)
	if v is float:
		var n = U.norm(v)
		return str(n) if n is int else str(v)
	if v is String or v is StringName:
		return _py_str(str(v))
	if v is Array:
		var parts := PackedStringArray()
		for x in v:
			parts.append(py_json(x))
		return "[" + ", ".join(parts) + "]"
	if v is Dictionary:
		var parts := PackedStringArray()
		for k in v:
			parts.append(_py_str(U.js_str(k)) + ": " + py_json(v[k]))
		return "{" + ", ".join(parts) + "}"
	return _py_str(str(v))


static func _py_str(s: String) -> String:
	var out := PackedStringArray(["\""])
	var start := 0
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x20 and c != 0x22 and c != 0x5c:
			continue
		out.append(s.substr(start, i - start))
		match c:
			0x22: out.append("\\\"")
			0x5c: out.append("\\\\")
			0x0a: out.append("\\n")
			0x0d: out.append("\\r")
			0x09: out.append("\\t")
			0x08: out.append("\\b")
			0x0c: out.append("\\f")
			_: out.append("\\u%04x" % c)
		start = i + 1
	out.append(s.substr(start))
	out.append("\"")
	return "".join(out)


static func _txt(v) -> String:
	return str(v) if v is String else py_json(v)


static func _annotate(x):
	if x is Array:
		var out := []
		for i in x.size():
			var v = _annotate(x[i])
			if x.size() >= ANNOTATE_MIN:
				var row := {"_index": i}
				if v is Dictionary:
					row.merge(v, true)
				else:
					row["value"] = v
				v = row
			out.append(v)
		return out
	if x is Dictionary:
		var out := {}
		for k in x:
			out[k] = _annotate(x[k])
		return out
	return x


## render_state: a string state as it is, anything else as JSON with long arrays indexed
static func render_state(state) -> String:
	return str(state) if state is String else py_json(_annotate(state))


# ---------------------------------------------------------------- questions and rows

static func _empty(v) -> bool:
	return v == null or (v is String and v == "")


## render_question: -> {question, options, type, names, legend}, or {"error": ...} for a question Decider would refuse.
## names: what the answer reports for each option (choice ids, score levels, [false, true] for noul).
static func render_question(spec: Dictionary) -> Dictionary:
	var t: String = str(spec.get("type", "choice"))
	var crit = spec.get("criteria", spec.get("options"))
	var raw = spec.get("instructions", spec.get("question", ""))
	var ins := ""
	if t == "noul" and _empty(raw):
		var described: bool = crit is Dictionary and (not _empty(crit.get("true")) or not _empty(crit.get("false")))
		if not described and (crit == null or crit is Dictionary):
			return {"error": "noul question without instructions: criteria must describe true or false"}
		ins = NOUL_WITHOUT_INSTRUCTIONS
	else:
		ins = _txt(raw)
	if ins == "":
		return {"error": "question without instructions"}
	var names := []
	var options := []
	var legend = null
	match t:
		"choice":
			if crit is Array:
				var as_map := {}
				for c in crit:
					as_map[U.js_str(c)] = null
				crit = as_map
			if not crit is Dictionary or crit.size() < 2 or crit.size() > MAX_OPTIONS:
				return {"error": "choice criteria: a map of 2..%d options" % MAX_OPTIONS}
			for n in crit:
				names.append(n)
				options.append(U.js_str(n) if _empty(crit[n]) else "%s: %s" % [U.js_str(n), _txt(crit[n])])
		"score":
			if crit is Dictionary:
				var keys: Array = crit.keys()
				keys.sort_custom(func(a, b): return float(str(a)) < float(str(b)))
				crit = keys.map(func(k): return crit[k])
			if not crit is Array or crit.size() < 2 or crit.size() > MAX_LEVELS:
				return {"error": "score criteria: an ordered list of 2..%d level descriptions" % MAX_LEVELS}
			legend = []
			for i in crit.size():
				names.append(i)
				options.append("%d: %s" % [i, _txt(crit[i])])
				legend.append(_txt(crit[i]))
		"noul":
			if crit != null and not crit is Dictionary:
				return {"error": "noul criteria: a map of optional true/false descriptions"}
			var c: Dictionary = crit if crit != null else {}
			names = [false, true]
			options = [
				"no" if _empty(c.get("false")) else "no: " + _txt(c["false"]),
				"yes" if _empty(c.get("true")) else "yes: " + _txt(c["true"]),
			]
		_:
			return {"error": "unknown question type %s" % t}
	return {"question": ins, "options": options, "type": t, "names": names, "legend": legend}


## "2: somewhat" -> "somewhat": an isolated level must not carry its number
static func strip_level_number(text: String) -> String:
	return RegEx.create_from_string("^\\s*-?\\d+\\s*:\\s*").sub(text, "")


## plan_rows with isolated Score levels: one row per question, and one yes/no row per level of a Score question.
## `rqs`: {id: render_question output}. -> {rows: [{question, options, type}], index: [[id, "iso" | "list", first row, rows]]}
static func plan_rows(rqs: Dictionary) -> Dictionary:
	var rows := []
	var index := []
	for k in rqs:
		var r: Dictionary = rqs[k]
		if r["type"] == "score":
			index.append([k, "iso", rows.size(), r["legend"].size()])
			for l in r["legend"]:
				rows.append({"question": ISOLATED % [r["question"], strip_level_number(l)], "options": ["no", "yes"], "type": "score"})
		else:
			index.append([k, "list", rows.size(), 1])
			rows.append({"question": r["question"], "options": r["options"], "type": r["type"]})
	return {"rows": rows, "index": index}


## The pieces a row is tokenized from, after "Context:\n<state>": strings, and {"label": j} where the wide rendering
## puts option j's label token
static func pieces(row: Dictionary) -> Array:
	var head := "\n\nQuestion: %s\nOptions:" % row["question"]
	var tail := "\nAnswer: ("
	var opts: Array = row["options"]
	if opts.size() <= NARROW:
		var parts := PackedStringArray([head])
		for j in opts.size():
			parts.append("\n(%s) %s" % [LETTERS[j], opts[j]])
		parts.append(tail)
		return ["".join(parts)]
	var out := [head]
	for j in opts.size():
		out.append_array(["\n(", {"label": j}, ") %s" % opts[j]])
	out.append(tail)
	return out


# ---------------------------------------------------------------- probabilities and answers

## softmax(logits / t) from softmax(logits): p_i^(1/t), normalized (all zero reads as uniform)
static func with_temperature(p: Array, t: float) -> Array:
	var out := []
	var s := 0.0
	for x in p:
		var y := pow(float(x), 1.0 / t) if float(x) > 0.0 else 0.0
		out.append(y)
		s += y
	if s <= 0.0:
		return p.map(func(_x): return 1.0 / p.size())
	return out.map(func(y): return y / s)


static func _normalised(p: Array) -> Array:
	var s := 0.0
	for x in p:
		s += float(x)
	if s == 0.0:
		return p.map(func(_x): return 1.0 / p.size())
	return p.map(func(x): return float(x) / s)


static func _argmax(p: Array) -> int:
	var j := 0
	for i in p.size():
		if p[i] > p[j]:
			j = i
	return j


static func _clip01(x: float) -> float:
	return clampf(x, 0.0, 1.0)


static func _round(x: float, nd: int) -> float:
	return snappedf(x, pow(10.0, -nd))


## 1 - normalised entropy: 1 when all mass is on one option, 0 when the distribution is flat
static func certainty(p: Array) -> float:
	if p.size() <= 1:
		return 1.0
	var h := 0.0
	for x in p:
		if x > 0.0:
			h -= x * log(x)
	return maxf(0.0, 1.0 - h / log(p.size()))


## TypeSafe's Choice confidence: (n * p_max - 1) / (n - 1), so a uniform answer is 0 and a certain one 1
static func choice_confidence(p: Array) -> float:
	if p.size() <= 1:
		return 1.0
	var q := _normalised(p)
	return _clip01((q.size() * q.max() - 1.0) / (q.size() - 1))


## TypeSafe's Score confidence: 1 minus the expected distance from the most likely level over the mean distance of the
## levels from the middle of the scale, floored at 0
static func score_confidence(p: Array) -> float:
	var n := p.size()
	if n <= 1:
		return 1.0
	var q := _normalised(p)
	var k := _argmax(q)
	var spread := 0.0
	var uniform := 0.0
	for i in n:
		spread += q[i] * absf(i - k)
		uniform += absf(i - (n - 1) / 2.0)
	return _clip01(1.0 - spread / (uniform / n))


## One answer from the probabilities over a question's options, in option order
static func format_answer(rq: Dictionary, p: Array) -> Dictionary:
	var q := _normalised(p.slice(0, rq["options"].size()))
	var j := _argmax(q)
	if rq["type"] == "noul":
		return {"type": "noul", "noul": _round(q[1], 4)}
	if rq["type"] == "choice":
		var probabilities := {}
		for i in q.size():
			probabilities[rq["names"][i]] = _round(q[i], 4)
		return {
			"type": "choice", "choice": rq["names"][j], "confidence": _round(choice_confidence(q), 4), "x_p_max": _round(q[j], 4),
			"certainty": _round(certainty(q), 4), "probabilities": probabilities,
		}
	var score := 0.0
	var legend := {}
	var probabilities := {}
	for i in q.size():
		score += i * q[i]
		legend[str(i)] = rq["legend"][i]
		probabilities[str(i)] = _round(q[i], 4)
	return {
		"type": "score", "score": _round(score, 2), "confidence": _round(score_confidence(q), 4), "x_p_max": _round(q[j], 4),
		"certainty": _round(certainty(q), 4), "legend": legend, "probabilities": probabilities,
	}


## assemble: one answer per question from one probability list per row (plan_rows order). An isolated Score question's
## levels are each P(fits) from their own row, normalized into a distribution; level_fit and fit_mass say how well they fit.
static func assemble(rqs: Dictionary, index: Array, probs: Array) -> Dictionary:
	var out := {}
	for entry in index:
		var k = entry[0]
		var s: int = entry[2]
		if entry[1] == "iso":
			var fit := []
			var tot := 0.0
			for j in int(entry[3]):
				fit.append(float(probs[s + j][1]))
				tot += fit[j]
			if tot == 0.0:
				tot = 1e-9
			var a := format_answer(rqs[k], fit.map(func(x): return x / tot))
			var level_fit := {}
			for j in fit.size():
				level_fit[str(j)] = _round(fit[j], 4)
			a["level_fit"] = level_fit
			a["fit_mass"] = _round(tot, 4)
			out[k] = a
		else:
			out[k] = format_answer(rqs[k], probs[s])
	return out
