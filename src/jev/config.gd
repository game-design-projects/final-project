## Decides how the game reaches its System One model, once. In order:
##   1. mock: flag `mock` (command line / address) or env JEV_MOCK=1; the seed is flag `seed=N` or env JEV_SEED
##   2. res://config/jev_config.json (git-ignored), plus "debug": true for debug mode:
##        {"provider": "local", "server": "<llama-server>", "model": "<decider .gguf>", "gpu": true, "port": 41715}
##                                      the game starts that llama-server and talks to it
##        {"provider": "local", "apiBase": "http://127.0.0.1:41715"}   a llama-server you started yourself
##        {"provider": "systemone", "apiBase": "http://host:8000"}      any server that answers POST /v1/systemone
##   3. user://local-model/install.json, which cli/setup_local.gd writes: the game starts that llama-server
##   4. nothing found: mock, with a warning the game shows in its log
## The flag `cpu` keeps a llama-server the game starts off the GPU. Every source can be injected (`sources`), so tests
## never read the real files or start a process. Load it with `const JevConfig = preload("res://src/jev/config.gd")`.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Flags = preload("res://src/core/flags.gd")
const Jev = preload("res://src/jev/jev.gd")
const LocalServer = preload("res://src/jev/local_server.gd")
const LocalSetup = preload("res://src/jev/local_setup.gd")

const JSON_PATH := "res://config/jev_config.json"
const NO_MODEL := "No local model installed (cli/setup_local.gd, or the setup-local flag): monsters act at random, not sensibly."
## How long the first request waits for a llama-server the game started (loading 2.7 GB from a slow disk takes a while)
const LAUNCH_WAIT_S := 180.0

static var _current: Dictionary = {}


## Works out the way in without configuring anything. `sources` (all optional, for tests and tools):
##   flags_text   the string the flags are searched in (default: the real flags)
##   env          {JEV_MOCK, JEV_SEED} (default: the real environment; no other variable is ever read)
##   json_text    the text of jev_config.json (default: the file at json_path)
##   json_path    where that file is (default: res://config/jev_config.json)
##   install      the setup's install.json contents (default: LocalSetup.installed(), {} when there is none)
##   latency      ms of fake latency for mock answers (default 150)
## Returns { provider: "mock"|"local"|"systemone", api_base, server, model, gpu, port, debug, seed, latency, warning,
## source }. server/model are set when the game is to start llama-server itself.
static func resolve(sources := {}) -> Dictionary:
	var out := {
		"provider": "mock", "api_base": "", "server": "", "model": "", "gpu": true, "port": LocalServer.DEFAULT_PORT,
		"debug": false, "seed": 0, "latency": sources.get("latency", 150), "warning": "", "source": "",
	}
	var flags: String = sources["flags_text"] if sources.has("flags_text") else Flags.text()
	var env: Dictionary = sources["env"] if sources.has("env") else {"JEV_MOCK": OS.get_environment("JEV_MOCK"), "JEV_SEED": OS.get_environment("JEV_SEED")}

	var wants_mock: bool = RegEx.create_from_string("(?i)mock").search(flags) != null or str(env.get("JEV_MOCK", "")) == "1"
	var seed_flag := RegEx.create_from_string("(?i)seed=(\\d+)").search(flags)
	var seed := int(seed_flag.get_string(1)) if seed_flag != null else int(str(env.get("JEV_SEED", "")).to_int())
	out["seed"] = seed if seed != 0 else int(J.date_ms()) % 1000000
	if wants_mock:
		out["source"] = "flag or JEV_MOCK"
		return out

	if not _from_json(sources, out):
		var inst: Dictionary = sources["install"] if sources.has("install") else LocalSetup.installed()
		if not inst.is_empty():
			out.merge({"provider": "local", "server": str(inst.get("server", "")), "model": str(inst.get("model", "")), "gpu": inst.get("gpu", true) != false, "source": "install.json"}, true)
		else:
			out["warning"] = NO_MODEL
			out["source"] = "none"
	if out["provider"] == "local":
		if RegEx.create_from_string("(?i)(^|[^a-z])cpu($|[^a-z])").search(flags) != null:
			out["gpu"] = false
		if out["api_base"] == "":
			out["api_base"] = "http://127.0.0.1:%d" % out["port"]
	return out


