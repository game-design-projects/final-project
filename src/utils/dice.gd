## The draws behind the chances of an interaction (a cut, a feeling, mercy, joining, an ally's verdict). It hands out the
## seeded generator's numbers, or, while `pinned` is 0 or more, always that one number: the personality slice pins it so
## the same actions give the same outcomes. Odds and Allies take a Dice and not a Rng, so a draw cannot go around the pin.
extends RefCounted

const Rng = preload("res://src/utils/rng.gd")

## In [0, 1) while pinned; -1 for the generator's own numbers.
var pinned := -1.0

var _rng: Rng


func _init(rng: Rng) -> void:
	_rng = rng


## A float in [0, 1).
func real() -> float:
	return _rng.real() if pinned < 0.0 else pinned
