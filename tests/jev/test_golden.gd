# What Jev is asked, byte for byte. golden/*.json holds, for each scenario, a request body and the {model, state,
# questions} the JavaScript game sent to Jev for it (recorded from the web version with a node script, kept in git history before the JS was removed). The port must send exactly the same
# text in exactly the same order: Jev's answers depend on the wording and on the order of the options.
extends "res://tests/test_case.gd"

const JevApi = preload("res://src/jev/api.gd")
const Jev = preload("res://src/jev/jev.gd")
const MockJev = preload("res://src/jev/mock_jev.gd")

const DIR := "res://tests/jev/golden"


func before_each():
	seed(5)


func after_each():
	Jev.configure_jev()


static func full(v) -> String:
	return JSON.stringify(v, "", false, true)


## The first place two JSON texts differ, with a little context, or "" when they are equal
static func first_difference(want: String, got: String) -> String:
	if want == got:
		return ""
	var i := 0
	while i < want.length() and i < got.length() and want[i] == got[i]:
		i += 1
	return "differ at %d:\n  want …%s…\n  got  …%s…" % [i, want.substr(maxi(0, i - 60), 140), got.substr(maxi(0, i - 60), 140)]


func test_every_scenario_asks_jev_exactly_what_the_js_asked():
	var names: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json") and f != "results.json":
			names.append(f)
	names.sort()
	ok(names.size() >= 11, "golden files are there (%d)" % names.size())
	for f in names:
		var golden = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(f)))
		var server := MockJev.Server.new(1)
		Jev.configure_jev({"via": "systemone", "api_base": "http://s1.test", "transport": server})
		var r: Dictionary = await JevApi.handle(golden["path"], golden["body"])
		eq(r["status"], 200, "%s: %s" % [f, r["body"]])
		eq(server.calls.size(), 1, "%s: one Jev call" % f)
		if server.calls.size() != 1:
			continue
		var want: Dictionary = golden["request"]
		var got: Dictionary = server.calls[0]
		eq(got["model"], "decider", "%s: the model is the provider's; the fixtures recorded Jev's" % f)
		var d := first_difference(full(want["state"]), full(got["state"]))
		ok(d == "", "%s state %s" % [f, d])
		d = first_difference(full(want["questions"]), full(got["questions"]))
		ok(d == "", "%s questions %s" % [f, d])
