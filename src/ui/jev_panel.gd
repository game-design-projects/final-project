## The Jev mind panel, debug runs only (showJev, jevTab, renderRequests in game.js; .jev, .jtabs, .req, .jsec in
## style.css). MIND: every monster's meters, what it heard, Jev's action and feeling odds, its answer to an
## invitation, what code blocked; how allies scored the fight. REQUESTS: every API call, newest first, opened to
## read what was sent and answered and each raw Jev call behind it, with COPY buttons. J shows or hides it.
extends "res://src/ui/widget.gd"

const J = preload("res://src/core/js.gd")
const Inspector = preload("res://src/rules/inspector.gd")
const LogPanel = preload("res://src/ui/log_panel.gd")

const PAD_X := 12.0
const PAD_Y := 10.0
const META := 18
const INTRO := "MEET A MONSTER. EVERY ROUND, ONE JEV REQUEST DECIDES WHAT IT HEARD, WHAT IT DOES, WHO IT TARGETS AND WHAT IT SAYS. AFTER EACH FIGHT, YOUR MONSTER ALLIES JUDGE YOU."

var tab := "mind"
var tabs_shown := false
var scroll: ScrollContainer
var list: VBoxContainer
var mind: MindView
## The REQUESTS tab: the log it shows and which entries (and Jev calls) are open
var api_log: Array = []
var open_requests := {}
var open_calls := {}
var _req_sig := ""
var _header_h := 0.0
## The most the panel may take (max-height: calc(100vh - 32px)); it is as tall as its content up to this
var max_h := 0.0


func _init() -> void:
	super()
	solid = true
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	LogPanel.style_scrollbar(scroll.get_v_scroll_bar())
	add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)
	mind = MindView.new()
	mind.blocks = [{"type": "meta", "text": INTRO}]
	list.add_child(mind)
	list.minimum_size_changed.connect(fit.call_deferred)


func _ready() -> void:
	mind.ui = ui


func _notification(what: int) -> void:
	super(what)
	if what == NOTIFICATION_RESIZED:
		_place()


func _place() -> void:
	_header_h = 2.0 + PAD_Y + 11.0 + 8.0 + (24.0 + 10.0 if tabs_shown else 0.0)
	scroll.position = Vector2(2.0 + PAD_X, _header_h)
	scroll.size = Vector2(maxf(0.0, size.x - 4.0 - 2.0 * PAD_X), maxf(0.0, size.y - _header_h - PAD_Y - 2.0))


## As tall as what it shows, up to max_h (then it scrolls)
func fit() -> void:
	if max_h <= 0.0:
		return
	var want := _header_h + list.get_combined_minimum_size().y + PAD_Y + 2.0
	var h := minf(max_h, ceilf(want))
	if absf(size.y - h) > 0.5:
		size.y = h
		_place()
		queue_redraw()


func paint() -> void:
	var box := Rect2(Vector2.ZERO, size)
	draw_rect(box, Css.BG)
	Css.frame(self, box, Css.FAINT, 2.0)
	var x := 2.0 + PAD_X
	var y := 2.0 + PAD_Y
	var w := Css.text(self, Css.ps(), 11, x, y, "JEV MIND", Css.INK, 11)
	Css.text(self, Css.ps(), 9, x + w + 9.0, y + 2.0, "(J)", Css.DIM, 9)
	if tabs_shown:
		var ty := y + 11.0 + 8.0
		var tx := x
		for t in [["mind", "MIND"], ["requests", "REQUESTS %d" % api_log.size()]]:
			var label: String = t[1]
			var r := Rect2(tx, ty, 2.0 + 8.0 + Css.width(Css.ps(), 8, label) + 8.0 + 2.0, 24.0)
			var on: bool = tab == t[0]
			var hot: bool = hover_id == "tab:" + t[0]
			draw_rect(r, Css.INK if on else Css.BG)
			Css.frame(self, r, Css.INK if on or hot else Css.FAINT, 2.0)
			Css.text(self, Css.ps(), 8, r.position.x + 10.0, r.position.y + 2.0, label, Color.BLACK if on else (Css.INK if hot else Css.DIM), 20.0)
			add_hit(r, {"id": "tab:" + t[0], "click": true, "tab": t[0]})
			tx = r.end.x + 4.0


