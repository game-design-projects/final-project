## The game's screen: the web page (crawler/public/index.html + style.css) and every part of game.js that draws or
## listens. It makes the game node (src/game/game.gd) and the sound (src/audio/), hands them to each other, lays out
## the screen like the page, turns keys and clicks into game.key(k), runs the frame loop (the view, danger, the
## heartbeat, the shader), answers the rules' fx events with shake, hit-stop, flashes and music dips, and implements
## every `ui.*` hook game.gd calls. Before the first key or click it shows the title card.
## Flags: `nofx` (no shader), `genre-halls` (open the Genre Halls instead), `debug`, `mock`, `floorN` (see Flags).
extends Control

const J = preload("res://src/core/js.gd")
const Flags = preload("res://src/core/flags.gd")
const Css = preload("res://src/ui/css.gd")
const Keys = preload("res://src/ui/keys.gd")
const Layout = preload("res://src/ui/layout.gd")
const DockModel = preload("res://src/ui/dock_model.gd")
const PartyModel = preload("res://src/ui/party_model.gd")
const AchUi = preload("res://src/ui/ach_ui.gd")
const Juice = preload("res://src/rules/juice.gd")
const Status = preload("res://src/rules/status.gd")
const Tutorial = preload("res://src/rules/tutorial.gd")
const Art = preload("res://src/view/art.gd")
const Postfx = preload("res://src/view/postfx.gd")
const Mix = preload("res://src/audio/mix.gd")
const Ambient = preload("res://src/audio/ambient.gd")
const Sfx = preload("res://src/audio/sfx.gd")
const Tts = preload("res://src/audio/tts.gd")
const Voice = preload("res://src/audio/voice.gd")
const Game = preload("res://src/game/game.gd")

const TopBar = preload("res://src/ui/top_bar.gd")
const ViewCanvas = preload("res://src/ui/view_canvas.gd")
const MapBox = preload("res://src/ui/map_box.gd")
const PartyPanel = preload("res://src/ui/party_panel.gd")
const LogPanel = preload("res://src/ui/log_panel.gd")
const VowsPanel = preload("res://src/ui/vows_panel.gd")
const Dock = preload("res://src/ui/dock.gd")
const Modal = preload("res://src/ui/modal.gd")
const TipBox = preload("res://src/ui/tip_box.gd")
const Toasts = preload("res://src/ui/toasts.gd")
const AchScreen = preload("res://src/ui/ach_screen.gd")
const JevPanel = preload("res://src/ui/jev_panel.gd")
const TooltipBox = preload("res://src/ui/tooltip.gd")
const Widget = preload("res://src/ui/widget.gd")

const GENRE_HALLS := "res://src/genre/genre_halls.tscn"
## Tools and tests set this to keep the game's saved data (tips seen, achievements) out of the player's store
static var store_override = null
const TIPS_TICK_MS := 250.0

# ---------------------------------------------------------------- the game and its sound
var game
var store
var music
var sfx
var narrator
var voice
var mixer = null # made with the audio on the first key press
var heart = null
var tips
var ach
var post = null
var shake = Juice.Shake.new()
var hitstop = Juice.HitStop.new()
var reduced_motion := false
var started := false
var debug := false

# ---------------------------------------------------------------- the screen
var L := {}
var bar: TopBar
var vp: SubViewport
var view: ViewCanvas
var view_box: ViewBox
var picture: TextureRect
var map_box: MapBox
var party: PartyPanel
var log_panel: LogPanel
var vows: VowsPanel
var dock: Dock
var modal: Modal
var tip_box: TipBox
var toasts: Toasts
var ach_screen: AchScreen
var jev: JevPanel
var tooltip: TooltipBox

var jev_open := false
var map_hidden := false
## What the tip on screen lights up: the keys' buttons and whole panels (#map, #party, #log, #party .dying)
var focus := {"keys": {}, "ids": {}}
var danger := 0.0
var last_frame := 0.0
var last_accent = null
var _last_tips_tick := 0.0
var _pace = null
## Space held down where holding means "speak": {plan, listening}
var space_down = null


