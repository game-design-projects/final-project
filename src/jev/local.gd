## Answers System One requests ({state, questions} -> {model, answers, usage}) with Decider running in a local
## llama-server (llama.cpp's HTTP server, any platform and backend: CPU, Metal, CUDA, Vulkan, ROCm). decider.gd builds
## the prompt rows and reads the answers; each row is one /completion call that returns the probabilities of the option
## letters at the answer slot. A Server is a transport for jev.gd (fetch(url, headers, body)), like mock_jev.gd's.
##
## Speed comes from the prompt cache: a request first runs the state alone, so the server keeps a checkpoint at its end
## (Decider's Qwen3.5 layers are partly recurrent and can't be rewound past one), and every row after it only runs its
## own question. Rows go one at a time on one slot: parallel slots each keep their own cache and are slower here, and
## llama.cpp's batching moves a row's probabilities with its neighbours'. Requests are queued for the same reason.
## Load it with `const Local = preload("res://src/jev/local.gd")`.
extends RefCounted

const DEFAULT_BASE := "http://127.0.0.1:41715"


## One local llama-server. `request` (for tests): (method, url, headers, body, timeout_s) -> {"status", "text"} | {"error"},
## like Http.request. `wait_s`: how long to wait for the server to answer /health (it may still be loading the model).
class Server:
	extends RefCounted
	const J = preload("res://src/core/js.gd")
	const Http = preload("res://src/jev/http.gd")
	const Decider = preload("res://src/jev/decider.gd")

	## Lifts every option letter far above the rest of the vocabulary: the letters keep their ratios and nothing else
	## takes any mass, so the probabilities that come back are the softmax over the letters alone
	const BIAS := 100.0
	## Tokens of state a row may carry (the server's context is 16384; the rest is the question's)
	const MAX_STATE_TOKENS := 12288
	const ROW_TIMEOUT_S := 120.0

	var base: String
	var request: Callable
	var wait_s: float
	var model := {}  # the Decider.MODELS entry of what the server runs, once known
	var file := ""
	var labels := []  # token ids of "A".."Z"
	var calls := 0  # HTTP requests made
	var _busy := false
	var _queue: Array = []

	func _init(api_base := "http://127.0.0.1:41715", opts := {}) -> void:
		base = str(api_base).rstrip("/")
		request = opts.get("request", Callable(Http, "request"))
		wait_s = float(opts.get("wait_s", 3.0))

	## fetch(url, headers, body) -> {"status": 200, "json": reply}, {"status": 400, "json": {"error"}} for a question
	## Decider can't take, or {"error": ...} like a fetch that rejects (no server, a wrong model, a failed row)
	func fetch(_url: String, _headers: Dictionary, body: Dictionary) -> Dictionary:
		while _busy:
			var turn := J.Waiter.new()
			_queue.append(turn)
			await turn.wait()
		_busy = true
		var out: Dictionary = await _answer(body)
		_busy = false
		if not _queue.is_empty():
			_queue.pop_front().resolve()
		return out

	func _answer(body: Dictionary) -> Dictionary:
		var ready: Dictionary = await _ready_server()
		if ready.has("error"):
			return ready
		var questions: Dictionary = body.get("questions", {})
		var rqs := {}
		for k in questions:
			var rq: Dictionary = Decider.render_question(questions[k] if questions[k] is Dictionary else {})
			if rq.has("error"):
				return {"status": 400, "json": {"error": "%s: %s" % [k, rq["error"]]}}
			rqs[k] = rq
		var plan: Dictionary = Decider.plan_rows(rqs)
		var t0 := J.now_ms()
		var tok: Dictionary = await _post("/tokenize", {"content": "Context:\n" + Decider.render_state(body.get("state", {}))}, 30.0)
		if tok.has("error"):
			return tok
		var ctx := []
		for t in (tok["json"].get("tokens", []) as Array).slice(0, MAX_STATE_TOKENS):
			ctx.append(int(t))
		# the state alone first: the server checkpoints its end, and every row below resumes from there
		var prime: Dictionary = await _post("/completion", {"prompt": ctx, "n_predict": 0, "cache_prompt": true}, ROW_TIMEOUT_S)
		if prime.has("error"):
			return prime
		var tokens := int(prime["json"].get("timings", {}).get("prompt_n", ctx.size()))
		var temps: Dictionary = model["temperatures"]
		var probs := []
		for row in plan["rows"]:
			var p: Dictionary = await _row(ctx, row)
			if p.has("error"):
				return p
			probs.append(Decider.with_temperature(p["p"], float(temps[row["type"]])))
			tokens += int(p["prompt_n"])
		var answers: Dictionary = Decider.assemble(rqs, plan["index"], probs)
		print_verbose("local model: %s, %d questions in %d rows, %d prompt tokens, %d ms" % [model["id"], rqs.size(), plan["rows"].size(), tokens, int(J.now_ms() - t0)])
		return {"status": 200, "json": {"model": model["id"], "answers": answers, "usage": {"input_tokens": tokens, "output_tokens": 0}}}

	## One row: the probabilities of its option letters (softmax at temperature 1) and the tokens the server ran
	func _row(ctx: Array, row: Dictionary) -> Dictionary:
		var n: int = row["options"].size()
		var prompt := ctx.duplicate()
		for piece in Decider.pieces(row):
			prompt.append(labels[piece["label"]] if piece is Dictionary else piece)
		var bias := []
		for j in n:
			bias.append([labels[j], BIAS])
		var out: Dictionary = await _post("/completion", {
			"prompt": prompt, "n_predict": 0, "n_probs": n, "post_sampling_probs": true, "samplers": ["temperature"],
			"temperature": 1.0, "logit_bias": bias, "cache_prompt": true,
		}, ROW_TIMEOUT_S)
		if out.has("error"):
			return out
		var cp = out["json"].get("completion_probabilities")
		if not cp is Array or cp.is_empty() or not cp[0] is Dictionary or not cp[0].get("top_probs") is Array:
			return {"error": "llama-server sent no token probabilities (is it llama.cpp's server, a recent build?)"}
		var by_id := {}
		for t in cp[0]["top_probs"]:
			by_id[int(t.get("id", -1))] = float(t.get("prob", 0.0))
		var p := []
		var s := 0.0
		for j in n:
			p.append(by_id.get(labels[j], 0.0))
			s += p[j]
		if s <= 0.0:
			return {"error": "llama-server gave the option letters no probability"}
		return {"p": p.map(func(x): return x / s), "prompt_n": out["json"].get("timings", {}).get("prompt_n", prompt.size())}

	## Waits for the server, learns which model it runs (from /props) and the token ids of the option letters, once
	func _ready_server() -> Dictionary:
		if not model.is_empty():
			return {}
		var deadline := J.now_ms() + wait_s * 1000.0
		var why := ""
		while true:
			var h: Dictionary = await _send(HTTPClient.METHOD_GET, "/health", null, 3.0)
			if not h.has("error") and h["status"] == 200:
				break
			# 503 while the model loads; nothing listening while the process starts
			why = h["error"] if h.has("error") else "HTTP %d%s" % [h["status"], " (loading the model)" if h["status"] == 503 else ""]
			if not h.has("error") and h["status"] != 503:
				return {"error": "%s answers /health with %s: is it llama-server?" % [base, why]}
			if J.now_ms() >= deadline:
				return {"error": "no llama-server at %s (%s)" % [base, why]}
			await J.sleep(500)
		var props: Dictionary = await _send(HTTPClient.METHOD_GET, "/props", null, 5.0)
		if props.has("error"):
			return props
		var info = Http.parse(props.get("text", ""))
		var path := str(info.get("model_path", "")) if info is Dictionary else ""
		var m := Decider.model_for(path)
		if m.is_empty():
			return {"error": "llama-server at %s runs %s, not a Decider model this game knows (%s)" % [base, path.get_file() if path != "" else "an unknown model", ", ".join(Decider.MODELS.keys())]}
		var ids := []
		for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
			var t: Dictionary = await _post("/tokenize", {"content": c}, 5.0)
			if t.has("error"):
				return t
			var got: Array = t["json"].get("tokens", [])
			if got.size() != 1:
				return {"error": "the option letter %s is not one token in %s" % [c, path.get_file()]}
			ids.append(int(got[0]))
		labels = ids
		model = m
		file = path.get_file()
		print("local model: %s at %s" % [m["id"], base])
		return {}

	func _send(method: int, path: String, body, timeout_s: float) -> Dictionary:
		calls += 1
		var headers := {} if body == null else {"content-type": "application/json"}
		return await request.call(method, base + path, headers, body, timeout_s)

	## POST a JSON body; -> {"json": reply} for a 200 with a JSON object, else {"error": ...}
	func _post(path: String, body: Dictionary, timeout_s: float) -> Dictionary:
		var r: Dictionary = await _send(HTTPClient.METHOD_POST, path, body, timeout_s)
		if r.has("error"):
			return {"error": "llama-server %s: %s" % [path, r["error"]]}
		var parsed = Http.parse(str(r.get("text", "")))
		if r["status"] != 200:
			return {"error": "llama-server %s %d: %s" % [path, r["status"], str(r.get("text", "")).left(200)]}
		if not parsed is Dictionary:
			return {"error": "llama-server %s: the reply was not a JSON object" % path}
		return {"json": parsed}
