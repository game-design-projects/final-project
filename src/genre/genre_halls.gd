## DONJON: Genre Halls. Exploration is DONJON's wireframe maze; encounters switch into an Undertale-style box where each
## faction attacks in its own genre (chess, shadow, rhythm, goo rain), all with one rule: lit squares hurt.
## FIGHT / ACT / SPARE / FLEE. The monster's mind answers Jev-shaped questions (choice and yes/no with
## probabilities, or a fixed pressure score); here a local stand-in answers them. The rules live in genre_rules.gd.
## Port of crawler/public/genre-halls.js + genre-halls.html.
##
## Launch:  godot --path .   (the main menu starts it: src/menu/main_menu.tscn; `-- meet=slime` goes straight to a fight)
## `meet=<species>` (slime, bandit, snake, rock, dragon) jumps straight into that faction's fight, like the
## console hook genreHalls.meet("rock"). Keys: arrows / WASD, Enter / Space / Z, Esc / X, 1-9 on the menus.
## Esc while walking or in a fight's menu opens the pause menu (save, load, settings, main menu); Esc on the route screen
## or the title card goes to the main menu. Opened by the menu it starts a run or loads a save (src/menu/session.gd).
##
## The screen is one framed CRT that fills the window: a thin top line (where, route), the 448x288 view (Canvas2D, drawn
## in a SubViewport and scaled up to the free space) with the automap and the allies as small overlays, and a text box
## under it (HP bar, log, commands). Explanations live in tooltips: hover a command for what it does, an ally for its
## charm, the foe for what Jev reads in it. The game logic is clock-driven:
## `tick(t)` advances it to time `t` (ms), `_process` feeds it the real clock, tests feed it a fake one
## (`clock_override`) and call `on_key(key)` with the JS key names ("ArrowUp", "Enter", "Escape", "1", ...).
extends Control

const J = preload("res://src/core/js.gd")
const Flags = preload("res://src/core/flags.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")
const Render = preload("res://src/view/render.gd")
const Art = preload("res://src/view/art.gd")
const Postfx = preload("res://src/view/postfx.gd")
const Stage3D = preload("res://src/view/stage3d.gd")
const SfxModule = preload("res://src/audio/sfx.gd")
const Ambient = preload("res://src/audio/ambient.gd")
const Species = preload("res://src/rules/species.gd")
const Emotions = preload("res://src/rules/emotions.gd")
const Rules = preload("res://src/genre/genre_rules.gd")
const Settings = preload("res://src/menu/settings.gd")
const Saves = preload("res://src/menu/saves.gd")
const Session = preload("res://src/menu/session.gd")
const Menus = preload("res://src/menu/menus.gd")
const MenuPanel = preload("res://src/menu/menu_panel.gd")

const MAIN_SCENE := "res://src/ui/main.tscn" ## the original Donjon, reached with the `main` flag
const MENU_SCENE := "res://src/menu/main_menu.tscn"
const TITLE_HINT := "ESC: MENU" ## on the title card (only seen when this scene is opened without the menu)
const W := Rules.W
const H := Rules.H
const COLS := Rules.COLS
const ROWS := Rules.ROWS
const CELL := Rules.CELL
const BX := Rules.BX
const BY := Rules.BY
const BOSS_COLOR := Art.BOSS_COLOR

# The page's colors (genre-halls.html :root)
const C_BG := "#000000"
const C_FRAME := "#0d0d0f"
const C_INK := "#e8e8e8"
const C_DIM := "#8a8a8a"
const C_FAINT := "#2e2e33"
const C_WARN := "#ff5a4a"
const C_YOU := "#8fd3ff"
const C_MERCY := "#ffd27a"

const SPARE_TIP := "Acceptance is a roll at any odds. Gold marks a 50%+ chance, not a guarantee. A spared monster may join as a passive charm."

const SAY_H := 66 ## the log: 3 lines of 20px
const SLOT_H := 74 ## the commands (two rows of 34) or the talk box
const KEYS_H := 26 ## the key hints: 2 lines

const KEYMAP := {"w": "ArrowUp", "s": "ArrowDown", "a": "ArrowLeft", "d": "ArrowRight", " ": "Enter", "z": "Enter", "x": "Escape"}

# ---------------------------------------------------------------- state

var G := {
	"mode": "title",
	"map": null,
	"x": 1,
	"y": 1,
	"dir": 1,
	"seen": {}, # set of y * n + x
	"visited": {},
	"hp": 20,
	"maxHp": 20,
	"gold": 8,
	"foe": null,
	"menu": [],
	"sel": 0,
	"tally": {"spared": 0, "slain": 0, "fled": 0, "recruited": 0, "left": 0},
	"allies": [],
	"shake": 0.0,
}
var D = null # the dodge phase
var bar = null # the strike bar
var hurt_until := 0.0
var intro_until := 0.0
var pending_judgement = null
var last_mind := {"m": null, "answers": []}
var last_say := "" # the dock text as BBCode, for tests and tools

## Tests and tools set this (ms, >= 0) to drive the clock by hand and call `tick` themselves.
var clock_override := -1.0
## Tests can pin a negotiation or answer roll; normal play always rolls afresh.
var interaction_roll_override := -1.0
var slice_next: Dictionary = {}
var _timers: Array = []
var _last_map := 0.0

var sfx = null
## The music (src/audio/ambient.gd): the dungeon loop while walking, a battle loop in a fight, stings for wins and stairs.
## Null with `nosound`; tests may put a recorder here.
var music = null
var _music_started := false
var postfx = null
## Tests turn this off so Esc doesn't change the scene under the test runner
var navigate := true
var left_for := "" ## where the last scene change went ("menu"), for tests
var _pause: MenuPanel
var _applied_hash := 0

# UI nodes
var _view_vp: SubViewport
var stage: Stage3D ## the dungeon as a 3D set drawn as lines (null with the `flat` flag: the old 2D corridor)
var _view_canvas: DrawArea
var _view_rect: TextureRect
var _map_panel: PanelContainer
var _map_canvas: DrawArea
var _where: RichTextLabel
var _route: RichTextLabel
var _hp: RichTextLabel
var _hp_bar: HpBar
var _say: RichTextLabel
var _keys: RichTextLabel
var _menu_grid: GridContainer
var _talk: HBoxContainer
var _talk_in: LineEdit
var _chips: HBoxContainer ## the allies, one chip each, over the view's bottom-left
var _tip: PanelContainer ## the one tooltip: a command's help, an ally's charm, or the foe's mind
var _tip_body: VBoxContainer
var _tip_key := "" ## what the tooltip shows now ("" = hidden), so it is only rebuilt when that changes
var _tip_anchor := Rect2() ## where it sits: above this (a command), or by the mouse
var _tip_at_mouse := false
var _hover_item := -1 ## the command under the mouse
var _hover_foe := false ## the mouse is over the foe in the view
var _kbd_nav := false ## the last input was a key: the highlighted command shows its tooltip too
var _pad: GridContainer
var _pix: Font
var _term: Font
var _bold: Font


func now() -> float:
	return clock_override if clock_override >= 0.0 else J.now_ms()


## True when the run flags ask for the main game (`-- main`, `?main`): the Genre Halls is the startup scene, so this
## is how `-- main mock floor5` reaches the game with its own flags. Matches the whole word, not `--only=ui/main`.
static func wants_main() -> bool:
	return Flags.test("(^|[\\s?#&-])main($|[\\s&])")


func _ready() -> void:
	if wants_main() and ResourceLoader.exists(MAIN_SCENE):
		print("genre halls: main game (flag)")
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
		return
	print("genre halls: startup scene" if get_tree().current_scene == self else "genre halls: entered from the main game")
	_pix = Canvas2D.pixel_font("press start 2p")
	var term := FontVariation.new()
	term.base_font = Canvas2D.pixel_font("vt323")
	term.fallbacks = [_pix] # VT323 has no arrows
	_term = term
	var heavy := FontVariation.new()
	heavy.base_font = term
	heavy.variation_embolden = 0.5
	_bold = heavy
	_build_ui()
	sfx = _make_sfx()
	music = _make_music()
	if not OS.has_feature("web"):
		_sfx_init() # browsers keep audio locked until the first key press (on_key calls it again)
	_attach_postfx()
	render_party()
	say(sys("Press any key to start."))
	set_menu([], kbd("ANY KEY") + " START")
	hud()
	apply_settings()
	var req := Session.take()
	if req.get("kind", "") == "new":
		new_run()
	elif req.get("kind", "") == "load":
		if not import_state(req.state):
			new_run()
	if Flags.test("(^|[\\s?#&-])personality-slice($|[\\s&])"):
		var slice_seed := int(Flags.capture("seed=(\\d+)")) if Flags.capture("seed=(\\d+)") != "" else 7042
		start_personality_slice(slice_seed)
		return
	var species := Flags.capture("meet=(\\w+)")
	if species != "":
		meet(species)


func _process(_delta: float) -> void:
	if clock_override >= 0.0 or _view_canvas == null:
		return # a fake clock in tests, or on the way to the main game
	var t := now()
	apply_settings()
	tick(t)
	if postfx != null:
		postfx.render(t)
	_view_canvas.queue_redraw()
	if t - _last_map > 100.0:
		_last_map = t
		_map_canvas.queue_redraw()


# ---------------------------------------------------------------- audio and post effects

class NullSfx:
	extends RefCounted
	var on := false

	func init(_a = null, _b = null) -> void:
		pass

	func play(_name: String, _opts := {}) -> void:
		pass

	func shout(_line: String, _species: String, _opts := {}) -> void:
		pass


## The effects (src/audio/sfx.gd) live under this node; `nosound` plays silent (tests, tools)
func _make_sfx():
	if Flags.test("nosound|nosfx"):
		return NullSfx.new()
	var s = SfxModule.Sfx.new(Settings.sfx_gain(Settings.current()))
	add_child(s)
	return s


func _sfx_init() -> void:
	if sfx != null and sfx.has_method("init"):
		sfx.init()
	_music_init()


## The music (src/audio/ambient.gd) lives under this node; `nosound` has none
func _make_music():
	if Flags.test("nosound|nomusic") or DisplayServer.get_name() == "headless":
		return null
	var m = Ambient.Ambient.new()
	m.name = "Music"
	add_child(m)
	m.attach()
	return m


## Starts the music once (on the web that waits for the first key press, since browsers keep audio locked until then)
func _music_init() -> void:
	if music == null or _music_started:
		return
	_music_started = true
	var r = await music.start()
	if r is Dictionary and r.has("error"):
		push_warning("music: %s" % r.error)
		_music_started = false


func _music_mood(mood: String) -> void:
	if music != null:
		music.set_mood(mood)


func _music_sting(name: String) -> void:
	if music != null:
		music.sting(name)


func _exit_tree() -> void:
	if music is Node and is_instance_valid(music):
		music.stop() # the sound stops first, so no player is freed mid-stream
		for c in music.get_children():
			if c is AudioStreamPlayer:
				c.stop()


func _sfx_play(name: String, opts := {}) -> void:
	if sfx != null:
		sfx.play(name, opts)


## The view's CRT pass (glow, scanlines, hurt flash); the `nofx` flag shows the plain view
func _attach_postfx() -> void:
	if DisplayServer.get_name() == "headless":
		return # nothing is rendered, and the shader compiler has nothing to build for
	if not Settings.get_value("crt"):
		return
	postfx = Postfx.PostFx.create({"reducedMotion": Settings.get_value("calm")})
	if postfx != null:
		postfx.attach(_view_rect)
		if G.map != null:
			postfx.set_accent(G.map.palette.accent)
		hud()


## Pick up changes made on the settings pages: the glow, calm hits and the sound volume (the window is applied by
## the settings module itself, the shake is read when it happens)
func apply_settings() -> void:
	var s := Settings.current()
	if s.hash() == _applied_hash:
		return
	_applied_hash = s.hash()
	if s.crt and postfx == null:
		_attach_postfx()
	elif not s.crt and postfx != null:
		postfx.detach()
		postfx = null
	if postfx != null:
		postfx.reduced_motion = s.calm
	if sfx != null and sfx.get("volume") != null:
		var g := Settings.sfx_gain(s)
		sfx.volume = g
		if sfx.get("out_gain") != null:
			sfx.out_gain.set_value_at_time(g, sfx.clock.call())


