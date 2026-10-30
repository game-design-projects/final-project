## Monsters read their lines aloud. Off by default, and on by itself once you've talked to the game with your voice
## (hold Space): someone speaking to the monsters wants to hear them answer. The voices are pluggable
## (tts_engines.gd): lines rendered ahead of time with CosyVoice3 (the Feiyu stack) or Qwen3-TTS, a Feiyu or Qwen3-TTS
## service on your network, or the system's text to speech (DisplayServer.tts_*; on the web build the browser's
## speechSynthesis). L steps through the ones this build has, then off, and the choice is kept (tts_config.gd says
## which there are). The pure parts (speakable, line_key, pick_voice, tts_on) are tested without any speech engine.
## Load it with `const Tts = preload("res://src/audio/tts.gd")` and use `Tts.Narrator`.
extends RefCounted

const Self = preload("res://src/audio/tts.gd")
const Engines = preload("res://src/audio/tts_engines.gd")
const TtsConfig = preload("res://src/audio/tts_config.gd")

# Each kind of monster sounds like itself: pitch 0..2 and rate 0.1..10 as DisplayServer.tts_speak takes them
const VOICES := {
	"dragon": {"pitch": 0.3, "rate": 0.8},
	"rock": {"pitch": 0.2, "rate": 0.7},
	"goblin": {"pitch": 0.7, "rate": 1.05},
	"bandit": {"pitch": 0.9, "rate": 1.0},
	"snake": {"pitch": 1.2, "rate": 0.85},
	"slime": {"pitch": 1.8, "rate": 1.15},
}
const DEFAULT_VOICE := {"pitch": 1.0, "rate": 1.0}

const MAX_QUEUE := 2  # more than this waiting and the oldest are dropped, so speech keeps up with the fight

static var _stage := _re("\\*[^*]*\\*")
static var _braces := _re("\\{[^}]*\\}")
static var _dots := _re("\\.{2,}|…")
static var _space_before := _re("\\s+([,.!?])")
static var _edges := _re("^[\\s,]+|[\\s,]+$")
static var _spaces := _re("\\s+")
static var _english := _re("(?i)^en(-|_|$)")
static var _good_engine := _re("(?i)google|natural|enhanced|premium")
static var _us_gb := _re("(?i)en[-_]?(us|gb)")
static var _male := _re("(?i)male|daniel|fred|alex|david|george|guy")
static var _female := _re("(?i)female")


static func _re(pattern: String) -> RegEx:
	var re := RegEx.create_from_string(pattern)
	assert(re != null and re.is_valid(), "tts: bad pattern " + pattern)
	return re


## What's worth saying out loud: the words, not the *stage directions* or {placeholders}
static func speakable(line) -> String:
	var s := "" if line == null else str(line)
	s = _stage.sub(s, " ", true)
	s = _braces.sub(s, " ", true)
	s = _dots.sub(s, ", ", true)
	s = _space_before.sub(s, "$1", true)
	s = _edges.sub(s, "", true)
	s = _spaces.sub(s, " ", true)
	return s.strip_edges()


## What a rendered line is filed under: the words said, lower case, single spaces (tts_engines.gd Bank)
static func line_key(text) -> String:
	return _spaces.sub(speakable(text).to_lower(), " ", true).strip_edges()


## Monster lines are English: pick an English voice, preferring local ones (no network) and the better
## engines' voices; species with a deep voice prefer a male-sounding name when the system offers one.
## A voice is {name, lang (or language), localService (assumed true when missing), ...}; null if none is English.
static func pick_voice(voices: Array, species = null):
	var best = null
	var best_score := -1
	for v in voices:
		var lang := str(v.get("lang", v.get("language", "")))
		if _english.search(lang) == null:
			continue
		var name := str(v.get("name", ""))
		var score := 0
		if v.get("localService", true):
			score += 4
		if _good_engine.search(name) != null:
			score += 2
		if _us_gb.search(lang) != null:
			score += 1
		if species in ["dragon", "rock", "goblin"] and _male.search(name) != null and _female.search(name) == null:
			score += 3
		if best == null or score > best_score:
			best = v
			best_score = score
	return best


