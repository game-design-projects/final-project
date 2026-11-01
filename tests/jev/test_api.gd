# The game's API end to end against the mock model: every endpoint answers and debug mode returns each raw model call.
# Ported from crawler/test/api.test.js, plus the sanitisers and error paths.
extends "res://tests/test_case.gd"

const JevApi = preload("res://src/jev/api.gd")
const Jev = preload("res://src/jev/jev.gd")
const MockJev = preload("res://src/jev/mock_jev.gd")
const Species = preload("res://src/rules/species.gd")

var fake: MockJev.Server

const PARTY := [
	{"id": "h0", "name": "HORTENSE", "kind": "human", "hp": 14, "maxHp": 14},
	{"id": "h1", "name": "ROLF", "kind": "human", "hp": 13, "maxHp": 13},
]


func before_each():
	seed(7)
	fake = MockJev.Server.new(42)
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": fake})


func after_each():
	Jev.configure_jev()


static func mon(id: String, species: String, name: String) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[species]
	return {
		"id": id, "species": species, "name": name, "traits": sp["traits"].slice(0, 2), "hp": sp["hp"][1], "maxHp": sp["hp"][1],
		"meters": sp["start"].duplicate(), "specialReady": true, "impressions": [], "grudges": [], "thisRound": [],
	}


func endpoints() -> Dictionary:
	return {
		"/api/group-turn": {"monsters": [mon("e0", "goblin", "Grok"), mon("e1", "slime", "Glop")], "party": PARTY.duplicate(true), "round": 1, "playerAction": {"type": "talk", "message": "Glop, join us?"}, "events": ["The party spoke."], "conversation": [], "partyGold": 40},
		"/api/enemy-turn": {"enemy": mon("e0", "slime", "Drip"), "party": PARTY.duplicate(true), "round": 1, "playerAction": {"type": "start"}, "events": [], "conversation": [], "partyGold": 10},
		"/api/ally-reactions": {"allies": [{"id": "a1", "species": "slime", "name": "Glop", "traits": ["shy", "hungry"], "loyalty": 60}], "events": ["The party killed a begging slime."]},
		"/api/ally-talk": {"ally": {"id": "a1", "species": "goblin", "name": "Grok", "traits": ["greedy", "boastful"], "loyalty": 50}, "message": "You fought well.", "vows": []},
		"/api/vow": {"monster": {"species": "dragon", "name": "Vex", "traits": ["vain", "proud"]}, "vow": {"text": "i will not run from dragons"}},
		"/api/vow-broken": {"monster": {"species": "slime", "name": "Glop", "traits": ["shy", "hungry"]}, "vow": {"text": "i won't kill slimes"}, "how": "The party killed a slime.", "gold": 30},
	}


func test_every_endpoint_works_against_the_mock_jev():
	var all := endpoints()
	for path in all:
		var r: Dictionary = await JevApi.handle(path, all[path].duplicate(true))
		eq(r["status"], 200, "%s: %s" % [path, r["body"]])
		ok(not r["body"].has("_debug"), "%s: no debug data unless asked" % path)


func test_debug_mode_returns_every_raw_jev_call_and_never_the_key():
	var all := endpoints()
	for path in all:
		var before := fake.calls.size()
		var r: Dictionary = await JevApi.handle(path, all[path].duplicate(true), {"debug": true})
		eq(r["status"], 200, "%s: %s" % [path, r["body"]])
		var calls: Array = r["body"]["_debug"]["jev"]
		ok(calls.size() >= 1, path)
		eq(calls.size(), fake.calls.size() - before, "%s: one trace entry per Jev call" % path)
		for c in calls:
			ok(c.has("state") and c.has("questions") and c.get("response", {}).has("answers"), "request and response both recorded")
			eq(c["status"], 200)
			ok(c["ms"] >= 0)
			eq(c["model"], "decider")


func test_the_local_model_is_reached_the_same_way():
	Jev.configure_jev({"via": "local", "transport": fake})
	var before := fake.calls.size()
	var r: Dictionary = await JevApi.handle("/api/vow", endpoints()["/api/vow"], {"debug": true})
	eq(r["status"], 200)
	eq(fake.calls[-1]["model"], "decider")
	eq(r["body"]["_debug"]["jev"][0]["via"], "local")
	ok(fake.calls.size() > before)


func test_the_request_body_is_never_modified():
	var body: Dictionary = endpoints()["/api/group-turn"]
	body["events"] = ["x".repeat(500)]
	body["monsters"][0]["impressions"] = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
	var snapshot := body.duplicate(true)
	await JevApi.handle("/api/group-turn", body)
	eq(body, snapshot)


