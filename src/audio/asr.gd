## Hold to talk on the desktop builds: speech to text on the player's own machine, no server. A small helper program
## (native/asr/donjon_asr.c: sherpa-onnx running NVIDIA's Nemotron Speech Streaming model, 160 ms chunks, int8) turns
## the microphone into words as you speak. The game captures the microphone (AudioStreamMicrophone into a muted bus
## with an AudioEffectCapture), runs the helper as a child process and streams the audio to it over stdin; the words
## come back on stdout as JSON lines (the protocol is at the top of donjon_asr.c).
##
## Where things are:
##   the helper  res://native/dist/<platform>/ (built by native/asr/build.sh; each desktop export carries its own).
##               Run in place from source; an exported build copies it to user://asr/bin/ first, because a program
##               can't run from inside the .pck.
##   the model   user://asr/<MODEL.id>/, downloaded from Hugging Face the first time the player asks for it
##               (630 MB, once), or build/asr-model/ when run from source (native/asr/build.sh model).
##
## NativeRecognition has the shape of the browser's SpeechRecognition (see voice.gd WebRecognition), so voice.gd's
## Listener drives it unchanged. Runtime (one, shared) owns the helper, the microphone and the download.
## The pure parts (frames, events, paths) and the session logic are tested with a fake helper and microphone;
## tests/audio/test_asr.gd also runs the real helper on a recording when it has been built.
## Load it with `const Asr = preload("res://src/audio/asr.gd")`.
extends RefCounted

const Self = preload("res://src/audio/asr.gd")

## The speech model: the sherpa-onnx export of nvidia/nemotron-speech-streaming-en-0.6b, pinned to one commit of the
## sherpa-onnx author's mirror (the same files as the sherpa-onnx release archive). Sizes and SHA-256 are checked.
const MODEL := {
	"id": "nemotron-speech-streaming-en-0.6b-160ms-int8-2026-04-25",
	"url": "https://huggingface.co/csukuangfj2/sherpa-onnx-nemotron-speech-streaming-en-0.6b-160ms-int8-2026-04-25/resolve/237e551abd7a411ef92d3595454d9f6ab5fe7d6c/",
	"files": [
		{"name": "tokens.txt", "size": 8952, "sha256": "dc0b4584ab2e4ddbf888425c076c61b736e7356a015250db7d307e6f1a8188ff"},
		{"name": "decoder.int8.onnx", "size": 7257753, "sha256": "0be9702c2f427a2b6bb241d298e0d3836a558de1f5b9fd3018f1cce6e2b3fa98"},
		{"name": "joiner.int8.onnx", "size": 1735862, "sha256": "a35eac38a22ebceb04d230ed7afe0d68f446ba6914a036b97f14fece95967e23"},
		{"name": "encoder.int8.onnx", "size": 652916849, "sha256": "71111f61b18e1e65e01e369434a5c0434868d2f44892742ae54240600c681209"},
	],
}
const THREADS := 2  # one keeps up on a laptop; two keep up on slower machines too (and load the model faster)
const DIST := "res://native/dist"
const DEV_MODEL := "res://build/asr-model"  # native/asr/build.sh model
const USER_DIR := "user://asr"
const MIC_BUS := "Mic"
const NO_SOUND_MS := 2000.0  # listening this long without a single sample from the microphone means it isn't working
const EXECUTABLE := 0b111_101_101  # rwxr-xr-x for the copied helper and its libraries (FileAccess.UNIX_* bits)


## "linux", "windows", "macos", or "" where there is no helper (the web, other systems and processors)
static func platform() -> String:
	if OS.has_feature("web"):
		return ""
	var x64 := Engine.get_architecture_name() == "x86_64"
	match OS.get_name():
		"Linux":
			return "linux" if x64 else ""
		"Windows":
			return "windows" if x64 else ""
		"macOS":
			return "macos"  # universal: arm64 and x86_64
	return ""


static func exe_name(p: String) -> String:
	return "donjon-asr.exe" if p == "windows" else "donjon-asr"


## Total download in bytes (for "630 MB")
static func model_bytes() -> int:
	var n := 0
	for f in MODEL.files:
		n += int(f.size)
	return n


