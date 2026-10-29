## The debug request inspector's summaries, copy lookups and JSON coloring.
extends "res://tests/test_case.gd"

const Inspector = preload("res://src/rules/inspector.gd")


func _call(q: int, tokens: int) -> Dictionary:
	var questions := {}
	for i in q:
		questions["q%d" % i] = {}
	return {"state": {"a": 1}, "questions": questions, "status": 200, "ms": 120, "response": {"answers": {"q0": {"noul": 0.4}}, "usage": {"input_tokens": tokens}}}


func _entry(over := {}) -> Dictionary:
	var e := {"n": 3, "path": "/api/group-turn", "at": "23:41:05", "request": {"x": "<hi>"}, "status": 200, "ms": 240, "response": {"results": []}, "jev": [_call(12, 900), _call(4, 300)]}
	e.merge(over, true)
	return e


func test_a_request_is_summed_up_by_name_status_time_and_what_jev_was_asked():
	eq(Inspector.summarize(_entry()), {"name": "GROUP TURN", "state": "ok", "status": "200", "ms": 240, "calls": 2, "questions": 16, "tokens": 1200, "traced": true})


func test_failed_pending_and_untraced_requests_read_as_such():
	eq(Inspector.summarize(_entry({"status": 503})).state, "bad")
	eq(Inspector.summarize(_entry({"status": "FAILED"})).state, "bad")
	eq(Inspector.summarize(_entry({"status": "FAILED"})).status, "FAILED")
	var pending := Inspector.summarize(_entry({"status": null}))
	eq(pending.state, "pending")
	eq(pending.status, "…")
	var s := Inspector.summarize(_entry({"jev": null}))
	eq(s.traced, false)
	eq(s.calls, 0)
	eq(s.tokens, 0)


func test_numbers_parsed_from_json_summarize_like_ints():
	var e = JSON.parse_string(JSON.stringify(_entry()))
	var s := Inspector.summarize(e)
	eq(s.status, "200")
	eq(s.tokens, 1200)
	eq(s.questions, 16)


func test_copy_buttons_find_the_right_piece():
	var log := [_entry()]
	eq(Inspector.find_value(log, "3:request"), {"x": "<hi>"})
	eq(Inspector.find_value(log, "3:1:questions"), _call(4, 300).questions)
	eq(Inspector.find_value(log, "3:0:answers"), {"q0": {"noul": 0.4}})
	eq(Inspector.find_value(log, "3:0:state"), {"a": 1})
	eq(Inspector.find_value(log, "3").n, 3)
	eq(Inspector.find_value(log, "3:response"), {"results": []})
	eq(Inspector.find_value(log, "9:request"), null)
	eq(Inspector.find_value(log, "3:7:state"), null)
	eq(Inspector.find_value(log, "x:request"), null)
	eq(Inspector.find_value([_entry({"jev": null})], "3:0:state"), null)


func test_copy_value_returns_the_pretty_json_text():
	var log := [_entry()]
	eq(Inspector.copy_value(log, "3:request"), '{\n  "x": "<hi>"\n}')
	eq(Inspector.copy_value(log, "9:request"), "null")


func test_json_text_matches_what_js_would_print():
	eq(Inspector.json_text({"a": [1, 2.0, 2.5, "x\"y"], "b": {}, "c": [], "d": null, "e": true}), '{\n  "a": [\n    1,\n    2,\n    2.5,\n    "x\\"y"\n  ],\n  "b": {},\n  "c": [],\n  "d": null,\n  "e": true\n}')
	eq(Inspector.json_text(7.0), "7")
	eq(Inspector.json_text("é\n"), '"é\\n"')


func test_json_is_colored_by_token_kind_keys_strings_numbers_true_false_null():
	var value := {"name": "Drip [3", "hp": -7, "p": 0.25, "ok": true, "none": null, "id": "e0", "list": [1]}
	var h := Inspector.highlight_json(value)
	ok(h.contains('[color=#7fd6ff]"name"[/color]:'), h)
	ok(h.contains('[color=#f2e6c4]"Drip [lb]3"[/color]'), "brackets inside strings are escaped")
	ok(h.contains("[color=#6bd36b]-7[/color]") and h.contains("[color=#6bd36b]0.25[/color]"))
	ok(h.contains("[color=#ff9de2]true[/color]") and h.contains("[color=#ff9de2]null[/color]"))
	ok(h.contains('[color=#f2e6c4]"e0"[/color]'), "digits inside strings stay part of the string")
	ok(h.contains("[lb]\n") and h.contains("[rb]"), "the array's own brackets are escaped")
	# Stripping the markup gives back exactly the pretty JSON
	var plain := RegEx.create_from_string("\\[/?color[^\\]]*\\]").sub(h, "", true).replace("[lb]", "[").replace("[rb]", "]")
	eq(plain, Inspector.json_text(value))
	eq(Inspector.highlight_json(null), "[color=#ff9de2]null[/color]")
