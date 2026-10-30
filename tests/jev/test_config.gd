# How the game decides to reach its System One model. Every source is injected: these tests never read the real
# jev_config.json or install.json, and never start a process (the launcher is a recorder).
extends "res://tests/test_case.gd"

const JevConfig = preload("res://src/jev/config.gd")
const Jev = preload("res://src/jev/jev.gd")
const Local = preload("res://src/jev/local.gd")
const LocalServer = preload("res://src/jev/local_server.gd")

const NOTHING := {"json_text": "", "install": {}, "flags_text": "", "env": {}}
const INSTALL := {"server": "/opt/llama/llama-server", "model": "/data/decider-4b-v3-Q4_K_M.gguf", "gpu": true}


func before_each():
	JevConfig.reset()
	Jev.configure_jev()


func after_each():
	JevConfig.reset()
	Jev.configure_jev()


static func with(overrides: Dictionary) -> Dictionary:
	return NOTHING.merged(overrides, true)


## A launcher that records what it was asked to start, and fails when told to
class Launcher:
	extends RefCounted
	var calls: Array = []
	var error := ""

	func start(server: String, model: String, port: int, gpu: bool) -> Dictionary:
		calls.append([server, model, port, gpu])
		return {"error": error} if error != "" else {"pid": 4242}


func test_the_mock_flag_wins_over_any_model():
	var cfg := JevConfig.resolve(with({"flags_text": "floor5-debug mock", "install": INSTALL, "json_text": "{\"provider\":\"systemone\",\"apiBase\":\"http://x\"}"}))
	eq(cfg["provider"], "mock")
	eq(cfg["warning"], "", "asking for the mock is no reason to warn")


func test_the_mock_flag_is_case_insensitive_and_jev_mock_1_works_too():
	eq(JevConfig.resolve(with({"flags_text": "?MOCK"}))["provider"], "mock")
	eq(JevConfig.resolve(with({"env": {"JEV_MOCK": "1"}, "install": INSTALL}))["provider"], "mock")
	eq(JevConfig.resolve(with({"env": {"JEV_MOCK": "0"}, "install": INSTALL}))["provider"], "local", "only JEV_MOCK=1 means mock")


func test_the_seed_comes_from_the_flag_then_the_environment_then_the_clock():
	eq(JevConfig.resolve(with({"flags_text": "mock seed=7"}))["seed"], 7)
	eq(JevConfig.resolve(with({"flags_text": "mock --seed=12", "env": {"JEV_SEED": "9"}}))["seed"], 12)
	eq(JevConfig.resolve(with({"flags_text": "mock", "env": {"JEV_MOCK": "1", "JEV_SEED": "9"}}))["seed"], 9)
	var clock: int = JevConfig.resolve(with({"flags_text": "mock"}))["seed"]
	ok(clock > 0, "a seed from the clock")


func test_jev_config_local_with_a_server_and_a_model_is_started_by_the_game():
	var cfg := JevConfig.resolve(with({"json_text": "{\"provider\":\"local\",\"server\":\"/s/llama-server\",\"model\":\"/m/decider-2b-v12-Q4_K_M.gguf\",\"gpu\":false,\"port\":5000,\"debug\":true}"}))
	eq([cfg["provider"], cfg["server"], cfg["model"], cfg["gpu"], cfg["port"], cfg["debug"], cfg["source"]], ["local", "/s/llama-server", "/m/decider-2b-v12-Q4_K_M.gguf", false, 5000, true, "jev_config.json"])
	eq(cfg["api_base"], "http://127.0.0.1:5000")


func test_jev_config_local_with_only_an_api_base_is_a_server_you_run():
	var cfg := JevConfig.resolve(with({"json_text": "{\"apiBase\":\"http://127.0.0.1:8080/\"}"}))
	eq([cfg["provider"], cfg["api_base"], cfg["server"]], ["local", "http://127.0.0.1:8080", ""], "provider defaults to local")


func test_jev_config_systemone_needs_an_api_base():
	var cfg := JevConfig.resolve(with({"json_text": "{\"provider\":\"systemone\",\"apiBase\":\"http://gpu-box:8000\"}"}))
	eq([cfg["provider"], cfg["api_base"]], ["systemone", "http://gpu-box:8000"])
	eq(JevConfig.resolve(with({"json_text": "{\"provider\":\"systemone\"}"}))["provider"], "mock", "no address, no server")


func test_a_bad_jev_config_is_ignored():
	for text in ["not json", "[1, 2]", "{\"provider\":\"typesafe\",\"key\":\"k\"}", "{\"provider\":\"local\",\"server\":\"/s\"}"]:
		var cfg := JevConfig.resolve(with({"json_text": text, "install": INSTALL}))
		eq(cfg["source"], "install.json", "%s falls through to the install" % text)


func test_jev_config_wins_over_the_install():
	var cfg := JevConfig.resolve(with({"json_text": "{\"provider\":\"systemone\",\"apiBase\":\"http://x\"}", "install": INSTALL}))
	eq(cfg["provider"], "systemone")


