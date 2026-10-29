## Small helpers the jev modules share, for numbers and text that JS handles by itself.
## Load it with `const U = preload("res://src/jev/util.gd")`.
extends RefCounted

const J = preload("res://src/core/js.gd")


## 3.0 → 3: numbers that were whole in JS stay ints (so JSON shows `3`, not `3.0`, and text reads right)
static func norm(x):
	if x is float and is_finite(x) and x == floor(x) and absf(x) < 1e15:
		return int(x)
	return x


## Number(v) || fallback: v as a number if it reads as a non-zero finite number, else the fallback
static func num_or(v, fallback):
	var n := NAN
	if v is int or v is float:
		n = float(v)
	elif v is bool:
		n = 1.0 if v else 0.0
	elif v is String:
		var s := (v as String).strip_edges()
		n = 0.0 if s == "" else (s.to_float() if s.is_valid_float() else NAN)
	elif v == null:
		n = 0.0
	if is_nan(n) or is_inf(n) or n == 0.0:
		return fallback
	return v if (v is int or v is float) else norm(n)


## arr.slice(-n): the last n elements (all of them when there are fewer)
static func last(arr: Array, n: int) -> Array:
	return arr.slice(maxi(0, arr.size() - n))


## String(v) as JS writes it
static func js_str(v) -> String:
	if v == null:
		return "null"
	if v is bool:
		return "true" if v else "false"
	if v is float or v is int:
		return J.num(v)
	return str(v)


## String(v ?? "").slice(0, n)
static func short(v, n := 240) -> String:
	return js_str(J.nz(v, "")).left(n)