func _shake(ms: float, at := -1.0) -> void:
	if Settings.get_value("shake"):
		G.shake = (now() if at < 0.0 else at) + ms



# ---------------------------------------------------------------- BBCode helpers (the page's spans)

static func sys(s: String) -> String:
	return "[color=%s]%s[/color]" % [C_DIM, s]


static func who(s: String) -> String:
	return "[color=%s]%s[/color]" % [C_MERCY, s]


static func bold(s: String) -> String:
	return "[b]%s[/b]" % s


static func kbd(s: String) -> String:
	return "[bgcolor=%s][color=%s] %s [/color][/bgcolor]" % [C_FAINT, C_INK, s]


## String(x) with the BBCode brackets defused (the JS esc())
static func esc(s) -> String:
	return str(s).replace("[", "[lb]")


# ---------------------------------------------------------------- run

func new_run() -> void:
	slice_next = {}
	interaction_roll_override = -1.0
	G.map = Rules.gen_floor()
	G.map.palette = J.pick(Render.PALETTES)
	G.map.seed = randi() % 1000000000
	G.x = 1
	G.y = 1
	G.dir = 0
	for i in 4:
		var d: Array = Render.DIRS[i]
		if G.map.grid[1 + d[1]][1 + d[0]] == 1:
			G.dir = i
			break
	G.seen = {}
	G.visited = {G.map.n + 1: true}
	G.hp = G.maxHp
	G.gold = 8
	G.tally = {"spared": 0, "slain": 0, "fled": 0, "recruited": 0, "left": 0}
	G.allies = []
	render_party()
	G.foe = null
	explore(sys("B1F. Find the stairs."))


## The console hook: jump straight into that faction's fight
func meet(species := "bandit") -> void:
	if G.map == null:
		new_run()
	for m in G.map.monsters:
		if m.species == species and not J.truthy(m.gone):
			start_encounter(m)
			return


## A reproducible two-bandit encounter for the personality playtest. The same fair-cut offer
## succeeds for the straight dealer and fails for the wary one at the fixed interaction roll.
func start_personality_slice(slice_seed := 7042) -> void:
	seed(slice_seed)
	new_run()
	G.gold = 12 # Both can hear the same 6-gold offer, even if the first accepts.
	interaction_roll_override = 0.5
	var pair: Array = G.map.monsters.slice(0, 2)
	var traits := ["surprisingly honest about being dishonest", "jumpy"]
	var names := ["ROOK", "VEX"]
	for i in 2:
		var m: Dictionary = pair[i]
		m.species = "bandit"
		m.genre = "chess"
		m.name = names[i]
		m.hp = 24
		m.maxHp = 24
		m.threshold = Species.SPECIES.bandit.joinThreshold
		m.traits = [traits[i]]
		m.taste = Rules.TRAIT_TASTE[traits[i]].duplicate()
		m.meters = {"friendliness": 78.0, "anger": 12.0, "fear": 15.0}
		m.lastIntent = ""
	slice_next = pair[1]
	print("genre halls: personality slice seed %d: %s then %s" % [slice_seed, pair[0].name, pair[1].name])
	start_encounter(pair[0])


# ---------------------------------------------------------------- the mind (Jev-shaped questions, local answers)

func render_mind_append(m, rows: Array) -> void:
	var prev: Array = last_mind.answers if last_mind.m != null and is_same(last_mind.m, m) else []
	render_mind(m, prev + rows)


## The mind is kept as data; the tooltip over the foe draws it (`_fill_mind_tip`) when the mouse is there
func render_mind(m, answers: Array) -> void:
	last_mind = {"m": m, "answers": answers}
	if _tip_key == "foe":
		_show_tip("foe", Rect2(), true, true) # open now: redraw with the new answers


## The foe's tooltip: who it is, how it feels, and the last two questions Jev answered about it
func _fill_mind_tip(box: VBoxContainer) -> void:
	var m = last_mind.m
	if m == null:
		return
	var head := HBoxContainer.new()
	var nm := _label(m.name, _pix, 9, C_INK)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	head.add_child(_label(str(Species.SPECIES[m.species].label).to_upper(), _pix, 9, C_DIM))
	box.add_child(head)
	if not m.traits.is_empty():
		var note := _rich(_term, 16, C_DIM)
		note.text = "Seems %s." % esc(" and ".join(m.traits))
		var clues: Array = Rules.personality_clues(m)
		if not clues.is_empty():
			note.text += "\nIt %s." % esc(". It ".join(clues))
		box.add_child(note)
	var meters := HBoxContainer.new()
	meters.add_theme_constant_override("separation", 16)
	for pair in [["FRIENDLY", m.meters.friendliness], ["ANGER", m.meters.anger], ["FEAR", m.meters.fear]]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(_label(pair[0], _term, 16, C_DIM))
		cell.add_child(_label(str(J.round_js(pair[1])), _term, 20, C_INK))
		meters.add_child(cell)
	box.add_child(meters)
	var shown: Array = last_mind.answers.slice(-2)
	for q in shown:
		box.add_child(_question(q))
	var offline := _rich(_term, 15, C_FAINT)
	offline.text = "Offline stand-in for Jev."
	box.add_child(offline)


func _question(q: Dictionary) -> Control:
	var a: Dictionary = q.a
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	var lab := _label(q.label, _term, 18, C_DIM)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(lab)
	var code := _label(a.type, _term, 15, C_YOU)
	code.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(code)
	box.add_child(head)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 2)
	box.add_child(bars)
	if a.type == "choice":
		var rows := []
		var i := 0
		for k in a.probabilities:
			rows.append([k, a.probabilities[k], i])
			i += 1
		rows.sort_custom(func(x, y): return x[1] > y[1] or (x[1] == y[1] and x[2] < y[2]))
		for r in rows.slice(0, 3):
			var name: String = Emotions.EMOTIONS[r[0]].label if Emotions.EMOTIONS.has(r[0]) else str(r[0]).to_upper()
			bars.add_child(_bar_row(name, r[1], r[0] == a.choice))
	elif a.type == "noul":
		var label := "YES"
		if a.has("yes"):
			label += " → YES" if a.yes else " → NO"
		bars.add_child(_bar_row(label, a.noul, true))
	elif a.type == "pressure":
		var note := _rich(_term, 17, C_INK)
		note.text = "Pressure %.2f / 3 sets the next dodge's pace." % a.score
		bars.add_child(note)
	else:
		for k in a.probabilities:
			bars.add_child(_bar_row("LEVEL %s" % k, a.probabilities[k], J.round_js(a.score) == int(k)))
	return box


func _bar_row(label: String, p: float, pick: bool) -> Control:
	var row := BarRow.new()
	row.label = label
	row.p = p
	row.pick = pick
	row.pct = chance_label(p)
	row.font = _term
	return row


static func chance_label(p: float) -> String:
	if p > 0.0 and p < 0.01:
		return "<1%"
	if p < 1.0 and p > 0.99:
		return ">99%"
	return "%d%%" % J.round_js(p * 100.0)


# ---------------------------------------------------------------- dock (text + menu)

func say(bbcode: String) -> void:
	last_say = bbcode
	_say.text = bbcode


func line(m: Dictionary, kind: String) -> String:
	var sp: Dictionary = Species.SPECIES[m.species]
	var pool: Array = sp.get("lines", {}).get(kind, [])
	if pool.is_empty():
		return ""
	var text := Species.fill(J.pick(pool), {"name": m.name[0] + m.name.substr(1).to_lower(), "target": "you"})
	if sfx != null:
		sfx.shout(text, m.species, {"boss": m.boss})
	return who(esc(m.name) + ":") + " " + esc(text)


func set_menu(items: Array, keys := "") -> void:
	G.menu = items
	G.sel = clampi(G.sel, 0, maxi(0, items.size() - 1))
	_hover_item = -1
	_kbd_nav = false ## a new menu shows no help until you hover it or move onto a command
	_clear(_menu_grid)
	_menu_grid.columns = clampi(items.size(), 1, 4)
	for i in items.size():
		var it := MenuItem.new()
		it.index = i
		it.label = items[i].label
		it.sub = items[i].get("sub", "")
		it.gold = items[i].get("gold", false)
		it.on = i == G.sel
		it.pix = _pix
		it.picked.connect(_on_menu_picked)
		it.hovered.connect(_on_menu_hover)
		_menu_grid.add_child(it)
	_keys.text = keys
	_refresh_tip()


func _on_menu_picked(i: int) -> void:
	_sfx_init()
	_hover_item = -1
	G.sel = i
	if i < G.menu.size():
		G.menu[i].run.call()


func move_sel(d: int) -> void:
	if G.menu.is_empty():
		return
	G.sel = (G.sel + d + G.menu.size()) % G.menu.size()
	for i in _menu_grid.get_child_count():
		var it: MenuItem = _menu_grid.get_child(i)
		it.on = i == G.sel
		it.queue_redraw()
	_sfx_play("tick")
	_kbd_nav = true
	_refresh_tip()


func foe_genre() -> String:
	return Rules.BOSS.genres[G.foe.turn % Rules.BOSS.genres.size()] if G.foe.boss else G.foe.genre


func hud() -> void:
	if postfx != null:
		postfx.set_danger(clampf((0.5 - float(G.hp) / G.maxHp) * 2.0, 0.0, 1.0))
	_hp.text = "HP [color=%s]%d/%d[/color]   GOLD [color=%s]%d[/color]" % [C_YOU, maxi(0, G.hp), G.maxHp, C_MERCY, G.gold]
	_hp_bar.set_hp(G.hp, G.maxHp)
	var spared: int = G.tally.spared
	var slain: int = G.tally.slain
	_route.text = "ROUTE [color=%s]%s[/color]" % [C_INK, "UNWRITTEN" if spared + slain == 0 else "%d SPARED · %d SLAIN" % [spared, slain]]
	_where.text = "B1F [color=%s]%s[/color]" % [C_INK, "%s ENCOUNTER" % Rules.GENRES[foe_genre()].name if G.foe != null else "THE GENRE HALLS"]
	_map_panel.visible = G.mode == "explore" or G.mode == "end" # it steps aside in a fight


# ---------------------------------------------------------------- exploring

func explore(msg := "", autosave := true) -> void:
	G.mode = "explore"
	G.foe = null
	_music_mood("explore")
	if postfx != null and G.map != null:
		postfx.set_accent(G.map.palette.accent)
	if msg != "":
		say(msg)
	set_menu([], kbd("↑") + kbd("↓") + " WALK  " + kbd("←") + kbd("→") + " TURN")
	hud()
	if autosave:
		_autosave()


# ---------------------------------------------------------------- saving

## A run is one floor: what is saved is the map, where you stand, HP, allies and the tally, written whenever you are
## back to walking (a floor's start, after a fight, after backing away). A fight in progress isn't saved: loading
## puts you back on the corridor before it.
func export_state() -> Dictionary:
	return {
		"map": G.map, "x": G.x, "y": G.y, "dir": G.dir, "seen": G.seen, "visited": G.visited,
		"hp": G.hp, "maxHp": G.maxHp, "gold": G.gold, "tally": G.tally, "allies": G.allies,
	}


func summary() -> String:
	var t: Dictionary = G.tally
	var text := "B1F · HP %d/%d · gold %d · spared %d · slain %d" % [G.hp, G.maxHp, G.gold, t.spared, t.slain]
	if not G.allies.is_empty():
		text += " · %d allies" % G.allies.size()
	return text


