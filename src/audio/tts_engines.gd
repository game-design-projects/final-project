## The voices a monster can speak with, each behind the interface tts.gd's Narrator uses: get_voices(),
## speak(utterance), cancel(), and can_say(utterance) for an engine that may not have a line.
##   Bank    lines rendered ahead of time (tools/voices/render.py) and shipped as Ogg files in assets/voices/<id>/:
##           "cosyvoice3" (the Feiyu stack's engine, CosyVoice3) and "qwen3" (Qwen3-TTS), each monster's voice cloned
##           from a Creative Commons recording (assets/CREDITS.txt). Instant and the same on every machine, but only
##           the fixed lines of species.gd: a line that names someone else falls through to the next engine.
##   Feiyu   a Feiyu voice service on your network (FastAPI job queue: POST /v1/speech, poll GET /v1/jobs/{id},
##           fetch GET /v1/jobs/{id}/audio): any line, at run time, a second or several each; needs an NVIDIA GPU
##   Qwen    a Qwen3-TTS service (POST /synthesize, WAV back), the same way
##   system  the system's speech engine (tts.gd DisplayServerSynth)
## Chain tries them in order. Bank and the services play through one Player, which keeps lines in the order they
## were asked for even when a service answers out of order. tts_config.gd decides which engines exist.
## Load it with `const Engines = preload("res://src/audio/tts_engines.gd")`.
extends RefCounted

const Self = preload("res://src/audio/tts_engines.gd")
const Tts = preload("res://src/audio/tts.gd")
const J = preload("res://src/core/js.gd")

const DOWN_MS := 30000.0  # after a service fails, lines go to the next engine for this long
const JOB_POLL_MS := 250.0
const JOB_TIMEOUT_MS := 60000.0
const CACHE_LINES := 64  # synthesised lines kept, so a line heard again plays at once


## A WAV file's bytes as a stream (null if they aren't a WAV)
static func wav_stream(bytes: PackedByteArray) -> AudioStream:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	return AudioStreamWAV.load_from_buffer(bytes)


## Tries each engine in turn: the first that can say the line says it. Cancels all of them.
class Chain:
	extends RefCounted
	var engines: Array = []

	func _init(list: Array) -> void:
		engines = list

	func get_voices() -> Array:
		var out := []
		for e in engines:
			out.append_array(e.get_voices())
		return out

	func can_say(u) -> bool:
		return pick(u) != null

	func pick(u):
		for e in engines:
			if not e.has_method("can_say") or e.can_say(u):
				return e
		return null

	func speak(u) -> void:
		var e = pick(u)
		if e != null:
			e.speak(u)
		elif u.onerror.is_valid():
			u.onerror.call()

	func cancel() -> void:
		for e in engines:
			e.cancel()


## Plays one line at a time, in the order they were queued. enqueue(u) holds a place; fill(slot, stream) or
## fail(slot) when its sound is known. Calls the utterance's onstart / onend / onerror.
class Player:
	extends Node
	var bus := "Master"
	var _queue: Array = []  # slots: {u, stream, failed}
	var _current = null
	var _asp: AudioStreamPlayer = null

	func _ready() -> void:
		_asp = AudioStreamPlayer.new()
		_asp.name = "Speech"
		_asp.bus = bus
		_asp.finished.connect(_ended)
		add_child(_asp)

	var playing: bool:
		get:
			return _current != null

	func enqueue(u) -> Dictionary:
		var slot := {"u": u, "stream": null, "failed": false}
		_queue.append(slot)
		return slot

	func fill(slot: Dictionary, stream: AudioStream) -> void:
		slot.stream = stream
		_pump()

	func fail(slot: Dictionary) -> void:
		slot.failed = true
		_pump()

	func cancel() -> void:
		var dropped := _queue
		_queue = []
		var cur = _current
		_current = null
		if _asp != null:
			_asp.stop()
		if cur != null and cur.u.onerror.is_valid():
			cur.u.onerror.call()
		for slot in dropped:
			if slot.u.onerror.is_valid():
				slot.u.onerror.call()

	## The line playing has ended (the player's `finished`; tests call it)
	func _ended() -> void:
		var cur = _current
		_current = null
		if cur != null and cur.u.onend.is_valid():
			cur.u.onend.call()
		_pump()

	func _pump() -> void:
		while _current == null and not _queue.is_empty():
			var head: Dictionary = _queue[0]
			if head.failed:
				_queue.pop_front()
				if head.u.onerror.is_valid():
					head.u.onerror.call()
				continue
			if head.stream == null:
				return  # still being synthesised: the lines behind it wait their turn
			_queue.pop_front()
			_current = head
			if _asp != null:
				_asp.stream = head.stream
				_asp.volume_db = linear_to_db(maxf(0.0001, head.u.volume))
				_asp.play()
			if head.u.onstart.is_valid():
				head.u.onstart.call()


