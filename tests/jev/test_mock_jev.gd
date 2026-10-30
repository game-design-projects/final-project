# mulberry32 parity with the JS (node: seeded(seed) from crawler/src/mock-jev.js, printed with full precision) and the
# mock's answer shapes. Numbers are compared as their shortest round-trip text: GDScript's own float literals are not
# parsed to the exact double, so an expected number written as a literal would differ in the last digit.
extends "res://tests/test_case.gd"

const MockJev = preload("res://src/jev/mock_jev.gd")

# first five numbers of seeded(seed), from node
const EXPECTED := {
	1: ["0.6270739405881613", "0.002735721180215478", "0.5274470399599522", "0.9810509674716741", "0.9683778982143849"],
	42: ["0.6011037519201636", "0.44829055899754167", "0.8524657934904099", "0.6697340414393693", "0.17481389874592423"],
	0: ["0.26642920868471265", "0.0003297457005828619", "0.2232720274478197", "0.1462021479383111", "0.46732782293111086"],
	4294967295: ["0.8964226141106337", "0.189478256739676", "0.7156526781618595", "0.9440599093213677", "0.8452364315744489"],
	123456789: ["0.2577907438389957", "0.9707721115555614", "0.7853280142880976", "0.20616457983851433", "0.30307188746519387"],
}


## JSON text with every digit, in insertion order (what node's JSON.stringify prints)
static func full(v) -> String:
	return JSON.stringify(v, "", false, true)


func test_seeded_is_bit_exact_mulberry32():
	for seed in EXPECTED:
		var rand := MockJev.seeded(seed)
		for want in EXPECTED[seed]:
			eq(full(rand.call()), want, "seed %d" % seed)


func test_seed_is_taken_modulo_2_pow_32_like_unsigned_shift():
	eq(full(MockJev.seeded(-1).call()), "0.8964226141106337", "-1 >>> 0 is 4294967295")
	eq(full(MockJev.seeded(4294967295 + 1).call()), "0.26642920868471265", "2^32 wraps to 0")
	eq(full(MockJev.seeded(7.9).call()), "0.011704753153026104", "a fraction is truncated")


func test_two_generators_with_one_seed_agree_and_do_not_share_state():
	var a := MockJev.seeded(9)
	var b := MockJev.seeded(9)
	var xs := [a.call(), a.call(), a.call()]
	eq([b.call(), b.call(), b.call()], xs)


func test_answers_match_the_js_for_a_seed():
	var r := MockJev.seeded(3)
	eq(full(MockJev.mock_answer({"type": "noul"}, r)), '{"type":"noul","noul":0.7202267837710679}')
	eq(
		full(MockJev.mock_answer({"type": "choice", "criteria": {"a": "x", "b": "y", "c": "z"}}, r)),
		'{"type":"choice","choice":"b","probabilities":{"a":0.04687525183193449,"b":0.8894505436742821,"c":0.06367420449378348}}',
	)
	eq(
		full(MockJev.mock_answer({"type": "score", "criteria": ["no", "some", "lots", "very"]}, r)),
		'{"type":"score","score":0.7556290726368644,"confidence":0.5,"probabilities":{"0":0.5302461114257472,"1":0.21627440927392397,"2":0.2210837745380464,"3":0.03239570476228256}}',
	)


func test_a_whole_system_one_reply_matches_the_js():
	var questions := {
		"q1": {"type": "noul", "instructions": "x"},
		"q2": {"type": "choice", "instructions": "y", "criteria": {"a": 1, "b": 2}},
		"q3": {"type": "score", "instructions": "z", "criteria": ["a", "b", "c"]},
	}
	var out := MockJev.mock_system_one({"questions": questions}, MockJev.seeded(5))
	eq(
		full(out),
		'{"model":"jev-mock","answers":{"q1":{"type":"noul","noul":0.6897749109193683},"q2":{"type":"choice","choice":"a","probabilities":{"a":0.9123935492361843,"b":0.08760645076381574}},"q3":{"type":"score","score":0.9514433924833461,"confidence":0.5,"probabilities":{"0":0.5131683959579686,"1":0.02221981560071658,"2":0.46461178844131473}}},"usage":{"input_tokens":43}}',
	)


func test_mock_answers_have_the_shape_the_sdk_documents():
	var r := MockJev.seeded(3)
	var n := MockJev.mock_answer({"type": "noul"}, r)
	ok(n["noul"] >= 0 and n["noul"] <= 1)
	var c := MockJev.mock_answer({"type": "choice", "criteria": {"a": "x", "b": "y", "c": "z"}}, r)
	ok(["a", "b", "c"].has(c["choice"]))
	var sum := 0.0
	for p in c["probabilities"].values():
		sum += p
	ok(absf(sum - 1) < 1e-9)
	eq(c["probabilities"][c["choice"]], (c["probabilities"].values() as Array).max())
	var s := MockJev.mock_answer({"type": "score", "criteria": ["no", "some", "lots", "very"]}, r)
	ok(s["score"] >= 0 and s["score"] <= 3)
	eq(s["probabilities"].keys(), ["0", "1", "2", "3"])


func test_the_same_seed_gives_the_same_answers():
	var q := {"type": "choice", "criteria": {"a": 1, "b": 2, "c": 3}}
	eq(MockJev.mock_answer(q, MockJev.seeded(9)), MockJev.mock_answer(q, MockJev.seeded(9)))


func test_an_unknown_question_type_is_an_error_not_a_crash():
	ok(MockJev.mock_answer({"type": "wat"}, MockJev.seeded(1)).has("error"))
	ok(MockJev.mock_system_one({"questions": {"q": {"type": "wat"}}}, MockJev.seeded(1)).has("error"))


func test_server_answers_system_one_urls_records_calls_and_refuses_others():
	var server := MockJev.Server.new(5)
	var body := {"model": "jev-latest", "state": {}, "questions": {"q1": {"type": "noul", "instructions": "x"}}}
	var res: Dictionary = await server.fetch(MockJev.JEV_URL, {}, body)
	eq(res["status"], 200)
	eq(res["json"]["answers"]["q1"]["noul"], MockJev.mock_system_one(body, MockJev.seeded(5))["answers"]["q1"]["noul"])
	eq(server.calls.size(), 1)
	eq(server.calls[0]["model"], "jev-latest")
	var elsewhere: Dictionary = await server.fetch("http://gpu-box:8000/v1/systemone", {}, body)
	eq(elsewhere["status"], 200, "any System One endpoint")
	ok((await server.fetch("https://example.com/", {}, body)).has("error"), "only System One endpoints are mocked")
	eq(server.calls.size(), 2)