## The view's frame: the 2px border, a click on it starts the game
class ViewBox:
	extends "res://src/ui/widget.gd"

	func _init() -> void:
		super()
		solid = true

	func paint() -> void:
		Css.frame(self, Rect2(Vector2.ZERO, size), Css.INK, 2.0)
		add_hit(Rect2(Vector2.ZERO, size), {"id": "view", "click": not ui.started if ui != null else true})

	func _pressed(_h: Dictionary) -> void:
		if ui != null:
			ui.start()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if Flags.test("genre-halls") and ResourceLoader.exists(GENRE_HALLS):
		print("genre halls (flag)")
		get_tree().change_scene_to_file.call_deferred(GENRE_HALLS)
		return
	store = store_override if store_override != null else get_node_or_null("/root/Store")
	if store == null:
		store = preload("res://src/core/store.gd").Memory.new()
	reduced_motion = _prefers_reduced_motion()
	Css.reduced_motion = reduced_motion
	_build_screen()
	_make_game()
	get_viewport().size_changed.connect(relayout)
	relayout()
	render()
	last_frame = J.now_ms()
	print_verbose("ui ready: debug %s, postfx %s%s" % ["on" if debug else "off", "on" if post != null else "off (plain view)", ", reduced motion" if reduced_motion else ""])


## Leaving (a new scene, quitting): the sound stops first, so no player is freed mid-stream
func _exit_tree() -> void:
	for n in [music, sfx, narrator]:
		if n != null and is_instance_valid(n):
			_stop_players(n)
	if narrator != null and is_instance_valid(narrator):
		narrator.hush()


static func _stop_players(n: Node) -> void:
	for c in n.get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
		_stop_players(c)


static func _prefers_reduced_motion() -> bool:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var r = JavaScriptBridge.eval("!!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches)", true)
		return r == true
	return false


func _build_screen() -> void:
	vp = SubViewport.new()
	vp.name = "View"
	vp.size = Vector2i(448, 288)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	view = ViewCanvas.new()
	view.ui = self
	vp.add_child(view)

	bar = _widget(TopBar.new(), "TopBar")
	view_box = _widget(ViewBox.new(), "ViewBox")
	picture = TextureRect.new()
	picture.name = "Picture"
	picture.texture = vp.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_box.add_child(picture)
	post = Postfx.PostFx.create({"reducedMotion": reduced_motion})
	if post != null:
		post.attach(picture)
	toasts = _widget(Toasts.new(), "Toasts", view_box)
	toasts.clip_contents = true # .ach-toasts { overflow: hidden }: a toast leaving upward is cut at the view's edge
	modal = _widget(Modal.new(), "Modal", view_box)
	modal.visible = false
	tip_box = _widget(TipBox.new(), "Tip", view_box)
	map_box = _widget(MapBox.new(), "MapBox")
	party = _widget(PartyPanel.new(), "Party")
	log_panel = LogPanel.new()
	log_panel.name = "Log"
	log_panel.ui = self
	add_child(log_panel)
	vows = _widget(VowsPanel.new(), "Vows")
	dock = _widget(Dock.new(), "Dock")
	dock.line_edit.text_submitted.connect(func(_t): _submit())
	ach_screen = _widget(AchScreen.new(), "Achievements")
	jev = _widget(JevPanel.new(), "Jev")
	jev.visible = false
	tooltip = TooltipBox.new()
	tooltip.name = "Tooltip"
	add_child(tooltip)


func _widget(w: Control, n: String, parent: Node = null) -> Control:
	w.name = n
	w.set("ui", self)
	(parent if parent != null else self).add_child(w)
	return w


## The game node and everything handed to it before start(): music, sfx, narrator, voice, tips, ach
func _make_game() -> void:
	game = Game.new()
	game.name = "Game"
	game.store = store
	music = Ambient.Ambient.new()
	music.name = "Music"
	sfx = Sfx.Sfx.new()
	sfx.name = "Sfx"
	narrator = Tts.Narrator.new({"store": store, "onDuck": func(on: bool):
		music.duck(on)
		sfx.duck(on)})
	narrator.name = "Narrator"
	voice = Voice.Listener.new({
		"onText": _heard_so_far,
		"onError": func(err): game.on_voice_error(err),
		"onStatus": func(text: String):
			if game.G != null:
				game.say(text, "dim")
				game.render(),
	})
	voice.name = "Voice"
	if store.get_item("donjon.usedVoice") == "1":
		voice.warm.call_deferred() # the desktop recognizer takes seconds to load: start now for someone who talks
	for n in [music, sfx, narrator, voice]:
		add_child(n)
	tips = Tutorial.create_tutorial({
		"store": store,
		"context": func(): return game.tips_context(),
		"show": _show_tip,
		"hide": _hide_tip,
		"nudge": func(_id): tip_box.nudge(),
		"log": func(msg: String): print_verbose("[tips] " + msg),
	})
	ach = AchUi.new({
		"store": store,
		"toasts": toasts,
		"screen": ach_screen,
		"accent": func(): return _accent_css(),
		"jingle": func(): sfx.play("achieve"),
		"onUnlock": func(a): game.on_achievement_unlocked(a),
		"onToggle": func(_open): render_bar(),
	})
	game.ui = self
	game.music = music
	game.sfx = sfx
	game.narrator = narrator
	game.voice = voice
	game.tips = tips
	game.ach = ach
	add_child(game)
	debug = game.DEBUG
	_subscribe(game.fx)
	jev.show_tabs(debug)
	if debug:
		jev_open = store.get_item("hallsOfJev.jev") != "0"
		jev.set_tab("requests" if store.get_item("donjon.jevTab") == "requests" else "mind")
		jev.visible = jev_open
		_install_halls()


