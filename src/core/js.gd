## The few JavaScript semantics the port leans on, in one place, so every module behaves like the JS it came from.
## Load it with `const J = preload("res://src/core/js.gd")`.
extends RefCounted


## Math.round: halves go up (-2.5 -> -2, 2.5 -> 3), unlike GDScript's round(), which goes away from zero.
static func round_js(x: float) -> int:
	return int(floor(x + 0.5))


## String(n) for a number, as JS writes it: 3.0 -> "3", 2.5 -> "2.5". Numbers parsed from JSON are always
## floats in Godot, so anything shown to the player goes through here (or int()) first.
static func num(x) -> String:
	if x is int:
		return str(x)
	if x is float:
		if is_nan(x):
			return "NaN"
		if is_inf(x):
			return "Infinity" if x > 0 else "-Infinity"
		if x == floor(x) and absf(x) < 1e15:
			return str(int(x))
		return str(x)
	return str(x)


## a + Math.floor(Math.random() * (b - a + 1))
static func rnd(a: int, b: int) -> int:
	return randi_range(a, b)


## arr[Math.floor(Math.random() * arr.length)]
static func pick(arr: Array):
	return null if arr.is_empty() else arr[randi() % arr.size()]


## performance.now(): milliseconds since start, fractional
static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


## Date.now(): milliseconds since the epoch
static func date_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0


## a ?? b
static func nz(a, b):
	return b if a == null else a


## await sleep(ms)
static func sleep(ms: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(maxf(0.0, ms) / 1000.0).timeout


## String.prototype.toUpperCase on anything
static func up(s) -> String:
	return str(s).to_upper()


## A JS-style truthiness test: empty arrays and dictionaries are truthy, as in JS ([] and {} are objects).
static func truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0 and not is_nan(float(v))
	if v is String or v is StringName:
		return v != ""
	return true


## A promise you settle by hand. `await w.wait()` returns its value, at once if it is already settled.
class Waiter:
	extends RefCounted
	signal done(value)
	var settled := false
	var value = null

	func resolve(v = null) -> void:
		if settled:
			return
		settled = true
		value = v
		done.emit(v)

	func wait():
		if settled:
			return value
		return await done


## Promise.all over callables (each may be a coroutine): starts them all, returns their results in order.
static func all(fns: Array) -> Array:
	var results := []
	results.resize(fns.size())
	if fns.is_empty():
		return results
	var w := Waiter.new()
	var left := [fns.size()]
	for i in fns.size():
		_run_one(fns[i], i, results, left, w)
	await w.wait()
	return results


static func _run_one(fn: Callable, i: int, results: Array, left: Array, w: Waiter) -> void:
	results[i] = await fn.call()
	left[0] -= 1
	if left[0] == 0:
		w.resolve(results)
