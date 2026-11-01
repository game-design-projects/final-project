## Which voices the monsters can speak with, and in what order L steps through them (tts_engines.gd):
##   banks     every assets/voices/<id>/manifest.json (rendered lines; tools/voices/render.py), best first: BANKS
##   feiyu     a Feiyu voice service, when configured with its url and the voice to use
##   qwen      a Qwen3-TTS service, when configured with its url
##   system    the system's speech engine, when there is one
## The services are configured in res://config/tts_config.json (what an exported build ships):
##   {"engines": ["cosyvoice3", "feiyu", ...],   optional: the order (and choice) of engines
##    "feiyu": {"url": "http://gpu-box:8000", "key": "...", "voice": "<a voice package that isn't the Feiyu library>",
##              "style": "gentle", "voices": {"dragon": {"voice": "...", "style": "..."}, ...}},
##    "qwen": {"url": "http://mac:8001", "language": "en", "voices": {"dragon": {"speaker": "...", "instruct": "..."}}}}
## or, run from source, in the project's .env: FEIYU_TTS_URL, FEIYU_TTS_KEY, FEIYU_TTS_VOICE, QWEN_TTS_URL.
## The flag `tts=<id>` (command line) puts that engine first for this run.
## Every source can be injected (`sources`), as in jev/config.gd. Load it with
## `const TtsConfig = preload("res://src/audio/tts_config.gd")`.
extends RefCounted

const Flags = preload("res://src/core/flags.gd")
const JevConfig = preload("res://src/jev/config.gd")

const JSON_PATH := "res://config/tts_config.json"
const VOICES_DIR := "res://assets/voices"
## Banks in the order they're offered (any other bank found comes after them)
const BANKS := ["cosyvoice3", "qwen3"]
## What each engine is called on screen
const LABELS := {
	"cosyvoice3": "COSYVOICE3 (FEIYU STACK), PRE-RENDERED",
	"qwen3": "QWEN3-TTS, PRE-RENDERED",
	"feiyu": "FEIYU SERVICE, LIVE",
	"qwen": "QWEN3-TTS SERVICE, LIVE",
	"system": "YOUR SYSTEM'S VOICE",
}
## Qwen3-TTS CustomVoice speakers for the monsters when the config names none (the model's English-native ones)
const QWEN_SPEAKERS := {"dragon": "Ryan", "rock": "Ryan", "goblin": "Aiden", "bandit": "Aiden", "snake": "Ryan", "slime": "Aiden"}


## sources (all optional): flags_text, json_text, json_path, dotenv_text, dotenv_path, exported, banks (Array of ids
## found; default: the folders under VOICES_DIR), system (bool: is there a system engine; default: DisplayServer's).
## Returns {order: [ids, best first], banks: {id: res dir}, feiyu: cfg or null, qwen: cfg or null, system: bool,
## warnings: [String]}.
static func resolve(sources := {}) -> Dictionary:
	var out := {"order": [], "banks": {}, "feiyu": null, "qwen": null, "system": false, "warnings": []}
	var found: Array = sources["banks"] if sources.has("banks") else _bank_dirs()
	var banks: Array = []
	for id in BANKS:
		if found.has(id):
			banks.append(id)
	for id in found:
		if not banks.has(id):
			banks.append(id)
	for id in banks:
		out.banks[id] = VOICES_DIR.path_join(id)

	var cfg := _json(sources, out)
	var env := {}
	if not _exported(sources):
		env = JevConfig.parse_dotenv(_read("dotenv_text", "dotenv_path", ProjectSettings.globalize_path("res://").path_join(".env"), sources))

	var feiyu: Dictionary = cfg.get("feiyu", {}) if cfg.get("feiyu") is Dictionary else {}
	feiyu = feiyu.duplicate(true)
	for pair in [["url", "FEIYU_TTS_URL"], ["key", "FEIYU_TTS_KEY"], ["voice", "FEIYU_TTS_VOICE"]]:
		if str(feiyu.get(pair[0], "")) == "" and str(env.get(pair[1], "")) != "":
			feiyu[pair[0]] = env[pair[1]]
	if str(feiyu.get("url", "")) != "":
		if str(feiyu.get("voice", "")) == "" and feiyu.get("voices", {}).is_empty():
			out.warnings.append("tts: the Feiyu service needs a voice (FEIYU_TTS_VOICE or feiyu.voice): its default is the Feiyu voice library, which the game may not use")
		else:
			out.feiyu = {
				"url": feiyu.url,
				"key": str(feiyu.get("key", "")),
				"defaults": {"voice": str(feiyu.get("voice", "")), "style": str(feiyu.get("style", "gentle"))},
				"voices": feiyu.get("voices", {}),
			}
			if out.feiyu.defaults.voice == "":
				out.feiyu.defaults.erase("voice")

	var qwen: Dictionary = cfg.get("qwen", {}) if cfg.get("qwen") is Dictionary else {}
	qwen = qwen.duplicate(true)
	if str(qwen.get("url", "")) == "" and str(env.get("QWEN_TTS_URL", "")) != "":
		qwen["url"] = env["QWEN_TTS_URL"]
	if str(qwen.get("url", "")) != "":
		var voices := {}
		for sp in QWEN_SPEAKERS:
			voices[sp] = {"speaker": QWEN_SPEAKERS[sp]}
		for sp in qwen.get("voices", {}):
			voices[sp] = qwen.voices[sp]
		out.qwen = {"url": qwen.url, "key": str(qwen.get("key", "")), "defaults": {"language": str(qwen.get("language", "en"))}, "voices": voices}

	out.system = sources["system"] if sources.has("system") else DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)

	var available: Array = banks.duplicate()
	for id in ["feiyu", "qwen"]:
		if out[id] != null:
			available.append(id)
	if out.system:
		available.append("system")
	var order := []
	if cfg.get("engines") is Array:
		for id in cfg.engines:
			if available.has(str(id)) and not order.has(str(id)):
				order.append(str(id))
	for id in available:
		if not order.has(id):
			order.append(id)
	var flags: String = sources["flags_text"] if sources.has("flags_text") else Flags.text()
	var m := RegEx.create_from_string("(?i)\\btts=([a-z0-9_-]+)").search(flags)
	if m != null:
		var want := m.get_string(1).to_lower()
		if order.has(want):
			order.erase(want)
			order.push_front(want)
		else:
			out.warnings.append("tts: no engine \"%s\" here (have: %s)" % [want, ", ".join(order)])
	out.order = order
	return out


static func label(id: String) -> String:
	return LABELS.get(id, id.to_upper())


static func _bank_dirs() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(VOICES_DIR):
		return out
	for d in DirAccess.get_directories_at(VOICES_DIR):
		if FileAccess.file_exists(VOICES_DIR.path_join(d).path_join("manifest.json")):
			out.append(d)
	return out


static func _exported(sources: Dictionary) -> bool:
	return sources["exported"] if sources.has("exported") else not OS.has_feature("editor")


static func _read(text_key: String, path_key: String, default_path: String, sources: Dictionary) -> String:
	if sources.has(text_key):
		return str(sources[text_key])
	var path: String = sources.get(path_key, default_path)
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


static func _json(sources: Dictionary, out: Dictionary) -> Dictionary:
	var text := _read("json_text", "json_path", JSON_PATH, sources)
	if text.strip_edges() == "":
		return {}
	var cfg = JSON.parse_string(text)
	if not cfg is Dictionary:
		out.warnings.append("tts: %s is not a JSON object, ignoring it" % JSON_PATH)
		return {}
	return cfg