# ---------------------------------------------------------------- presentation: the rules' fx events
# The rules announce combat moments and moves as events (juice.gd FX_EVENTS); the shake, the hit-stop, the shader
# and the mixing desk answer them here, and never reach back into the rules.

func _subscribe(fx) -> void:
	for name in Juice.FX_EVENTS:
		fx.on(name, func(p):
			var k: float = Juice.trauma_for(name, p)
			if k > 0.0 and not reduced_motion:
				shake.add(k, p.get("at")))
	fx.on("party:hurt", func(p):
		if post != null:
			post.hurt(0.45 + 0.55 * minf(1.0, float(p.dmg) / maxf(1.0, float(p.maxHp))))
		if mixer != null:
			mixer.impact(Mix.IMPACT.hurt, mixer.audio_at(J.nz(p.get("at"), J.now_ms()))))
	fx.on("party:down", func(p):
		hitstop.freeze(J.nz(p.get("at"), J.now_ms()), Juice.HITSTOP_MS.down)
		if post != null:
			post.hurt(1.0))
	fx.on("enemy:hit", func(p):
		if not J.truthy(p.get("crit")):
			return
		hitstop.freeze(J.nz(p.get("at"), J.now_ms()), Juice.HITSTOP_MS.crit)
		if post != null:
			post.flash("#ffe03a", 0.2)
		if mixer != null:
			mixer.impact(Mix.IMPACT.crit, mixer.audio_at(J.nz(p.get("at"), J.now_ms()))))
	fx.on("enemy:kill", func(p):
		var boss := J.truthy(p.get("boss"))
		hitstop.freeze(J.nz(p.get("at"), J.now_ms()), Juice.HITSTOP_MS.bossKill if boss else Juice.HITSTOP_MS.kill)
		if post != null:
			post.flash(Art.BOSS_COLOR if boss else "#ffffff", 0.45 if boss else 0.14)
		if mixer != null:
			mixer.impact(Mix.IMPACT.bossKill if boss else Mix.IMPACT.kill, mixer.audio_at(J.nz(p.get("at"), J.now_ms()))))
	fx.on("combat:start", func(p):
		if post != null:
			post.flash(Art.BOSS_COLOR if J.truthy(p.get("boss")) else (_accent_css() if _accent_css() != null else "#ffffff"), 0.28))
	fx.on("view:step", func(p): begin_transition("step", int(p.dir)))
	fx.on("view:turn", func(p): begin_transition("turn", int(p.dir)))
	fx.on("view:bump", func(_p): begin_transition("bump", 1))


## Moving and turning ease from the old view to the new one: the frame on screen is kept before the move
func begin_transition(kind: String, dir: int) -> void:
	if reduced_motion or DisplayServer.get_name() == "headless":
		return
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	view.begin_transition(kind, dir, ImageTexture.create_from_image(img))


# ---------------------------------------------------------------- audio

## startAudio(): the mixing desk and the heartbeat, made on the first key press (browsers keep audio locked until
## then). The music and the effects share its buses, so the heartbeat lands on the music's beat.
func start_audio() -> void:
	if mixer != null:
		return
	mixer = Mix.Mixer.new()
	mixer.name = "Mixer"
	add_child(mixer)
	sfx.init(mixer)
	music.attach(mixer)
	heart = Mix.BeatScheduler.new({
		"clock": func(): return music.beat_clock() if music.on else null,
		"onBeat": _heartbeat,
	})
	print_verbose("audio started")