static func mb(bytes: float) -> String:
	return "%d MB" % roundi(bytes / 1000000.0)


## The helper's arguments for a model folder (an OS path)
static func helper_args(model_dir: String, threads := THREADS) -> PackedStringArray:
	return PackedStringArray([
		"--tokens=" + model_dir.path_join("tokens.txt"),
		"--encoder=" + model_dir.path_join("encoder.int8.onnx"),
		"--decoder=" + model_dir.path_join("decoder.int8.onnx"),
		"--joiner=" + model_dir.path_join("joiner.int8.onnx"),
		"--threads=%d" % threads,
	])


## One frame of the helper's input: a tag byte, the payload length (uint32 LE), the payload
static func frame(tag: String, payload := PackedByteArray()) -> PackedByteArray:
	var out := PackedByteArray([tag.unicode_at(0), 0, 0, 0, 0])
	out.encode_u32(1, payload.size())
	out.append_array(payload)
	return out


static func start_frame(rate: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(4)
	p.encode_s32(0, rate)
	return frame("S", p)


static func audio_frame(samples: PackedFloat32Array) -> PackedByteArray:
	return frame("A", samples.to_byte_array())


## Splits what the helper has printed into whole JSON lines. Returns {events: [Dictionary], rest: String}; `rest` is
## an unfinished last line to keep for next time. Lines that aren't JSON objects are skipped.
static func parse_events(text: String) -> Dictionary:
	var lines := text.split("\n")
	var rest := lines[lines.size() - 1]
	var events := []
	for i in lines.size() - 1:
		var line := lines[i].strip_edges()
		if line == "":
			continue
		var ev = JSON.parse_string(line)
		if ev is Dictionary:
			events.append(ev)
		else:
			push_warning("asr: not a JSON line from the helper: " + line.left(120))
	return {"events": events, "rest": rest}


## Stereo frames from the capture effect, as one mono channel
static func mono(frames: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames.size())
	for i in frames.size():
		out[i] = (frames[i].x + frames[i].y) * 0.5
	return out


## Whether a model folder holds every file at its full size
static func model_complete(dir: String) -> bool:
	for f in MODEL.files:
		var path := dir.path_join(f.name)
		if not FileAccess.file_exists(path):
			return false
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() != int(f.size):
			return false
	return true


## The helper as a child process (OS.execute_with_pipe, non-blocking): what Runtime talks to. Tests use a fake
## with the same methods.
class Pipe:
	extends RefCounted
	var pid := -1
	var _io: FileAccess = null
	var _err: FileAccess = null

	static func spawn(exe: String, args: PackedStringArray) -> Pipe:
		var info := OS.execute_with_pipe(exe, args, false)
		if info.is_empty():
			return null
		var p := Pipe.new()
		p.pid = info.pid
		p._io = info.stdio
		p._err = info.stderr
		return p

	func write(bytes: PackedByteArray) -> bool:
		return _io != null and _io.store_buffer(bytes)

	## Everything printed on stdout since the last call (possibly nothing)
	func read() -> PackedByteArray:
		return _drain(_io)

	func read_err() -> PackedByteArray:
		return _drain(_err)

	func running() -> bool:
		return pid > 0 and OS.is_process_running(pid)

	## Closing stdin ends the helper; kill it if it doesn't go
	func close() -> void:
		if _io != null:
			_io.close()
			_io = null
		if running():
			OS.delay_msec(50)
			if running():
				OS.kill(pid)

	func _drain(f: FileAccess) -> PackedByteArray:
		var out := PackedByteArray()
		if f == null:
			return out
		while true:
			var b := f.get_buffer(65536)
			if b.is_empty():
				break
			out.append_array(b)
		return out


## The microphone: AudioStreamMicrophone played into a muted bus that has a capture effect. read() hands over what
## came in since the last call, as mono samples at `rate`. Only open while listening (the system's "mic in use"
## light is honest). Tests use a fake with the same methods.
class Mic:
	extends Node
	var rate := 48000
	var _player: AudioStreamPlayer = null
	var _capture: AudioEffectCapture = null

	func start() -> bool:
		_capture = _bus_capture()
		if _player == null:
			_player = AudioStreamPlayer.new()
			_player.name = "Microphone"
			add_child(_player)
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = Self.MIC_BUS
		rate = int(AudioServer.get_mix_rate())
		_capture.clear_buffer()
		_player.play()
		return true

	func read() -> PackedFloat32Array:
		if _capture == null:
			return PackedFloat32Array()
		var n := _capture.get_frames_available()
		return Self.mono(_capture.get_buffer(n)) if n > 0 else PackedFloat32Array()

	func stop() -> void:
		if _player != null:
			_player.stop()

	static func _bus_capture() -> AudioEffectCapture:
		var idx := AudioServer.get_bus_index(Self.MIC_BUS)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, Self.MIC_BUS)
			AudioServer.set_bus_mute(idx, true)  # the game mustn't play your voice back to you
			var cap := AudioEffectCapture.new()
			cap.buffer_length = 1.0  # a hitch of up to a second loses nothing
			AudioServer.add_bus_effect(idx, cap)
		for i in AudioServer.get_bus_effect_count(idx):
			var e := AudioServer.get_bus_effect(idx, i)
			if e is AudioEffectCapture:
				return e
		var added := AudioEffectCapture.new()
		AudioServer.add_bus_effect(idx, added)
		return added


