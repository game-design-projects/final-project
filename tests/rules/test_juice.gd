## Game feel (src/rules/juice.gd): the event bus, shake, hit-stop, danger and view transitions.
extends "res://tests/test_case.gd"

const Juice = preload("res://src/rules/juice.gd")


func _hypot(o: Array) -> float:
	return Vector2(o[0], o[1]).length()


func test_the_bus_delivers_typed_events_and_refuses_unknown_names_or_missing_fields():
	var bus := Juice.create_bus()
	var errors := []
	bus.on_error = func(m): errors.append(m)
	var got := []
	var off := bus.on("enemy:hit", func(p): got.append(p.dmg))
	bus.emit("enemy:hit", {"dmg": 4, "maxHp": 10, "crit": false})
	off.call()
	bus.emit("enemy:hit", {"dmg": 9, "maxHp": 10, "crit": true})
	eq(got, [4])
	eq(errors, [])
	match_re(bus.emit("enemy:hti", {}).error, "no such event")
	match_re(bus.emit("enemy:hit", {"dmg": 1}).error, "needs maxHp, crit")
	bus.on("nope", func(_p): pass)
	eq(errors.size(), 3)
	match_re(errors[0], "no such event")
	match_re(errors[1], "needs maxHp, crit")
	match_re(errors[2], "no such event")
	eq(bus.emit("view:bump"), {}, "a good emit returns an empty result")


func test_a_listener_that_is_gone_never_stops_the_others_or_the_game():
	var bus := Juice.create_bus()
	var got := []
	var node := Node.new()
	bus.on("view:bump", Callable(node, "queue_free"))
	node.free()
	bus.on("view:bump", func(_p): got.append("ok"))
	bus.emit("view:bump")
	eq(got, ["ok"])


func test_the_same_listener_is_added_once_and_one_can_unsubscribe_while_an_event_is_delivered():
	var bus := Juice.create_bus()
	var got := []
	var l := func(_p): got.append("a")
	bus.on("view:bump", l)
	bus.on("view:bump", l)
	bus.emit("view:bump")
	eq(got, ["a"])
	var cell := []
	cell.append(bus.on("view:bump", func(_p):
		got.append("once")
		cell[0].call()))
	bus.emit("view:bump")
	bus.emit("view:bump")
	eq(got, ["a", "a", "once", "a"])
	cell.clear() # the unsubscribe Callable and its listener reference each other


func test_every_event_in_the_catalog_lists_its_fields_as_an_array():
	for name in Juice.FX_EVENTS:
		ok(Juice.FX_EVENTS[name] is Array, name)
		match_re(name, "^[a-z]+:[a-z]+$")


func test_shake_no_trauma_no_motion_a_hit_shakes_then_settles_within_a_second():
	var s := Juice.Shake.new()
	eq(s.offset(0), [0, 0])
	s.add(0.6)
	var peak := 0.0
	var t := 16
	while t <= 300:
		peak = maxf(peak, _hypot(s.offset(t)))
		t += 16
	ok(peak > 1, "it moves")
	ok(peak <= 10, "never past the cap")
	eq(s.offset(1000), [0, 0], "settled after the trauma drains")


func _peak(amount: float) -> float:
	var s := Juice.Shake.new()
	s.offset(0)
	s.add(amount)
	var m := 0.0
	for t in range(1, 121):
		m = maxf(m, _hypot(s.offset(t)))
	return m


func test_shake_grows_with_the_square_of_trauma_so_small_hits_barely_nudge():
	ok(_peak(0.8) > 3 * _peak(0.3))


func test_shake_a_kick_dated_in_the_future_waits_for_its_die_to_land():
	var s := Juice.Shake.new()
	s.offset(0)
	s.add(0.5, 200)
	eq(s.offset(100), [0, 0], "not yet")
	s.offset(210)
	ok(s.trauma > 0.4, "landed")


func test_shake_options_and_trauma_cap():
	var s := Juice.Shake.new({"maxPx": 4, "drainPerSec": 0, "seed": 2})
	s.add(5.0)
	eq(s.trauma, 1.0)
	s.offset(0)
	var peak := 0.0
	for t in range(1, 400):
		peak = maxf(peak, _hypot(s.offset(t * 3)))
	ok(peak > 0.5 and peak <= 4.0 * 1.6, "scaled by maxPx: %s" % peak)
	eq(s.trauma, 1.0, "no drain")