## Whether lines are read aloud: an explicit choice wins; otherwise on once the player has used their voice
static func tts_on(opts := {}) -> bool:
	var choice = opts.get("choice")
	if choice == "on":
		return true
	if choice == "off":
		return false
	return opts.get("usedVoice", false) == true


## One line being spoken: what DisplayServer.tts_speak is given, and what to do as it starts and ends.
## `voice` is one of the dictionaries pick_voice returned (or null: the engine's default voice); `species` is who
## speaks (the rendered banks and the services pick the monster's voice by it).
class Utterance:
	extends RefCounted
	var text := ""
	var species = null
	var voice = null
	var lang := "en-US"
	var pitch := 1.0
	var rate := 1.0
	var volume := 1.0  # 0..1
	var onstart := Callable()
	var onend := Callable()
	var onerror := Callable()


## The system's speech engine behind the interface Narrator uses: get_voices(), speak(utterance), cancel().
## DisplayServer reports one callback per event for the whole program, so this keeps the utterances by id.
class DisplayServerSynth:
	extends RefCounted
	var _pending := {}  # utterance id -> Utterance
	var _next_id := 1

	static func available() -> bool:
		return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)

	func _init() -> void:
		if available():
			DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, _on_started)
			DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_ended)
			DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_canceled)

	func get_voices() -> Array:
		var out := []
		for v in DisplayServer.tts_get_voices():
			out.append({"name": v.get("name", ""), "id": v.get("id", ""), "lang": v.get("language", ""), "localService": true})
		return out

	func speak(u: Utterance) -> void:
		var id := _next_id
		_next_id += 1
		_pending[id] = u
		var voice_id: String = u.voice.get("id", "") if u.voice != null else ""
		DisplayServer.tts_speak(u.text, voice_id, int(round(u.volume * 100.0)), u.pitch, u.rate, id)

	func cancel() -> void:
		_pending.clear()
		DisplayServer.tts_stop()

	func _on_started(id: int) -> void:
		var u = _pending.get(id)
		if u != null and u.onstart.is_valid():
			u.onstart.call()

	func _on_ended(id: int) -> void:
		var u = _pending.get(id)
		_pending.erase(id)
		if u != null and u.onend.is_valid():
			u.onend.call()

	func _on_canceled(id: int) -> void:
		var u = _pending.get(id)
		_pending.erase(id)
		if u != null and u.onerror.is_valid():
			u.onerror.call()