func _pressed(h: Dictionary) -> void:
	if h.has("tab") and ui != null:
		ui.jev_tab(h.tab)


func show_tabs(on: bool) -> void:
	tabs_shown = on
	_place()
	queue_redraw()


## jevTab(): MIND or REQUESTS
func set_tab(t: String) -> void:
	tab = t
	_req_sig = ""
	_rebuild()
	queue_redraw()


## showJev(x): the MIND tab's content for one decision
func show_mind(blocks: Array) -> void:
	mind.blocks = blocks
	mind.relayout()
	if tab == "mind":
		scroll.scroll_vertical = 0


## renderRequests(): the REQUESTS tab, if it's showing
func show_requests(log: Array) -> void:
	api_log = log
	queue_redraw()
	if tab != "requests":
		return
	var parts := []
	for e in log:
		parts.append("%s:%s:%s" % [e.n, e.status, e.ms])
	var sig := ",".join(parts)
	if sig == _req_sig:
		return
	_req_sig = sig
	_rebuild()


func _rebuild() -> void:
	for c in list.get_children():
		if c != mind:
			list.remove_child(c)
			c.queue_free()
	mind.visible = tab == "mind"
	if tab != "requests":
		return
	if api_log.is_empty():
		var m := MindView.new()
		m.ui = ui
		m.blocks = [{"type": "meta", "text": "NO REQUESTS YET. EVERY CALL TO THE GAME SERVER SHOWS UP HERE, WITH THE JEV CALLS BEHIND IT."}]
		list.add_child(m)
		return
	for e in api_log:
		var item := ReqItem.new()
		item.panel = self
		item.ui = ui
		item.entry = e
		list.add_child(item)
		item.build()


func toggle_request(n, item) -> void:
	if open_requests.has(n):
		open_requests.erase(n)
	else:
		open_requests[n] = true
	item.build()


func toggle_call(key: String, item) -> void:
	if open_calls.has(key):
		open_calls.erase(key)
	else:
		open_calls[key] = true
	item.build()


# ---------------------------------------------------------------- MIND: showJev's markup as blocks

static func bar_block(label: String, v: float, max_v: float, value: String, hot := false) -> Dictionary:
	return {"label": label, "pct": clampf(v / max_v, 0.0, 1.0) if max_v != 0.0 else 0.0, "value": value, "hot": hot}


static func words(s) -> String:
	return str(s).replace("_", " ").to_upper()


static func pct(p) -> String:
	return "%d%%" % J.round_js(float(p) * 100.0)


static func _fixed(x, d: int) -> String:
	return ("%." + str(d) + "f") % float(x)