func test_unknown_routes_species_and_empty_groups_are_refused_without_asking_jev():
	var before := fake.calls.size()
	var r: Dictionary = await JevApi.handle("/nope", {})
	eq([r["status"], r["body"]], [404, {"error": "Not found"}])
	r = await JevApi.handle("/api/nope", {})
	eq(r["status"], 404)
	r = await JevApi.handle("/api/vow", {"monster": {"species": "unicorn", "name": "X"}, "vow": {"text": "t"}})
	eq([r["status"], r["body"]], [400, {"error": "Unknown monster"}])
	r = await JevApi.handle("/api/ally-talk", {"message": "hi"})
	eq(r["status"], 400)
	r = await JevApi.handle("/api/enemy-turn", {"enemy": {"species": "unicorn"}})
	eq(r["status"], 400)
	r = await JevApi.handle("/api/group-turn", {"monsters": [], "party": []})
	eq([r["status"], r["body"]], [400, {"error": "No monsters"}])
	var bad: Dictionary = endpoints()["/api/group-turn"]
	bad["monsters"].append({"id": "e9", "species": "unicorn", "name": "X"})
	eq((await JevApi.handle("/api/group-turn", bad))["status"], 400)
	eq(fake.calls.size(), before, "none of those reached Jev")


func test_a_request_over_64kb_is_too_large():
	var body: Dictionary = endpoints()["/api/vow"]
	body["padding"] = "x".repeat(70000)
	var r: Dictionary = await JevApi.handle("/api/vow", body)
	eq([r["status"], r["body"]], [413, {"error": "Request too large"}])
	eq(fake.calls.size(), 0)


func test_player_text_is_trimmed_before_it_reaches_jev():
	var body: Dictionary = endpoints()["/api/group-turn"]
	body["playerAction"] = {"type": "talk", "message": "m".repeat(600), "gold": -5, "delivery": 9, "pitch": "nonsense"}
	body["events"] = range(20).map(func(i): return "event %d %s" % [i, "e".repeat(300)])
	body["conversation"] = range(15).map(func(i): return {"speaker": "S%d" % i, "text": "t".repeat(400)})
	body["party"] = range(9).map(func(i): return {"id": "h%d" % i, "name": "P%d" % i, "kind": "human", "hp": 5, "maxHp": 5})
	body["monsters"][0]["impressions"] = range(12).map(func(i): return "impression %d" % i)
	body["monsters"][0]["thisRound"] = range(9).map(func(i): return "this %d" % i)
	body["vows"] = range(15).map(func(i): return {"text": "v".repeat(200), "toId": "e0", "status": "kept"})
	var r: Dictionary = await JevApi.handle("/api/group-turn", body)
	eq(r["status"], 200, str(r["body"]))
	var asked: Dictionary = fake.calls[-1]
	var state: Dictionary = asked["state"]
	eq(state["party"]["this_round"].size(), 12, "12 events at most")
	for e in state["party"]["this_round"]:
		ok(e.length() <= 200)
	eq(state["party"]["latest_message"].length(), 240, "the message is cut to 240")
	eq(state["recent_conversation"].size(), 8, "the last 8 lines of the last 10")
	eq(state["recent_conversation"][0].split(": ")[0], "S7")
	eq(state["party"]["members"].size(), 6, "6 party members at most")
	eq(state["monsters"]["e0"]["impressions"].size(), 6, "the last 6 impressions")
	eq(state["monsters"]["e0"]["impressions"][0], "impression 6")
	eq(state["monsters"]["e0"]["promises_party_made_to_it"].size(), 12, "12 vows at most")
	eq(r["body"]["results"].size(), 2)


func test_gold_and_delivery_arrive_as_clean_numbers():
	# 3.0 from a JSON parse must read as 3 in the text Jev sees ("3 gold", not "3.0 gold")
	var body: Dictionary = endpoints()["/api/group-turn"]
	body["playerAction"] = {"type": "give", "targetId": "e0", "gold": 3.0, "message": null}
	await JevApi.handle("/api/group-turn", body)
	ok(fake.calls[-1]["state"]["party"]["offering"].begins_with("3 gold to Grok"), fake.calls[-1]["state"]["party"]["offering"])


func test_a_jev_failure_is_a_500_server_error_with_the_trace_in_debug_mode():
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": FailingJev.new(500)})
	var r: Dictionary = await JevApi.handle("/api/vow", endpoints()["/api/vow"])
	eq([r["status"], r["body"]], [500, {"error": "Server error"}])
	r = await JevApi.handle("/api/vow", endpoints()["/api/vow"], {"debug": true})
	eq(r["status"], 500)
	eq(r["body"]["_debug"]["jev"][0]["status"], 500)
	ok(r["body"]["_debug"]["jev"][0]["error"].contains("down for lunch"))


func test_a_reply_missing_the_answers_the_rules_need_is_a_500_not_a_crash():
	Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": EmptyJev.new()})
	for path in ["/api/group-turn", "/api/ally-reactions", "/api/ally-talk", "/api/vow", "/api/vow-broken"]:
		var r: Dictionary = await JevApi.handle(path, endpoints()[path])
		eq(r["status"], 500, path)


func test_a_query_string_can_ask_for_debug_like_the_web_api():
	var r: Dictionary = await JevApi.handle("/api/vow?debug=1", endpoints()["/api/vow"])
	eq(r["status"], 200)
	ok(r["body"].has("_debug"))


class FailingJev:
	extends RefCounted
	var status: int

	func _init(s: int) -> void:
		status = s

	func fetch(_url, _headers, _body) -> Dictionary:
		return {"status": status, "text": "down for lunch"}


class EmptyJev:
	extends RefCounted

	func fetch(_url, _headers, _body) -> Dictionary:
		return {"status": 200, "json": {"answers": {}, "usage": {"input_tokens": 1}, "model": "empty"}}
