## The voice banks in assets/voices/ (tools/voices/render.py): each covers every line a monster can say aloud
## (cli/voice_lines.gd), and every file is a sound of a sensible length
extends "res://tests/test_case.gd"

const Tts = preload("res://src/audio/tts.gd")
const Engines = preload("res://src/audio/tts_engines.gd")
const TtsConfig = preload("res://src/audio/tts_config.gd")
const VoiceLines = preload("res://cli/voice_lines.gd")


func _banks() -> Dictionary:
	return TtsConfig.resolve({"flags_text": "", "json_text": "", "dotenv_text": "", "system": false}).banks


func test_every_bank_has_every_line_a_monster_says():
	var lines := VoiceLines.collect()
	ok(lines.count > 300, "the lines to render (%d)" % lines.count)
	for id in _banks():
		var bank := Engines.Bank.open(_banks()[id], null)
		ok(bank != null, id + " opens")
		var missing := []
		for sp in lines.species:
			for l in lines.species[sp]:
				var u := Tts.Utterance.new()
				u.text = l.text
				u.species = sp
				if not bank.can_say(u):
					missing.append("%s: %s" % [sp, l.text])
		eq(missing, [], id + " is missing lines")


func test_every_file_in_a_bank_is_a_sound_of_a_sensible_length():
	for id in _banks():
		var bank := Engines.Bank.open(_banks()[id], null)
		var bad := []
		for sp in bank.lines:
			for key in bank.lines[sp]:
				var path: String = bank.dir.path_join(bank.lines[sp][key])
				var s = load(path) if ResourceLoader.exists(path) else null
				if not s is AudioStream:
					bad.append("%s: not a sound" % path)
				elif s.get_length() < 0.2 or s.get_length() > 15.0:
					bad.append("%s: %.2f s for \"%s\"" % [path, s.get_length(), key])
		eq(bad, [], id)


func test_a_bank_speaks_before_the_live_services_and_the_system():
	var cfg := TtsConfig.resolve({"flags_text": "", "json_text": "", "exported": false, "system": true,
		"dotenv_text": "QWEN_TTS_URL=http://mac:8001"})
	for id in cfg.banks:
		ok(cfg.order.find(id) < cfg.order.find("qwen"), id + " comes before the service")
	eq(cfg.order.back(), "system")
