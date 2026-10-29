# How the game decides to reach Jev. Every source is injected: these tests never read the real .env, the real
# jev_config.json or an API key from the environment.
extends "res://tests/test_case.gd"

const JevConfig = preload("res://src/jev/config.gd")
const Jev = preload("res://src/jev/jev.gd")

const NOTHING := {"json_text": "", "dotenv_text": "", "exported": false, "flags_text": "", "env": {}}


func before_each():
	JevConfig.reset()
	Jev.configure_jev(null)


func after_each():
	JevConfig.reset()
	Jev.configure_jev(null)


static func with(overrides: Dictionary) -> Dictionary:
	return NOTHING.merged(overrides, true)


func test_the_mock_flag_wins_over_any_key():
	var cfg := JevConfig.resolve(with({"flags_text": "floor5-debug mock", "dotenv_text": "OPENROUTER_API_KEY=sk-or-abc", "json_text": "{\"key\":\"k\"}"}))
	eq(cfg["provider"], "mock")
	eq(cfg["warning"], "", "a chosen mock is not a warning")
	eq(cfg["key"], "")


func test_the_mock_flag_is_case_insensitive_like_the_js_regexes():
	eq(JevConfig.resolve(with({"flags_text": "?MOCK"}))["provider"], "mock")


func test_jev_mock_env_asks_for_the_mock():
	eq(JevConfig.resolve(with({"env": {"JEV_MOCK": "1"}, "dotenv_text": "TYPESAFE_API_KEY=k"}))["provider"], "mock")
	eq(JevConfig.resolve(with({"env": {"JEV_MOCK": "0"}}))["provider"], "mock", "no key anywhere is a mock anyway")
	ok(JevConfig.resolve(with({"env": {"JEV_MOCK": "0"}, "dotenv_text": "TYPESAFE_API_KEY=k"}))["provider"] == "typesafe", "only JEV_MOCK=1 means mock")


func test_the_seed_comes_from_the_flag_then_the_env_then_the_clock():
	eq(JevConfig.resolve(with({"flags_text": "mock seed=7"}))["seed"], 7)
	eq(JevConfig.resolve(with({"flags_text": "mock --seed=12", "env": {"JEV_SEED": "9"}}))["seed"], 12)
	eq(JevConfig.resolve(with({"flags_text": "mock", "env": {"JEV_MOCK": "1", "JEV_SEED": "9"}}))["seed"], 9)
	var clock: int = JevConfig.resolve(with({"flags_text": "mock"}))["seed"]
	ok(clock > 0 and clock < 1000000, "a clock-based seed when nothing says (%d)" % clock)


func test_the_json_config_of_an_exported_build():
	var cfg := JevConfig.resolve(with({"exported": true, "json_text": "{\"provider\":\"openrouter\",\"key\":\"sk-or-xyz\",\"debug\":true}"}))
	eq([cfg["provider"], cfg["key"], cfg["debug"], cfg["source"], cfg["warning"]], ["openrouter", "sk-or-xyz", true, "jev_config.json", ""])
	cfg = JevConfig.resolve(with({"exported": true, "json_text": "{\"provider\":\"typesafe\",\"key\":\"tk\"}"}))
	eq([cfg["provider"], cfg["debug"]], ["typesafe", false])


func test_the_provider_is_guessed_from_the_key_when_the_json_does_not_name_one():
	eq(JevConfig.resolve(with({"json_text": "{\"key\":\"sk-or-1\"}"}))["provider"], "openrouter")
	eq(JevConfig.resolve(with({"json_text": "{\"key\":\"abc\"}"}))["provider"], "typesafe")


func test_a_proxy_config_needs_no_key():
	var cfg := JevConfig.resolve(with({"exported": true, "json_text": "{\"provider\":\"proxy\",\"apiBase\":\"https://jev.example.workers.dev/\"}"}))
	eq([cfg["provider"], cfg["api_base"], cfg["key"], cfg["warning"]], ["proxy", "https://jev.example.workers.dev", "", ""])
	eq(JevConfig.resolve(with({"json_text": "{\"apiBase\":\"https://x.dev\"}"}))["provider"], "proxy", "an apiBase and no key means proxy")
	eq(JevConfig.resolve(with({"json_text": "{\"provider\":\"proxy\"}"}))["provider"], "mock", "a proxy without an apiBase is unusable")


func test_a_broken_or_keyless_json_falls_through():
	for text in ["not json", "[1,2]", "{\"provider\":\"typesafe\"}", "{\"provider\":\"gemini\",\"key\":\"k\"}", "{\"key\":\"\"}"]:
		var cfg := JevConfig.resolve(with({"exported": true, "json_text": text}))
		eq(cfg["provider"], "mock", text)
		ok(cfg["warning"] != "", text)
	var cfg := JevConfig.resolve(with({"json_text": "not json", "dotenv_text": "TYPESAFE_API_KEY=from-env-file"}))
	eq([cfg["provider"], cfg["key"]], ["typesafe", "from-env-file"], "a broken json does not hide the .env")


func test_dotenv_prefers_openrouter_over_typesafe():
	var cfg := JevConfig.resolve(with({"dotenv_text": "TYPESAFE_API_KEY=tk\nOPENROUTER_API_KEY=ok\n"}))
	eq([cfg["provider"], cfg["key"], cfg["source"]], ["openrouter", "ok", ".env"])
	cfg = JevConfig.resolve(with({"dotenv_text": "OTHER=1\nTYPESAFE_API_KEY=tk\n"}))
	eq([cfg["provider"], cfg["key"]], ["typesafe", "tk"])


