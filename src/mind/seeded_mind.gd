## A mind that answers at random, but with answers that are always well-formed (probabilities that add up, numbers in
## range). It is what the `mock` flag selects and what scenario runs use, so a whole game can be played with no network
## and no rules behind the answers. The same seed gives the same answers.
extends "res://src/mind/mind.gd"

const Content = preload("res://src/rules/content.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Odds = preload("res://src/rules/odds.gd")
const Rng = preload("res://src/utils/rng.gd")

var _rng: Rng


func _init(rng: Rng) -> void:
	_rng = rng


func label() -> String:
	return "seeded"


func read_words(_text: String) -> Dictionary:
	var ids: Array = Content.table("words").cues.keys() + ["other", "gibberish"]
	return _random_odds(ids)


func feeling_when_hit(_m) -> Dictionary:
	return _random_odds(Feelings.all().keys())


func feeling_when_told(_m, _intents: Array) -> Dictionary:
	return _random_odds(Feelings.all().keys())


func mercy(_m) -> float:
	return _rng.real()


func join(_m) -> float:
	return _rng.real()


func pressure(_m) -> float:
	return _rng.real() * 3.0


func _random_odds(ids: Array) -> Dictionary:
	var logits := {}
	for id in ids:
		logits[id] = _rng.real() * 3.0
	return Odds.softmax(logits)