func _heartbeat(at: float, k: int) -> void:
	var G = game.G
	var every = Mix.heart_every(mixer.danger) if G != null and G.mode != "over" else null
	if every != _pace:
		print_verbose("heartbeat: %s (danger %.2f)" % [("every %sbeat" % ("" if every == 1 else "other ")) if every != null else "off", mixer.danger])
	_pace = every
	if every == null or k % int(every) != 0:
		return
	sfx.play("heartbeat", {"delay": maxf(0.0, at - Mix.clock() - 0.01), "level": 0.45 + 0.55 * mixer.danger})
	if post != null:
		post.beat(perf_at(at))


## An audio-clock time as a J.now_ms() time
func perf_at(at: float) -> float:
	return J.now_ms() + (at - Mix.clock()) * 1000.0


## audioAt(ms): a J.now_ms() time (when a die lands) on the audio clock
func audio_at(ms: float):
	return mixer.audio_at(ms) if mixer != null else null


# ---------------------------------------------------------------- the frame loop

## frame(): the view repaints, the danger eases toward where the party is, the heartbeat and the shader follow
func _process(_delta: float) -> void:
	if game == null:
		return # on the way to the Genre Halls
	var now := J.now_ms()
	view.queue_redraw()
	var G = game.G if game != null else null
	if G != null:
		var target: float = 0.5 if G.mode == "over" else Juice.danger_of(G.party)
		danger = Juice.approach(danger, target, now - last_frame, 300.0)
		if mixer != null:
			mixer.set_danger(target)
		if heart != null:
			heart.tick()
		if post != null:
			post.set_danger(danger)
	var accent = _accent_css()
	if accent == null:
		accent = "#e8e8e8"
	if accent != last_accent:
		last_accent = accent
		if post != null:
			post.set_accent(accent)
	last_frame = now
	if post != null:
		post.render(now)
	if now - _last_tips_tick >= TIPS_TICK_MS:
		_last_tips_tick = now
		tips.tick()
	tooltip.tick()
	for w in [dock, modal, tip_box, toasts, ach_screen, party, vows]:
		if w.animating():
			w.queue_redraw()
	if not focus.keys.is_empty() or not focus.ids.is_empty():
		for w in [dock, bar, party, map_box]:
			w.queue_redraw()
		queue_redraw()


# ---------------------------------------------------------------- layout

func relayout() -> void:
	hide_tooltip()
	Css.set_scale(get_viewport().get_final_transform().get_scale().x)
	L = Layout.compute(size, {"jev": debug and jev_open, "wide": jev.tab == "requests", "dock_h": dock.natural_h})
	bar.position = L.bar.position
	bar.size = Vector2(L.bar.size.x, Layout.BAR_H)
	view_box.position = L.view.position
	view_box.size = L.view.size
	picture.position = Vector2(Layout.VIEW_BORDER, Layout.VIEW_BORDER)
	picture.size = L.picture.size
	for o in [toasts, modal, tip_box]:
		o.position = Vector2.ZERO
		o.size = L.view.size
	map_box.position = L.map.position
	map_box.size = Vector2(L.map.size.x + Layout.LEGEND_GAP + L.legend.size.x, L.map.size.y)
	dock.position = L.dock.position
	dock.size = L.dock.size
	ach_screen.position = L.ach.position
	ach_screen.size = L.ach.size
	jev.visible = debug and jev_open
	if L.jev != null:
		jev.position = L.jev.position
		jev.size = L.jev.size
		jev.max_h = L.jev.size.y
		jev.fit()
	_layout_side()
	queue_redraw()


## .side: the party at the top (its own height), the vows at the bottom, the log takes what's left and scrolls
func _layout_side() -> void:
	var side: Rect2 = L.side
	party.position = side.position
	party.size.x = side.size.x
	var party_h: float = party.measure()
	party.size = Vector2(side.size.x, party_h)
	vows.size.x = side.size.x
	vows.natural_h = vows.measure(side.size.x)
	var vows_h: float = vows.natural_h
	vows.visible = vows_h > 0.0
	vows.position = Vector2(side.position.x, side.end.y - vows_h)
	vows.size = Vector2(side.size.x, vows_h)
	var log_top := side.position.y + party_h + Layout.COL_INNER_GAP
	var log_bottom := (vows.position.y - Layout.COL_INNER_GAP) if vows_h > 0.0 else side.end.y
	log_panel.position = Vector2(side.position.x, log_top)
	log_panel.size = Vector2(side.size.x, maxf(0.0, log_bottom - log_top))
	log_panel.visible = log_panel.size.y > 0.0