func test_the_setup_install_is_started_by_the_game_on_the_gpu_unless_the_cpu_flag_says_otherwise():
	var cfg := JevConfig.resolve(with({"install": INSTALL}))
	eq([cfg["provider"], cfg["server"], cfg["model"], cfg["gpu"], cfg["source"]], ["local", INSTALL["server"], INSTALL["model"], true, "install.json"])
	eq(cfg["api_base"], "http://127.0.0.1:%d" % LocalServer.DEFAULT_PORT)
	eq(JevConfig.resolve(with({"install": INSTALL, "flags_text": "cpu"}))["gpu"], false)
	eq(JevConfig.resolve(with({"install": INSTALL.merged({"gpu": false}, true)}))["gpu"], false, "a CPU install stays on the CPU")
	eq(JevConfig.resolve(with({"install": INSTALL, "flags_text": "cpuhalls"}))["gpu"], true, "cpu is a word, not a substring")


func test_no_model_anywhere_is_the_mock_with_a_warning_for_the_game_log():
	var cfg := JevConfig.resolve(NOTHING)
	eq([cfg["provider"], cfg["source"], cfg["warning"]], ["mock", "none", JevConfig.NO_MODEL])
	ok(cfg["warning"].contains("random"))


func test_setup_starts_the_installed_server_and_points_jev_at_it():
	var launcher := Launcher.new()
	var cfg := JevConfig.setup(with({"install": INSTALL, "launch": launcher.start}))
	eq(launcher.calls, [[INSTALL["server"], INSTALL["model"], LocalServer.DEFAULT_PORT, true]])
	eq([cfg["provider"], cfg["warning"]], ["local", ""])
	eq(Jev.via, "local")
	ok(Jev.transport is Local.Server)
	eq(Jev.transport.wait_s, JevConfig.LAUNCH_WAIT_S, "a server the game started gets time to load the model")


func test_setup_falls_back_to_the_mock_when_the_server_cannot_start():
	var launcher := Launcher.new()
	launcher.error = "no llama-server at /opt/llama/llama-server"
	var cfg := JevConfig.setup(with({"install": INSTALL, "launch": launcher.start, "latency": 0}))
	eq([cfg["provider"], Jev.via], ["mock", "mock"])
	ok(cfg["warning"].contains("could not start") and cfg["warning"].contains("no llama-server"), cfg["warning"])


func test_setup_with_a_server_you_run_starts_nothing():
	var launcher := Launcher.new()
	JevConfig.setup(with({"json_text": "{\"apiBase\":\"http://127.0.0.1:8080\"}", "launch": launcher.start}))
	eq(launcher.calls, [])
	eq([Jev.via, Jev.provider["url"], Jev.transport.wait_s], ["local", "http://127.0.0.1:8080/v1/systemone", 3.0])


func test_setup_with_a_system_one_server():
	JevConfig.setup(with({"json_text": "{\"provider\":\"systemone\",\"apiBase\":\"http://gpu-box:8000/\"}"}))
	eq([Jev.via, Jev.provider["url"], Jev.transport], ["systemone", "http://gpu-box:8000/v1/systemone", null])


func test_setup_without_a_model_configures_the_mock_and_returns_the_warning():
	var cfg := JevConfig.setup(with({"latency": 0}))
	eq(cfg["warning"], JevConfig.NO_MODEL)
	eq(Jev.via, "mock")
	var r := await Jev.jev({}, {"q": {"type": "noul", "instructions": "x"}})
	eq(r["model"], "jev-mock")


func test_setup_decides_once():
	var first := JevConfig.setup(with({"flags_text": "mock seed=3"}))
	eq(first["seed"], 3)
	var again := JevConfig.setup(with({"json_text": "{\"provider\":\"systemone\",\"apiBase\":\"http://x\"}"}))
	eq(again["provider"], "mock", "the first decision stands")
	eq(JevConfig.current()["seed"], 3)
	var forced := JevConfig.setup(with({"json_text": "{\"provider\":\"systemone\",\"apiBase\":\"http://x\"}"}), true)
	eq(forced["provider"], "systemone")


func test_the_scenario_scripts_get_a_seeded_mock_by_default():
	var t := JevConfig.setup_tool(false, 5)
	ok(t["ok"])
	ok(t["banner"].begins_with("MOCK model (seed 5)"))
	eq(Jev.via, "mock")
	var a := await Jev.jev({}, {"q": {"type": "noul", "instructions": "x"}})
	Jev.configure_jev({"via": "mock", "seed": 5})
	var b := await Jev.jev({}, {"q": {"type": "noul", "instructions": "x"}})
	eq(a["answers"], b["answers"])
	ok(a["ms"] < 100, "no fake latency in the scripts")


func test_live_scripts_need_a_model_and_use_the_one_they_are_given():
	var none := JevConfig.setup_tool(true, 1, NOTHING)
	eq(none["ok"], false)
	ok(none["banner"].contains("--live needs a model"))
	# a stray `mock` in the real flags must not turn a live run into a mock one
	var live := JevConfig.setup_tool(true, 1, with({"json_text": "{\"provider\":\"systemone\",\"apiBase\":\"http://gpu-box:8000\"}", "flags_text": "mock"}))
	eq(live["ok"], true)
	ok(live["banner"].begins_with("LIVE model (systemone at http://gpu-box:8000)"), live["banner"])
	eq(Jev.via, "systemone")
	eq(Jev.raw_dir, "user://jev-raw", "raw replies are saved before they are parsed")
	Jev.raw_dir = ""
