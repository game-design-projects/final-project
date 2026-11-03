## What a monster thinks. A mind answers questions about the monster and the player's words, and the answers are
## probabilities, never decisions: the game rolls them with its own Rng, so the odds belong to the code and a mind
## can be swapped (rules, a seeded random one for tests, or Jev over the network) without changing what can happen.
##
## Every question may take time (a mind that calls out to Jev has to wait), so callers `await` the answer; the
## game stays playable while it waits. This base class only says what the questions are; subclasses answer them.
extends RefCounted

## For logs and the debug panel.
func label() -> String:
	return "mind"


## Which kind of words did the player type? Intent -> probability, adding up to 1. Intents are the keys of
## words.cues plus "other" (said something, nothing we know) and "gibberish".
func read_words(_text: String) -> Dictionary:
	return _unanswered("read_words")


## How does the monster feel after being hit? Feeling id -> probability.
func feeling_when_hit(_m) -> Dictionary:
	return _unanswered("feeling_when_hit")


## How does it feel about what the player said or did? `intents` is [{intent, w}]: one entry for an ACT button, a
## spread for typed words. Feeling id -> probability.
func feeling_when_told(_m, _intents: Array) -> Dictionary:
	return _unanswered("feeling_when_told")


## Would it accept mercy now? 0..1
func mercy(_m) -> float:
	return _unanswered("mercy")


## Would it join the party if asked now? 0..1
func join(_m) -> float:
	return _unanswered("join")


## How hard will its next attack press the player? 0 (gentle) .. 3 (relentless)
func pressure(_m) -> float:
	return _unanswered("pressure")


func _unanswered(question: String):
	push_error("mind: %s doesn't answer %s" % [label(), question])
	return {} if question in ["read_words", "feeling_when_hit", "feeling_when_told"] else 0.0