func _draw() -> void:
	if L.is_empty():
		return
	# the CRT: black, framed in ink
	draw_rect(L.crt, Css.BG)
	Css.frame(self, L.crt, Css.INK, 2.0)
	if focus.ids.has("#log") and log_panel.visible:
		_focus_outline(self, Rect2(log_panel.position, log_panel.size))


## The light on what a tip talks about: an outline 2px out, pulsing white with a glow (tip-focus)
func paint_focus(w: Control) -> void:
	if focus.keys.is_empty() and focus.ids.is_empty():
		return
	for h in w.hits:
		var k = h.get("focus_key")
		var p = h.get("panel")
		if (k != null and focus.keys.has(k)) or (p != null and focus.ids.has(p)):
			_focus_outline(w, h.rect)


func _focus_outline(ci: CanvasItem, r: Rect2) -> void:
	var accent := _accent_color(tips_accent())
	var p := Css.pulse(J.now_ms(), 1200.0)
	Css.glow(ci, r.grow(4.0), Css.alpha(accent, p), 16.0)
	Css.frame(ci, r.grow(4.0).grow(2.0 * p), Css.alpha(Color.BLACK, p), 2.0 * p)
	Css.frame(ci, r.grow(4.0), accent.lerp(Color.WHITE, p), 2.0)


func tips_accent():
	return _accent_css()


# ---------------------------------------------------------------- render: what game.gd calls

func _accent_css():
	var G = game.G if game != null else null
	if G == null or G.get("map") == null or G.map.get("palette") == null:
		return null
	return G.map.palette.accent


func _accent_color(css = null) -> Color:
	var c = css if css != null else _accent_css()
	return Css.css(c) if c != null else Css.ACCENT


## render(): everything but the view (which repaints every frame)
func render() -> void:
	var G = game.G if game != null else null
	if G == null:
		bar.model = null
		bar.queue_redraw()
		dock.set_model(DockModel.title(), Css.ACCENT)
		_dock_changed()
		map_box.refresh()
		return
	map_box.fighting = G.combat != null
	map_box.hidden_map = map_hidden
	map_box.refresh()
	render_bar()
	render_log()
	render_party()
	render_vows()
	render_dock()
	render_modal()


func render_log() -> void:
	log_panel.show_log(game.G.log)


func render_party() -> void:
	var rows := PartyModel.rows(game.G, {"color_of": Game.color_of, "boon_title": Game.boon_title})
	party.set_rows(rows, _accent_color())
	_layout_side()


func render_vows() -> void:
	var before: float = vows.natural_h
	vows.set_vows(game.G.vows)
	if vows.natural_h != before or vows.visible != (vows.natural_h > 0.0):
		_layout_side()


## renderVows' signature reset (a recruit hands vows to the new ally)
func reset_vows() -> void:
	vows.reset()


func render_modal() -> void:
	var G = game.G
	modal.set_prompt(G.prompt if G != null else null, _accent_color())


## The status line on top: where you are, the facing (or the fight), gold, boons, the switches
func render_bar() -> void:
	var G = game.G
	if G == null:
		return
	var pal: Dictionary = G.map.palette
	var n: int = G.boons.size()
	var floor_word := Status.floor_name(G.floor)
	var m := {
		"loc": {"floor": floor_word, "accent": pal.accent, "name": str(pal.name), "tip": "%s: %s" % [floor_word, pal.name]},
		"gold": {"icon": "coin", "icon_color": "#ffd27a", "text": "%s GOLD" % J.num(G.gold), "color": "#ffd27a", "tip": "%s GOLD" % J.num(G.gold)},
		"boons": {"icon": "star", "icon_color": "#ffd27a" if n > 0 else "#5a5a5a", "text": "%d BOON%s" % [n, "" if n == 1 else "S"], "color": "#8a8a8a", "tip": "ROLL OF FATE BOONS YOU HAVE WON. PRESS B TO LIST THEM"},
	}
	if G.combat != null:
		m.dir = {"icon": "flame", "icon_color": "#ff5a4a", "text": "FIGHT", "color": "#ff5a4a", "tip": "IN A FIGHT"}
	else:
		var word := Status.facing_word(G.dir)
		m.dir = {"icon": ["up", "right", "down", "left"][G.dir], "icon_color": "#8a8a8a", "text": word, "color": "#8a8a8a", "tip": "FACING %s (UP ON THE MAP IS NORTH)" % word}
	m.sys = sys_toggles()
	bar.model = m
	bar.queue_redraw()