## The helper, the microphone and the model download, shared by every NativeRecognition. Add it to the tree (it polls
## the helper and the microphone every frame; Runtime.shared() does) or call poll() yourself (tests).
## state: "idle" (helper there, not running), "no-model", "downloading", "loading" (helper starting), "ready", "failed".
## Signals `said(text)` with what the player should be told (a download finished, the model is ready, it broke).
class Runtime:
	extends Node
	signal said(text: String)

	static var _shared: Runtime = null

	var state := "idle"
	var why := ""  # what went wrong, when failed
	var helper_dir := ""  # an OS path
	var model_dir := ""  # an OS path
	var spawn := Callable()  # (exe: String, args: PackedStringArray) -> Pipe-like or null
	var mic = null  # Mic-like: start() -> bool, read() -> PackedFloat32Array, stop(), rate
	var threads := Self.THREADS
	var offered := false  # the player has been told about the download once
	var progress := 0.0  # 0..1 while downloading
	var pipe = null
	var session = null  # the NativeRecognition listening (or finishing)
	var _out := ""  # an unfinished line from the helper
	var _err_tail := ""  # the helper's last words on stderr, for the log when it dies
	var _sending := false  # this session's audio is going to the helper
	var _finishing := false
	var _heard_any := false
	var _listen_ms := 0.0
	var _download = null  # {files, index, http}
	var _verify_task := -1
	var _verify_ok := false
	var _announce := false  # say so once the freshly downloaded model is loaded

	## The one the game uses, made (and put in the tree) on first use
	static func shared() -> Runtime:
		if _shared == null:
			_shared = Runtime.new()
			_shared.name = "Asr"
			var tree := Engine.get_main_loop() as SceneTree
			if tree != null:
				tree.root.add_child.call_deferred(_shared)
		return _shared

	## opts (tests): helper_dir, model_dir, spawn, mic, threads. By default: the places in the file header.
	func _init(opts := {}) -> void:
		spawn = opts.get("spawn", func(exe, args): return Pipe.spawn(exe, args))
		mic = opts.get("mic")
		threads = opts.get("threads", Self.THREADS)
		helper_dir = opts.get("helper_dir", "")
		model_dir = opts.get("model_dir", "")
		if model_dir == "":
			var dev := ProjectSettings.globalize_path(Self.DEV_MODEL)
			model_dir = dev if OS.has_feature("editor") and Self.model_complete(dev) else ProjectSettings.globalize_path(Self.USER_DIR.path_join(Self.MODEL.id))
		if not Self.model_complete(model_dir):
			state = "no-model"

	func _ready() -> void:
		if mic == null:
			mic = Mic.new()
			mic.name = "Mic"
			add_child(mic)

	func _process(_delta: float) -> void:
		poll()

	func _exit_tree() -> void:
		shut()

	## Whether this build has a helper for this machine
	static func available() -> bool:
		var p := Self.platform()
		return p != "" and FileAccess.file_exists(Self.DIST.path_join(p).path_join("VERSION"))

	## Before listening: "" when it can listen now (it may still be loading: the audio waits for it), otherwise what to
	## tell the player. Without the model, the first call offers the download and the next one starts it.
	func prepare() -> String:
		match state:
			"no-model":
				if not offered:
					offered = true
					return "TO HEAR YOU, THE GAME NEEDS A SPEECH MODEL: A ONE-TIME %s DOWNLOAD. HOLD SPACE AGAIN TO GET IT, OR JUST TYPE." % Self.mb(Self.model_bytes())
				download()
				return "DOWNLOADING THE SPEECH MODEL (%s). KEEP TYPING: THE GAME WILL SAY WHEN IT CAN HEAR YOU." % Self.mb(Self.model_bytes())
			"downloading":
				return "STILL DOWNLOADING THE SPEECH MODEL: %d%%. TYPE FOR NOW." % floori(progress * 100.0)
			"failed":
				var msg := "VOICE INPUT ISN'T WORKING (%s). TYPE INSTEAD; HOLD SPACE TO TRY AGAIN." % why.to_upper()
				state = "idle" if Self.model_complete(model_dir) else "no-model"
				return msg
		return ""

	## Starts the helper (it takes a few seconds to load the model) so the first words don't wait for it
	func warm() -> void:
		if state == "idle":
			_start_helper()

	func listen(rec) -> bool:
		if state not in ["idle", "loading", "ready"]:
			return false
		if session != null and session != rec:
			abort(session)
		if state == "idle" and not _start_helper():
			return false
		if mic == null or not mic.start():
			return false
		session = rec
		_finishing = false
		_heard_any = false
		_listen_ms = Time.get_ticks_msec()
		_sending = pipe.write(Self.start_frame(int(mic.rate)))
		print_verbose("asr: listening at %d Hz (%s)" % [mic.rate, state])
		return true

	## Let go: the last words are decoded, then the session ends with the final text
	func finish(rec) -> void:
		if rec != session or _finishing:
			return
		_pump_mic()
		mic.stop()
		_finishing = true
		pipe.write(Self.frame("F"))

	## Drop the session at once, no result
	func abort(rec) -> void:
		if rec != session:
			return
		session = null
		mic.stop()
		if pipe != null and _sending:
			pipe.write(Self.frame("X"))  # after an F, its final line still comes: _on_event drops it
		_sending = false
		_finishing = false
		_end(rec)

	func poll() -> void:
		_poll_download()
		if pipe == null:
			return
		var out: PackedByteArray = pipe.read()
		if not out.is_empty():
			var parsed := Self.parse_events(_out + out.get_string_from_utf8())
			_out = parsed.rest
			for ev in parsed.events:
				_on_event(ev)
		var err: PackedByteArray = pipe.read_err()
		if not err.is_empty():
			var text := err.get_string_from_utf8().strip_edges()
			print_verbose("asr helper: " + text)
			_err_tail = text.get_slice("\n", text.get_slice_count("\n") - 1)
		if pipe != null and not pipe.running() and state in ["loading", "ready"]:
			_fail("the speech helper stopped" + (": " + _err_tail if _err_tail != "" else ""))
			return
		if session != null and not _finishing:
			_pump_mic()
			if not _heard_any and Time.get_ticks_msec() - _listen_ms > Self.NO_SOUND_MS:
				var rec = session
				abort(rec)
				if rec.onerror.is_valid():
					rec.onerror.call({"error": "audio-capture"})

	## Stop the helper (the game is closing)
	func shut() -> void:
		if session != null:
			abort(session)
		if pipe != null:
			pipe.close()
			pipe = null
		if state in ["loading", "ready"]:
			state = "idle"

	func download() -> void:
		if state != "no-model":
			return
		DirAccess.make_dir_recursive_absolute(model_dir)
		var files := []
		for f in Self.MODEL.files:
			if not _has_file(f):
				files.append(f)
		state = "downloading"
		progress = 0.0
		_download = {"files": files, "index": -1, "http": null, "done_bytes": 0, "total": 0}
		for f in files:
			_download.total += int(f.size)
		print("asr: downloading the speech model to %s (%s)" % [model_dir, Self.mb(_download.total)])
		_next_file()

	func _has_file(f: Dictionary) -> bool:
		var file := FileAccess.open(model_dir.path_join(f.name), FileAccess.READ)
		return file != null and file.get_length() == int(f.size)

	func _next_file() -> void:
		var d: Dictionary = _download
		if d.http != null:
			d.http.queue_free()
			d.http = null
		d.index += 1
		if d.index >= d.files.size():
			_verify()
			return
		var f: Dictionary = d.files[d.index]
		var http := HTTPRequest.new()
		http.use_threads = true
		http.download_file = model_dir.path_join(f.name + ".part")
		http.download_chunk_size = 1 << 20
		add_child(http)
		d.http = http
		http.request_completed.connect(func(result: int, code: int, _headers, _body): _file_done(f, result, code))
		var err := http.request(Self.MODEL.url + f.name)
		if err != OK:
			_download_failed("couldn't start the download (%s)" % error_string(err))

	func _file_done(f: Dictionary, result: int, code: int) -> void:
		var part := model_dir.path_join(f.name + ".part")
		var file := FileAccess.open(part, FileAccess.READ)
		var size := file.get_length() if file != null else -1
		file = null
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or size != int(f.size):
			DirAccess.remove_absolute(part)
			_download_failed("%s: HTTP %d, result %d, %d bytes" % [f.name, code, result, size])
			return
		DirAccess.rename_absolute(part, model_dir.path_join(f.name))
		_download.done_bytes += int(f.size)
		_next_file()

	func _poll_download() -> void:
		if state == "downloading" and _download != null and _download.http != null:
			var got: int = _download.http.get_downloaded_bytes()
			var p := float(_download.done_bytes + got) / maxf(1.0, _download.total)
			if floori(p * 4.0) > floori(progress * 4.0) and p < 1.0:
				said.emit("SPEECH MODEL: %d%% DOWNLOADED." % (floori(p * 4.0) * 25))
			progress = p
		if _verify_task >= 0 and WorkerThreadPool.is_task_completed(_verify_task):
			WorkerThreadPool.wait_for_task_completion(_verify_task)
			_verify_task = -1
			if _verify_ok:
				state = "idle"
				print("asr: speech model downloaded and checked")
				_announce = true
				_start_helper()
			else:
				for f in Self.MODEL.files:
					DirAccess.remove_absolute(model_dir.path_join(f.name))
				_download_failed("the downloaded files didn't match (SHA-256)")

	# SHA-256 of 660 MB takes a few seconds: off the main thread
	func _verify() -> void:
		var dir := model_dir
		_verify_ok = false
		_verify_task = WorkerThreadPool.add_task(func():
			var ok := true
			for f in Self.MODEL.files:
				if FileAccess.get_sha256(dir.path_join(f.name)) != f.sha256:
					ok = false
			_verify_ok = ok)

	func _download_failed(reason: String) -> void:
		push_warning("asr: download failed: " + reason)
		if _download != null and _download.http != null:
			_download.http.queue_free()
		_download = null
		state = "no-model"
		said.emit("THE SPEECH MODEL DIDN'T DOWNLOAD (%s). HOLD SPACE TO TRY AGAIN." % reason.to_upper())

	# The helper's folder: in place from source, copied out of the .pck in an exported build
	func _helper_exe() -> String:
		var p := Self.platform()
		if helper_dir == "":
			if OS.has_feature("editor"):
				helper_dir = ProjectSettings.globalize_path(Self.DIST.path_join(p))
			else:
				helper_dir = _extract(p)
		return helper_dir.path_join(Self.exe_name(p)) if helper_dir != "" else ""

	## Copies res://native/dist/<p>/ to user://asr/bin/ unless the copy there is the same version; "" if it fails
	static func _extract(p: String) -> String:
		var src := Self.DIST.path_join(p)
		var dst := ProjectSettings.globalize_path(Self.USER_DIR.path_join("bin"))
		var version := FileAccess.get_file_as_string(src.path_join("VERSION"))
		if version != "" and FileAccess.get_file_as_string(dst.path_join("VERSION")) == version:
			return dst
		DirAccess.make_dir_recursive_absolute(dst)
		for name in DirAccess.get_files_at(src):
			var bytes := FileAccess.get_file_as_bytes(src.path_join(name))
			var out := FileAccess.open(dst.path_join(name), FileAccess.WRITE)
			if out == null or not out.store_buffer(bytes):
				push_warning("asr: can't write %s" % dst.path_join(name))
				return ""
			out.close()
			if p != "windows" and (name == Self.exe_name(p) or name.contains(".so") or name.ends_with(".dylib")):
				FileAccess.set_unix_permissions(dst.path_join(name), EXECUTABLE)
		print_verbose("asr: helper copied to " + dst)
		return dst

	func _start_helper() -> bool:
		if pipe != null:
			return true
		var exe := _helper_exe()
		if exe == "" or not FileAccess.file_exists(exe):
			_fail("no speech helper for this build")
			return false
		_out = ""
		_err_tail = ""
		pipe = spawn.call(exe, Self.helper_args(model_dir, threads))
		if pipe == null:
			_fail("couldn't start the speech helper")
			return false
		state = "loading"
		print_verbose("asr: starting %s" % exe)
		return true

	func _pump_mic() -> void:
		var samples: PackedFloat32Array = mic.read()
		if samples.is_empty():
			return
		_heard_any = true
		if _sending and not pipe.write(Self.audio_frame(samples)):
			_fail("couldn't send audio to the speech helper")

	func _on_event(ev: Dictionary) -> void:
		match str(ev.get("event", "")):
			"ready":
				state = "ready"
				print_verbose("asr: ready")
				if _announce:
					_announce = false
					said.emit("THE GAME CAN HEAR YOU NOW: HOLD SPACE AND SPEAK.")
			"text":
				if session != null and not _finishing and session.onresult.is_valid():
					session.onresult.call({"results": [{"transcript": str(ev.get("text", "")), "isFinal": false}]})
			"final":
				if session == null or not _finishing:
					return  # the end of an aborted session
				var rec = session
				session = null
				_sending = false
				_finishing = false
				if rec.onresult.is_valid():
					rec.onresult.call({"results": [{"transcript": str(ev.get("text", "")), "isFinal": true}]})
				_end(rec)
			"error":
				_fail(str(ev.get("message", "the speech helper failed")))

	func _fail(reason: String) -> void:
		push_warning("asr: " + reason)
		why = reason
		state = "failed"
		if pipe != null:
			pipe.close()
			pipe = null
		var rec = session
		session = null
		_sending = false
		_finishing = false
		if mic != null:
			mic.stop()
		if rec != null:
			if rec.onerror.is_valid():
				rec.onerror.call({"error": "asr-failed"})
			_end(rec)
		said.emit("VOICE INPUT STOPPED WORKING (%s). TYPE INSTEAD." % reason.to_upper())

	func _end(rec) -> void:
		if rec.onend.is_valid():
			rec.onend.call()


## The helper behind the interface voice.gd's Listener uses (see WebRecognition there): lang, continuous,
## interimResults; onresult(ev), onerror(ev), onend(); start() -> bool, stop(), abort(). Always continuous with
## interim results, English only.
class NativeRecognition:
	extends RefCounted
	## The Runtime every recognition uses (tests set their own; null: Runtime.shared())
	static var runtime = null
	var lang := "en-US"
	var continuous := false
	var interimResults := false
	var onresult := Callable()
	var onerror := Callable()
	var onend := Callable()

	static func available() -> bool:
		return runtime != null or Runtime.available()

	static func rt() -> Runtime:
		return runtime if runtime != null else Runtime.shared()

	func start() -> bool:
		return rt().listen(self)

	func stop() -> void:
		rt().finish(self)

	func abort() -> void:
		rt().abort(self)