## Lines rendered ahead of time. assets/voices/<id>/manifest.json:
##   {"id", "label", "engine", "lines": {species: {line_key: "file.ogg", ...}}, ...}
## (line_key is tts.gd line_key of what is said; files are relative to the manifest, or res:// paths)
class Bank:
	extends RefCounted
	var id := ""
	var label := ""
	var dir := ""
	var lines := {}
	var player: Player = null

	## The bank in `dir` (a res:// folder), or null when there is none
	static func open(dir_path: String, with_player: Player) -> Bank:
		var path := dir_path.path_join("manifest.json")
		if not FileAccess.file_exists(path):
			return null
		var m = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not m is Dictionary or not m.get("lines") is Dictionary:
			push_warning("tts: %s is not a voice bank manifest" % path)
			return null
		var b := Bank.new()
		b.id = str(m.get("id", dir_path.get_file()))
		b.label = str(m.get("label", b.id))
		b.dir = dir_path
		b.lines = m.lines
		b.player = with_player
		return b

	func size() -> int:
		var n := 0
		for sp in lines:
			n += lines[sp].size()
		return n

	func get_voices() -> Array:
		return []

	func file_for(u) -> String:
		var f = lines.get(str(u.species), {}).get(Tts.line_key(u.text))
		if f == null:
			return ""
		return f if str(f).begins_with("res://") else dir.path_join(f)

	func can_say(u) -> bool:
		return file_for(u) != ""

	func speak(u) -> void:
		var slot := player.enqueue(u)
		var stream = load(file_for(u)) if can_say(u) else null
		if stream is AudioStream:
			player.fill(slot, stream)
		else:
			push_warning("tts: %s has no sound for %s \"%s\"" % [id, u.species, u.text])
			player.fail(slot)

	func cancel() -> void:
		player.cancel()


## What a speech service has in common: one request (or job) per line, answers cached, out of the chain for a while
## after a failure. A subclass implements _synth(u) -> PackedByteArray (WAV) or {"error": String}.
## `fetch` carries requests: (method: int, url, headers: PackedStringArray, body: String) ->
## {"status": int, "body": PackedByteArray} or {"error": String}; by default a real HTTPRequest under the player.
class Service:
	extends RefCounted
	var id := ""
	var label := ""
	var base := ""
	var key := ""
	var voices := {}  # species -> fields merged into the request for that monster
	var defaults := {}  # fields for every request
	var player: Player = null
	var fetch := Callable()
	var down_until := 0.0
	var why := ""  # the last failure
	var _gen := 0
	var _cache := {}  # "species|key" -> AudioStream
	var _order: Array = []

	func _init(cfg := {}, with_player: Player = null) -> void:
		base = str(cfg.get("url", "")).rstrip("/")
		key = str(cfg.get("key", ""))
		voices = cfg.get("voices", {})
		defaults = cfg.get("defaults", {})
		player = with_player
		fetch = cfg.get("fetch", _http)

	func get_voices() -> Array:
		return []

	func can_say(_u) -> bool:
		return base != "" and Time.get_ticks_msec() >= down_until

	func body_for(u) -> Dictionary:
		var b: Dictionary = defaults.duplicate(true)
		b.merge(voices.get(str(u.species), {}), true)
		b["text"] = u.text
		return b

	func speak(u) -> void:
		var slot := player.enqueue(u)
		var k := "%s|%s" % [u.species, Tts.line_key(u.text)]
		if _cache.has(k):
			player.fill(slot, _cache[k])
			return
		var g := _gen
		var t0 := Time.get_ticks_msec()
		var wav = await _synth(u)
		if g != _gen:
			return  # cancelled meanwhile: its slot is gone
		var stream := Self.wav_stream(wav) if wav is PackedByteArray else null
		if stream == null:
			why = str(wav.get("error", "no audio")) if wav is Dictionary else "not a WAV"
			down_until = Time.get_ticks_msec() + Self.DOWN_MS
			push_warning("tts: %s failed (%s); the next engine speaks for %d s" % [id, why, int(Self.DOWN_MS / 1000.0)])
			player.fail(slot)
			return
		print_verbose("tts: %s synthesised \"%s\" in %d ms" % [id, u.text, Time.get_ticks_msec() - t0])
		_cache[k] = stream
		_order.append(k)
		if _order.size() > Self.CACHE_LINES:
			_cache.erase(_order.pop_front())
		player.fill(slot, stream)

	func cancel() -> void:
		_gen += 1
		player.cancel()

	func headers(json := true) -> PackedStringArray:
		var h := PackedStringArray()
		if json:
			h.append("Content-Type: application/json")
		if key != "":
			h.append("Authorization: Bearer " + key)
		return h

	func _synth(_u):
		return {"error": "not implemented"}

	func _http(method: int, url: String, hdrs: PackedStringArray, body: String) -> Dictionary:
		var req := HTTPRequest.new()
		req.timeout = 30.0
		var host: Node = player if player != null and player.is_inside_tree() else (Engine.get_main_loop() as SceneTree).root
		host.add_child(req)
		var err := req.request(url, hdrs, method, body)
		if err != OK:
			req.queue_free()
			return {"error": "request failed to start (%s)" % error_string(err)}
		var done: Array = await req.request_completed  # [result, code, headers, body]
		req.queue_free()
		if int(done[0]) != HTTPRequest.RESULT_SUCCESS:
			return {"error": "%s unreachable (HTTPRequest result %d)" % [base, int(done[0])]}
		return {"status": int(done[1]), "body": done[3]}