## showJev(x) as blocks: {type: meta|h3|rows|ul|blocked, text, color, rows: [{label, pct, value, hot}], items}
static func mind_blocks(x: Dictionary, color_of: Callable) -> Array:
	var b := []
	var kind: String = x.get("kind", "")
	if kind == "group":
		var out: Dictionary = x.out
		var here: Array = x.here
		b.append({"type": "meta", "text": "%s QUESTIONS · %s MS · %s TOKENS · ACTIONS ROLLED ON JEV'S ODDS" % [J.num(out.get("questionCount")), J.num(out.get("ms")), J.num(out.get("inputTokens"))]})
		for r in out.get("results", []):
			var e = null
			for m in here:
				if m.id == r.id:
					e = m
			if e == null:
				continue
			b.append({"type": "h3", "text": "%s · %s" % [J.up(e.name), words(r.get("side", ""))], "color": color_of.call(e)})
			var rows := []
			for k in ["friendliness", "anger", "fear"]:
				rows.append(bar_block(J.up(k), float(r.meters.get(k, 0)), 100.0, J.num(r.meters.get(k, 0))))
			for p in r.get("perception", []):
				if float(p.value) >= 0.5 or p.get("type") == "score":
					rows.append(bar_block("HEARD: %s" % J.up(p.label), float(p.value), float(J.nz(p.get("max"), 1)), _fixed(p.value, 2)))
			var probs: Array = r.get("probabilities", [])
			for p in probs.slice(0, 4):
				rows.append(bar_block(words(p.id), float(p.p), 1.0, pct(p.p), p.id == r.get("picked")))
			var emo = r.get("emotion")
			for p in J.nz(r.get("emotionProbabilities"), []):
				rows.append(bar_block("FEELS %s" % words(p.id), float(p.p), 1.0, pct(p.p), emo is Dictionary and p.id == emo.get("id")))
			b.append({"type": "rows", "rows": rows})
			if emo is Dictionary:
				b.append({"type": "meta", "text": "FEELING: %s → %s" % [emo.get("label", ""), emo.get("effect", "")]})
			var join = r.get("join")
			if join is Dictionary:
				var ans := ("ASKS TO COME" if J.truthy(join.get("moved")) else "YES") if J.truthy(join.get("accepted")) else "NO"
				b.append({"type": "meta", "text": "JOIN: %s · REASON %s" % [ans, words(join.get("reason", ""))]})
			if J.truthy(r.get("blocked")):
				b.append({"type": "blocked", "text": "CODE BLOCKED %s: %s → %s" % [words(r.get("picked", "")), r.blocked, words(r.get("action", ""))]})
	elif kind == "allies":
		var r: Dictionary = x.r
		b.append({"type": "meta", "text": "ALLY CHECK · %s QUESTIONS · %s MS" % [J.num(r.get("questionCount")), J.num(r.get("ms"))]})
		b.append({"type": "h3", "text": "WHAT THEY SAW", "color": ""})
		b.append({"type": "ul", "items": x.get("events", [])})
		for a in r.get("reactions", []):
			b.append({"type": "h3", "text": str(a.name), "color": ""})
			var d := float(a.get("delta", 0))
			b.append({"type": "rows", "rows": [
				bar_block("APPROVAL 0–4", float(a.approval), 4.0, _fixed(a.approval, 1)),
				bar_block("LOYALTY %s%s" % ["+" if d >= 0 else "", J.num(a.delta)], float(a.loyalty), 100.0, J.num(a.loyalty)),
			]})
			var said := " (JEV SAID %s)" % words(a.picked) if a.get("picked") != "stay" and a.get("picked") != a.get("decision") else ""
			b.append({"type": "meta", "text": "DECISION: %s%s" % [words(a.get("decision", "")), said]})
			if J.truthy(a.get("moment")):
				b.append({"type": "meta", "text": "MOST STRUCK BY: %s" % a.moment})
			if J.truthy(a.get("blocked")):
				b.append({"type": "blocked", "text": str(a.blocked)})
	elif kind == "talk":
		var ally: Dictionary = x.ally
		var r: Dictionary = x.r
		var d := float(r.get("loyaltyDelta", 0))
		b.append({"type": "meta", "text": "ALLY TALK · %s MS" % J.num(r.get("ms"))})
		b.append({"type": "h3", "text": str(ally.name), "color": color_of.call(ally)})
		b.append({"type": "rows", "rows": [
			bar_block("HOW IT LANDED 0–4", float(r.resonance), 4.0, _fixed(r.resonance, 1)),
			bar_block("LOYALTY %s%s" % ["+" if d >= 0 else "", J.num(r.loyaltyDelta)], float(ally.loyalty), 100.0, J.num(ally.loyalty)),
		]})
		var got := []
		for k in ["outcome", "buff"]:
			if r.get(k) is Dictionary and J.truthy(r[k].get("id")):
				got.append(r[k].id)
		b.append({"type": "meta", "text": "RESULT: %s (0 SULK · 1 DISTRACTED · 2 STEADY · 3 BUFF · 4 INSPIRED + BUFF)" % (" + ".join(got) if not got.is_empty() else "NONE")})
	elif kind == "vow":
		var to: Dictionary = x.to
		var r: Dictionary = x.r
		b.append({"type": "meta", "text": "VOW · %s MS" % J.num(r.get("ms"))})
		b.append({"type": "h3", "text": "%s HEARS \"%s\"" % [J.up(to.name), x.vow.text], "color": color_of.call(to)})
		b.append({"type": "rows", "rows": [bar_block("HOW IT FEELS 0–4", float(r.liking), 4.0, _fixed(r.liking, 1))]})
	elif kind == "broken":
		var ally: Dictionary = x.ally
		var r: Dictionary = x.r
		b.append({"type": "meta", "text": "BROKEN VOW · %s MS" % J.num(r.get("ms"))})
		b.append({"type": "h3", "text": "%s · \"%s\"" % [ally.name, x.v.text], "color": color_of.call(ally)})
		var probs: Dictionary = r.get("probabilities", {})
		var ids := probs.keys()
		ids.sort_custom(func(p, q): return probs[p] > probs[q] or (probs[p] == probs[q] and ids.find(p) < ids.find(q)))
		var rows := []
		for id in ids:
			rows.append(bar_block(words(id), float(probs[id]), 1.0, pct(probs[id]), id == r.get("picked")))
		b.append({"type": "rows", "rows": rows})
		if J.truthy(r.get("blocked")):
			b.append({"type": "blocked", "text": str(r.blocked)})
		if r.get("response") == "steal_gold":
			b.append({"type": "meta", "text": "STEAL ROLL (60%%): %s" % ("SUCCESS, %s GOLD" % J.num(r.stolen) if J.truthy(r.get("stolen")) else "CAUGHT")})
	return b


