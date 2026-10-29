## The game's API: what the browser used to POST to the server, answered in-process. `handle` is `handleApi`: it
## sanitises the request (player-controlled text stays small before it reaches the model), asks Jev through
## enemy.gd / allies.gd / bonds.gd, and returns {"status": int, "body": Dictionary}.
## Load it with `const JevApi = preload("res://src/jev/api.gd")`.
##
##   var r = await JevApi.handle("/api/group-turn", {...}, {"debug": true})
##   if r.status == 200: use(r.body) else: say(r.body.error)
extends RefCounted

const J = preload("res://src/core/js.gd")
const Jev = preload("res://src/jev/jev.gd")
const U = preload("res://src/jev/util.gd")
const JevConfig = preload("res://src/jev/config.gd")
const Enemy = preload("res://src/jev/enemy.gd")
const Allies = preload("res://src/jev/allies.gd")
const Bonds = preload("res://src/jev/bonds.gd")
const Species = preload("res://src/rules/species.gd")
const Emotions = preload("res://src/rules/emotions.gd")

const MAX_REQUEST := 64000


## handleApi. path: "/api/group-turn" | "/api/enemy-turn" | "/api/ally-reactions" | "/api/ally-talk" | "/api/vow" |
## "/api/vow-broken". body: the request, as the JS game posted it (never modified: it is copied first).
## opts: { debug = false }: true puts every raw Jev call behind this request under body._debug.jev, what went out
## and what came back, never the key. Jev is whatever config.gd (or a test) configured; if nothing did yet, the
## config is settled now.
## Returns {"status": 200, "body": reply}, {"status": 400|404|413, "body": {"error": ...}}, or a 500 "Server error" when
## Jev could not be reached or answered badly (the details are in the log and, in debug mode, in body._debug).
static func handle(path: String, body: Dictionary, opts := {}) -> Dictionary:
	var debug: bool = J.truthy(opts.get("debug"))
	var route := path
	var q := path.find("?")
	if q != -1:
		route = path.left(q)
		debug = debug or path.substr(q).contains("debug=1")
	if not route.begins_with("/api/"):
		return _reply(404, {"error": "Not found"})
	if JSON.stringify(body).length() > MAX_REQUEST:
		return _reply(413, {"error": "Request too large"})
	if not Jev.is_configured():
		JevConfig.setup()
	var b: Dictionary = body.duplicate(true)
	# Debug mode: every Jev call behind this request, what went out and what came back, is returned under _debug.
	# Per request, so concurrent requests never mix.
	var trace = [] if debug else null
	var out: Dictionary
	match route:
		"/api/enemy-turn":
			var bad := _sanitize_enemy(b)
			if bad != "":
				return _reply(400, {"error": bad})
			b["trace"] = trace
			out = await Enemy.enemy_turn(b)
		"/api/ally-reactions":
			_sanitize_allies(b)
			b["trace"] = trace
			out = await Allies.ally_reactions(b)
		"/api/group-turn":
			var bad := _sanitize_group(b)
			if bad != "":
				return _reply(400, {"error": bad})
			b["trace"] = trace
			out = await Enemy.group_turn(b)
		"/api/ally-talk":
			if not _ok_species(b.get("ally")):
				return _reply(400, {"error": "Unknown monster"})
			var vows: Array = _arr(b.get("vows")).slice(0, 12)
			out = await Bonds.ally_talk({"ally": b["ally"], "message": U.short(b.get("message")), "vows": vows, "trace": trace})
		"/api/vow":
			if not _ok_species(b.get("monster")):
				return _reply(400, {"error": "Unknown monster"})
			out = await Bonds.vow_made({"monster": b["monster"], "vow": {"text": U.short(_dict(b.get("vow")).get("text"), 80)}, "trace": trace})
		"/api/vow-broken":
			if not _ok_species(b.get("monster")):
				return _reply(400, {"error": "Unknown monster"})
			out = await Bonds.vow_broken({
				"monster": b["monster"],
				"vow": {"text": U.short(_dict(b.get("vow")).get("text"), 80)},
				"how": U.short(b.get("how"), 200),
				"gold": _number(b.get("gold")),
				"trace": trace,
			})
		_:
			return _reply(404, {"error": "Not found"})
	if out.has("error"):
		push_warning("jev api %s: %s" % [route, out["error"]])
		var failed := {"error": "Server error"}
		if trace != null:
			failed["_debug"] = {"jev": trace}
		return _reply(500, failed)
	if trace != null:
		out["_debug"] = {"jev": trace}
	return _reply(200, out)