## The rarely-touched switches, in keyboard order H J K L O P: a keycap and a pixel icon each (slashed when off)
func sys_toggles() -> Array:
	var sw := func(k: String, icon: String, name: String, on: bool, what: String) -> Dictionary:
		return {"key": k, "icon": icon, "icon_color": "#e8e8e8" if on else "#5a5a5a", "on": on, "title": "%s %s · %s · PRESS %s" % [name, "ON" if on else "OFF", what, k.to_upper()]}
	var out := [sw.call("h", "question", "TIPS", tips.on(), "ONE SHORT HINT AT A TIME, THE FIRST TIME SOMETHING MATTERS")]
	if debug:
		out.append(sw.call("j", "eye", "JEV MIND PANEL", jev_open, "WHAT JEV DECIDED, AND EVERY API REQUEST"))
	out.append(ach_cap())
	if narrator.supported:
		var which: String = (" IN " + narrator.label) if narrator.order.size() > 1 else ""
		out.append(sw.call("l", "bubble", "VOICES", narrator.on, "MONSTERS READ THEIR LINES ALOUD%s. ON BY ITSELF ONCE YOU SPEAK (HOLD SPACE)" % which))
	out.append(sw.call("o", "speaker", "SOUND", sfx.on, "HITS, SPELLS, DICE AND MONSTER VOICES"))
	out.append(sw.call("p", "note", "MUSIC", music.on, "THE DUNGEON AND BATTLE MUSIC"))
	return out


## K: the achievements, a trophy and how many you've earned (lit while the list is open)
func ach_cap() -> Dictionary:
	var c: Dictionary = ach.count()
	return {"key": "k", "trophy": true, "icon_color": "#ffd27a" if c.earned > 0 else "#5a5a5a", "text": "%d/%d" % [c.earned, c.total], "open": ach.is_open(), "on": true, "title": "ACHIEVEMENTS: %d OF %d EARNED. PRESS K" % [c.earned, c.total]}


func render_dock() -> void:
	var G = game.G
	if G == null:
		return
	var here: Array = game.present()
	var model := DockModel.build(G, {
		"voice": voice.supported,
		"present": here,
		"target": game.target_enemy() if G.combat != null else null,
		"color_of": Game.color_of,
		"allies": game.allies().size(),
	})
	dock.set_model(model, _accent_color())
	_dock_changed()


func _dock_changed() -> void:
	if absf(dock.natural_h - L.get("dock", Rect2()).size.y) > 0.5:
		relayout()


func nudge_dock() -> void:
	dock.nudge()


func nudge_modal() -> void:
	modal.nudge()


func toggle_map() -> void:
	map_hidden = not map_hidden
	map_box.hidden_map = map_hidden
	map_box.refresh()


## A new floor cell came into view: the automap redraws
func map_changed() -> void:
	map_box.canvas.queue_redraw()


# ---------------------------------------------------------------- the talk box

func open_input(label: String, numeric: bool) -> void:
	dock.set_input(true, label, numeric, voice.supported)
	dock.line_edit.text = ""
	dock.line_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER if numeric else LineEdit.KEYBOARD_TYPE_DEFAULT
	_dock_changed()
	focus_input.call_deferred()


func close_input() -> void:
	if dock.line_edit.has_focus():
		dock.line_edit.release_focus()
	dock.set_input(false)
	_dock_changed()


func input_text() -> String:
	return dock.line_edit.text


func set_input_text(s: String) -> void:
	dock.line_edit.text = s
	dock.line_edit.caret_column = s.length()


func focus_input() -> void:
	if dock.line_edit.visible:
		dock.line_edit.grab_focus()


func _submit() -> void:
	if game.G != null and game.G.input != null:
		game.submit_input()


func _heard_so_far(text: String) -> void:
	var G = game.G
	if G != null and G.input != null and J.truthy(G.input.get("listening")):
		set_input_text(text)



# ---------------------------------------------------------------- the Jev panel (debug only)

func show_jev(x: Dictionary) -> void:
	if not debug:
		return
	jev.show_mind(JevPanel.mind_blocks(x, Game.color_of))


