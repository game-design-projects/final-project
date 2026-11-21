## A mind around another one: the edge where a mind's answer is checked before the game uses it (see utils/fault.gd for why
## the two builds differ). An answer that isn't one (not odds, a number out of range or null, half a pair, or none at all by
## DEADLINE_S) is a fault:
##   debug build   reported and handed on as it is: the debugger stops there and the tools fail as they would without this.
##   export        reported, and the local rules answer instead, so the fight goes on. Without this an export uses the null
##                 as it comes: a pair whose mercy was lost plays as 0% mercy and nothing says so.
## A good answer passes through untouched and in the same order, so a seeded mind draws as it always did. Minds.create puts
## every mind the game uses inside one.
extends "res://src/mind/mind.gd"

const Fault = preload("res://src/utils/fault.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Network = preload("res://src/network/network.gd")

## The longest a question may be out in an export: every try of one request, the waits between them, and a little more.
## Nothing in the network layer waits longer, so only a mind that has lost its own answer gets here.
const DEADLINE_S := Network.TIMEOUT_S * (Network.RETRIES + 1) + 6.0
## What is said when even the local rules have no answer: words nobody knows, a muddled monster, no mercy, a firm attack.
const LAST_WORDS := {"other": 1.0}
const LAST_FEELING := {"confused": 1.0}
const LAST_MERCY := 0.0
const LAST_JOIN := 0.0
const LAST_PRESSURE := 1.0


## Opens when the answer is in, or when the wait is over.
class Gate extends RefCounted:
	signal opened

var saved := 0 # how many answers came from the local rules because the mind's own was no answer
var deadline_s := DEADLINE_S
var _inner # a Mind
var _spare # a Mind that needs nothing but the monster: the local rules


func _init(inner, spare = null) -> void:
	_inner = inner
	_spare = spare if spare != null else LocalMind.new()


func label() -> String:
	return _inner.label()


func read_words(text: String) -> Dictionary:
	return await _guard("read_words", func(): return await _inner.read_words(text), is_odds, func(): return await _spare.read_words(text), LAST_WORDS)


func sounds_like(text: String, what: String) -> float:
	return await _guard("sounds_like", func(): return await _inner.sounds_like(text, what), is_chance, func(): return await _spare.sounds_like(text, what), 0.0)


func feeling_when_hit(m) -> Dictionary:
	return await _guard("feeling_when_hit", func(): return await _inner.feeling_when_hit(m), is_odds, func(): return await _spare.feeling_when_hit(m), LAST_FEELING)


func feeling_when_told(m, intents: Array) -> Dictionary:
	return await _guard("feeling_when_told", func(): return await _inner.feeling_when_told(m, intents), is_odds, func(): return await _spare.feeling_when_told(m, intents), LAST_FEELING)


func mercy(m) -> float:
	return await _guard("mercy", func(): return await _inner.mercy(m), is_chance, func(): return await _spare.mercy(m), LAST_MERCY)


func join(m) -> float:
	return await _guard("join", func(): return await _inner.join(m), is_chance, func(): return await _spare.join(m), LAST_JOIN)


func pressure(m) -> float:
	return await _guard("pressure", func(): return await _inner.pressure(m), is_pressure, func(): return await _spare.pressure(m), LAST_PRESSURE)


func mercy_and_pressure(m) -> Dictionary:
	var spare := func(): return {"mercy": await _spare.mercy(m), "pressure": await _spare.pressure(m)}
	return await _guard("mercy_and_pressure", func(): return await _inner.mercy_and_pressure(m), is_pair, spare, {"mercy": LAST_MERCY, "pressure": LAST_PRESSURE})


## Probabilities the game can roll: something -> a finite number that is 0 or more, at least one of them above 0, and a
## total the game can divide by (an infinite total makes every roll the same key).
static func is_odds(answer) -> bool:
	if not answer is Dictionary or answer.is_empty():
		return false
	var total := 0.0
	for k in answer:
		if not is_number(answer[k], INF):
			return false
		total += float(answer[k])
	return is_finite(total) and total > 0.0


## A finite number from 0 to `high` (INF itself is not one: the game can't roll it).
static func is_number(value, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= high


static func is_chance(answer) -> bool:
	return is_number(answer, 1.0)


static func is_pressure(answer) -> bool:
	return is_number(answer, 3.0)


static func is_pair(answer) -> bool:
	return answer is Dictionary and is_chance(answer.get("mercy")) and is_pressure(answer.get("pressure"))


## The mind's answer to `question` when it is `ok`. When it is not: handed on as it is after the report (fail fast), or
## the `spare` answer, or `last` when that is no answer either (an export).
func _guard(question: String, ask: Callable, ok: Callable, spare: Callable, last):
	if not Fault.tolerant():
		var given = await ask.call()
		if not ok.call(given):
			Fault.report("mind", "%s answered %s to %s" % [label(), str(given).left(120), question])
		return given
	var got: Dictionary = await _within_deadline(ask)
	var answer = got.value
	if ok.call(answer):
		return answer
	saved += 1
	var why: String = "answered %s" % str(answer).left(120) if got.answered else "gave no answer in %.0f s" % deadline_s
	Fault.report("mind", "%s %s to %s, local rules instead (%d so far)" % [label(), why, question, saved])
	var other = await spare.call()
	return other if ok.call(other) else last


## What the mind said: {"answered": whether it said anything at all, "value": the answer}. `answered` stays false, and the
## value null, when deadline_s passes first (what comes after that is not used). A mind that answers null at once has
## answered — it is a bad answer, not a question still out; the two read differently in the log. A mind that answers at
## once (the local rules, a seeded one) is not waited for: no timer, no frame.
func _within_deadline(ask: Callable) -> Dictionary:
	var box := {"open": true, "answered": false, "value": null}
	var gate := Gate.new()
	var asking := func():
		var answer = await ask.call()
		if box.open:
			box.open = false
			box.answered = true
			box.value = answer
			gate.opened.emit()
	asking.call() # not awaited: it may never come back
	if box.open:
		Engine.get_main_loop().create_timer(deadline_s).timeout.connect(func():
			if box.open:
				box.open = false
				gate.opened.emit())
		await gate.opened
	return {"answered": box.answered, "value": box.value}
