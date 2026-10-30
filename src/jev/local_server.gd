## The llama-server process the game starts for the local model (the one cli/setup_local.gd installed, or the one
## config/jev_config.json names), and stops when the game quits. One slot, a 16k context, bound to 127.0.0.1 only; the
## server's own log goes to user://llama-server.log. Starting returns at once: local.gd waits for /health.
## Load it with `const LocalServer = preload("res://src/jev/local_server.gd")`.
extends RefCounted

const DEFAULT_PORT := 41715
const CONTEXT := 16384
const LOG := "user://llama-server.log"

static var pid := -1


## The command line. gpu: every layer on the GPU the build supports (Metal, CUDA, Vulkan...); false keeps it all on the CPU.
static func args(model: String, port: int, gpu: bool, log_file := "") -> PackedStringArray:
	var a := PackedStringArray(["-m", model, "--host", "127.0.0.1", "--port", str(port), "-c", str(CONTEXT), "-np", "1", "--no-webui"])
	if gpu:
		a.append_array(["-ngl", "999"])
	else:
		a.append_array(["-ngl", "0", "-dev", "none"])
	if log_file != "":
		a.append_array(["--log-file", log_file])
	return a


## Starts llama-server unless the game already did. -> {"pid"} or {"error"}. A server already listening on the port
## (left from an earlier run, or started by you) is fine: the new one fails to bind and exits, and the game uses the old.
static func start(server: String, model: String, port := DEFAULT_PORT, gpu := true) -> Dictionary:
	if pid > 0 and OS.is_process_running(pid):
		return {"pid": pid}
	if not FileAccess.file_exists(server):
		return {"error": "no llama-server at %s" % server}
	if not FileAccess.file_exists(model):
		return {"error": "no model at %s" % model}
	pid = OS.create_process(server, args(model, port, gpu, ProjectSettings.globalize_path(LOG)))
	if pid <= 0:
		pid = -1
		return {"error": "could not start %s" % server}
	print("local model: started llama-server (pid %d) on port %d, %s, %s" % [pid, port, model.get_file(), "GPU" if gpu else "CPU only"])
	return {"pid": pid}


## Stops the server the game started (nothing else)
static func stop() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
		print_verbose("local model: stopped llama-server (pid %d)" % pid)
	pid = -1