## resolve() + point jev.gd at the result, starting llama-server when the game is to run it (`sources.launch`, a
## Callable like LocalServer.start, replaces that in tests). Decides once: later calls return the same answer unless
## `force`. `warning` is non-empty when the game fell back to the mock, and the game shows it in its log.
static func setup(sources := {}, force := false) -> Dictionary:
	if not _current.is_empty() and not force:
		return _current
	var cfg := resolve(sources)
	if cfg["provider"] == "local" and cfg["server"] != "":
		var launch: Callable = sources.get("launch", Callable(LocalServer, "start"))
		var started: Dictionary = launch.call(cfg["server"], cfg["model"], cfg["port"], cfg["gpu"])
		if started.has("error"):
			cfg["warning"] = "The local model could not start (%s): monsters act at random, not sensibly." % started["error"]
			cfg["provider"] = "mock"
	match cfg["provider"]:
		"mock":
			Jev.configure_jev({"via": "mock", "seed": cfg["seed"], "latency": cfg["latency"]})
		"local":
			Jev.configure_jev({"via": "local", "api_base": cfg["api_base"], "wait_s": LAUNCH_WAIT_S if cfg["server"] != "" else 3.0})
		"systemone":
			Jev.configure_jev({"via": "systemone", "api_base": cfg["api_base"]})
	if cfg["warning"] != "":
		push_warning(cfg["warning"])
	print_verbose("jev config: %s (%s)" % [cfg["provider"], cfg["source"]])
	_current = cfg
	return cfg


## For the scenario scripts (cli/): mock with this seed and no fake latency, or with `live` the real model (the local one
## the setup installed, or what jev_config.json names; raw text replies are saved to user://jev-raw).
## Returns { ok, banner }; ok is false when `live` was asked for and no model was found.
static func setup_tool(live: bool, seed: int, sources := {}) -> Dictionary:
	if not live:
		Jev.configure_jev({"via": "mock", "seed": seed})
		return {"ok": true, "banner": "MOCK model (seed %d): random answers. Add --live for the real model." % seed}
	var quiet := sources.merged({"flags_text": "", "env": {}}, true)
	if resolve(quiet)["provider"] == "mock":
		return {"ok": false, "banner": "--live needs a model: run cli/setup_local.gd, or name one in config/jev_config.json."}
	var cfg := setup(quiet, true)
	if cfg["provider"] == "mock":
		return {"ok": false, "banner": "--live: %s" % cfg["warning"]}
	Jev.raw_dir = "user://jev-raw"
	return {"ok": true, "banner": "LIVE model (%s at %s)." % [cfg["provider"], cfg["api_base"]]}


## The config setup() settled on (empty before it ran)
static func current() -> Dictionary:
	return _current


## Forget the decision (tests)
static func reset() -> void:
	_current = {}


static func _read(text_key: String, path_key: String, default_path: String, sources: Dictionary) -> String:
	if sources.has(text_key):
		return str(sources[text_key])
	var path: String = sources.get(path_key, default_path)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func _from_json(sources: Dictionary, out: Dictionary) -> bool:
	var text := _read("json_text", "json_path", JSON_PATH, sources)
	if text.strip_edges() == "":
		return false
	var json := JSON.new()
	var cfg = json.data if json.parse(text) == OK else null
	if not cfg is Dictionary:
		push_warning("jev config: %s is not a JSON object, ignoring it" % JSON_PATH)
		return false
	var provider := str(cfg.get("provider", "local"))
	var api_base := str(cfg.get("apiBase", "")).strip_edges().rstrip("/")
	var server := str(cfg.get("server", "")).strip_edges()
	var model := str(cfg.get("model", "")).strip_edges()
	if provider == "systemone":
		if api_base == "":
			push_warning("jev config: provider systemone needs an apiBase, ignoring %s" % JSON_PATH)
			return false
	elif provider == "local":
		if (server == "") != (model == ""):
			push_warning("jev config: provider local needs both server and model (or neither, with apiBase), ignoring %s" % JSON_PATH)
			return false
	else:
		push_warning("jev config: unknown provider \"%s\" (local or systemone), ignoring %s" % [provider, JSON_PATH])
		return false
	out.merge({
		"provider": provider, "api_base": api_base, "server": server, "model": model, "gpu": cfg.get("gpu", true) != false,
		"port": int(cfg.get("port", LocalServer.DEFAULT_PORT)), "debug": cfg.get("debug") == true, "source": "jev_config.json",
	}, true)
	return true