func render_requests() -> void:
	if not debug:
		return
	jev.show_requests(game.api_log)


func jev_tab(t: String) -> void:
	jev.set_tab(t)
	store.set_item("donjon.jevTab", t)
	relayout()
	render_requests()


func toggle_jev() -> void:
	jev_open = not jev_open
	store.set_item("hallsOfJev.jev", "1" if jev_open else "0")
	relayout()


# ---------------------------------------------------------------- tips and tooltips

func _show_tip(id: String, h: Dictionary) -> void:
	tip_box.show_hint(id, h, _accent_color())
	focus = {"keys": {}, "ids": {}}
	var key_re := RegEx.create_from_string("^\\[data-key=\"(.+)\"\\]$")
	for sel in Tutorial.focus_of(id):
		var m := key_re.search(sel)
		if m != null:
			focus.keys[m.get_string(1)] = true
		else:
			focus.ids[sel] = true
	sfx.play("tick")


func _hide_tip(_id) -> void:
	tip_box.hide_hint()
	focus = {"keys": {}, "ids": {}}
	for w in [dock, bar, party, map_box]:
		w.queue_redraw()
	queue_redraw()


func dismiss_tip() -> void:
	tips.dismiss({"force": true})


func show_tooltip(owner: Control, r: Rect2, text: String) -> void:
	tooltip.hover(owner, Rect2(owner.get_global_transform() * r.position, r.size), text, _accent_color())


func leave_tooltip(owner: Control) -> void:
	tooltip.leave(owner)


func hide_tooltip() -> void:
	tooltip.hide_now()


# ---------------------------------------------------------------- input

## A click on a keycap (the dock, the top bar's switches, the question's answers, the list's close buttons)
func press_key(k: String) -> void:
	hide_tooltip()
	if not started:
		if k == "g":
			open_genre_halls()
		return
	if game.G == null:
		return
	game.key(k)


## Hovering a menu option highlights it (and the member it's about)
func hover_option(i: int) -> void:
	var G = game.G
	if G == null or G.menu == null or int(G.menu.sel) == i:
		return
	G.menu.sel = i
	render_party()
	render_dock()


func start() -> void:
	if started:
		return
	started = true
	print("start")
	game.start()
	debug = game.DEBUG
	relayout()


func open_genre_halls() -> void:
	if not ResourceLoader.exists(GENRE_HALLS):
		push_warning("no genre halls scene at %s" % GENRE_HALLS)
		return
	print("genre halls")
	get_tree().change_scene_to_file.call_deferred(GENRE_HALLS)


func _input(ev: InputEvent) -> void:
	if game == null:
		return
	if ev is InputEventKey:
		if ev.pressed:
			_key_down(ev)
		else:
			_key_up(ev)


func _key_down(ev: InputEventKey) -> void:
	if Keys.is_shortcut(ev):
		return
	hide_tooltip()
	if Keys.is_space(ev) and started:
		# Held Space repeats: swallow the repeats while it's a talk hold
		if ev.echo:
			if space_down != null:
				get_viewport().set_input_as_handled()
			return
		var plan = space_plan()
		if plan != null:
			get_viewport().set_input_as_handled()
			space_start(plan)
			return
	if dock.line_edit.has_focus():
		if ev.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			game.cancel_input() # undefined = cancelled; an empty submit is null
		return
	get_viewport().set_input_as_handled()
	if not started:
		if Keys.js_key(ev) == "g":
			open_genre_halls()
			return
		start()
		return
	var k := Keys.js_key(ev)
	if k == "":
		return
	var mapped: String = Game.KEYMAP.get(k, k)
	game.key(mapped)
	if not ev.echo:
		# the tips see the key after the game has: it clears the hint, unless the game said it ignored it
		tips.keyed.call_deferred()


func _key_up(ev: InputEventKey) -> void:
	if not Keys.is_space(ev) or space_down == null:
		return
	var sd: Dictionary = space_down
	space_down = null
	if sd.listening:
		stop_listening("space")
		return
	# Let go before it counted as a hold: Space was just a tap
	if game.G == null or game.G.input == null:
		game.key(" ")


