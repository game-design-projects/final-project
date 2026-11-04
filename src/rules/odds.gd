## Chances. Code owns the odds: a mind says how a monster feels or how likely something is, and these turn that into a
## roll, so what can happen never depends on who is answering.
extends RefCounted

const LIKELY := 0.5 # odds this high read as likely: SPARE turns gold, the monster asks to join

const Dice = preload("res://src/utils/dice.gd")
const Monster = preload("res://src/rules/monster.gd")

## An answer less likely than this never happens (unless nothing is that likely).
const POSSIBLE := 0.15
const ODDS_MIN := 0.12
const ODDS_MAX := 0.88


static func sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))


## Scores to probabilities that add up to 1.
static func softmax(logits: Dictionary) -> Dictionary:
	var top := -INF
	for k in logits:
		top = maxf(top, logits[k])
	var weights := {}
	var total := 0.0
	for k in logits:
		weights[k] = exp(logits[k] - top)
		total += weights[k]
	var out := {}
	for k in weights:
		out[k] = weights[k] / total
	return out


## Picks one key by its probability, among those at least POSSIBLE (or the likeliest, if none is).
static func pick_by_odds(dice: Dice, probs: Dictionary) -> String:
	var pool := []
	for k in probs:
		if probs[k] >= POSSIBLE:
			pool.append([k, probs[k]])
	if pool.is_empty():
		var best := ""
		for k in probs:
			if best == "" or probs[k] > probs[best]:
				best = k
		pool = [[best, probs[best]]]
	var total := 0.0
	for entry in pool:
		total += entry[1]
	var r := dice.real() * total
	for entry in pool:
		r -= entry[1]
		if r <= 0.0:
			return entry[0]
	return pool[-1][0]


## The likeliest key, or "" for an empty set.
static func top(probs: Dictionary) -> String:
	var best := ""
	for k in probs:
		if best == "" or probs[k] > probs[best]:
			best = k
	return best


## Will it answer a question? Curious monsters tend to; secretive and jumpy ones don't. Never certain either way.
static func reveal_odds(m) -> float:
	var willingness: float = m.affinity("question") + m.meters.friendliness / 50.0 - m.meters.anger / 50.0
	for t in m.traits:
		match t:
			"curious", "remembers everything", "surprisingly honest about being dishonest":
				willingness += 0.8
			"secretive", "jumpy":
				willingness -= 1.5
	return clampf(sigmoid((willingness - 0.8) * 1.4), ODDS_MIN, ODDS_MAX)


## Will it take a fair cut of gold to stand down? Can fail even on good terms, and fails more when it is angry.
static func cut_odds(m) -> float:
	var willingness: float = -0.6 + m.affinity("gold") * 0.45 + m.meters.friendliness / 75.0 - m.meters.anger / 35.0
	if m.species == "bandit":
		for t in m.traits:
			if t in ["surprisingly honest about being dishonest", "greedy", "owes money to someone"]:
				willingness += 0.7
			if t in ["jumpy", "proud"]:
				willingness -= 1.3
	if m.species == "snake":
		if m.has_trait("always bargaining"):
			willingness += 0.7
		if m.has_trait("secretive"):
			willingness -= 1.3
	return clampf(sigmoid(willingness * 1.7), ODDS_MIN, ODDS_MAX)


## One draw against the odds.
static func succeeds(dice: Dice, odds: float) -> bool:
	return dice.real() < odds
