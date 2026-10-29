## A stand-in for TypeSafe's Jev endpoint, for tests, the scenario scripts and `mock` runs (no API key, no credits).
## It answers every question with a well-formed answer of the right type, from a seeded random source, so a run is
## repeatable: noul -> { noul }, choice -> { choice, probabilities }, score -> { score, probabilities }.
## The answers are random, not sensible: this exercises the game's plumbing and rules, not Jev's judgement.
## Load it with `const MockJev = preload("res://src/jev/mock_jev.gd")`.
extends RefCounted

const JEV_URL := "https://api.typesafe.ai/v1/systemone"
const JEV_URLS := [JEV_URL, "https://openrouter.ai/api/alpha/decisions"]

const _MASK := 0xFFFFFFFF


## Math.imul on two uint32 values, returned as a uint32 (the low 32 bits of the product; the 64-bit product wraps
## but its low 32 bits stay right).
static func _imul(a: int, b: int) -> int:
	return ((a & _MASK) * (b & _MASK)) & _MASK


## mulberry32: a small seeded PRNG, bit-exact with the JS, so a seed gives the same numbers in both.
class Mulberry32:
	extends RefCounted
	var a := 0

	func _init(seed = 1) -> void:
		# seed >>> 0: truncate toward zero, then modulo 2^32 (the mask does that for negatives too)
		a = int(seed) & 0xFFFFFFFF

	func next() -> float:
		var m := 0xFFFFFFFF
		a = (a + 0x6d2b79f5) & m
		var t := a
		t = (((t ^ (t >> 15)) & m) * ((t | 1) & m)) & m
		var u := (((t ^ (t >> 7)) & m) * ((t | 61) & m)) & m
		t = (t ^ ((t + u) & m)) & m
		return float((t ^ (t >> 14)) & m) / 4294967296.0


## seeded(seed): a function returning the next number in [0, 1) each time it is called (`rand.call()`).
static func seeded(seed = 1) -> Callable:
	var r := Mulberry32.new(seed)
	return func() -> float: return r.next()


## Random probabilities over labels, summing to 1
static func _spread(labels: Array, rand: Callable) -> Dictionary:
	var w := []
	for _l in labels:
		var r: float = rand.call()
		w.append(r * r + 0.01)
	var sum := 0.0
	for x in w:
		sum += x
	var out := {}
	for i in labels.size():
		out[labels[i]] = w[i] / sum
	return out


## One answer for one question. An unknown question type gives {"error": ...} (the JS throws).
static func mock_answer(question: Dictionary, rand: Callable) -> Dictionary:
	var type = question.get("type")
	if type == "noul":
		return {"type": "noul", "noul": rand.call()}
	if type == "choice":
		var criteria = question.get("criteria")
		var labels: Array = criteria.keys() if criteria is Dictionary else []
		var probabilities := _spread(labels, rand)
		# the first label with the highest probability (a stable descending sort's first element)
		var best = null
		var best_p := -1.0
		for l in probabilities:
			if probabilities[l] > best_p:
				best_p = probabilities[l]
				best = l
		return {"type": "choice", "choice": best, "probabilities": probabilities}
	if type == "score":
		var criteria = question.get("criteria")
		var n: int = criteria.size() if criteria is Array else 2
		var levels := []
		for i in n:
			levels.append(str(i))
		var probabilities := _spread(levels, rand)
		var s := 0.0
		for i in n:
			s += i * probabilities[levels[i]]
		return {"type": "score", "score": s, "confidence": 0.5, "probabilities": probabilities}
	return {"error": "mock Jev: unknown question type %s" % str(type)}


## The body of a System One reply to `{questions}`: {model, answers, usage}, or {"error": ...}
static func mock_system_one(body: Dictionary, rand: Callable) -> Dictionary:
	var questions: Dictionary = body.get("questions", {})
	var answers := {}
	for name in questions:
		var a := mock_answer(questions[name], rand)
		if a.has("error"):
			return a
		answers[name] = a
	var input_tokens := JSON.stringify(questions).length() >> 2
	return {"model": "jev-mock", "answers": answers, "usage": {"input_tokens": input_tokens}}


## What mockFetch was: a transport (see jev.gd) that answers the Jev endpoints itself, from a seeded source.
##   var server := MockJev.Server.new(7)            # seed 7, no latency
##   Jev.configure_jev("key", {"transport": server})
## `calls` has every request body it received, so a test can see what was asked (model, state, questions).
class Server:
	extends RefCounted
	const J = preload("res://src/core/js.gd")
	var rand: Callable
	var latency := 0.0
	var calls: Array = []

	func _init(seed = 1, latency_ms = 0) -> void:
		rand = _outer().seeded(seed)
		latency = float(latency_ms)

	## The enclosing script, for its static functions (an inner class can't call them unqualified)
	static func _outer() -> GDScript:
		return load("res://src/jev/mock_jev.gd")

	## fetch(url, headers, body) -> {"status": 200, "json": {...}}, or {"error": ...} like a rejected fetch
	func fetch(url: String, _headers: Dictionary, body: Dictionary) -> Dictionary:
		if not JEV_URLS.has(url):
			return {"error": "mock Jev: no mock for %s" % url}
		calls.append(body.duplicate(true))
		if latency > 0.0:
			await J.sleep(latency)
		var out: Dictionary = _outer().mock_system_one(body, rand)
		if out.has("error"):
			return out
		return {"status": 200, "json": out}