static func _reply(status: int, body: Dictionary) -> Dictionary:
	return {"status": status, "body": body}


# ---- sanitisers: keep player-controlled text small before it reaches the model

static func _arr(v) -> Array:
	return v if v is Array else []


static func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}


## Number(v) || 0
static func _number(v) -> Variant:
	return U.num_or(v, 0)


static func _ok_species(m) -> bool:
	return m is Dictionary and Species.SPECIES.has(m.get("species"))


## Dictionaries only, the first `n` of them
static func _dicts(v, n: int) -> Array:
	return _arr(v).slice(0, n).filter(func(x): return x is Dictionary)


static func _sanitize_enemy(b: Dictionary) -> String:
	if not _ok_species(b.get("enemy")):
		return "Unknown monster"
	var pa = b.get("playerAction")
	if pa is Dictionary and J.truthy(pa.get("message")):
		pa["message"] = U.js_str(pa["message"]).left(240)
	var conversation := []
	for l in _arr(b.get("conversation")).slice(-10):
		var line := _dict(l)
		conversation.append({"speaker": U.js_str(line.get("speaker")), "text": U.js_str(line.get("text")).left(240)})
	b["conversation"] = conversation
	b["events"] = _arr(b.get("events")).slice(0, 12).map(func(e): return U.js_str(e).left(200))
	b["party"] = _dicts(b.get("party"), 6)
	return ""


static func _sanitize_group(b: Dictionary) -> String:
	var monsters := []
	for m in _arr(b.get("monsters")).slice(0, 3):
		if not _ok_species(m):
			return "Unknown monster"
		monsters.append(m)
	if monsters.is_empty():
		return "No monsters"
	for m in monsters:
		m["thisRound"] = _arr(m.get("thisRound")).slice(0, 6).map(func(t): return U.short(t, 160))
		m["impressions"] = U.last(_arr(m.get("impressions")), 8).map(func(t): return U.short(t, 160))
	b["monsters"] = monsters
	var pa := _dict(b.get("playerAction"))
	b["playerAction"] = {
		"type": U.short(pa.get("type"), 20),
		"message": U.short(pa.get("message")) if J.truthy(pa.get("message")) else null,
		"gold": U.norm(maxf(0.0, float(_number(pa.get("gold"))))),
		"targetId": U.short(pa.get("targetId"), 20),
		"delivery": U.norm(clampf(float(U.num_or(pa.get("delivery"), 1)), 0.5, 2.0)),
		"pitch": pa.get("pitch") if Emotions.PITCH.has(pa.get("pitch")) else null,
	}
	var conversation := []
	for l in U.last(_arr(b.get("conversation")), 10):
		var line := _dict(l)
		conversation.append({"speaker": U.short(line.get("speaker"), 40), "text": U.short(line.get("text"))})
	b["conversation"] = conversation
	b["events"] = _arr(b.get("events")).slice(0, 12).map(func(e): return U.short(e, 200))
	b["guided"] = b.get("guided") is bool and b["guided"]
	b["party"] = _dicts(b.get("party"), 6)
	b["vows"] = _dicts(b.get("vows"), 12).map(func(v): return {"text": U.short(v.get("text"), 80), "toId": U.short(v.get("toId"), 20), "status": U.short(v.get("status"), 10)})
	return ""


static func _sanitize_allies(b: Dictionary) -> void:
	b["allies"] = _arr(b.get("allies")).slice(0, 5).filter(func(a): return _ok_species(a))
	b["events"] = _arr(b.get("events")).slice(0, 16).map(func(e): return U.js_str(e).left(200))