## What holding Space would do right now (voice.gd space_hold)
func space_plan():
	var G = game.G
	if G == null or not voice.supported:
		return null
	var waiting: bool = G.prompt != null or G.menu != null or G.waitKey != null or G.roll != null or J.truthy(G.busy) or G.mode == "over" or ach.is_open()
	return Voice.space_hold({
		"inputOpen": G.input != null,
		"inputEmpty": dock.line_edit.text == "",
		"numeric": G.input != null and J.truthy(G.input.get("numeric")),
		"waiting": waiting,
		"combat": G.combat != null,
		"allies": game.allies().size(),
	})


## Space went down where holding it means "speak": wait to see if it's a hold, then open the box and listen
func space_start(plan: String) -> void:
	var sd := {"plan": plan, "listening": false}
	space_down = sd
	await get_tree().create_timer(Voice.HOLD_MS / 1000.0).timeout
	if not is_same(space_down, sd):
		return
	var G = game.G
	if plan == "talk":
		game.key("r" if G.combat != null and G.combat.get("guide") == "recruit" else "t")
	if plan == "ally":
		game.key("e")
	# The box may open a moment later (or after you pick an ally); listen once it's there, while Space is held
	var tries := J.now_ms()
	while is_same(space_down, sd):
		G = game.G
		if G != null and G.input != null and not J.truthy(G.input.get("numeric")):
			sd.listening = true
			listen("space")
			return
		if J.now_ms() - tries >= 1500.0 or (G != null and G.menu != null):
			return
		await get_tree().create_timer(0.04).timeout


func listen(how: String) -> void:
	var G = game.G
	var inp = G.input if G != null else null
	if inp == null or J.truthy(inp.get("numeric")) or J.truthy(inp.get("listening")) or not voice.supported:
		return
	var not_yet: String = voice.prepare()
	if not_yet != "":
		game.say(not_yet, "dim")
		focus_input()
		game.render()
		return
	inp.listening = how
	set_input_text("")
	dock.listening = true
	narrator.hush() # the microphone mustn't hear the monsters talking
	game.render()
	var text = await voice.start()
	dock.listening = false
	if game.G == null or not is_same(game.G.input, inp):
		return # closed while listening
	inp.listening = null
	if text is String and text != "":
		if narrator.supported and not narrator.on and store.get_item("donjon.tts") == null:
			narrator.heard_player()
			game.say("YOU SPOKE, SO THE MONSTERS WILL ANSWER OUT LOUD. L TURNS VOICES OFF.", "dim")
		else:
			narrator.heard_player()
		set_input_text(text)
		game.submit_input()
		return
	if text is String and text == "":
		game.say("DIDN'T CATCH THAT. HOLD AND SPEAK AGAIN, OR TYPE IT.", "dim")
	focus_input()
	game.render()


func stop_listening(how: String) -> void:
	var G = game.G
	if G != null and G.input != null and G.input.get("listening") == how:
		voice.stop()


## The HOLD TO SPEAK button: press and hold to speak, let go to say it
func mic_down() -> void:
	listen("button")


func mic_up() -> void:
	stop_listening("button")


# ---------------------------------------------------------------- the `halls` debug hooks (web console)

var _halls_callbacks := []


## In a debug run on the web, window.halls has the game's debug hooks, as the JS game had them in the console
func _install_halls() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	var win = JavaScriptBridge.get_interface("window")
	if win == null:
		return
	var halls = JavaScriptBridge.create_object("Object")
	var hooks := {
		"hostile": func(a): game.debug_hostile(str(a[0])),
		"lesson": func(_a): game.debug_lesson(),
		"meet": func(a): game.debug_meet(a.map(func(s): return str(s))),
		"ally": func(a): game.debug_ally(str(a[0]), a[1] if a.size() > 1 else null),
		"boss": func(_a): game.debug_boss(),
		"floor": func(a): game.debug_floor(int(a[0])),
		"xp": func(a): game.debug_xp(int(a[0])),
		"roll": func(a): game.debug_roll(a.size() > 0 and a[0] == true, str(a[1]) if a.size() > 1 else "floor"),
		"shiny": func(a): game.debug_shiny(str(a[0]) if a.size() > 0 else "slime"),
		"descend": func(_a): game.debug_descend(),
		"ask": func(a): game.debug_ask(a[0] if a.size() > 0 else null),
		"state": func(_a): return JSON.stringify(game.debug_state()),
	}
	for k in hooks:
		var cb = JavaScriptBridge.create_callback(hooks[k])
		_halls_callbacks.append(cb)
		halls[k] = cb
	win.halls = halls
	print("debug: window.halls has the game's debug hooks")