## The MIND tab: blocks painted the way .jev's markup looks
class MindView:
	extends "res://src/ui/widget.gd"
	var blocks: Array = []

	func _init() -> void:
		super()
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _notification(what: int) -> void:
		super(what)
		if what == NOTIFICATION_RESIZED:
			relayout()

	func relayout() -> void:
		custom_minimum_size.y = _walk(false)
		queue_redraw()

	func paint() -> void:
		_walk(true)

	## Lays the blocks out (and paints them when `draw` is set); returns the height
	func _walk(draw: bool) -> float:
		var w := size.x
		var y := 0.0
		var vt := Css.vt()
		for i in blocks.size():
			var b: Dictionary = blocks[i]
			match b.type:
				"meta", "blocked":
					if b.type == "blocked":
						y += 8.0
					for l in Css.wrap(vt, 18, str(b.text), w):
						if draw:
							Css.text(self, vt, 18, 0, y, l, Css.WARN if b.type == "blocked" else Css.DIM, 20)
						y += 20.0
					y += 4.0
				"h3":
					y += 12.0 - (4.0 if i > 0 and blocks[i - 1].type == "meta" else 0.0)
					for l in Css.wrap(Css.ps(), 9, str(b.text), w):
						if draw:
							Css.text(self, Css.ps(), 9, 0, y, l, Css.css(b.color) if str(b.get("color", "")) != "" else Css.DIM, 11)
						y += 11.0
					y += 6.0
				"rows":
					for r in b.rows:
						if draw:
							_row(r, y, w)
						y += 23.0
					y -= 3.0
					y += 4.0
				"ul":
					for item in b.items:
						var lines := Css.wrap(vt, 18, str(item), w - 16.0)
						for j in lines.size():
							if draw:
								if j == 0:
									draw_rect(Rect2(5, y + 8, 5, 5), Css.DIM)
								Css.text(self, vt, 18, 16, y, lines[j], Css.DIM, 20)
							y += 20.0
		return y

	## One row: the label, a meter 70px wide, the number right-aligned in 38px
	func _row(r: Dictionary, y: float, w: float) -> void:
		var vt := Css.vt()
		var label_w := w - 70.0 - 38.0 - 16.0
		var hot: bool = r.hot
		var label := Css.ellipsize(vt, 18, str(r.label), label_w)
		var lw := Css.text(self, vt, 18, 0, y, label, Color.WHITE if hot else Css.INK, 20)
		if hot:
			draw_rect(Rect2(0, y + 17, lw, 1), Color.WHITE)
		var m := Rect2(label_w + 8.0, y + 6.0, 70, 7)
		Css.frame(self, m, Css.DIM, 1.0)
		draw_rect(Rect2(m.position, Vector2(roundf(70.0 * r.pct), 7)), Css.INK)
		Css.text(self, vt, 18, w - Css.width(vt, 18, str(r.value)), y, str(r.value), Css.INK, 20)


