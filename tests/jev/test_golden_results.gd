# The rules, decision for decision. golden/results.json has generated requests and what the JavaScript game's rules
# made of them when Jev gave the scripted answers below (recorded from the web version). The port gets the same requests and
# the same scripted answers and must reach the same replies: actions, blocked reasons, mood numbers, lines, loyalty.
extends "res://tests/test_case.gd"

const JevApi = preload("res://src/jev/api.gd")
const Jev = preload("res://src/jev/jev.gd")

const NOULS := [0, 0.2, 0.35, 0.55, 0.65, 0.75, 0.95, 1]
const CONFIDENCE := [0.1, 0.2, 0.3, 0.9]


func after_each():
	Jev.configure_jev(null)


## The same scripted Jev the recording used: answers depend only on the question's name and a seed.
class Scripted:
	extends RefCounted
	var seed: int

	func _init(s: int) -> void:
		seed = s

	static func hash_of(key: String, s: int) -> int:
		var m := 0xFFFFFFFF
		var h := (2166136261 ^ ((s * 2654435761) & m)) & m
		for c in key.to_utf8_buffer():
			h ^= c
			h = (h * 16777619) & m
		return h

	func answer(key: String, q: Dictionary) -> Dictionary:
		var h := hash_of(key, seed)
		if q["type"] == "noul":
			return {"type": "noul", "noul": NOULS[h % 8]}
		if q["type"] == "score":
			return {"type": "score", "score": float(h % (4 * (q["criteria"].size() - 1) + 1)) / 4}
		var keys: Array = q["criteria"].keys()
		var pick: String = keys[h % keys.size()]
		var other: String = keys[(h >> 8) % keys.size()]
		var probabilities := {}
		for k in keys:
			probabilities[k] = 0
		probabilities[pick] = 1 if other == pick else 0.9
		if other != pick:
			probabilities[other] = 0.1
		return {"type": "choice", "choice": pick, "probabilities": probabilities, "confidence": CONFIDENCE[(h >> 16) % 4]}

	func fetch(_url, _headers, body) -> Dictionary:
		var answers := {}
		for key in body["questions"]:
			answers[key] = answer(key, body["questions"][key])
		return {"status": 200, "json": {"answers": answers, "usage": {"input_tokens": 7}, "model": "scripted"}}


## What the JS decided at random is left out: the leave/betray line, and what a theft does.
static func clean(v, path: String, context: Dictionary):
	if v is Dictionary:
		var out := {}
		for k in v:
			if v[k] == null or k == "ms" or k == "_debug":
				continue
			out[k] = clean(v[k], path + "." + str(k), context)
		if path.begins_with(".reactions[") and v.get("decision") != "stay":
			out.erase("line")
		if v.get("response") == "steal_gold":
			out.erase("stolen")
			out.erase("caught")
			out.erase("loyalty")
		return out
	if v is Array:
		var out := []
		for i in v.size():
			out.append(clean(v[i], "%s[%d]" % [path, i], context))
		return out
	return v


## The first place two cleaned replies differ, or ""
static func diff(want, got, path := "") -> String:
	if (want is int or want is float) and (got is int or got is float):
		return "" if absf(float(want) - float(got)) < 1e-9 else "%s: want %s, got %s" % [path, want, got]
	if typeof(want) != typeof(got):
		return "%s: want %s, got %s" % [path, JSON.stringify(want), JSON.stringify(got)]
	if want is Dictionary:
		for k in want:
			if not got.has(k):
				return "%s.%s: missing (want %s)" % [path, k, JSON.stringify(want[k])]
			var d := diff(want[k], got[k], path + "." + str(k))
			if d != "":
				return d
		for k in got:
			if not want.has(k):
				return "%s.%s: unexpected %s" % [path, k, JSON.stringify(got[k])]
		return ""
	if want is Array:
		if want.size() != got.size():
			return "%s: want %d items, got %d" % [path, want.size(), got.size()]
		for i in want.size():
			var d := diff(want[i], got[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if want == got else "%s: want %s, got %s" % [path, JSON.stringify(want), JSON.stringify(got)]


func test_every_generated_request_gets_the_same_reply_as_the_js():
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://tests/jev/golden/results.json"))
	ok(cases is Array and cases.size() >= 130, "golden results are there")
	var decisions := {}
	for i in cases.size():
		var c: Dictionary = cases[i]
		Jev.configure_jev("k", {"transport": Scripted.new(int(c["seed"]))})
		var r: Dictionary = await JevApi.handle(c["path"], c["body"])
		eq(r["status"], int(c["status"]), "case %d %s" % [i, c["path"]])
		var want = clean(c["expected"], "", {})
		var got = clean(r["body"], "", {})
		var d := diff(want, got)
		ok(d == "", "case %d %s: %s" % [i, c["path"], d])
		for res in got.get("results", []):
			decisions[res["action"]] = true
	ok(decisions.size() >= 8, "the cases cover many different actions (%s)" % str(decisions.keys()))