## A Feiyu voice service (the stack of astrbot_plugin_feiyu_voice's server: CosyVoice3 behind a FastAPI job queue).
## Request: {"voice", "style", "text"} plus whatever the config adds for that species. The service's default voice
## is the Feiyu voice library, which may not ship with the game: tts_config.gd requires a voice to be named.
class Feiyu:
	extends Service

	func _init(cfg := {}, with_player: Player = null) -> void:
		super(cfg, with_player)
		id = "feiyu"
		label = "FEIYU SERVICE"

	func _synth(u):
		var r: Dictionary = await fetch.call(HTTPClient.METHOD_POST, base + "/v1/speech", headers(), JSON.stringify(body_for(u)))
		if r.has("error"):
			return r
		if r.status != 202 and r.status != 200:
			return {"error": "POST /v1/speech: HTTP %d %s" % [r.status, (r.body as PackedByteArray).get_string_from_utf8().left(120)]}
		var job = JSON.parse_string((r.body as PackedByteArray).get_string_from_utf8())
		if not job is Dictionary or not job.has("id"):
			return {"error": "POST /v1/speech: no job id"}
		var url := "%s/v1/jobs/%s" % [base, job.id]
		var t0 := Time.get_ticks_msec()
		while str(job.get("status", "")) != "success":
			if str(job.get("status", "")) in ["failed", "interrupted"]:
				return {"error": "job %s: %s" % [job.status, str(job.get("error", ""))]}
			if Time.get_ticks_msec() - t0 > Self.JOB_TIMEOUT_MS:
				return {"error": "job %s still %s after %d s" % [job.id, job.get("status", "?"), int(Self.JOB_TIMEOUT_MS / 1000.0)]}
			await J.sleep(Self.JOB_POLL_MS)
			r = await fetch.call(HTTPClient.METHOD_GET, url, headers(false), "")
			if r.has("error"):
				return r
			job = JSON.parse_string((r.body as PackedByteArray).get_string_from_utf8())
			if not job is Dictionary:
				return {"error": "GET %s: not JSON" % url}
		r = await fetch.call(HTTPClient.METHOD_GET, url + "/audio", headers(false), "")
		if r.has("error"):
			return r
		if r.status != 200:
			return {"error": "GET %s/audio: HTTP %d" % [url, r.status]}
		return r.body


## A Qwen3-TTS service: POST /synthesize {text, language, speaker, instruct, ...} answered with the WAV
class Qwen:
	extends Service

	func _init(cfg := {}, with_player: Player = null) -> void:
		super(cfg, with_player)
		id = "qwen"
		label = "QWEN3-TTS SERVICE"

	func _synth(u):
		var r: Dictionary = await fetch.call(HTTPClient.METHOD_POST, base + "/synthesize", headers(), JSON.stringify(body_for(u)))
		if r.has("error"):
			return r
		if r.status != 200:
			return {"error": "POST /synthesize: HTTP %d %s" % [r.status, (r.body as PackedByteArray).get_string_from_utf8().left(120)]}
		return r.body
