## The draws behind the chances of an interaction (a cut, a feeling, mercy, joining, an ally's verdict). It hands out the
## seeded generator's numbers, or, while pinned, always that one number: the personality slice pins it so the same actions
## give the same outcomes. Odds and Allies take a Dice and not a Rng, so a draw cannot go around the pin.
extends RefCounted

const Rng = preload("res://src/utils/rng.gd")

var _rng: Rng
var _pinned := -1.0 # the one number handed out while pinned; negative otherwise


func _init(rng: Rng) -> void:
	_rng = rng


## Hand out `roll` (0 up to, not including, 1) every time until `unpin`. Anything else is refused and the dice is left as it was.
func pin(roll: float) -> void:
	if not (roll >= 0.0 and roll < 1.0): # also false for NaN
		push_warning("dice: %s is not a roll (0 or more, below 1); not pinned" % roll)
		return
	_pinned = roll
	print_verbose("dice: pinned at %.2f" % roll)


func unpin() -> void:
	if is_pinned():
		print_verbose("dice: unpinned")
	_pinned = -1.0


func is_pinned() -> bool:
	return _pinned >= 0.0


## A float in [0, 1).
func real() -> float:
	var roll := _pinned if is_pinned() else _rng.real()
	if OS.is_stdout_verbose():
		print("dice: %.3f%s" % [roll, " (pinned)" if is_pinned() else ""])
	return roll


## A whole number from a to b, both included (drawn from `real`, so not the same numbers as `Rng.int_range`).
func int_between(a: int, b: int) -> int:
	assert(a <= b, "dice: int_between(%d, %d) has no numbers in it" % [a, b])
	return a + int(real() * (b - a + 1))