func test_trauma_party_damage_scales_with_the_share_of_health_taken_crits_and_kills_hit_harder():
	ok(Juice.trauma_for("party:hurt", {"dmg": 9, "maxHp": 10}) > Juice.trauma_for("party:hurt", {"dmg": 1, "maxHp": 10}))
	ok(Juice.trauma_for("enemy:hit", {"dmg": 3, "maxHp": 10, "crit": true}) > Juice.trauma_for("enemy:hit", {"dmg": 3, "maxHp": 10, "crit": false}))
	ok(Juice.trauma_for("enemy:kill", {"boss": true}) > Juice.trauma_for("enemy:kill", {"boss": false}))
	eq(Juice.trauma_for("combat:start", {"boss": false}), 0)
	near(Juice.trauma_for("party:hurt", {"dmg": 5, "maxHp": 10}), 0.53)
	near(Juice.trauma_for("enemy:hit", {"dmg": 5, "maxHp": 10, "crit": false}), 0.21)
	for n in Juice.FX_EVENTS:
		ok(Juice.trauma_for(n, {"dmg": 99, "maxHp": 1, "crit": true, "boss": true}) <= 1, n)


func test_hit_stop_the_animation_clock_stands_still_during_a_freeze_then_carries_on_without_a_jump():
	var h := Juice.HitStop.new()
	eq(h.clock(100), 100)
	h.freeze(100, Juice.HITSTOP_MS.crit)
	eq(h.clock(120), 100, "frozen")
	eq(h.clock(180), 100, "still frozen")
	eq(h.clock(200), 200 - Juice.HITSTOP_MS.crit, "carries on from where it stopped")
	eq(h.clock(300), 300 - Juice.HITSTOP_MS.crit)
	h.freeze(300, 50)
	h.freeze(310, 100) # a second blow during the freeze extends it
	eq(h.clock(400), 300 - Juice.HITSTOP_MS.crit)
	eq(h.clock(500), 500 - Juice.HITSTOP_MS.crit - 110)


func _m(hp, max_hp := 10, extra := {}) -> Dictionary:
	var m := {"hp": hp, "maxHp": max_hp, "dead": false, "down": false}
	m.merge(extra, true)
	return m


func test_danger_none_at_half_health_or_more_rising_as_health_runs_out_high_while_someone_is_dying():
	eq(Juice.danger_of([_m(10), _m(10), _m(10)]), 0)
	eq(Juice.danger_of([_m(5), _m(5)]), 0)
	ok(Juice.danger_of([_m(3), _m(3)]) > 0 and Juice.danger_of([_m(3), _m(3)]) < 1)
	eq(Juice.danger_of([_m(1), _m(1), _m(1, 20)]), 1)
	ok(Juice.danger_of([_m(10), _m(10), _m(0, 10, {"down": true})]) >= 0.6, "someone rolling death saves")
	ok(Juice.danger_of([_m(10), _m(10), _m(0, 10, {"down": true, "stable": true})]) < 0.6, "stable is not dying")
	eq(Juice.danger_of([_m(0, 10, {"dead": true})]), 1, "everyone dead")
	eq(Juice.danger_of([_m(10), _m(0, 10, {"dead": true})]), 0, "the dead don't count against the living")
	near(Juice.danger_of([_m(10), _m(10), _m(0, 10, {"down": true}), _m(0, 10, {"down": true})]), 0.8)


func test_approach_eases_toward_the_target_at_the_same_speed_whatever_the_frame_rate():
	var a := 0.0
	for i in 4:
		a = Juice.approach(a, 1, 62.5, 250)
	var b := Juice.approach(0, 1, 250, 250)
	near(a, b, 1e-9)
	near(b, 0.5, 1e-9)


func test_view_transitions_a_step_forward_grows_the_old_frame_and_fades_it_a_turn_pans_both_end_on_time():
	var step = Juice.transition_at({"kind": "step", "dir": 1, "t0": 0}, Juice.TRANSITION_MS.step / 2.0)
	ok(step.scale > 1 and step.alpha > 0 and step.alpha < 1)
	ok(Juice.transition_at({"kind": "step", "dir": -1, "t0": 0}, 50).scale < 1, "stepping back shrinks it")
	var left = Juice.transition_at({"kind": "turn", "dir": -1, "t0": 0}, 80)
	ok(left.shift > 0, "turning left slides the old view off to the right")
	ok(Juice.transition_at({"kind": "turn", "dir": 1, "t0": 0}, 80).shift < 0)
	for kind in Juice.TRANSITION_MS:
		eq(Juice.transition_at({"kind": kind, "dir": 1, "t0": 0}, Juice.TRANSITION_MS[kind]), null, kind)
	eq(Juice.transition_at(null, 0), null)
	var bump = Juice.transition_at({"kind": "bump", "t0": 10}, 80)
	eq(bump.kind, "bump")
	ok(bump.scale > 1 and bump.alpha == 0)
	eq(Juice.transition_at({"kind": "step", "dir": 1, "t0": 100}, 50), null, "not started yet")
