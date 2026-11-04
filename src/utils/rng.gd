## Seeded random numbers. Anything random in the game goes through one of these instead of the engine's global
## generator, so a run started with `seed=N` plays out the same way every time.
extends RefCounted

const Flags = preload("res://src/utils/flags.gd")

## The seed this generator started from, so a run can print it and be repeated.
var seed_value := 0

var _gen := RandomNumberGenerator.new()


## Without a seed it takes the `seed` flag (a whole number, 0 or more; anything else is warned about and ignored), and
## without that a fresh random one.
func _init(seed := -1) -> void:
	if seed < 0:
		seed = _flag_seed()
	if seed < 0:
		_gen.randomize()
		seed = _gen.seed & 0x7FFFFFFFFFFFFFFF # the engine's seed is unsigned; a negative one could not be passed back as `seed=N`
	seed_value = seed
	_gen.seed = seed
	print_verbose("rng: seed %d" % seed)


static func _flag_seed() -> int:
	var text := Flags.value("seed", "")
	if text.is_valid_int() and int(text) >= 0:
		return int(text)
	if text != "":
		push_warning("rng: seed=%s is not a seed (a whole number, 0 or more); using a random one" % text)
	return -1


## An int from a to b, both included.
func int_range(a: int, b: int) -> int:
	return _gen.randi_range(a, b)


## A float in [0, 1).
func real() -> float:
	return _gen.randf()


## True with probability p.
func chance(p: float) -> bool:
	return _gen.randf() < p


func pick(items: Array):
	assert(not items.is_empty(), "rng: pick from an empty array")
	return items[_gen.randi_range(0, items.size() - 1)]


## Shuffles in place (Fisher-Yates), and returns the array for chaining.
func shuffle(items: Array) -> Array:
	for i in range(items.size() - 1, 0, -1):
		var j := _gen.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
	return items
