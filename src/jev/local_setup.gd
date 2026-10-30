## Installs the local model: llama.cpp's llama-server built for this computer and Decider's weights, into
## user://local-model/, then writes user://local-model/install.json, which config.gd reads to start the server with the
## game. From source: `godot --headless --path . -s res://cli/setup_local.gd`; an exported build: `Donjon --headless --
## setup-local`. Every download is checked against the sha256 pinned here. Load it with
## `const LocalSetup = preload("res://src/jev/local_setup.gd")`.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Decider = preload("res://src/jev/decider.gd")

const DIR := "user://local-model"
const INSTALL := DIR + "/install.json"
const LLAMA_BUILD := "b11429"
const RELEASE := "https://github.com/ggml-org/llama.cpp/releases/download/b11429/"
const MODELS := {"4b": "decider-4b-v3-Q4_K_M.gguf", "2b": "decider-2b-v12-Q4_K_M.gguf"}
const BACKENDS := ["auto", "cpu", "metal", "cuda", "vulkan"]

## llama.cpp's builds of llama-server per platform and backend: [archive, sha256] (a CUDA build needs its runtime beside it).
## The Metal build is also the CPU build on Apple Silicon (started without GPU layers).
const BUILDS := {
	"macos-arm64-metal": [["llama-b11429-bin-macos-arm64.tar.gz", "740288ec6887be94280a5dfa25b5e23a78285cab104519e6c7e218904ee82459"]],
	"macos-x86_64-cpu": [["llama-b11429-bin-macos-x64.tar.gz", "29ac3ea02be6bd143e824973f2cc5fa74bc4094393a9eaab0ff6814f19dd8522"]],
	"linux-x86_64-cpu": [["llama-b11429-bin-ubuntu-x64.tar.gz", "f6d25dde8f51133143d1453da4fd5f73b145127177612a283bf7995957af3392"]],
	"linux-x86_64-vulkan": [["llama-b11429-bin-ubuntu-vulkan-x64.tar.gz", "632c4e98feba2b94407a2130e3133e0c3aefb0ea1ab41337e926d8bfafdd0b74"]],
	"linux-x86_64-cuda": [
		["llama-b11429-bin-ubuntu-cuda-12.8-x64.tar.gz", "b13c64b9224d3c89d9993945d70cc21177ad00178c21b8d34237e3bc139834f1"],
		["cudart-llama-b11429-bin-ubuntu-cuda-12.8-x64.tar.gz", "f4ab593e31507320b121f2cb21791f4c72420a2483d3df8bf2ca1a97d04e6845"],
	],
	"linux-arm64-cpu": [["llama-b11429-bin-ubuntu-arm64.tar.gz", "ed44c0f79c3d02424f62bdc87e106318b0b89f49050e2e80c5f352723d14e00b"]],
	"linux-arm64-vulkan": [["llama-b11429-bin-ubuntu-vulkan-arm64.tar.gz", "702d99c4219b4314cc6d3b10fb41ae96cbfc68226305c2681269dfb51487af34"]],
	"windows-x86_64-cpu": [["llama-b11429-bin-win-cpu-x64.zip", "1283323272b04cd07905816a597a0da810918102de958f4ff6f7bbaa70ed2efe"]],
	"windows-x86_64-vulkan": [["llama-b11429-bin-win-vulkan-x64.zip", "1bfe78ad9168b79fa02bf67f6af9f5e17a966d824d77238517f7bef12ac73b36"]],
	"windows-x86_64-cuda": [
		["llama-b11429-bin-win-cuda-12.4-x64.zip", "dd6df685c1024e6aa55ca55ad35038692d5e284d4dc895e7a646c3245d3d14ff"],
		["cudart-llama-bin-win-cuda-12.4-x64.zip", "8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6"],
	],
	"windows-arm64-cpu": [["llama-b11429-bin-win-cpu-arm64.zip", "ee0f631a9e58b146ff50714099d9cb498906af3143a773b580093a9214a8d1e5"]],
	"windows-arm64-vulkan": [["llama-b11429-bin-win-vulkan-arm64.zip", "739747b9912d19525977b0346a02087037eec487fea7b58c2826324407e588ce"]],
}


## Which build to fetch. os_name: OS.get_name() ("macOS", "Windows", "Linux"); arch: Engine.get_architecture_name();
## backend: one of BACKENDS ("auto": Metal on Apple Silicon, CUDA when an NVIDIA driver answers, else the CPU).
## -> {key, backend, gpu, archives} or {"error"}
static func plan(os_name: String, arch: String, backend: String, has_nvidia: bool) -> Dictionary:
	var os_id: String = {"macOS": "macos", "Windows": "windows", "Linux": "linux"}.get(os_name, "")
	if os_id == "":
		return {"error": "llama.cpp has no prebuilt llama-server for %s here; build it yourself and pass --server=<path>" % os_name}
	if not BACKENDS.has(backend):
		return {"error": "unknown backend %s (one of %s)" % [backend, ", ".join(BACKENDS)]}
	var b := backend
	if b == "auto":
		if os_id == "macos":
			b = "metal" if arch == "arm64" else "cpu"
		else:
			b = "cuda" if has_nvidia and arch == "x86_64" else "cpu"
	var key := "%s-%s-%s" % [os_id, arch, b]
	if os_id == "macos" and arch == "arm64" and (b == "cpu" or b == "metal"):
		key = "macos-arm64-metal"
	if not BUILDS.has(key):
		return {"error": "llama.cpp has no %s build for %s %s (try --backend=cpu)" % [b, os_name, arch]}
	return {"key": key, "backend": b, "gpu": b != "cpu", "archives": BUILDS[key]}