class Narrator:
	extends Node
	## opts: `synth` (one engine: get_voices / speak / cancel; null means no speech), or `engines` (the lineup L steps
	## through: {order: [ids], make: Callable(id) -> engine}; default: what tts_config.gd finds), `store` (get_item /
	## set_item: Store, or Store.Memory in tests), `onDuck` (Callable(on: bool)): called with true when a monster starts
	## speaking and false once it (and any line right after) is done. Speech can't go louder than the engine's full
	## volume, so the music and effects make room instead.
	var synth = null
	var order: Array = []  # engine ids, in the order L steps through them
	var engine := ""  # the one speaking
	var _make := Callable()
	var store = null
	var on_duck := Callable()
	var queued := 0  # lines waiting or being spoken
	var ducked := false
	var gen := 0  # bumped by hush(): late events from cancelled lines are ignored

	func _init(opts := {}) -> void:
		store = opts.get("store")
		on_duck = opts.get("onDuck", Callable())
		if opts.has("synth"):
			synth = opts["synth"]
			order = ["default"] if synth != null else []
			engine = "default" if synth != null else ""
			return
		var lineup: Dictionary = opts["engines"] if opts.has("engines") else _lineup()
		order = lineup.order
		_make = lineup.make
		var saved = store.get_item("donjon.ttsEngine") if store != null else null
		use(saved if saved != null and order.has(saved) else (order[0] if not order.is_empty() else ""))

	## What tts_config.gd finds, made into engines that share one player (a child of this node)
	func _lineup() -> Dictionary:
		var cfg := TtsConfig.resolve()
		for w in cfg.warnings:
			push_warning(w)
		var player := Engines.Player.new()
		player.name = "Speech"
		add_child(player)
		var made := {}
		var make_one := func(id: String):
			if made.has(id):
				return made[id]
			var e = null
			if cfg.banks.has(id):
				e = Engines.Bank.open(cfg.banks[id], player)
			elif id == "feiyu":
				e = Engines.Feiyu.new(cfg.feiyu, player)
			elif id == "qwen":
				e = Engines.Qwen.new(cfg.qwen, player)
			elif id == "system":
				e = DisplayServerSynth.new()
			made[id] = e
			return e
		# The chosen engine first; a rendered bank falls back to the live services; anything to the system's voice
		var make := func(id: String):
			var list := [make_one.call(id)]
			if cfg.banks.has(id):
				for live in ["feiyu", "qwen"]:
					if cfg.order.has(live):
						list.append(make_one.call(live))
			if id != "system" and cfg.order.has("system"):
				list.append(make_one.call("system"))
			return Engines.Chain.new(list.filter(func(e): return e != null))
		print_verbose("tts: engines %s" % ", ".join(cfg.order))
		return {"order": cfg.order, "make": make}

	## Speak with this engine from now on
	func use(id: String) -> void:
		if synth != null:
			synth.cancel()
		engine = id
		synth = _make.call(id) if id != "" and _make.is_valid() else null

	var label: String:
		get:
			return TtsConfig.label(engine)

	var supported: bool:
		get:
			return synth != null

	var on: bool:
		get:
			if not supported:
				return false
			return Self.tts_on({
				"choice": store.get_item("donjon.tts") if store != null else null,
				"usedVoice": store != null and store.get_item("donjon.usedVoice") == "1",
			})

	## The player just spoke to the game: from now on (unless they said otherwise) monsters answer aloud
	func heard_player() -> void:
		if store != null:
			store.set_item("donjon.usedVoice", "1")

	## L: off -> the first engine -> the next... -> off (with one engine, simply on and off). True when it's on.
	func toggle() -> bool:
		var next := "off" if on else "on"
		var i := order.find(engine)
		if on and i >= 0 and i + 1 < order.size():
			next = "on"
			hush()
			use(order[i + 1])
		elif next == "off" and not order.is_empty() and order[0] != engine:
			hush()
			use(order[0])  # back to the first one, for next time
		if store != null:
			store.set_item("donjon.tts", next)
			if engine != "" and engine != "default":
				store.set_item("donjon.ttsEngine", engine)
		if next == "off":
			hush()
		return next == "on"

	## Speaks a line in the species' voice; returns the Utterance, or null when it stays silent
	func say(text, species = null):
		var words := Self.speakable(text)
		if not on or words == "":
			return null
		if queued >= Self.MAX_QUEUE:
			hush()
		var u := Utterance.new()
		u.text = words
		u.species = species
		var voice = Self.pick_voice(synth.get_voices(), species)
		if voice != null:
			u.voice = voice
		u.lang = voice.get("lang", "en-US") if voice != null else "en-US"
		var v: Dictionary = Self.VOICES.get(species, Self.DEFAULT_VOICE)
		u.pitch = v.pitch
		u.rate = v.rate
		u.volume = 1.0
		queued += 1
		var g := gen
		u.onstart = func():
			if g == gen:
				set_duck(true)
		# Back up only when nothing else is waiting to be said, so two lines in a row stay ducked
		var finished := func():
			if g != gen:
				return
			queued = maxi(0, queued - 1)
			if queued == 0:
				set_duck(false)
		u.onend = finished
		u.onerror = finished
		synth.speak(u)
		print_verbose("tts (%s): %s \"%s\"" % [engine, species if species != null else "?", words])
		return u

	## Stop at once (e.g. while the microphone listens, so the game doesn't hear itself)
	func hush() -> void:
		gen += 1
		if synth != null:
			synth.cancel()
		queued = 0
		set_duck(false)

	## Tells the game to duck under speech (or come back); only calls out when the state changes
	func set_duck(is_on: bool) -> void:
		if is_on == ducked:
			return
		ducked = is_on
		if on_duck.is_valid():
			on_duck.call(is_on)
