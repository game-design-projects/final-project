## Decides how the game reaches Jev, once. In order:
##   1. mock: flag `mock` (command line / address) or env JEV_MOCK=1; the seed is flag `seed=N` or env JEV_SEED
##   2. res://config/jev_config.json  {"provider": "openrouter"|"typesafe"|"proxy", "key": "...", "apiBase": "...", "debug": true}
##      (what an exported build ships; a key with a small credit limit, or the proxy's apiBase)
##   3. the project's .env (only when run from source, never in an exported build): OPENROUTER_API_KEY, preferred, or
##      TYPESAFE_API_KEY, like the JS server
##   4. nothing found: mock, with a warning the game shows in its log
## API keys are read from those files only, never from OS environment variables.
## Every source can be injected (`sources`), so tests never touch the real .env. Load it with
## `const JevConfig = preload("res://src/jev/config.gd")`.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Flags = preload("res://src/core/flags.gd")
const Jev = preload("res://src/jev/jev.gd")

const JSON_PATH := "res://config/jev_config.json"
const NO_KEY := "No Jev key found (config/jev_config.json or .env): Jev is mocked, so monsters act at random, not sensibly."

static var _current: Dictionary = {}


## Works out the provider without configuring anything. `sources` (all optional, for tests and tools):
##   flags_text   the string the flags are searched in (default: the real flags)
##   env          {JEV_MOCK, JEV_SEED} (default: the real environment; no other variable is ever read)
##   json_text    the text of jev_config.json (default: the file at json_path)
##   json_path    where that file is (default: res://config/jev_config.json)
##   dotenv_text  the text of the .env file (default: the file at dotenv_path)
##   dotenv_path  where it is (default: the project's .env)
##   exported     true to ignore .env as an exported build does (default: not OS.has_feature("editor"))
##   latency      ms of fake latency for mock answers (default 150, like the JS server)
## Returns { provider: "mock"|"openrouter"|"typesafe"|"proxy", key, api_base, debug, seed, latency, warning, source }.
static func resolve(sources := {}) -> Dictionary:
	var out := {"provider": "mock", "key": "", "api_base": "", "debug": false, "seed": 0, "latency": sources.get("latency", 150), "warning": "", "source": ""}
	var flags: String = sources["flags_text"] if sources.has("flags_text") else Flags.text()
	var env: Dictionary = sources["env"] if sources.has("env") else {"JEV_MOCK": OS.get_environment("JEV_MOCK"), "JEV_SEED": OS.get_environment("JEV_SEED")}

	var wants_mock: bool = RegEx.create_from_string("(?i)mock").search(flags) != null or str(env.get("JEV_MOCK", "")) == "1"
	var seed_flag := RegEx.create_from_string("(?i)seed=(\\d+)").search(flags)
	var seed := int(seed_flag.get_string(1)) if seed_flag != null else int(str(env.get("JEV_SEED", "")).to_int())
	out["seed"] = seed if seed != 0 else int(J.date_ms()) % 1000000
	if wants_mock:
		out["source"] = "flag or JEV_MOCK"
		return out

	var found := _from_json(sources, out)
	if not found and not _exported(sources):
		found = _from_dotenv(sources, out)
	if not found:
		out["warning"] = NO_KEY
		out["source"] = "none"
	return out


## resolve() + point jev.gd at the result. Decides once: later calls return the same answer unless `force`.
## The returned Dictionary has no key (it is safe to log); `warning` is non-empty when Jev fell back to the mock
## for lack of a key, and the game shows it in its log.
static func setup(sources := {}, force := false) -> Dictionary:
	if not _current.is_empty() and not force:
		return _current
	var cfg := resolve(sources)
	match cfg["provider"]:
		"mock":
			Jev.configure_jev(null, {"via": "mock", "seed": cfg["seed"], "latency": cfg["latency"]})
		"proxy":
			Jev.configure_jev(null, {"via": "proxy", "api_base": cfg["api_base"]})
		_:
			Jev.configure_jev(cfg["key"], {"via": cfg["provider"]})
	if cfg["warning"] != "":
		push_warning(cfg["warning"])
	print_verbose("jev config: %s (%s)" % [cfg["provider"], cfg["source"]])
	cfg["has_key"] = cfg["key"] != ""
	cfg.erase("key")
	_current = cfg
	return cfg


## The config setup() settled on (empty before it ran)
static func current() -> Dictionary:
	return _current


## Forget the decision (tests)
static func reset() -> void:
	_current = {}


static func _exported(sources: Dictionary) -> bool:
	return sources["exported"] if sources.has("exported") else not OS.has_feature("editor")


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
	var cfg = JSON.parse_string(text)
	if not cfg is Dictionary:
		push_warning("jev config: %s is not a JSON object, ignoring it" % JSON_PATH)
		return false
	var key := str(cfg.get("key", "")).strip_edges()
	var api_base := str(cfg.get("apiBase", "")).strip_edges().rstrip("/")
	var provider := str(cfg.get("provider", ""))
	if provider == "":
		provider = "proxy" if api_base != "" and key == "" else ("openrouter" if key.begins_with("sk-or-") else "typesafe")
	if provider == "proxy":
		if api_base == "":
			push_warning("jev config: provider proxy needs an apiBase, ignoring %s" % JSON_PATH)
			return false
	elif provider != "openrouter" and provider != "typesafe":
		push_warning("jev config: unknown provider \"%s\", ignoring %s" % [provider, JSON_PATH])
		return false
	elif key == "":
		return false
	out["provider"] = provider
	out["key"] = key
	out["api_base"] = api_base
	out["debug"] = cfg.get("debug") == true
	out["source"] = "jev_config.json"
	return true


static func _from_dotenv(sources: Dictionary, out: Dictionary) -> bool:
	var text := _read("dotenv_text", "dotenv_path", ProjectSettings.globalize_path("res://").path_join(".env"), sources)
	if text == "":
		return false
	var vars := parse_dotenv(text)
	var provider := ""
	var key := ""
	for candidate in [["openrouter", "OPENROUTER_API_KEY"], ["typesafe", "TYPESAFE_API_KEY"]]:
		var v: String = vars.get(candidate[1], "")
		if v != "":
			provider = candidate[0]
			key = v
			break
	if key == "":
		return false
	out["provider"] = provider
	out["key"] = key
	out["source"] = ".env"
	return true


## KEY=value lines of a .env file (comments, blank lines, `export ` and quotes handled)
static func parse_dotenv(text: String) -> Dictionary:
	var vars := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("export "):
			line = line.trim_prefix("export ").strip_edges()
		var eq := line.find("=")
		if eq < 1:
			continue
		var value := line.substr(eq + 1).strip_edges()
		if value.length() >= 2 and (value[0] == "\"" or value[0] == "'") and value[value.length() - 1] == value[0]:
			value = value.substr(1, value.length() - 2)
		vars[line.left(eq).strip_edges()] = value
	return vars