## Puts a saved state on the screen. False (nothing changed) if it isn't a state this game wrote.
func import_state(st: Dictionary) -> bool:
	var map = st.get("map")
	var ok: bool = map is Dictionary and map.get("grid") is Array and map.get("monsters") is Array and map.get("stairs") is Dictionary \
		and map.get("palette") is Dictionary and map.has("n") and st.get("tally") is Dictionary and st.get("allies") is Array \
		and st.has("x") and st.has("y") and st.has("dir") and st.has("hp") and st.has("maxHp")
	if ok:
		var gy := int(st.y)
		var gx := int(st.x)
		ok = gy >= 0 and gy < map.grid.size() and gx >= 0 and gx < map.grid[gy].size() and map.grid[gy][gx] == 1
	if not ok:
		push_warning("genre halls: that save isn't one this version can load")
		return false
	G.map = map
	G.x = int(st.x)
	G.y = int(st.y)
	G.dir = posmod(int(st.dir), 4)
	G.seen = st.get("seen", {}) if st.get("seen") is Dictionary else {}
	G.visited = st.get("visited", {}) if st.get("visited") is Dictionary else {}
	G.maxHp = int(st.maxHp)
	G.hp = clampi(int(st.hp), 1, G.maxHp)
	G.gold = maxi(0, int(st.get("gold", 8)))
	G.tally = st.tally
	G.allies = st.allies
	slice_next = {}
	interaction_roll_override = -1.0
	D = null
	bar = null
	pending_judgement = null
	_timers.clear()
	if _talk != null:
		close_talk()
	render_party()
	print("genre halls: loaded a run (%s)" % summary())
	explore(sys("Welcome back. " + summary().replace(" · ", ", ") + "."), false)
	return true


func _autosave() -> void:
	if clock_override >= 0.0 or G.map == null or Flags.test("nosave|personality-slice"):
		return
	Saves.write(Saves.AUTO, export_state(), summary())


# ---------------------------------------------------------------- the pause menu

func open_pause() -> void:
	if _pause == null:
		_pause = MenuPanel.new()
		_pause.backdrop = 0.86
		add_child(_pause)
	var ctx := {
		"resume": func(): _pause.close(),
		"to_main_menu": func(): to_menu(),
		"load_slot": func(slot):
			var st := Saves.read(slot)
			_pause.close()
			if st.is_empty() or not import_state(st):
				say(sys("That save can't be loaded.")),
	}
	if not OS.has_feature("web"):
		ctx["quit"] = func():
			print("genre halls: quit from the pause menu")
			if navigate:
				get_tree().quit()
	if G.mode == "explore":
		ctx["save_slot"] = func(slot) -> bool:
			var wrote := Saves.write(slot, export_state(), summary())
			say(sys("Saved to slot %s." % str(slot)) if wrote else sys("Couldn't save to slot %s." % str(slot)))
			return wrote
	_pause.open(func(): return Menus.pause(_pause, ctx))


func pause_open() -> bool:
	return _pause != null and _pause.visible


func monster_at(x: int, y: int):
	for m in G.map.monsters:
		if not J.truthy(m.gone) and m.x == x and m.y == y:
			return m
	return null


func _open(x: int, y: int) -> bool:
	var grid: Array = G.map.grid
	return y >= 0 and y < grid.size() and x >= 0 and x < grid[y].size() and grid[y][x] == 1


func step(forward: int) -> void:
	var d: Array = Render.DIRS[G.dir if forward > 0 else (G.dir + 2) % 4]
	var nx: int = G.x + d[0]
	var ny: int = G.y + d[1]
	if not _open(nx, ny):
		_sfx_play("bump")
		_shake(160.0)
		if stage != null:
			stage.bump(now())
		return
	var m = monster_at(nx, ny)
	if m != null:
		start_encounter(m)
		return
	G.x = nx
	G.y = ny
	G.visited[ny * G.map.n + nx] = true
	if nx == G.map.stairs.x and ny == G.map.stairs.y:
		ending()


## The monsters you can see, far to near: [{ m, d, k }] (d cells ahead, k to the right). That includes the ones
## diagonal to you, down a side opening, not only the one straight ahead. With the 3D set it is what the camera
## sees (its field of view, a clear line over the floor); the flat corridor keeps the old six-cell rule.
func monsters_in_view() -> Array:
	var out := []
	var sight := {}
	var by_camera: bool = stage != null and stage.placed()
	if by_camera:
		for c in stage.sight(G.map.grid, G.x, G.y):
			sight[Vector2i(c[0], c[1])] = true
	for m in G.map.monsters:
		if J.truthy(m.gone):
			continue
		if by_camera:
			if not sight.has(Vector2i(m.x, m.y)):
				continue
			var f: Array = Render.DIRS[G.dir]
			var dx: int = m.x - G.x
			var dy: int = m.y - G.y
			out.append({"m": m, "d": dx * f[0] + dy * f[1], "k": dx * -f[1] + dy * f[0]})
			continue
		var slot = Render.slot_of(G.map, G.x, G.y, G.dir, m.x, m.y)
		if slot != null:
			out.append({"m": m, "d": slot.d, "k": slot.k})
	out.sort_custom(func(a, b): return a.d > b.d)
	return out


# ---------------------------------------------------------------- encounters