# ---------------------------------------------------------------- REQUESTS

## One request: a summary line you click to open, then what was sent, what came back and every Jev call
class ReqItem:
	extends "res://src/ui/widget.gd"
	var panel
	var entry: Dictionary
	var body: VBoxContainer
	var _summary_h := 44.0

	func _init() -> void:
		super()
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func is_open() -> bool:
		return panel.open_requests.has(entry.n)

	func build() -> void:
		if body != null:
			remove_child(body)
			body.queue_free()
			body = null
		if is_open():
			body = VBoxContainer.new()
			body.add_theme_constant_override("separation", 0)
			var e := entry
			var n := J.num(e.n)
			body.add_child(JsonSection.make(panel, "SENT TO THE GAME SERVER", e.get("request"), "%s:request" % n))
			if J.truthy(e.get("error")):
				body.add_child(Note.make(str(e.error), Css.WARN))
			else:
				body.add_child(JsonSection.make(panel, "THE GAME SERVER ANSWERED", e.get("response"), "%s:response" % n))
			if e.get("jev") == null:
				body.add_child(Note.make("NO JEV DETAILS: THIS SERVER DOESN'T SEND THEM (AN OLDER WORKER? REDEPLOY IT).", Css.DIM))
			var calls: Array = J.nz(e.get("jev"), [])
			for i in calls.size():
				var c := CallItem.new()
				c.panel = panel
				c.ui = ui
				c.entry = e
				c.index = i
				c.call_data = calls[i]
				body.add_child(c)
				c.build()
			add_child(body)
			body.minimum_size_changed.connect(_fit)
		_fit()

	func _notification(what: int) -> void:
		super(what)
		if what == NOTIFICATION_RESIZED:
			_fit()

	func _fit() -> void:
		var h := _summary_h
		if body != null:
			body.position = Vector2(10, _summary_h)
			body.size = Vector2(size.x - 20.0, body.get_combined_minimum_size().y)
			h += body.size.y + 10.0
		custom_minimum_size.y = h + 8.0
		queue_redraw()

	func paint() -> void:
		var open := is_open()
		var box := Rect2(0, 0, size.x, size.y - 8.0)
		if open:
			draw_rect(Rect2(box.position + Vector2(4, 4), box.size), Color("#1d1d1d"))
		draw_rect(box, Css.BG)
		Css.frame(self, box, Css.INK if open or hover_id == "sum" else Css.FAINT, 2.0)
		var s: Dictionary = Inspector.summarize(entry)
		var x := 10.0
		var y := 8.0
		# a pixel triangle: right when shut, down when open
		var c := Vector2(x + 6, y + 6)
		if open:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -3), c + Vector2(5, -3), c + Vector2(0, 4)]), Css.INK)
		else:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3, -5), c + Vector2(4, 0), c + Vector2(-3, 5)]), Css.INK)
		x += 20.0
		var font := Css.ps()
		x += Css.text(self, font, 8, x, y, "#%s" % J.num(entry.n), Css.INK, 13) + 8.0
		x += Css.text(self, font, 8, x, y, str(s.name), Css.INK, 13) + 8.0
		var st_c: Color = {"ok": Color("#6bd36b"), "bad": Css.WARN}.get(s.state, Css.DIM)
		var st_w := Css.width(font, 8, str(s.status)) + 8.0
		draw_rect(Rect2(x, y, st_w, 13), st_c)
		Css.text(self, font, 8, x + 4.0, y, str(s.status), Color.BLACK, 13)
		x += st_w + 8.0
		Css.text(self, font, 8, x, y, "%s MS" % (J.num(s.ms) if s.ms != null else "…"), Css.DIM, 13)
		var sub := ""
		if s.traced:
			sub = "%d JEV CALL%s · %d QUESTIONS%s" % [s.calls, "" if s.calls == 1 else "S", s.questions, " · %s TOKENS" % J.num(s.tokens) if J.truthy(s.tokens) else ""]
		var time := _time(entry.get("at"))
		var time_w := Css.width(Css.vt(), 16, time)
		Css.text(self, Css.vt(), 16, 30, y + 16.0, Css.ellipsize(Css.vt(), 16, sub, size.x - 10.0 - time_w - 8.0 - 30.0), Css.DIM, 16)
		Css.text(self, Css.vt(), 16, size.x - 10.0 - time_w, y + 16.0, time, Css.DIM, 16)
		add_hit(Rect2(0, 0, size.x, _summary_h), {"id": "sum", "click": true})

	static func _time(at) -> String:
		if at == null:
			return ""
		var bias: int = Time.get_time_zone_from_system().get("bias", 0)
		var d := Time.get_datetime_dict_from_unix_time(int(float(at) / 1000.0) + bias * 60)
		return "%02d:%02d:%02d" % [d.hour, d.minute, d.second]

	func _pressed(h: Dictionary) -> void:
		if h.id == "sum":
			panel.toggle_request(entry.n, self)


