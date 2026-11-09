## The draws behind the chances of an interaction (a cut, a feeling, mercy, joining, an ally's verdict). It hands out the
## seeded generator's numbers, or, while pinned, always that one number: the personality slice pins it so the same actions
## give the same outcomes. Odds and Allies take a Dice and not a Rng, so a draw cannot go around the pin.
extends RefCounted

const Rng = preload("res://src/utils/rng.gd")

var _rng: Rng
var _has_pin := false
var _pinned := 0.0 # the one number handed out while `_has_pin`


func _init(rng: Rng) -> void:
	_rng = rng


## Hand out `roll` (0 up to, not including, 1) every time until `unpin`. Anything else is refused, reported, and leaves the
## dice as it was; the result says whether it was pinned.
func pin(roll: float) -> bool:
	if not (roll >= 0.0 and roll < 1.0): # also false for NaN
		push_error("dice: %s is not a roll (0 or more, below 1); not pinned" % roll)
		return false
	_has_pin = true
	_pinned = roll
	print_verbose("dice: pinned at %.2f" % roll)
	return true


func unpin() -> void:
	if _has_pin:
		print_verbose("dice: unpinned")
	_has_pin = false


func is_pinned() -> bool:
	return _has_pin


## A float in [0, 1).
func real() -> float:
	var roll := _pinned if _has_pin else _rng.real()
	if OS.is_stdout_verbose(): # on the path of every chance: no string is built unless it will be printed
		print("dice: %.3f%s" % [roll, " (pinned)" if _has_pin else ""])
	return roll


## A whole number from a to b, both included (drawn from `real`, so not the same numbers as `Rng.int_range`). `real` is
## always below 1, so the product is below the count and no clamp is needed.
func int_between(a: int, b: int) -> int:
	assert(a <= b, "dice: int_between(%d, %d) has no numbers in it" % [a, b])
	return a + int(real() * (b - a + 1))


## A reproducible draw for a saved context (social scheduling), independent of animation timing and earlier rolls.
## It still goes through this flow's dice and honours the personality slice's pin.
func keyed(seed_value: int) -> float:
	return _pinned if _has_pin else Rng.new(seed_value).real()