func start_encounter(m: Dictionary) -> void:
	G.foe = m
	m.spoke = false
	G.mode = "intro"
	G.sel = 0
	if postfx != null:
		postfx.set_accent(BOSS_COLOR if m.boss else Species.SPECIES[m.species].color)
	_sfx_play("boss" if m.boss else "encounter")
	_music_mood("battle")
	intro_until = now() + 700.0
	render_mind(m, [{"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "a": Rules.ask_mercy(m)}])
	var rule: String = "The champion shifts its rules every turn: chess, shadow, rhythm, goo." if m.boss else "It fights in %s. %s." % [Rules.GENRES[m.genre].name, Rules.GENRES[m.genre].rule]
	say(line(m, "converse") + "\n" + sys(rule))
	hud()
	_after(700.0, func(): if G.mode == "intro" and G.foe != null and is_same(G.foe, m): main_menu())


func spareable(m: Dictionary) -> bool:
	return Rules.ask_mercy(m).noul >= 0.5


func main_menu(msg := "") -> void:
	G.mode = "menu"
	if msg != "":
		say(msg)
	var m: Dictionary = G.foe
	var mercy: float = Rules.ask_mercy(m).noul
	set_menu(
		[
			{"label": "FIGHT", "sub": "Time the strike", "run": func(): fight_bar()},
			{"label": "ACT", "sub": "Say or do something", "run": func(): act_menu()},
			{"label": "SPARE", "sub": "%s chance to accept. %s" % [chance_label(mercy), SPARE_TIP], "gold": mercy >= 0.5, "run": func(): spare()},
			{"label": "FLEE", "sub": "Champions block the way" if m.boss else "Back away", "run": func(): flee()},
		],
		kbd("↑") + kbd("↓") + " CHOOSE " + kbd("ENTER") + " PICK " + kbd("1") + "-" + kbd("4"),
	)
	hud()


func act_menu() -> void:
	var m: Dictionary = G.foe
	G.mode = "act"
	G.sel = 0
	var items := [{"label": "CHECK", "sub": "Free: read it", "run": func(): check()}]
	for a in Rules.ACTS[m.species]:
		items.append({"label": a.label, "sub": "Costs 6 gold if accepted; ends the fight" if m.species in ["bandit", "snake"] and a.intent == "gold" else "", "run": func(): do_act(a)})
	if m.spoke:
		items.append({"label": "SAY SOMETHING", "sub": "Already spoke this fight", "run": func(): main_menu(sys("You've had your say this fight."))})
	else:
		items.append({"label": "SAY SOMETHING", "sub": "Ask about stairs, the champion or another monster; one line per fight", "run": func(): open_talk()})
	set_menu(items, kbd("ENTER") + " PICK " + kbd("ESC") + " BACK")


func check() -> void:
	var m: Dictionary = G.foe
	var sp: Dictionary = Species.SPECIES[m.species]
	var traits := []
	for t in m.traits:
		traits.append(bold(esc(t)))
	var likes := []
	for l in sp.likes.slice(0, 2):
		likes.append(esc(l))
	var clues: Array = Rules.personality_clues(m)
	var individual := "This one may differ." if clues.is_empty() else "It %s." % esc(". It ".join(clues))
	main_menu(sys("%s seems %s. Its kind likes %s and hates %s. %s" % [esc(m.name), " and ".join(traits), ", ".join(likes), esc(sp.dislikes[0]), individual]))


## One round of the mind: how it feels about `act` ("fight" or a list of { intent, w }), whether it would accept
## mercy, and how hard it attacks. Applies the feeling to its meters.
func decide(m: Dictionary, act, act_label: String, words = null) -> Dictionary:
	if words != null:
		m.lastIntent = words.choice
	elif act is String:
		m.lastIntent = act
	elif not act.is_empty():
		m.lastIntent = act[0].intent
	var feeling := Rules.ask_feeling(m, act)
	var em := Rules.apply_feeling(m, feeling.choice)
	var mercy := Rules.ask_mercy(m)
	var pressure := Rules.ask_pressure(m)
	print_verbose("genre halls mind: %s (%s) hears %s -> %s, mercy %d%%, pressure %.2f" % [m.name, ", ".join(m.traits), m.lastIntent, feeling.choice, J.round_js(mercy.noul * 100.0), pressure.score])
	var rows := []
	if words != null:
		rows.append({"id": "words", "label": "WHAT DID YOUR WORDS MEAN?", "a": words})
	rows.append({"id": "feeling", "label": "HOW DOES IT FEEL? (%s)" % act_label, "a": feeling})
	rows.append({"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "a": mercy})
	rows.append({"id": "pressure", "label": "HOW HARD DOES IT ATTACK?", "a": pressure})
	render_mind(m, rows)
	return {"em": em, "id": feeling.choice, "pressure": pressure.score, "pacified": Emotions.PACIFYING.has(em.get("cond"))}


## The shared emotion descriptions include D&D conditions that this mode does not use.
## Report the meter changes Genre Halls actually applies; after_player reports a skipped attack.
static func genre_effect(em: Dictionary) -> String:
	var changes := []
	for k in ["friendliness", "anger", "fear"]:
		var amount: float = em.get("meters", {}).get(k, 0)
		if amount != 0:
			changes.append("%s %s" % [k, "rises" if amount > 0 else "falls"])
	return "; ".join(changes) if not changes.is_empty() else "its mood shifts"


func do_act(act: Dictionary) -> void:
	var m: Dictionary = G.foe
	if m.species in ["bandit", "snake"] and act.intent == "gold":
		offer_cut(m, act)
		return
	var r := decide(m, [{"intent": act.intent, "w": 1}], act.label)
	judge(act.intent)
	_sfx_play("good" if r.em.tone == "good" else ("bad" if r.em.tone == "bad" else "odd"))
	after_player("%s %s is %s: %s." % [sys("You %s." % esc(act.label.to_lower())), esc(m.name), bold(r.em.label), genre_effect(r.em)], r)


func offer_cut(m: Dictionary, act: Dictionary, words = null) -> void:
	if G.gold < 6:
		main_menu(sys("A fair cut is 6 gold. You have %d.%s" % [G.gold, " Your line is spent." if words != null else ""]))
		return
	var accepted := Rules.accepts_cut(m, interaction_roll_override)
	var refusal_reason := "It is too angry to trust an offer" if m.meters.anger >= 60 else ("It watches for a catch" if m.traits.has("secretive") else ("It keeps watching the exit" if m.traits.has("jumpy") else ("Its pride outweighs the coins" if m.traits.has("proud") else "It decides the risk is not worth the coins")))
	var r := decide(m, [{"intent": "gold", "w": 1}], act.label, words)
	judge("gold")
	if accepted:
		G.gold -= 6
		print("genre halls: %s accepted a 6 gold cut; %d gold left" % [m.name, G.gold])
		var reason := "It keeps its word." if m.traits.has("surprisingly honest about being dishonest") else ("It needed the coins." if m.traits.has("owes money to someone") else "The bargain suits it.")
		defeat(m, "spared", false, "SPARED. It takes 6 gold and leaves. " + reason)
		return
	_sfx_play("bad")
	after_player("%s %s. You keep your gold." % [sys("You offer 6 gold."), esc(refusal_reason)], r)


# ---------------------------------------------------------------- talking (optional, once per fight)

func open_talk() -> void:
	G.mode = "talk"
	_talk.visible = true
	_talk_in.text = ""
	set_menu([], "TYPE ANYTHING " + kbd("ENTER") + " SAY IT " + kbd("ESC") + " NEVER MIND · GOLD OFFERS COST 6 IF ACCEPTED")
	_talk_in.call_deferred("grab_focus")


func close_talk() -> void:
	_talk.visible = false
	_talk_in.release_focus()


## The SAY IT button / Enter in the box
func submit_talk(raw: String) -> void:
	var text := raw.strip_edges().left(140)
	close_talk()
	if text == "":
		act_menu()
		return
	say_text(text)


func say_text(text: String) -> void:
	var m: Dictionary = G.foe
	m.spoke = true
	var words := Rules.read_words(text)
	if m.species in ["bandit", "snake"] and words.choice == "gold":
		offer_cut(m, {"label": "YOUR OFFER"}, words)
		return
	var parts := []
	for k in words.probabilities:
		if k != "other" and words.probabilities[k] >= 0.12:
			parts.append({"intent": k, "w": words.probabilities[k]})
	var r := decide(m, parts if not parts.is_empty() else [{"intent": "question", "w": 0.3}], "YOUR WORDS", words)
	var top: String = words.choice
	judge(null if top == "other" else top)
	var extra := ""
	var asked: bool = words.probabilities.question >= 0.25 and top != "gibberish"
	if top == "gibberish":
		extra = "\n" + sys("It didn't understand a word of that.")
	elif asked:
		if Rules.will_reveal(m, interaction_roll_override):
			var reason := "Curious, it answers" if m.traits.has("curious") else ("It speaks plainly" if m.traits.has("surprisingly honest about being dishonest") else "It trusts you enough to answer")
			extra = "\n" + who(esc(m.name) + ":") + " " + esc(reason + ": " + hint_for(m, text).trim_prefix("..."))
		else:
			var reason := "It guards its secrets" if m.traits.has("secretive") else ("It keeps watching the exit" if m.traits.has("jumpy") else "It does not trust you yet")
			extra = "\n" + sys(reason + " and gives no answer.")
	var message := sys("You ask a question.") + " " + esc(m.name) + " is " + bold(r.em.label) + "." + extra if asked else "%s %s is %s: %s.%s" % [sys('You say "%s".' % esc(text)), esc(m.name), bold(r.em.label), genre_effect(r.em), extra]
	after_player(message, r, not asked)


# Facts come from this run's map and living monsters. The stair direction is the first walkable step,
# not a compass bearing through a wall.
static func _has_question_term(q: String, terms: Array) -> bool:
	for term in terms:
		if q.contains(" " + term + " "):
			return true
	return false


func hint_for(m: Dictionary, question := "") -> String:
	var words_re := RegEx.create_from_string("[^a-z0-9]+")
	var q: String = " " + words_re.sub(question.to_lower(), " ", true).strip_edges() + " "
	var asks_stairs := q == "  " or _has_question_term(q, ["stair", "stairs", "exit", "way out"])
	var asks_champion := _has_question_term(q, ["champion", "boss", "dragon", "vexalith"])
	if asks_stairs and asks_champion:
		return "...ask about the stairs or the champion, one at a time."
	var names := []
	for o in G.map.monsters:
		var name: String = words_re.sub(str(o.name).to_lower(), " ", true)
		if q.contains(" " + name + " "):
			names.append(o)
	if names.size() > 1:
		return "...which monster do you mean?"
	var species_matches := []
	for o in G.map.monsters:
		if q.contains(" " + str(o.species) + " "):
			species_matches.append(o)
	var asks_other := q.contains(" another monster ") or q.contains(" other monster ")
	if asks_stairs and (not names.is_empty() or not species_matches.is_empty() or asks_other):
		return "...ask about one thing at a time."
	if asks_stairs:
		if q != "  " and not _has_question_term(q, ["where", "way", "direction", "path", "route", "find", "reach"]) and q.strip_edges() not in ["stair", "stairs", "exit", "way out"]:
			return "...ask which way the stairs lie."
		if G.x == G.map.stairs.x and G.y == G.map.stairs.y:
			return "...you are standing on the stairs."
		return "...from here, take the corridor %s toward the stairs." % _stairs_step()
	var champion: Dictionary = G.map.monsters.back()
	if asks_champion:
		if (not names.is_empty() and not is_same(names[0], champion)) or species_matches.any(func(o): return not is_same(o, champion)) or asks_other:
			return "...ask about one monster at a time."
		if not _has_question_term(q, ["opening", "openings", "genre", "genres", "attack", "attacks", "fight", "fights", "pattern", "patterns"]) and q.strip_edges() not in ["champion", "boss", "dragon", "vexalith"]:
			return "...ask about the champion's opening genres."
		if champion.gone != null:
			return "...the champion has already fallen."
		return "...%s starts with %s, then shifts to %s." % [champion.name, Rules.GENRES[Rules.BOSS.genres[0]].name.to_lower(), Rules.GENRES[Rules.BOSS.genres[1]].name.to_lower()]
	var target: Dictionary = {}
	if not names.is_empty():
		target = names[0]
	else:
		if species_matches.size() > 1:
			return "...which %s do you mean?" % species_matches[0].species
		if not species_matches.is_empty():
			target = species_matches[0]
	if target.is_empty() and asks_other:
		for o in G.map.monsters:
			if not J.truthy(o.gone) and not is_same(o, m):
				target = o
				break
	if target.is_empty():
		return "...I know no one else left on this floor." if asks_other else "...ask me about the stairs, the champion, or another monster."
	if J.truthy(target.gone):
		return "...that monster is gone from this floor."
	if is_same(target, m):
		return "...you can see how I behave for yourself."
	if not _has_question_term(q, ["want", "wants", "like", "likes", "dislike", "dislikes", "hate", "hates", "fear", "fears", "weakness", "trait", "traits", "behave", "behavior", "about", "avoid", "avoids"]) and not asks_other and q.strip_edges() not in [str(target.name).to_lower(), str(target.species)]:
		return "...ask what %s wants or avoids." % target.name
	var worst: String = Rules.ACTS[target.species][0].intent
	for a in Rules.ACTS[target.species]:
		if Rules.aff(target, a.intent) < Rules.aff(target, worst):
			worst = a.intent
	var clues: Array = Rules.personality_clues(target)
	var clue := " It %s." % clues[0] if not clues.is_empty() else ""
	return "...%s seems uneasy around %s.%s" % [target.name, Rules.INTENT_WORDS[worst], clue]


func _stairs_step() -> String:
	var start := Vector2i(G.x, G.y)
	var goal := Vector2i(int(G.map.stairs.x), int(G.map.stairs.y))
	if start == goal:
		return "now; you are on them"
	var queue := [start]
	var first := {start: -1}
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for i in Render.DIRS.size():
			var d: Array = Render.DIRS[i]
			var next := at + Vector2i(d[0], d[1])
			if next.y < 0 or next.y >= G.map.grid.size() or next.x < 0 or next.x >= G.map.grid[next.y].size() or G.map.grid[next.y][next.x] != 1 or first.has(next):
				continue
			first[next] = i if at == start else first[at]
			if next == goal:
				return ["north", "east", "south", "west"][first[next]]
			queue.append(next)
	return "unknown"


# ---------------------------------------------------------------- allies: passive charms that judge you

func has_ally(species: String) -> bool:
	for a in G.allies:
		if a.species == species:
			return true
	return false


func judge(event) -> void:
	if event == null or event == "" or G.allies.is_empty():
		return
	var rows := []
	var notes := []
	for a in G.allies.duplicate():
		var table: Dictionary = Rules.APPROVE[a.species]
		if not table.has(event):
			continue
		var v: float = table[event]
		var mean := clampf(2.0 + v, 0.0, 4.0)
		var levels := []
		var sum := 0.0
		for i in 5:
			var lv := exp(-pow(i - mean, 2) * 0.9)
			levels.append(lv)
			sum += lv
		var probs := {}
		for i in 5:
			probs[str(i)] = levels[i] / sum
		var score := int(Rules.roll_odds(probs))
		a.loyalty = clampf(a.loyalty + (score - 2) * 10, 0.0, 100.0)
		rows.append({"id": "judge-%s" % a.name, "label": "%s JUDGES IT (0 HATES - 4 LOVES)" % a.name, "a": {"type": "score", "score": score, "probabilities": probs}})
		var sp: Dictionary = Species.SPECIES[a.species]
		var kind = "disapprove" if score <= 1 else ("approve" if score >= 3 else null)
		if kind != null:
			notes.append(who(esc(a.name) + ":") + " " + esc(Species.fill(J.pick(sp.reactions[kind]), {"name": a.name, "target": "you"})))
		if a.loyalty < 30:
			var p := Rules.sigmoid((30.0 - a.loyalty) / 6.0 - 0.5)
			var leaves := randf() < p
			rows.append({"id": "leave-%s" % a.name, "label": "DOES %s LEAVE?" % a.name, "a": {"type": "noul", "noul": p, "yes": leaves}})
			if leaves:
				var kept := []
				for x in G.allies:
					if not is_same(x, a):
						kept.append(x)
				G.allies = kept
				G.tally.left += 1
				_sfx_play("sad")
				notes.append(who(esc(a.name) + ":") + " " + esc(Species.fill(J.pick(sp.reactions.leave), {"name": a.name})) + " " + sys("(%s is gone)" % Rules.CHARMS[a.species].name))
	if not rows.is_empty():
		pending_judgement = {"rows": rows, "notes": notes}
	render_party()


## The allies are chips over the view's bottom-left (a colored dot, the charm's name; red when about to leave). The charm's
## text, the mood and what the ally cares about are in the tooltip. No allies, no chips.
func render_party() -> void:
	_clear(_chips)
	for i in G.allies.size():
		var a: Dictionary = G.allies[i]
		var c: Dictionary = Rules.CHARMS[a.species]
		var chip := AllyChip.new()
		chip.dot = Color(Species.SPECIES[a.species].color)
		chip.label = c.name
		chip.warn = a.loyalty < 30
		chip.font = _pix
		chip.hovered.connect(_on_chip_hover.bind(i))
		_chips.add_child(chip)
	if _tip_key.begins_with("ally"):
		_hide_tip()


func _ally_mood(a: Dictionary) -> String:
	return "DEVOTED" if a.loyalty >= 70 else ("CONTENT" if a.loyalty >= 45 else ("UNEASY" if a.loyalty >= 30 else "MAY LEAVE"))


func _fill_map_tip(box: VBoxContainer) -> void:
	box.add_child(_label("MONSTERS SHOW WHEN SEEN", _pix, 8, C_DIM))
	for e in [["#ff8a1f", "SLIME", "goo rain"], ["#e0524e", "BANDIT", "chess"], ["#6bd36b", "SNAKE", "shadow"], ["#a7a39b", "ROCK", "rhythm"], ["#ff2a2a", "DRAGON", "all four"]]:
		var li := HBoxContainer.new()
		li.add_theme_constant_override("separation", 8)
		var sw := ColorRect.new()
		sw.color = Color(e[0])
		sw.custom_minimum_size = Vector2(8, 8)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		li.add_child(sw)
		li.add_child(_label(e[1], _term, 18, C_INK))
		li.add_child(_label(e[2], _term, 18, C_DIM))
		box.add_child(li)


func _fill_ally_tip(box: VBoxContainer, i: int) -> void:
	if i >= G.allies.size():
		return
	var a: Dictionary = G.allies[i]
	var c: Dictionary = Rules.CHARMS[a.species]
	var head := HBoxContainer.new()
	var nm := _label(a.name, _term, 20, C_INK)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	head.add_child(_label(_ally_mood(a), _term, 16, C_WARN if a.loyalty < 30 else C_DIM))
	box.add_child(head)
	var row := BarRow.new()
	row.label = c.name
	row.p = a.loyalty / 100.0
	row.pct = str(J.round_js(a.loyalty))
	row.font = _term
	box.add_child(row)
	var note := _rich(_term, 16, C_DIM)
	note.text = "%s. Cares about: %s" % [esc(c.text), esc(Species.SPECIES[a.species].values)]
	note.text += "\nA refused gold offer may still affect loyalty; only an accepted offer spends gold."
	box.add_child(note)


# FIGHT: a timing bar. Press OK near the middle.
func fight_bar() -> void:
	G.mode = "fightbar"
	set_menu([], kbd("ENTER") + " STRIKE WHEN THE LINE CROSSES THE MIDDLE")
	bar = {"t0": now(), "dur": 1500.0 if has_ally("rock") else 1100.0}


func strike(t: float) -> void:
	var m: Dictionary = G.foe
	var x := clampf((t - bar.t0) / bar.dur, 0.0, 1.0)
	bar = null
	var off := absf(x - 0.5) * 2.0
	if off > 0.92:
		_sfx_play("miss")
		var rr := decide(m, "fight", "YOU SWUNG")
		after_player("%s %s is %s." % [sys("You swing wide and miss."), esc(m.name), bold(rr.em.label)], rr)
		return
	var crit := off < 0.08
	var dmg: int = J.round_js((14.0 if crit else 4.0 + 8.0 * pow(1.0 - off, 1.2)) * (0.8 if m.boss else 1.0)) + (4 if has_ally("dragon") else 0)
	m.hp = maxi(0, m.hp - dmg)
	_sfx_play("crit" if crit else "hit")
	if postfx != null:
		postfx.flash("#ffffff", 0.5 if crit else 0.25)
	hurt_until = t + 300.0
	m.meters.friendliness = clampf(m.meters.friendliness - 8, 0, 100)
	m.meters.anger = clampf(m.meters.anger + 10, 0, 100)
	m.meters.fear = clampf(m.meters.fear + 8, 0, 100)
	if m.hp <= 0:
		judge("slay_begging" if spareable(m) else "slay")
		defeat(m, "slain")
		return
	var begging := spareable(m)
	var r := decide(m, "fight", "YOU HIT IT")
	if begging:
		judge("slay_begging")
	after_player("%s %s is %s: %s." % [sys("%s%d damage." % ["A perfect strike! " if crit else "", dmg]), esc(m.name), bold(r.em.label), genre_effect(r.em)], r)


func spare() -> void:
	var m: Dictionary = G.foe
	var mercy := Rules.ask_mercy(m)
	var yes: bool = randf() < mercy.noul
	var shown := mercy.duplicate()
	shown["yes"] = yes
	render_mind(m, [{"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "a": shown}])
	if yes:
		judge("spare")
		defeat(m, "spared")
		return
	_sfx_play("bad")
	var r := {"pressure": Rules.ask_pressure(m).score, "pacified": false}
	m.meters.anger = clampf(m.meters.anger + 4, 0, 100)
	after_player("%s %s refuses mercy. (%s chance to accept)" % [sys("You offer mercy."), esc(m.name), chance_label(mercy.noul)], r)


func flee() -> void:
	var m: Dictionary = G.foe
	if m.boss:
		main_menu(sys("The champion's tail blocks the way back."))
		return
	G.tally.fled += 1
	_sfx_play("flee")
	judge("flee")
	m.hp = m.maxHp
	var notes := ""
	if pending_judgement != null and not pending_judgement.notes.is_empty():
		notes = "\n" + "\n".join(pending_judgement.notes)
	if pending_judgement != null:
		render_mind(m, pending_judgement.rows)
	pending_judgement = null
	explore(sys("You back away. %s stays where it is." % esc(m.name)) + notes)


func defeat(m: Dictionary, how: String, allow_join := true, settlement := "") -> void:
	m.gone = how
	G.tally[how] += 1
	if m.boss:
		G.map.boss.defeated = true
	_sfx_play("good" if how == "spared" else "kill")
	if postfx != null:
		postfx.flash(C_MERCY if how == "spared" else BOSS_COLOR, 0.4)
	var text := sys("%s falls." % esc(m.name))
	var joined := false
	if how == "spared" and allow_join:
		var room: bool = G.allies.size() < 3
		var p: float = Rules.ask_join(m).noul if room else 0.0
		joined = randf() < p
		var rows := [{"id": "join", "label": "DOES IT WANT TO COME ALONG?" if room else "DOES IT WANT TO COME ALONG? (PARTY FULL)", "a": {"type": "noul", "noul": p, "yes": joined}}]
		render_mind(m, rows + pending_judgement.rows if pending_judgement != null else rows)
		if joined:
			G.allies.append({"species": m.species, "name": m.name, "loyalty": 60.0 + J.rnd(0, 20)})
			G.tally.recruited += 1
			_sfx_play("join")
			render_party()
		text = line(m, "join_party" if joined else "leave_peacefully")
	elif how == "spared":
		text = line(m, "leave_peacefully")
		if pending_judgement != null:
			render_mind(m, pending_judgement.rows)
	elif pending_judgement != null:
		render_mind(m, pending_judgement.rows)
	var notes := ""
	if pending_judgement != null and not pending_judgement.notes.is_empty():
		notes = "\n" + "\n".join(pending_judgement.notes)
	pending_judgement = null
	G.mode = "result"
	_music_sting("victory")
	hud()
	var verdict: String
	if how == "spared":
		verdict = settlement if settlement != "" else ("SPARED. It joins you: %s, %s." % [Rules.CHARMS[m.species].name, Rules.CHARMS[m.species].text] if joined else "SPARED. It goes its own way.")
	else:
		verdict = "SLAIN."
	say(text + "\n" + sys(verdict) + notes)
	set_menu([{"label": "CONTINUE", "run": func(): continue_result()}], kbd("ENTER") + " CONTINUE")


func continue_result() -> void:
	if not slice_next.is_empty() and not is_same(G.foe, slice_next) and not J.truthy(slice_next.gone):
		start_encounter(slice_next)
		return
	slice_next = {}
	explore()


func after_player(msg: String, r: Dictionary, show_attack_line := true) -> void:
	var m: Dictionary = G.foe
	if pending_judgement != null:
		msg += "\n" + "\n".join(pending_judgement.notes)
		render_mind_append(m, pending_judgement.rows)
		pending_judgement = null
	if r.pacified:
		main_menu(msg + "\n" + sys("It doesn't attack this turn."))
		return
	say(msg + ("\n" + line(m, "attack") if show_attack_line else ""))
	G.mode = "wait"
	set_menu([], "")
	_after(650.0, func(): if G.foe != null and is_same(G.foe, m): start_dodge(r.pressure))


# ---------------------------------------------------------------- the box: one grid, one rule (lit squares hurt)

func start_dodge(pressure: float) -> void:
	var m: Dictionary = G.foe
	var genre := foe_genre()
	var intensity := (0.8 + 0.25 * pressure) * (1.2 if m.boss else 1.0)
	var t := now()
	D = {
		"genre": genre,
		"intensity": intensity,
		"t0": t,
		"end": t + (6200.0 if m.boss else 5400.0),
		"soul": {"c": 3, "r": 3},
		"hazards": [],
		"next": t + 300.0,
		"beat": -1,
		"blocked": {},
		"iframes": 0.0,
		"shield": has_ally("slime"),
		"hitFlash": -1e9,
		"blockFlash": -1e9,
		"pulse": 0.0,
	}
	if genre == "shadow":
		for k in Rules.PILLARS:
			D.blocked[k] = true
	G.mode = "dodge"
	set_menu([], kbd("↑") + kbd("↓") + kbd("←") + kbd("→") + " MOVE · " + Rules.GENRES[genre].rule)
	hud()


func hazard(cells: Array, warn_ms: float, hit_ms: float, kind: String, extra := {}) -> void:
	var t := now()
	if kind != "stomp" and has_ally("bandit"):
		warn_ms *= 1.3
	var live := {}
	for k in cells:
		if not D.blocked.has(k):
			live[k] = true
	var h := {"cells": live, "warn": t, "hit": t + warn_ms, "end": t + warn_ms + hit_ms, "kind": kind, "sounded": false}
	h.merge(extra, true)
	D.hazards.append(h)


func _spawn(t: float) -> void:
	match D.genre:
		"chess":
			_spawn_chess(t)
		"bullet":
			_spawn_bullet(t)
		"rhythm":
			_spawn_rhythm(t)
		"shadow":
			_spawn_shadow(t)


func _spawn_chess(t: float) -> void:
	if t < D.next:
		return
	D.next = t + 760.0 / D.intensity
	var c: int = D.soul.c
	var r: int = D.soul.r
	var kind: String = J.pick(["rook", "rook", "bishop", "bishop", "knight"])
	if kind == "rook":
		var o := {"c": J.pick([0, COLS - 1]), "r": r} if randf() < 0.5 else {"c": c, "r": J.pick([0, ROWS - 1])}
		hazard(Rules.rook_cells(o), 950.0, 320.0, "chess", {"glyph": "R", "at": Rules.idx(o.c, o.r)})
	elif kind == "bishop":
		var d: Array = J.pick([[1, 1], [1, -1], [-1, 1], [-1, -1]])
		var k := J.rnd(1, 3)
		while k > 0 and not Rules.in_box(c + d[0] * k, r + d[1] * k):
			k -= 1
		var o := {"c": c + d[0] * k, "r": r + d[1] * k}
		hazard(Rules.bishop_cells(o), 950.0, 320.0, "chess", {"glyph": "B", "at": Rules.idx(o.c, o.r)})
	else:
		var options := []
		for d in Rules.KNIGHT:
			if Rules.in_box(c + d[0], r + d[1]):
				options.append({"c": c + d[0], "r": r + d[1]})
		var o: Dictionary = J.pick(options)
		hazard(Rules.knight_cells(o), 900.0, 320.0, "chess", {"glyph": "N", "at": Rules.idx(o.c, o.r)})


func _spawn_bullet(t: float) -> void:
	if t < D.next:
		return
	D.next = t + 330.0 / D.intensity
	var aim := randf() < 0.4
	var c: int = D.soul.c if aim else J.rnd(0, COLS - 1)
	var r: int = D.soul.r if aim else J.rnd(0, ROWS - 1)
	var cells := []
	for d in [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]:
		if Rules.in_box(c + d[0], r + d[1]):
			cells.append(Rules.idx(c + d[0], r + d[1]))
	hazard(cells, 820.0, 260.0, "goo", {"at": Rules.idx(c, r)})


func _spawn_rhythm(t: float) -> void:
	var beat_ms: float = 600.0 / sqrt(D.intensity)
	var b := floori((t - D.t0) / beat_ms)
	if b <= D.beat:
		return
	D.beat = b
	_sfx_play("tick")
	D.pulse = t
	if b % 2 == 1:
		return # a new stomp every other beat, telegraphed for two beats
	var p: int = (b * 5 + (G.foe.turn % 3)) % Rules.STOMPS.size()
	# Telegraphed two beats ahead, lands on the beat
	hazard(Rules.STOMPS[p].call(D.soul), beat_ms * 2.0, 240.0, "stomp", {"beatHit": true})


func _spawn_shadow(t: float) -> void:
	if t < D.next:
		return
	D.next = t + 1250.0 / D.intensity
	var warn := 900.0
	var L := Rules.lantern_at(t + warn - D.t0, D.intensity)
	var cells := []
	for r in ROWS:
		for c in COLS:
			var k := Rules.idx(c, r)
			if not D.blocked.has(k) and not Rules.shaded(L, c, r, D.blocked):
				cells.append(k)
	hazard(cells, warn, 300.0, "light", {"L": L})


func update_dodge(t: float) -> void:
	_spawn(t)
	var here: int = Rules.idx(D.soul.c, D.soul.r)
	for h in D.hazards:
		if t >= h.hit and not h.sounded:
			h.sounded = true
			if h.kind == "stomp":
				_sfx_play("hit")
			elif h.kind == "chess":
				_sfx_play("slash")
			elif h.kind == "light":
				_sfx_play("holy")
		if t >= h.hit and t < h.end and h.cells.has(here) and t > D.iframes:
			var safe := 1100.0 if has_ally("snake") else 700.0
			if D.shield:
				D.shield = false
				D.iframes = t + safe
				D.blockFlash = t
				_sfx_play("buff")
				continue
			var dmg := 4 if G.foe.boss else 3
			G.hp -= dmg
			if postfx != null:
				postfx.hurt(1.0)
			D.iframes = t + safe
			D.hitFlash = t
			_shake(200.0, t)
			_sfx_play("hurt")
			hud()
			if G.hp <= 0:
				dead()
				return
	D.hazards = D.hazards.filter(func(h): return t < h.end)
	if t >= D.end:
		D = null
		G.foe.turn += 1
		main_menu(sys("%s pauses. %s" % [esc(G.foe.name), "Mercy odds are at least 50%." if spareable(G.foe) else "What now?"]))


func move_soul(dc: int, dr: int) -> void:
	var c: int = D.soul.c + dc
	var r: int = D.soul.r + dr
	if not Rules.in_box(c, r) or D.blocked.has(Rules.idx(c, r)):
		return
	D.soul = {"c": c, "r": r}


func dead() -> void:
	D = null
	G.mode = "dead"
	_sfx_play("death")
	say(sys("You fall. %s watches." % esc(G.foe.name)))
	set_menu(
		[
			{"label": "TRY THIS FIGHT AGAIN", "run": func(): retry_fight()},
			{"label": "NEW FLOOR", "run": func(): new_run()},
			{"label": "MAIN MENU", "run": func(): to_menu()},
		],
		kbd("ENTER") + " PICK",
	)


func retry_fight() -> void:
	G.hp = G.maxHp
	G.foe.hp = G.foe.maxHp
	G.foe.turn = 0
	G.foe.meters = Species.SPECIES[G.foe.species].start.duplicate()
	G.foe.lastIntent = ""
	start_encounter(G.foe)


func ending() -> void:
	G.mode = "end"
	_sfx_play("stairs")
	_music_sting("fanfare")
	var t: Dictionary = G.tally
	var met: int = t.spared + t.slain
	var route: String
	var text: String
	if met == 0:
		route = "THE GHOST ROUTE"
		text = "You slipped past everything. Nobody down here knows your name yet."
	elif t.slain == 0:
		route = "THE QUIET ROUTE"
		text = "Every monster you met is still alive, and some of them are following you down."
	elif t.spared == 0:
		route = "THE BLOOD ROUTE"
		text = "The halls go quiet behind you. On the next floor, the monsters will have heard."
	else:
		route = "THE TANGLED ROUTE"
		text = "Some you spared, some you didn't. The ones you spared saw what you did to the others."
	var tail := "Spared %d · slain %d · fled %d · recruited %d" % [t.spared, t.slain, t.fled, t.recruited]
	if t.left > 0:
		tail += " · %d walked out on you" % t.left
	if not G.allies.is_empty():
		var names := []
		for a in G.allies:
			names.append(a.name)
		tail += " · still with you: %s" % esc(", ".join(names))
	tail += ". In the full game the route carries into the next floor and the story's three acts."
	say(who(route + ".") + " " + esc(text) + "\n" + sys(tail))
	set_menu([{"label": "NEW FLOOR", "run": func(): new_run()}, {"label": "MAIN MENU", "run": func(): to_menu()}], kbd("ENTER") + " PICK")


# ---------------------------------------------------------------- clock

func _after(ms: float, fn: Callable) -> void:
	_timers.append({"at": now() + ms, "fn": fn})


## Advance the game to time `t` (ms): fire due timers, run the dodge, time out the strike bar
func tick(t: float) -> void:
	if not _timers.is_empty():
		var due := []
		var rest := []
		for e in _timers:
			(due if e.at <= t else rest).append(e)
		_timers = rest
		for e in due:
			e.fn.call()
	if G.mode == "dodge" and D != null:
		update_dodge(t)
	elif G.mode == "fightbar" and bar != null:
		if clampf((t - bar.t0) / bar.dur, 0.0, 1.0) >= 1.0:
			strike(t) # too late: a miss


# ---------------------------------------------------------------- drawing

func _paint_view(canvas: Control) -> void:
	draw_frame(Canvas2D.new(canvas, Vector2(W, H)), now())


func _paint_map(canvas: Control) -> void:
	var ctx := Canvas2D.new(canvas, Vector2(105, 105))
	if G.map == null:
		ctx.fill_style = "#000"
		ctx.fill_rect(0, 0, 105, 105)
		return
	Render.draw_map(ctx, G.map, G.seen, G.visited, G.x, G.y, G.dir)
	var s := floori(105.0 / G.map.n)
	for m in G.map.monsters:
		if J.truthy(m.gone) or m.boss or not G.seen.has(m.y * G.map.n + m.x):
			continue
		ctx.fill_style = Species.SPECIES[m.species].color
		ctx.fill_rect(m.x * s + 2, m.y * s + 2, s - 4, s - 4)


func draw_frame(ctx, t: float) -> void:
	if stage != null and G.mode != "explore" and G.mode != "end":
		stage.visible = false # the title and the battle screen are drawn flat
	ctx.save()
	if t < G.shake:
		ctx.translate((randf() - 0.5) * 6.0, (randf() - 0.5) * 6.0)
	if G.mode == "title":
		Render.draw_title(ctx, t, "PRESS ANY KEY")
		ctx.fill_style = C_YOU
		ctx.font = '8px "Press Start 2P", monospace'
		ctx.text_align = "center"
		ctx.fill_text("GENRE HALLS", W / 2.0, H * 0.55)
		ctx.fill_style = C_DIM
		ctx.fill_text(TITLE_HINT, W / 2.0, H * 0.82)
		ctx.text_align = "left"
	elif G.mode == "explore" or G.mode == "end":
		if stage != null:
			_draw_walk_3d(ctx, t)
		else:
			var seen: Array = Render.draw_corridor(ctx, G.map, G.x, G.y, G.dir, t)
			for c in seen:
				G.seen[c[1] * G.map.n + c[0]] = true
			draw_monsters_in_view(ctx, t)
	elif G.foe != null:
		Render.clear(ctx)
		if G.mode == "dodge" and D != null:
			draw_foe(ctx, t, true)
			draw_box(ctx, t)
		else:
			draw_foe(ctx, t, false)
			if G.mode == "fightbar":
				draw_bar(ctx, t)
			if G.mode == "intro":
				var a := clampf((intro_until - t) / 700.0, 0.0, 1.0)
				ctx.fill_style = Color(1, 1, 1, a * 0.5)
				ctx.fill_rect(0, 0, W, H)
		if D != null and t - D.blockFlash < 160.0:
			ctx.fill_style = Color(143 / 255.0, 211 / 255.0, 1.0, 0.22)
			ctx.fill_rect(0, 0, W, H)
			ctx.fill_style = C_YOU
			ctx.font = '8px "Press Start 2P", monospace'
			ctx.text_align = "center"
			ctx.fill_text("BOUNCY! THE SLIME TAKES THE HIT", W / 2.0, BY - 8)
			ctx.text_align = "left"
		if D != null and t - D.hitFlash < 120.0:
			ctx.fill_style = Color(1.0, 90 / 255.0, 74 / 255.0, 0.25)
			ctx.fill_rect(0, 0, W, H)
	ctx.restore()


## Walking: the corridor is the 3D set (the camera glides to each cell), the monsters stand in their cells with their
## name tags. Fights are the battle screen, drawn flat below.
func _draw_walk_3d(_ctx, t: float) -> void:
	stage.visible = true
	stage.use_map(G.map)
	stage.place(G.x, G.y, G.dir, t)
	stage.light(t)
	for c in stage.sight(G.map.grid, G.x, G.y):
		G.seen[c[1] * G.map.n + c[0]] = true
	# Every monster still on the floor stands in its cell with its genre over its head (3D text: the walls hide it,
	# like the monster, and it fades with distance)
	var list := []
	for i in G.map.monsters.size():
		var m: Dictionary = G.map.monsters[i]
		if J.truthy(m.gone):
			continue
		list.append({
			"id": i, "species": m.species, "look": {"color": BOSS_COLOR} if m.boss else {}, "x": m.x, "y": m.y,
			"label": "CHAMPION" if m.boss else Rules.GENRES[m.genre].name,
			"color": BOSS_COLOR if m.boss else Species.SPECIES[m.species].color,
		})
	stage.show_wanderers(list, t)


func draw_monsters_in_view(ctx, t: float) -> void:
	for v in monsters_in_view():
		var m: Dictionary = v.m
		var s := Render.scale_at(v.d + 0.5)
		var foot := Render.project(W, H, v.k, v.d + 0.5, 0.5)
		Art.draw_monster(ctx, m.species, t, 0.0, {"cx": foot.x, "s": s * 0.9, "by": foot.y}, 1, {"color": BOSS_COLOR} if m.boss else {})
		ctx.fill_style = BOSS_COLOR if m.boss else Species.SPECIES[m.species].color
		ctx.font = '8px "Press Start 2P", monospace'
		ctx.text_align = "center"
		ctx.fill_text("CHAMPION" if m.boss else Rules.GENRES[m.genre].name, foot.x, foot.y - 150 * s - 6)
		ctx.text_align = "left"


func draw_foe(ctx, t: float, small: bool) -> void:
	var m: Dictionary = G.foe
	var slot := {"cx": W / 2.0, "s": 0.27, "by": 76} if small else {"cx": W / 2.0, "s": 0.85, "by": 270}
	var hurt := 1.0 if t < hurt_until else 0.0
	Art.draw_monster(ctx, m.species, t, hurt, slot, 1, {"color": BOSS_COLOR} if m.boss else {})
	# name + health
	var can_spare: bool = not J.truthy(m.gone) and spareable(m)
	ctx.font = '8px "Press Start 2P", monospace'
	ctx.fill_style = "#ffd27a" if can_spare else "#e8e8e8"
	ctx.fill_text(str(m.name) + ("  (MERCY 50%+)" if can_spare else ""), 12, 20)
	ctx.fill_style = "#2e2e33"
	ctx.fill_rect(12, 26, 120, 6)
	ctx.fill_style = "#ff5a4a" if float(m.hp) / m.maxHp < 0.4 else "#9ed36b"
	ctx.fill_rect(12, 26, 120.0 * m.hp / m.maxHp, 6)
	ctx.fill_style = "#8a8a8a"
	ctx.text_align = "right"
	ctx.fill_text("TURN %d · %s" % [m.turn + 1, Rules.GENRES[foe_genre()].name] if m.boss else Rules.GENRES[m.genre].name, W - 12, 20)
	ctx.text_align = "left"


@warning_ignore("integer_division")
func draw_box(ctx, t: float) -> void:
	var accent: String = BOSS_COLOR if G.foe.boss else Species.SPECIES[G.foe.species].color
	# frame, with the beat pulsing it in rhythm fights
	var pulse: float = maxf(0.0, 1.0 - (t - D.pulse) / 180.0) if D.pulse > 0.0 else 0.0
	ctx.stroke_style = "#e8e8e8"
	ctx.line_width = 2.0 + pulse * 3.0
	ctx.stroke_rect(BX - 3, BY - 3, COLS * CELL + 6, ROWS * CELL + 6)
	ctx.line_width = 1.0
	for r in ROWS:
		for c in COLS:
			var k := Rules.idx(c, r)
			var x: float = BX + c * CELL
			var y: float = BY + r * CELL
			if D.blocked.has(k):
				ctx.fill_style = "#3a3a3a"
				ctx.fill_rect(x + 2, y + 2, CELL - 4, CELL - 4)
				ctx.stroke_style = "#a7a39b"
				ctx.stroke_rect(x + 2.5, y + 2.5, CELL - 5, CELL - 5)
				continue
			ctx.stroke_style = "#1c1c20"
			ctx.stroke_rect(x + 0.5, y + 0.5, CELL, CELL)
	# hazards: warning outlines, then filled when they land
	for h in D.hazards:
		var live: bool = t >= h.hit
		var prog := clampf((t - h.warn) / (h.hit - h.warn), 0.0, 1.0)
		var color: String = "#fff3b0" if h.kind == "light" else accent
		for k in h.cells:
			var x: float = BX + (k % COLS) * CELL
			var y: float = BY + (k / COLS) * CELL
			if live:
				ctx.global_alpha = 0.85
				ctx.fill_style = color
				ctx.fill_rect(x + 1, y + 1, CELL - 2, CELL - 2)
			else:
				ctx.global_alpha = 0.12 + 0.28 * prog
				ctx.fill_style = color
				ctx.fill_rect(x + 1, y + 1, CELL - 2, CELL - 2)
				ctx.global_alpha = 0.5 + 0.5 * absf(sin(t / 90.0))
				ctx.stroke_style = color
				ctx.stroke_rect(x + 3.5, y + 3.5, CELL - 7, CELL - 7)
		ctx.global_alpha = 1.0
		if h.has("glyph"):
			var gx: float = BX + (h.at % COLS) * CELL + CELL / 2.0
			var gy: float = BY + (h.at / COLS) * CELL + CELL / 2.0
			ctx.fill_style = "#000"
			ctx.fill_rect(gx - 11, gy - 11, 22, 22)
			ctx.fill_style = "#ffffff"
			ctx.font = '12px "Press Start 2P", monospace'
			ctx.text_align = "center"
			ctx.text_baseline = "middle"
			ctx.fill_text(h.glyph, gx, gy + 1)
			ctx.text_align = "left"
			ctx.text_baseline = "alphabetic"
		if h.kind == "goo" and not live:
			var gx: float = BX + (h.at % COLS) * CELL + CELL / 2.0
			var y0: float = BY + (h.at / COLS) * CELL + CELL / 2.0
			ctx.fill_style = accent
			ctx.begin_path()
			ctx.arc(gx, y0 - (1.0 - prog) * 70.0, 5, 0, 6.283)
			ctx.fill()
	# the lantern
	if D.genre == "shadow":
		var L := Rules.lantern_at(t - D.t0, D.intensity)
		var g = ctx.create_radial_gradient(L.x, L.y, 2, L.x, L.y, 40)
		g.add_color_stop(0, "rgba(255,243,176,0.9)")
		g.add_color_stop(1, "rgba(255,243,176,0)")
		ctx.fill_style = g
		ctx.begin_path()
		ctx.arc(L.x, L.y, 40, 0, 6.283)
		ctx.fill()
		ctx.fill_style = "#fff3b0"
		ctx.fill_rect(L.x - 3, L.y - 5, 6, 10)
	# you
	var sx: float = BX + D.soul.c * CELL + CELL / 2.0
	var sy: float = BY + D.soul.r * CELL + CELL / 2.0
	var blink: bool = t < D.iframes and floori(t / 70.0) % 2 == 0
	if not blink:
		ctx.fill_style = "#8fd3ff"
		ctx.begin_path()
		ctx.move_to(sx, sy - 8)
		ctx.line_to(sx + 8, sy)
		ctx.line_to(sx, sy + 8)
		ctx.line_to(sx - 8, sy)
		ctx.close_path()
		ctx.fill()
	# your charms
	if not G.allies.is_empty():
		ctx.font = '7px "Press Start 2P", monospace'
		ctx.fill_style = "#8a8a8a"
		ctx.fill_text("CHARMS", 12, BY + 8)
		for i in G.allies.size():
			var a: Dictionary = G.allies[i]
			var used: bool = a.species == "slime" and not D.shield
			ctx.fill_style = "#3a3a3a" if used else Species.SPECIES[a.species].color
			ctx.fill_text(Rules.CHARMS[a.species].name, 12, BY + 22 + i * 12)
	# time left
	var left := clampf((D.end - t) / (D.end - D.t0), 0.0, 1.0)
	ctx.fill_style = "#2e2e33"
	ctx.fill_rect(BX - 3, BY + ROWS * CELL + 8, COLS * CELL + 6, 3)
	ctx.fill_style = "#8a8a8a"
	ctx.fill_rect(BX - 3, BY + ROWS * CELL + 8, (COLS * CELL + 6) * left, 3)


func draw_bar(ctx, t: float) -> void:
	var x0 := 64
	var w := W - 128
	var y := 220
	ctx.fill_style = "#000"
	ctx.fill_rect(x0 - 6, y - 16, w + 12, 40)
	ctx.stroke_style = "#e8e8e8"
	ctx.line_width = 2.0
	ctx.stroke_rect(x0, y - 10, w, 28)
	ctx.fill_style = "#3a3a3a"
	ctx.fill_rect(x0 + w / 2.0 - 14, y - 9, 28, 26)
	ctx.fill_style = "#ffd27a"
	ctx.fill_rect(x0 + w / 2.0 - 2, y - 9, 4, 26)
	if bar == null:
		return
	var x := clampf((t - bar.t0) / bar.dur, 0.0, 1.0)
	ctx.fill_style = "#ffffff"
	ctx.fill_rect(x0 + x * w - 2, y - 14, 4, 36)


# ---------------------------------------------------------------- input

## `raw` is the JS key name: "ArrowUp", "Enter", "Escape", " ", or the typed character.
func on_key(raw: String) -> void:
	_sfx_init()
	if _tip != null and _tip_key == "foe":
		_hover_foe = false
		_hide_tip()
	var key: String = KEYMAP.get(raw, KEYMAP.get(raw.to_lower(), raw))
	var t := now()
	if G.mode == "title":
		if raw == "Escape" and to_menu():
			return
		new_run()
		return
	if G.mode == "explore":
		if key == "Escape":
			open_pause()
		elif key == "ArrowUp":
			step(1)
		elif key == "ArrowDown":
			step(-1)
		elif key == "ArrowLeft":
			G.dir = (G.dir + 3) % 4
		elif key == "ArrowRight":
			G.dir = (G.dir + 1) % 4
		return
	if G.mode == "dodge" and D != null:
		if key == "ArrowUp":
			move_soul(0, -1)
		elif key == "ArrowDown":
			move_soul(0, 1)
		elif key == "ArrowLeft":
			move_soul(-1, 0)
		elif key == "ArrowRight":
			move_soul(1, 0)
		return
	if G.mode == "fightbar":
		if key == "Enter" and bar != null:
			strike(t)
		return
	if G.mode in ["menu", "act", "result", "dead", "end"]:
		if G.mode == "end" and raw == "Escape" and to_menu():
			return
		if key == "ArrowUp" or key == "ArrowLeft":
			move_sel(-1)
		elif key == "ArrowDown" or key == "ArrowRight":
			move_sel(1)
		elif key == "Enter":
			if G.sel < G.menu.size():
				G.menu[G.sel].run.call()
		elif key == "Escape" and G.mode == "act":
			main_menu()
		elif key == "Escape" and G.mode == "menu":
			open_pause()
		elif key.length() == 1 and key >= "1" and key <= "9" and int(key) - 1 < G.menu.size():
			G.sel = int(key) - 1
			G.menu[G.sel].run.call()


## Esc on the title / route screen, or MAIN MENU on the pause menu
func to_menu() -> bool:
	if not ResourceLoader.exists(MENU_SCENE) or not is_inside_tree():
		return false
	left_for = "menu"
	if navigate:
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
	return true


func _input(event: InputEvent) -> void:
	if pause_open():
		return # the pause menu has the keys
	if _view_canvas == null or not event is InputEventKey or not event.pressed:
		return
	if event.meta_pressed or event.ctrl_pressed or event.alt_pressed:
		return
	if event.echo and G.mode != "dodge" and G.mode != "explore":
		return
	if _talk_in.has_focus():
		return # typing a line: the LineEdit has it (Esc is handled by its gui_input)
	var k := _js_key(event)
	if k == "":
		return
	get_viewport().set_input_as_handled()
	on_key(k)


static func _js_key(event: InputEventKey) -> String:
	match event.keycode:
		KEY_UP:
			return "ArrowUp"
		KEY_DOWN:
			return "ArrowDown"
		KEY_LEFT:
			return "ArrowLeft"
		KEY_RIGHT:
			return "ArrowRight"
		KEY_ENTER, KEY_KP_ENTER:
			return "Enter"
		KEY_ESCAPE:
			return "Escape"
		KEY_SPACE:
			return " "
	return char(event.unicode) if event.unicode > 31 else ""


func _on_talk_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_talk_in.accept_event()
		close_talk()
		act_menu()


func _on_view_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_view_motion(event)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		on_key("Enter")
	elif event is InputEventScreenTouch and event.pressed:
		on_key("Enter")


# ---------------------------------------------------------------- tooltips

func _on_menu_hover(i: int, on: bool) -> void:
	if on:
		_hover_item = i
		_kbd_nav = false
	elif _hover_item == i:
		_hover_item = -1
	_refresh_tip()


func _on_chip_hover(on: bool, i: int) -> void:
	if on:
		_show_tip("ally%d" % i, Rect2(), true)
	elif _tip_key == "ally%d" % i:
		_hide_tip()


## Decide which tooltip shows: the hovered ally or foe (they set their own), else the command under the mouse, or the
## highlighted one when the keys were used last. Commands without help show nothing.
func _refresh_tip() -> void:
	if _tip == null or _tip_key.begins_with("ally") or _tip_key == "foe" or _tip_key == "map":
		return
	var i: int = _hover_item if _hover_item >= 0 else (G.sel if _kbd_nav else -1)
	if i < 0 or i >= G.menu.size() or str(G.menu[i].get("sub", "")) == "" or G.mode == "dodge":
		_hide_tip()
		return
	var it: Control = _menu_grid.get_child(i) if i < _menu_grid.get_child_count() else null
	_show_tip("menu%d" % i, it.get_global_rect() if it != null else Rect2(), false)


## Show the tooltip for `key` (menu<i>, ally<i>, map or foe): above `anchor` (a command), or by the mouse. The content
## is only rebuilt when the key changes (or `force`); a mouse that just moves only moves the tooltip.
func _show_tip(key: String, anchor: Rect2, at_mouse: bool, force := false) -> void:
	if _tip == null:
		return
	if key != _tip_key or force or not _tip.visible:
		_clear(_tip_body)
		if key == "foe":
			_fill_mind_tip(_tip_body)
		elif key.begins_with("ally"):
			_fill_ally_tip(_tip_body, int(key.substr(4)))
		elif key == "map":
			_fill_map_tip(_tip_body)
		else:
			var text := _rich(_term, 18, C_INK)
			text.text = esc(G.menu[int(key.substr(4))].get("sub", ""))
			_tip_body.add_child(text)
		_tip_key = key
		_tip.visible = true
		_tip.modulate.a = 0.0 # wrapped text only knows its height after a layout pass: show it once it has one
		_refit_tip.call_deferred(key)
	_tip_anchor = anchor
	_tip_at_mouse = at_mouse
	_place_tip()


func _refit_tip(key: String) -> void:
	await get_tree().process_frame
	if _tip_key != key or _tip == null:
		return
	_tip.reset_size()
	_place_tip()
	_tip.modulate.a = 1.0


func _place_tip() -> void:
	var win := get_viewport_rect().size
	var mouse := get_global_mouse_position()
	var pos := mouse + Vector2(18, 18) if _tip_at_mouse else Vector2(_tip_anchor.position.x, _tip_anchor.position.y - _tip.size.y - 6)
	pos.x = clampf(pos.x, 6.0, maxf(6.0, win.x - _tip.size.x - 6.0))
	if pos.y + _tip.size.y > win.y - 6.0:
		pos.y = maxf(6.0, (mouse.y if _tip_at_mouse else _tip_anchor.position.y) - _tip.size.y - 12.0)
	_tip.position = pos


func _hide_tip() -> void:
	_tip_key = ""
	if _tip != null:
		_tip.visible = false


## Where the foe stands in the view (view coordinates), for hovering it
const FOE_RECT := Rect2(110, 20, 228, 258)


## The mouse over the view: the foe's tooltip while a fight waits on you, and moves with the mouse
func _on_view_motion(event: InputEventMouseMotion) -> void:
	_kbd_nav = false
	var p: Vector2 = event.position / _view_rect.size * Vector2(W, H)
	var over: bool = G.foe != null and G.mode in ["menu", "act", "result", "intro"] and FOE_RECT.has_point(p)
	if over:
		_hover_foe = true
		_show_tip("foe", Rect2(), true) # opens, then follows the mouse
	elif _hover_foe:
		_hover_foe = false
		_hide_tip()
		_refresh_tip()


# ---------------------------------------------------------------- building the page

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _style(bg: String, border: String, bw: int, mx := 0, my := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(bg)
	s.border_color = Color(border)
	s.set_border_width_all(bw)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s


func _label(text: String, font: Font, size: int, color: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rich(font: Font, size: int, color: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", font)
	r.add_theme_font_override("bold_font", _bold if font == _term else font)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", Color(color))
	r.add_theme_constant_override("line_separation", 0)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _stretch() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := ColorRect.new()
	bg.color = Color(C_BG)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# The 448x288 view: Canvas2D drawing in a SubViewport, shown scaled up
	_view_vp = SubViewport.new()
	_view_vp.size = Vector2i(W, H)
	_view_vp.disable_3d = Flags.test("flat")
	_view_vp.own_world_3d = true
	_view_vp.msaa_3d = Viewport.MSAA_4X
	_view_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_view_vp)
	if not _view_vp.disable_3d:
		stage = Stage3D.new()
		stage.visible = false
		_view_vp.add_child(stage)
	_view_canvas = DrawArea.new()
	_view_canvas.painter = _paint_view
	_view_canvas.custom_minimum_size = Vector2(W, H)
	_view_canvas.size = Vector2(W, H)
	_view_vp.add_child(_view_canvas)

	# ---- the CRT: one frame that fills the window (bar, view, text box)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var crt := PanelContainer.new()
	crt.add_theme_stylebox_override("panel", _style(C_BG, C_INK, 2, 14, 10))
	margin.add_child(crt)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	crt.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_where = _rich(_pix, 9, C_DIM)
	_route = _rich(_pix, 9, C_DIM)
	_route.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for r in [_where, _route]:
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_where)
	top.add_child(_route)
	col.add_child(top)
	var rule := ColorRect.new()
	rule.color = Color(C_INK)
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)

	# The stage takes whatever height the text box leaves; the view scales to fit it (kept 448:288)
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(320, 206)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stage)
	_view_rect = TextureRect.new()
	_view_rect.texture = _view_vp.get_texture()
	_view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_view_rect.gui_input.connect(_on_view_gui_input)
	_view_rect.mouse_exited.connect(func(): _hover_foe = false; if _tip_key == "foe": _hide_tip())
	var fit := AspectRatioContainer.new() ## the view keeps its 448:288 and takes the biggest size that fits the stage
	fit.ratio = float(W) / H
	fit.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(fit)
	fit.add_child(_view_rect)

	# automap: a small overlay in the view's top-right corner (it steps aside in a fight)
	_map_panel = PanelContainer.new()
	_map_panel.add_theme_stylebox_override("panel", _style(C_BG, C_FAINT, 1, 4, 4))
	_map_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	_map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_panel.mouse_entered.connect(func(): _show_tip("map", Rect2(), true))
	_map_panel.mouse_exited.connect(func(): if _tip_key == "map": _hide_tip())
	_view_rect.add_child(_map_panel)
	_map_canvas = DrawArea.new()
	_map_canvas.painter = _paint_map
	_map_canvas.custom_minimum_size = Vector2(105, 105)
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_panel.add_child(_map_canvas)

	# allies: chips in the bottom-left corner
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	_chips.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	_chips.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_rect.add_child(_chips)

	# ---- the text box: HP bar, log, commands
	var dock := VBoxContainer.new()
	dock.add_theme_constant_override("separation", 6)
	col.add_child(dock)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 12)
	_hp = _rich(_pix, 9, C_DIM)
	_hp.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hp.custom_minimum_size = Vector2(150, 0)
	hp_row.add_child(_hp)
	_hp_bar = HpBar.new()
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(_hp_bar)
	dock.add_child(hp_row)
	# Every part of the text box has a fixed height whatever it holds, so the view above never changes size between
	# exploring, a menu, the talk box and the dodge: a log of 3 lines, one slot for the talk box or two rows of commands,
	# and 2 lines of key hints.
	_say = _rich(_term, 20, C_INK)
	_say.fit_content = false
	_say.clip_contents = true
	_say.custom_minimum_size = Vector2(0, SAY_H)
	dock.add_child(_say)
	var slot := VBoxContainer.new()
	slot.add_theme_constant_override("separation", 6)
	slot.custom_minimum_size = Vector2(0, SLOT_H)
	slot.clip_contents = true
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(slot)

	_talk = HBoxContainer.new()
	_talk.add_theme_constant_override("separation", 8)
	_talk.visible = false
	slot.add_child(_talk)
	var talk_label := _label("SAY", _pix, 9, C_MERCY)
	talk_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_talk.add_child(talk_label)
	_talk_in = LineEdit.new()
	_talk_in.max_length = 140
	_talk_in.placeholder_text = "Anything. It answers to what it hears."
	_talk_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_talk_in.add_theme_font_override("font", _term)
	_talk_in.add_theme_font_size_override("font_size", 20)
	_talk_in.add_theme_color_override("font_color", Color(C_INK))
	_talk_in.add_theme_color_override("font_placeholder_color", Color(C_DIM))
	_talk_in.add_theme_color_override("caret_color", Color(C_YOU))
	_talk_in.add_theme_stylebox_override("normal", _style(C_BG, C_INK, 2, 8, 2))
	_talk_in.add_theme_stylebox_override("focus", _style(C_BG, C_YOU, 2, 8, 2))
	_talk_in.text_submitted.connect(submit_talk)
	_talk_in.gui_input.connect(_on_talk_gui_input)
	_talk.add_child(_talk_in)
	var send := Button.new()
	send.text = "SAY IT"
	send.focus_mode = Control.FOCUS_NONE
	send.add_theme_font_override("font", _pix)
	send.add_theme_font_size_override("font_size", 9)
	send.add_theme_color_override("font_color", Color(C_INK))
	send.add_theme_color_override("font_hover_color", Color(C_INK))
	send.add_theme_color_override("font_pressed_color", Color(C_YOU))
	send.add_theme_stylebox_override("normal", _style(C_BG, C_FAINT, 2, 10, 8))
	send.add_theme_stylebox_override("hover", _style(C_BG, C_INK, 2, 10, 8))
	send.add_theme_stylebox_override("pressed", _style(C_BG, C_YOU, 2, 10, 8))
	send.pressed.connect(func(): submit_talk(_talk_in.text))
	_talk.add_child(send)

	_menu_grid = GridContainer.new()
	_menu_grid.columns = 4
	_menu_grid.add_theme_constant_override("h_separation", 6)
	_menu_grid.add_theme_constant_override("v_separation", 6)
	slot.add_child(_menu_grid)
	_keys = _rich(_pix, 8, C_DIM)
	_keys.fit_content = false
	_keys.clip_contents = true
	_keys.add_theme_constant_override("line_separation", 6)
	_keys.custom_minimum_size = Vector2(0, KEYS_H)
	dock.add_child(_keys)

	# touch controls (the page shows these on coarse pointers)
	_pad = GridContainer.new()
	_pad.columns = 6
	_pad.add_theme_constant_override("h_separation", 6)
	_pad.add_theme_constant_override("v_separation", 6)
	_pad.visible = DisplayServer.is_touchscreen_available() or Flags.test("pad")
	dock.add_child(_pad)
	for spec in [["◀", "ArrowLeft"], ["▲", "ArrowUp"], ["▶", "ArrowRight"], ["", ""], ["OK", "Enter"], ["BACK", "Escape"], ["", ""], ["▼", "ArrowDown"]]:
		if spec[1] == "":
			var spacer := Control.new()
			_pad.add_child(spacer)
			continue
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(48, 44)
		b.add_theme_font_override("font", _pix)
		b.add_theme_font_size_override("font_size", 10)
		b.add_theme_stylebox_override("normal", _style(C_BG, C_FAINT, 2))
		b.add_theme_stylebox_override("pressed", _style(C_BG, C_YOU, 2))
		b.button_down.connect(on_key.bind(spec[1]))
		_pad.add_child(b)

	# the tooltip: above everything, never takes the mouse
	_tip = PanelContainer.new()
	_tip.top_level = true
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_theme_stylebox_override("panel", _style(C_BG, C_INK, 2, 12, 10))
	_tip_body = VBoxContainer.new()
	_tip_body.custom_minimum_size = Vector2(290, 0)
	_tip_body.add_theme_constant_override("separation", 6)
	_tip_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_body)
	add_child(_tip)


# ---------------------------------------------------------------- widgets

## A control that paints itself with a callback (so a Canvas2D can be made inside _draw)
class DrawArea:
	extends Control
	var painter: Callable

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


## One row of the mind panel: a label, a bar and a percent
class BarRow:
	extends Control
	var label := ""
	var p := 0.0
	var pick := false
	var ink_label := false
	var pct := ""
	var font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(0, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var asc := font.get_ascent(16)
		var base := (size.y - (asc + font.get_descent(16))) / 2.0 + asc
		var ink := Color("#e8e8e8")
		if label.contains("→"):
			# "YES → NO": the arrow is drawn small, the pixel font's own is a block
			var parts := label.split("→")
			var left: String = parts[0].strip_edges()
			var lw := font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, Vector2(0, base), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
			var ay := floorf(base - 5.0)
			draw_line(Vector2(lw + 5.0, ay), Vector2(lw + 14.0, ay), ink, 1.0)
			draw_line(Vector2(lw + 11.0, ay - 3.0), Vector2(lw + 14.0, ay), ink, 1.0)
			draw_line(Vector2(lw + 11.0, ay + 3.0), Vector2(lw + 14.0, ay), ink, 1.0)
			draw_string(font, Vector2(lw + 20.0, base), parts[1].strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
		else:
			draw_string(font, Vector2(0, base), label, HORIZONTAL_ALIGNMENT_LEFT, 92, 16, ink)
		var x0 := 98.0
		var x1 := size.x - 46.0
		var ty := floorf(size.y / 2.0 - 4.0)
		draw_rect(Rect2(x0, ty, maxf(0.0, x1 - x0), 8), Color("#2e2e33"))
		draw_rect(Rect2(x0, ty, maxf(0.0, x1 - x0) * clampf(p, 0.0, 1.0), 8), Color("#8fd3ff") if pick else Color("#8a8a8a"))
		draw_string(font, Vector2(size.x - 40.0, base), pct, HORIZONTAL_ALIGNMENT_RIGHT, 40, 16, Color("#8a8a8a"))


## The text box's bar: HP as a segmented-free bar, light blue, red once it is under 40%
class HpBar:
	extends Control
	var hp := 0
	var max_hp := 1

	func _init() -> void:
		custom_minimum_size = Vector2(0, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_hp(h: int, m: int) -> void:
		hp = h
		max_hp = maxi(1, m)
		queue_redraw()

	func _draw() -> void:
		var f := clampf(float(hp) / max_hp, 0.0, 1.0)
		var y := floorf(size.y / 2.0 - 6.0)
		draw_rect(Rect2(0, y, size.x, 12), Color("#2e2e33"))
		draw_rect(Rect2(0, y, size.x * f, 12), Color("#ff5a4a") if f < 0.4 else Color("#8fd3ff"))
		draw_rect(Rect2(0.5, y + 0.5, size.x - 1.0, 11.0), Color("#8a8a8a"), false, 1.0)


## An ally over the view: a colored dot and the charm's name; hover it for the charm's text
class AllyChip:
	extends Control
	signal hovered(on: bool)
	var dot := Color.WHITE
	var label := ""
	var warn := false
	var font: Font

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hovered.emit(true))
		mouse_exited.connect(func(): hovered.emit(false))

	func _ready() -> void:
		custom_minimum_size = Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 34.0, 24)

	func _draw() -> void:
		var edge := Color("#ff5a4a") if warn else Color("#2e2e33")
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), edge, false, 1.0)
		draw_rect(Rect2(8, size.y / 2.0 - 4.0, 8, 8), dot)
		draw_string(font, Vector2(24, size.y / 2.0 + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#ff5a4a") if warn else Color("#e8e8e8"))


## A command button: [> ] number label. Its help (`sub`) is the tooltip; `gold` lights SPARE at 50%+ mercy odds.
class MenuItem:
	extends Control
	signal picked(i: int)
	signal hovered(i: int, on: bool)
	var index := 0
	var label := ""
	var sub := ""
	var on := false
	var gold := false
	var hover := false
	var pix: Font

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): hover = true; hovered.emit(index, true); queue_redraw())
		mouse_exited.connect(func(): hover = false; hovered.emit(index, false); queue_redraw())

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 34)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			picked.emit(index)
		elif event is InputEventScreenTouch and event.pressed:
			accept_event()
			picked.emit(index)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#000000"))
		var border := Color("#e8e8e8") if (on or hover) else Color("#2e2e33")
		draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), border, false, 2.0)
		var asc := pix.get_ascent(10)
		var base := (size.y - (asc + pix.get_descent(10))) / 2.0 + asc
		var x := 12.0
		if on:
			draw_string(pix, Vector2(x, base), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8fd3ff"))
			x += 20.0
		draw_string(pix, Vector2(x, base), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8a8a8a"))
		x += 10.0 + 8.0
		draw_string(pix, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#ffd27a") if gold else Color("#e8e8e8"))