## One raw Jev call inside a request: STATE, QUESTIONS, ANSWERS
class CallItem:
	extends "res://src/ui/widget.gd"
	var panel
	var entry: Dictionary
	var index := 0
	var call_data: Dictionary
	var body: VBoxContainer
	const SUM_H := 26.0

	func _init() -> void:
		super()
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func key() -> String:
		return "%s:%d" % [J.num(entry.n), index]

	func build() -> void:
		if body != null:
			remove_child(body)
			body.queue_free()
			body = null
		if panel.open_calls.has(key()):
			body = VBoxContainer.new()
			body.add_theme_constant_override("separation", 0)
			var k := key()
			body.add_child(JsonSection.make(panel, "STATE (WHAT JEV KNOWS)", call_data.get("state"), "%s:state" % k))
			body.add_child(JsonSection.make(panel, "QUESTIONS", call_data.get("questions"), "%s:questions" % k))
			if J.truthy(call_data.get("error")):
				body.add_child(Note.make(str(call_data.error), Css.WARN))
			else:
				var response = call_data.get("response")
				body.add_child(JsonSection.make(panel, "ANSWERS", response.get("answers") if response is Dictionary else null, "%s:answers" % k))
			add_child(body)
			body.minimum_size_changed.connect(_fit)
		_fit()

	func _notification(what: int) -> void:
		super(what)
		if what == NOTIFICATION_RESIZED:
			_fit()

	func _fit() -> void:
		var h := 14.0 + SUM_H
		if body != null:
			body.position = Vector2(8, 14.0 + SUM_H)
			body.size = Vector2(size.x - 16.0, body.get_combined_minimum_size().y)
			h += body.size.y + 8.0
		custom_minimum_size.y = h
		queue_redraw()

	func paint() -> void:
		var open: bool = body != null
		var box := Rect2(0, 14, size.x, size.y - 14.0)
		var blue := Color("#9ad0ff")
		draw_rect(box, Css.BG)
		Css.frame(self, box, blue if open or hover_id == "sum" else Color("#1f3b52"), 2.0)
		var c := Vector2(14, 14 + SUM_H / 2.0)
		if open:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -2), c + Vector2(4, -2), c + Vector2(0, 3)]), blue)
		else:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-2, -4), c + Vector2(3, 0), c + Vector2(-2, 4)]), blue)
		var q: int = (J.nz(call_data.get("questions"), {}) as Dictionary).size()
		var response = call_data.get("response")
		var usage = response.get("usage") if response is Dictionary else null
		var text := "JEV CALL %d · %s MS · %d QUESTIONS" % [index + 1, J.num(J.nz(call_data.get("ms"), "?")), q]
		if usage is Dictionary:
			text += " · %s TOKENS" % J.num(usage.get("input_tokens"))
		if int(J.nz(call_data.get("attempts"), 1)) > 1:
			text += " · %s TRIES" % J.num(call_data.attempts)
		if J.truthy(call_data.get("error")):
			text += " · FAILED"
		Css.text(self, Css.ps(), 7, 24, 14, Css.ellipsize(Css.ps(), 7, text, size.x - 30.0), blue, SUM_H)
		add_hit(Rect2(0, 14, size.x, SUM_H), {"id": "sum", "click": true})

	func _pressed(h: Dictionary) -> void:
		if h.id == "sum":
			panel.toggle_call(key(), self)