func test_a_blank_key_in_dotenv_is_no_key():
	var cfg := JevConfig.resolve(with({"dotenv_text": "OPENROUTER_API_KEY=\nTYPESAFE_API_KEY=real"}))
	eq([cfg["provider"], cfg["key"]], ["typesafe", "real"])


func test_an_exported_build_ignores_dotenv():
	var cfg := JevConfig.resolve(with({"exported": true, "dotenv_text": "OPENROUTER_API_KEY=sk-or-abc"}))
	eq(cfg["provider"], "mock")
	ok(cfg["warning"] != "")


func test_the_json_takes_precedence_over_dotenv():
	var cfg := JevConfig.resolve(with({"json_text": "{\"provider\":\"typesafe\",\"key\":\"from-json\"}", "dotenv_text": "OPENROUTER_API_KEY=from-env"}))
	eq([cfg["provider"], cfg["key"]], ["typesafe", "from-json"])


func test_no_key_anywhere_is_the_mock_with_a_warning_for_the_game_log():
	var cfg := JevConfig.resolve(NOTHING)
	eq(cfg["provider"], "mock")
	eq(cfg["source"], "none")
	eq(cfg["warning"], JevConfig.NO_KEY)
	ok(cfg["warning"].contains("mocked"))


func test_keys_are_never_read_from_os_environment_variables():
	OS.set_environment("OPENROUTER_API_KEY", "sk-or-from-the-environment")
	OS.set_environment("TYPESAFE_API_KEY", "ts-from-the-environment")
	var cfg := JevConfig.resolve(NOTHING)
	OS.unset_environment("OPENROUTER_API_KEY")
	OS.unset_environment("TYPESAFE_API_KEY")
	eq(cfg["provider"], "mock")
	eq(cfg["key"], "")


func test_parse_dotenv_handles_comments_quotes_and_export():
	var vars := JevConfig.parse_dotenv("# a comment\n\nexport A=1\nB = \"two words\"\nC='single'\nD=x=y\r\nnoequals\n=novalue\n")
	eq(vars, {"A": "1", "B": "two words", "C": "single", "D": "x=y"})


func test_setup_points_jev_at_the_decision_and_keeps_the_key_out_of_the_result():
	var cfg := JevConfig.setup(with({"dotenv_text": "OPENROUTER_API_KEY=sk-or-secret"}))
	eq(cfg["provider"], "openrouter")
	ok(not cfg.has("key"))
	ok(not JSON.stringify(cfg).contains("sk-or-secret"))
	eq(cfg["has_key"], true)
	eq([Jev.via, Jev.api_key], ["openrouter", "sk-or-secret"])
	ok(Jev.is_configured())


func test_setup_without_a_key_configures_the_mock_and_returns_the_warning():
	var cfg := JevConfig.setup(with({"latency": 0}))
	eq(cfg["warning"], JevConfig.NO_KEY)
	eq(Jev.via, "mock")
	var r := await Jev.jev({}, {"q": {"type": "noul", "instructions": "x"}})
	eq(r["model"], "jev-mock")


func test_setup_with_a_proxy():
	JevConfig.setup(with({"json_text": "{\"provider\":\"proxy\",\"apiBase\":\"https://p.dev\"}"}))
	eq(Jev.via, "proxy")
	eq(Jev.provider["url"], "https://p.dev/api/jev")


func test_setup_decides_once():
	var first := JevConfig.setup(with({"flags_text": "mock seed=3"}))
	eq(first["seed"], 3)
	var again := JevConfig.setup(with({"dotenv_text": "OPENROUTER_API_KEY=sk-or-late"}))
	eq(again["provider"], "mock", "the first decision stands")
	eq(JevConfig.current()["seed"], 3)
	var forced := JevConfig.setup(with({"dotenv_text": "OPENROUTER_API_KEY=sk-or-late"}), true)
	eq(forced["provider"], "openrouter")


func test_the_scenario_scripts_get_a_seeded_mock_by_default():
	var t := JevConfig.setup_tool(false, 5)
	ok(t["ok"])
	ok(t["banner"].begins_with("MOCK Jev (seed 5)"))
	eq(Jev.via, "mock")
	var a := await Jev.jev({}, {"q": {"type": "noul", "instructions": "x"}})
	Jev.configure_jev(null, {"via": "mock", "seed": 5})
	var b := await Jev.jev({}, {"q": {"type": "noul", "instructions": "x"}})
	eq(a["answers"], b["answers"])
	ok(a["ms"] < 100, "no fake latency in the scripts")


func test_live_scripts_need_a_key_and_use_the_key_they_are_given():
	var none := JevConfig.setup_tool(true, 1, NOTHING)
	eq(none["ok"], false)
	ok(none["banner"].contains("--live needs a key"))
	# a stray `mock` in the real flags must not turn a live run into a mock one
	var live := JevConfig.setup_tool(true, 1, with({"dotenv_text": "OPENROUTER_API_KEY=sk-or-live", "flags_text": "mock"}))
	eq(live["ok"], true)
	ok(live["banner"].begins_with("LIVE Jev (openrouter)"))
	ok(not live["banner"].contains("sk-or-live"))
	eq([Jev.via, Jev.api_key], ["openrouter", "sk-or-live"])
	eq(Jev.raw_dir, "user://jev-raw", "paid replies are saved before they are parsed")
	Jev.raw_dir = ""
