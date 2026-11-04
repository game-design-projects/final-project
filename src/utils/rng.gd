## Seeded random numbers. Anything random in the game goes through one of these instead of the engine's global
## generator, so a run started with `seed=N` plays out the same way every time.
extends RefCounted

const Flags = preload("res://src/utils/flags.gd")

const INT64_MAX_TEXT := "9223372036854775807"

## The seed this generator started from, so a run can print it and be repeated.
var seed_value := 0

var _gen := RandomNumberGenerator.new()


## Without a seed it takes the `seed` flag (see `flag_seed`), and
## without that a fresh random one.
func _init(seed := -1) -> void:
	if seed < 0:
		seed = flag_seed()
	if seed < 0:
		_gen.randomize()
		seed = _gen.seed & 0x7FFFFFFFFFFFFFFF # the engine's seed is unsigned; a negative one could not be passed back as `seed=N`
	seed_value = seed
	_gen.seed = seed
	print_verbose("rng: seed %d" % seed)


## The `seed` flag as a seed: a whole number from 0 to 9223372036854775807, or -1 when it is absent or not one. A flag that
## is present but not a seed is warned about once, saying what happens instead (`fallback`). The one place the rule lives;
## a tool with its own fallback uses this instead of parsing the flag again. Every seed the game prints is one this takes.
static func flag_seed(fallback := "using a random one") -> int:
	var text := Flags.value("seed", "")
	var seed := _parse_seed(text)
	if seed < 0 and text != "":
		push_warning("rng: seed=%s is not a seed (a whole number from 0 to %s); %s" % [text, INT64_MAX_TEXT, fallback])
	return seed


## -1 unless the text is a whole number that fits 0..INT64_MAX (`-0` is 0). Compared as text, because `int()` clamps or wraps
## a number that is too big (and logs an engine error).
static func _parse_seed(text: String) -> int:
	if not text.is_valid_int():
		return -1
	var negative := text.begins_with("-")
	var digits := text.lstrip("+-").lstrip("0")
	if digits == "":
		return 0
	if negative or digits.length() > INT64_MAX_TEXT.length() or (digits.length() == INT64_MAX_TEXT.length() and digits > INT64_MAX_TEXT):
		return -1
	return int(digits)


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