## True when an NVIDIA driver answers (nvidia-smi is on PATH and lists a GPU)
static func has_nvidia() -> bool:
	if OS.get_name() == "macOS":
		return false
	var out := []
	return OS.execute("nvidia-smi", ["-L"], out, true) == 0 and str(out).contains("GPU")


## The llama-server (or llama-server.exe) under `dir`, searched recursively, or ""
static func find_server(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for f in d.get_files():
		if f == "llama-server" or f == "llama-server.exe":
			return dir.path_join(f)
	for sub in d.get_directories():
		var found := find_server(dir.path_join(sub))
		if found != "":
			return found
	return ""


## The install the game uses, or {} (install.json: server, model, gpu, backend, llama_build, model_id)
static func installed(path := INSTALL) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var d: Dictionary = json.data
	if not FileAccess.file_exists(str(d.get("server", ""))) or not FileAccess.file_exists(str(d.get("model", ""))):
		return {}
	return d


## Installs everything. opts: model ("4b" | "2b", default "4b"), backend (BACKENDS, default "auto"), server (a llama-server
## you already have: nothing is downloaded for it), dir (default DIR), log (Callable taking a line, default print).
## -> the install.json contents, or {"error"}
static func install(opts := {}) -> Dictionary:
	var report: Callable = opts.get("log", func(line: String) -> void: print(line))
	var dir: String = opts.get("dir", DIR)
	var abs_dir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var file: String = MODELS.get(str(opts.get("model", "4b")), "")
	if file == "":
		return {"error": "unknown model %s (4b or 2b)" % opts.get("model")}
	var server: String = str(opts.get("server", ""))
	var gpu := true
	var backend := "custom"
	if server == "":
		var p := plan(OS.get_name(), Engine.get_architecture_name(), str(opts.get("backend", "auto")), has_nvidia())
		if p.has("error"):
			return p
		gpu = p["gpu"]
		backend = p["backend"]
		var dest := abs_dir.path_join("llama-%s-%s" % [LLAMA_BUILD, p["key"]])
		server = find_server(dest)
		if server == "":
			report.call("llama.cpp %s, %s build (%s)" % [LLAMA_BUILD, p["key"], "GPU" if gpu else "CPU"])
			DirAccess.make_dir_recursive_absolute(dest)
			for a in p["archives"]:
				var archive := abs_dir.path_join(a[0])
				var got := await download(RELEASE + a[0], archive, a[1], report)
				if got.has("error"):
					return got
				var out := []
				if OS.execute("tar", ["-xf", archive, "-C", dest], out, true) != 0:
					return {"error": "could not unpack %s: %s" % [a[0], "".join(out).left(400)]}
				DirAccess.remove_absolute(archive)
			server = find_server(dest)
			if server == "":
				return {"error": "no llama-server inside %s" % dest}
		else:
			report.call("llama.cpp %s already installed: %s" % [LLAMA_BUILD, server])
	elif not FileAccess.file_exists(server):
		return {"error": "no llama-server at %s" % server}
	var model := abs_dir.path_join(file)
	var m: Dictionary = Decider.MODELS[file]
	if FileAccess.file_exists(model) and _size(model) == int(m["bytes"]):
		report.call("%s already downloaded" % file)
	else:
		report.call("Decider %s (%.1f GB) from huggingface.co/%s" % [m["id"], m["bytes"] / 1e9, m["repo"]])
		var got := await download(Decider.model_url(file), model, m["sha256"], report)
		if got.has("error"):
			return got
	var info := {"server": server, "model": model, "gpu": gpu, "backend": backend, "llama_build": LLAMA_BUILD if backend != "custom" else "", "model_id": m["id"]}
	var f := FileAccess.open(dir.path_join("install.json"), FileAccess.WRITE)
	if f == null:
		return {"error": "could not write %s" % dir.path_join("install.json")}
	f.store_string(JSON.stringify(info, "  "))
	f.close()
	report.call("installed: %s with %s (%s)" % [server, file, "GPU" if gpu else "CPU"])
	return info


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else -1


## Downloads `url` to `path` (through path.part, renamed once its sha256 matches). -> {} or {"error"}
static func download(url: String, path: String, sha256: String, report: Callable) -> Dictionary:
	var part := path + ".part"
	var tree := Engine.get_main_loop() as SceneTree
	var req := HTTPRequest.new()
	req.download_file = part
	req.use_threads = OS.has_feature("threads")
	req.download_chunk_size = 1 << 20
	req.timeout = 0.0
	tree.root.add_child(req)
	var done := J.Waiter.new()
	req.request_completed.connect(func(result, code, _h, _b): done.resolve([result, code]))
	var err := req.request(url)
	if err != OK:
		req.queue_free()
		return {"error": "could not start downloading %s (%s)" % [url, error_string(err)]}
	var last := J.now_ms()
	while not done.settled:
		await J.sleep(500)
		if J.now_ms() - last >= 5000 and not done.settled:
			last = J.now_ms()
			var total := req.get_body_size()
			report.call("  %s: %.0f MB%s" % [path.get_file(), req.get_downloaded_bytes() / 1e6, " of %.0f" % (total / 1e6) if total > 0 else ""])
	var r: Array = done.value
	req.queue_free()
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS or int(r[1]) != 200:
		DirAccess.remove_absolute(part)
		return {"error": "downloading %s failed (result %d, HTTP %d)" % [url, int(r[0]), int(r[1])]}
	var got := FileAccess.get_sha256(part)
	if got != sha256:
		DirAccess.remove_absolute(part)
		return {"error": "%s has sha256 %s, not the pinned %s: not installed" % [path.get_file(), got, sha256]}
	DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(part, path) != OK:
		return {"error": "could not move %s into place" % part}
	return {}