## A framed JSON block with its label on the top edge and a COPY button
class JsonSection:
	extends "res://src/ui/widget.gd"
	var panel
	var label := ""
	var copy_key := ""
	var rtl: RichTextLabel
	var _copied_at := -1e9
	var _copy_text := "COPY"
	const MAX_PRE := 260.0

	static func make(p, l: String, value, key: String) -> JsonSection:
		var s := JsonSection.new()
		s.panel = p
		s.ui = p.ui
		s.label = l
		s.copy_key = key
		s.rtl.text = Inspector.highlight_json(value)
		return s

	func _init() -> void:
		super()
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rtl = RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.scroll_active = true
		rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rtl.selection_enabled = true
		rtl.focus_mode = Control.FOCUS_NONE
		rtl.add_theme_font_override("normal_font", Css.vt())
		rtl.add_theme_font_size_override("normal_font_size", 16)
		rtl.add_theme_color_override("default_color", Css.INK)
		rtl.add_theme_constant_override("line_separation", 2)
		LogPanel.style_scrollbar(rtl.get_v_scroll_bar())
		add_child(rtl)
		custom_minimum_size.y = 60

	func _notification(what: int) -> void:
		super(what)
		if what == NOTIFICATION_RESIZED:
			_fit()

	func _fit() -> void:
		rtl.position = Vector2(2 + 8, 16 + 2 + 12)
		rtl.size.x = maxf(10.0, size.x - 4.0 - 16.0)
		var h := minf(rtl.get_content_height(), MAX_PRE - 20.0)
		rtl.size.y = maxf(16.0, h)
		var want := 16.0 + 2.0 + 12.0 + rtl.size.y + 8.0 + 2.0
		if absf(custom_minimum_size.y - want) > 0.5:
			custom_minimum_size.y = want
		queue_redraw()

	func paint() -> void:
		var box := Rect2(0, 16, size.x, size.y - 16.0)
		draw_rect(box, Css.BG)
		Css.frame(self, box, Css.FAINT, 2.0)
		var font := Css.ps()
		var tw := Css.width(font, 7, label) + 8.0
		draw_rect(Rect2(6, 16 - 9 + 2, tw, 11), Css.DIM)
		Css.text(self, font, 7, 10, 16 - 9 + 2, label, Color.BLACK, 11)
		if now_ms() - _copied_at > 1200.0:
			_copy_text = "COPY"
		var cw := Css.width(font, 7, _copy_text) + 14.0
		var cr := Rect2(size.x - 6.0 - cw, 16 - 9, cw, 15)
		draw_rect(cr, Css.BG)
		Css.frame(self, cr, Css.INK if hover_id == "copy" else Css.FAINT, 2.0)
		Css.text(self, font, 7, cr.position.x + 7.0, cr.position.y, _copy_text, Css.INK, 15)
		add_hit(cr, {"id": "copy", "click": true})

	func _pressed(h: Dictionary) -> void:
		if h.id != "copy":
			return
		Inspector.copy_value(panel.api_log, copy_key)
		_copy_text = "COPIED"
		_copied_at = now_ms()
		queue_redraw()
		get_tree().create_timer(1.25).timeout.connect(queue_redraw)


## A line of text inside a request (an error, or the note that the server sent no Jev details)
class Note:
	extends Control
	var text := ""
	var color := Css.DIM

	static func make(t: String, c: Color) -> Note:
		var n := Note.new()
		n.text = t
		n.color = c
		return n

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			custom_minimum_size.y = 12.0 + Css.wrap(Css.vt(), 18, text, size.x).size() * 20.0
			queue_redraw()

	func _draw() -> void:
		var y := 6.0
		for l in Css.wrap(Css.vt(), 18, text, size.x):
			Css.text(self, Css.vt(), 18, 0, y, l, color, 20)
			y += 20.0
