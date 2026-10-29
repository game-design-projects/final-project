extends "res://tests/test_case.gd"

const J = preload("res://src/core/js.gd")
const StoreScript = preload("res://src/core/store.gd")


func test_round_matches_math_round():
	eq(J.round_js(2.5), 3)
	eq(J.round_js(-2.5), -2)
	eq(J.round_js(1.49), 1)


func test_num_prints_like_js():
	eq(J.num(3.0), "3")
	eq(J.num(7), "7")
	eq(J.num(2.5), "2.5")


func test_truthy_treats_containers_like_js():
	ok(J.truthy([]))
	ok(J.truthy({}))
	ok(not J.truthy(""))
	ok(not J.truthy(0))
	ok(not J.truthy(null))


func _later(v, ms):
	await J.sleep(ms)
	return v


func test_all_keeps_order_and_waits():
	var out = await J.all([func(): return await _later("a", 30), func(): return "b", func(): return await _later("c", 5)])
	eq(out, ["a", "b", "c"])


func test_all_when_every_callable_is_synchronous():
	var out = await J.all([func(): return 1, func(): return 2])
	eq(out, [1, 2])


func test_waiter_settled_before_wait():
	var w := J.Waiter.new()
	w.resolve(5)
	eq(await w.wait(), 5)


func test_memory_store():
	var s = StoreScript.Memory.new({"a": "1"})
	eq(s.get_item("a"), "1")
	eq(s.get_item("b"), null)
	s.set_item("b", 2)
	eq(s.get_item("b"), "2")
