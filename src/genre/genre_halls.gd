## DONJON: Genre Halls. Exploration is DONJON's wireframe maze; encounters switch into an Undertale-style box where each
## faction attacks in its own genre (chess, shadow, rhythm, goo rain), all with one rule: lit squares hurt.
## FIGHT / ACT / SPARE / FLEE. The monster's mind answers Jev-shaped questions (choice / score / yes-no with
## probabilities); here a local stand-in answers them. The rules live in genre_rules.gd; this file draws and plays.
## Port of crawler/public/genre-halls.js + genre-halls.html.
##
## Launch:  godot --path . res://src/genre/genre_halls.tscn [-- meet=slime]
## `meet=<species>` (slime, bandit, snake, rock, dragon) jumps straight into that faction's fight, like the
## console hook genreHalls.meet("rock"). Keys: arrows / WASD, Enter / Space / Z, Esc / X, 1-9 on the menus.
## Esc on the title or the route screen goes back to the main game (res://src/ui/main.tscn) when it exists.
##
## The screen is the HTML page's layout: the 448x288 view (Canvas2D, drawn in a SubViewport and shown scaled up) with
## a command box under it, and the automap, party and Jev mind panels beside it. The game logic is clock-driven:
## `tick(t)` advances it to time `t` (ms), `_process` feeds it the real clock, tests feed it a fake one
## (`clock_override`) and call `on_key(key)` with the JS key names ("ArrowUp", "Enter", "Escape", "1", ...).
extends Control

const J = preload("res://src/core/js.gd")
const Flags = preload("res://src/core/flags.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")
const Render = preload("res://src/view/render.gd")
const Art = preload("res://src/view/art.gd")
const Postfx = preload("res://src/view/postfx.gd")
const Species = preload("res://src/rules/species.gd")
const Emotions = preload("res://src/rules/emotions.gd")
const Rules = preload("res://src/genre/genre_rules.gd")

const MAIN_SCENE := "res://src/ui/main.tscn"
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
var _timers: Array = []
var _last_map := 0.0

var sfx = null
var postfx = null

# UI nodes
var _view_vp: SubViewport
var _view_canvas: DrawArea
var _view_rect: TextureRect
var _map_canvas: DrawArea
var _where: RichTextLabel
var _route: RichTextLabel
var _hp: RichTextLabel
var _say: RichTextLabel
var _keys: RichTextLabel
var _menu_grid: GridContainer
var _talk: HBoxContainer
var _talk_in: LineEdit
var _party_box: VBoxContainer
var _mind_who: Label
var _mind_box: VBoxContainer
var _pad: GridContainer
var _pix: Font
var _term: Font
var _bold: Font


func now() -> float:
	return clock_override if clock_override >= 0.0 else J.now_ms()


func _ready() -> void:
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
	_attach_postfx()
	render_party()
	say(sys("DONJON's dungeon, with Undertale-style encounters: every faction attacks in its own genre. Press any key or tap the view to start."))
	set_menu([], kbd("ANY KEY") + " START")
	hud()
	var species := Flags.capture("meet=(\\w+)")
	if species != "":
		meet(species)


func _process(_delta: float) -> void:
	if clock_override >= 0.0:
		return
	var t := now()
	tick(t)
	if postfx != null:
		postfx.render(t)
	_view_canvas.queue_redraw()
	if t - _last_map > 100.0:
		_last_map = t
		_map_canvas.queue_redraw()


# ---------------------------------------------------------------- soft dependencies (audio, post effects)

class NullSfx:
	extends RefCounted
	var on := false

	func init(_a = null, _b = null) -> void:
		pass

	func play(_name: String, _opts := {}) -> void:
		pass

	func shout(_line: String, _species: String, _opts := {}) -> void:
		pass


static func _soft(path: String):
	return load(path) if ResourceLoader.exists(path) else null


func _make_sfx():
	if Flags.test("nosound|nosfx"):
		return NullSfx.new()
	var scr = _soft("res://src/audio/sfx.gd")
	if scr == null:
		push_warning("genre halls: src/audio/sfx.gd is missing, playing silent")
		return NullSfx.new()
	var cls = scr.get_script_constant_map().get("Sfx")
	if cls == null:
		push_warning("genre halls: sfx.gd has no Sfx class, playing silent")
		return NullSfx.new()
	var s = cls.new(0.5)
	if s is Node:
		add_child(s)
	return s


func _sfx_init() -> void:
	if sfx != null and sfx.has_method("init"):
		sfx.init()


func _sfx_play(name: String, opts := {}) -> void:
	if sfx != null:
		sfx.play(name, opts)


## The view's CRT pass (glow, scanlines, hurt flash); the `nofx` flag shows the plain view
func _attach_postfx() -> void:
	if DisplayServer.get_name() == "headless":
		return # nothing is rendered, and the shader compiler has nothing to build for
	postfx = Postfx.PostFx.create({})
	if postfx != null:
		postfx.attach(_view_rect)


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
	G.tally = {"spared": 0, "slain": 0, "fled": 0, "recruited": 0, "left": 0}
	G.allies = []
	render_party()
	G.foe = null
	explore(sys("B1F. Four kinds of monster hold this floor, and each one fights by its own rules. Lit squares hurt. You can fight them, talk them down, or spare them, and a spared monster may join you."))


## The console hook: jump straight into that faction's fight
func meet(species := "bandit") -> void:
	if G.map == null:
		new_run()
	for m in G.map.monsters:
		if m.species == species and not J.truthy(m.gone):
			start_encounter(m)
			return


# ---------------------------------------------------------------- the mind (Jev-shaped questions, local answers)

func render_mind_append(m, rows: Array) -> void:
	var prev: Array = last_mind.answers if last_mind.m != null and is_same(last_mind.m, m) else []
	render_mind(m, prev + rows)


func render_mind(m, answers: Array) -> void:
	last_mind = {"m": m, "answers": answers}
	_mind_who.text = "%s · %s" % [m.name, str(Species.SPECIES[m.species].label).to_upper()] if m != null else "NOBODY YET"
	if m == null:
		return
	_clear(_mind_box)
	if not m.traits.is_empty():
		var note := _rich(_term, 16, C_DIM)
		note.text = "Seems %s." % esc(" and ".join(m.traits))
		_mind_box.add_child(note)
	var meters := GridContainer.new()
	meters.columns = 3
	meters.add_theme_constant_override("h_separation", 6)
	for pair in [["FRIENDLY", m.meters.friendliness], ["ANGER", m.meters.anger], ["FEAR", m.meters.fear]]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(_label(pair[0], _term, 16, C_DIM))
		cell.add_child(_label(str(J.round_js(pair[1])), _term, 20, C_INK))
		meters.add_child(cell)
	_mind_box.add_child(meters)
	for q in answers:
		_mind_box.add_child(_question(q))


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
		for r in rows.slice(0, 5):
			var name: String = Emotions.EMOTIONS[r[0]].label if Emotions.EMOTIONS.has(r[0]) else str(r[0]).to_upper()
			bars.add_child(_bar_row(name, r[1], r[0] == a.choice))
	elif a.type == "noul":
		var label := "YES"
		if a.has("yes"):
			label += " → YES" if a.yes else " → NO"
		bars.add_child(_bar_row(label, a.noul, true))
	else:
		for k in a.probabilities:
			bars.add_child(_bar_row("LEVEL %s" % k, a.probabilities[k], J.round_js(a.score) == int(k)))
	return box


func _bar_row(label: String, p: float, pick: bool) -> Control:
	var row := BarRow.new()
	row.label = label
	row.p = p
	row.pick = pick
	row.pct = "%d%%" % J.round_js(p * 100.0)
	row.font = _term
	return row


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
	_clear(_menu_grid)
	for i in items.size():
		var it := MenuItem.new()
		it.index = i
		it.label = items[i].label
		it.sub = items[i].get("sub", "")
		it.on = i == G.sel
		it.pix = _pix
		it.term = _term
		it.picked.connect(_on_menu_picked)
		_menu_grid.add_child(it)
	_keys.text = keys


func _on_menu_picked(i: int) -> void:
	_sfx_init()
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


func foe_genre() -> String:
	return Rules.BOSS.genres[G.foe.turn % Rules.BOSS.genres.size()] if G.foe.boss else G.foe.genre


func hud() -> void:
	if postfx != null:
		postfx.set_danger(clampf((0.5 - float(G.hp) / G.maxHp) * 2.0, 0.0, 1.0))
	_hp.text = "HP [color=%s]%d/%d[/color]" % [C_YOU, maxi(0, G.hp), G.maxHp]
	var spared: int = G.tally.spared
	var slain: int = G.tally.slain
	_route.text = "ROUTE [color=%s]%s[/color]" % [C_INK, "UNWRITTEN" if spared + slain == 0 else "%d SPARED · %d SLAIN" % [spared, slain]]
	_where.text = "B1F [color=%s]%s[/color]" % [C_INK, "%s ENCOUNTER" % Rules.GENRES[foe_genre()].name if G.foe != null else "THE GENRE HALLS"]


# ---------------------------------------------------------------- exploring

func explore(msg := "") -> void:
	G.mode = "explore"
	G.foe = null
	if postfx != null and G.map != null:
		postfx.set_accent(G.map.palette.accent)
	if msg != "":
		say(msg)
	set_menu([], kbd("↑") + kbd("↓") + " WALK  " + kbd("←") + kbd("→") + " TURN  · FIND THE STAIRS. MONSTERS SHOW ON THE MAP WHEN SEEN")
	hud()


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
		G.shake = now() + 160.0
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


## The monster standing straight ahead, if nothing blocks the view: { m, d } or null
func monster_ahead():
	var dir: Array = Render.DIRS[G.dir]
	for d in range(1, Render.VIEW):
		var cx: int = G.x + dir[0] * d
		var cy: int = G.y + dir[1] * d
		if not _open(cx, cy):
			return null
		var m = monster_at(cx, cy)
		if m != null:
			return {"m": m, "d": d}
	return null


# ---------------------------------------------------------------- encounters

func start_encounter(m: Dictionary) -> void:
	G.foe = m
	G.mode = "intro"
	G.sel = 0
	if postfx != null:
		postfx.set_accent(BOSS_COLOR if m.boss else Species.SPECIES[m.species].color)
	_sfx_play("boss" if m.boss else "encounter")
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
			{"label": "SPARE", "sub": "It looks ready to stop" if mercy >= 0.5 else "It isn't ready yet", "run": func(): spare()},
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
		items.append({"label": a.label, "run": func(): do_act(a)})
	if m.spoke:
		items.append({"label": "SAY SOMETHING", "sub": "Already spoke this fight", "run": func(): main_menu(sys("You've had your say this fight."))})
	else:
		items.append({"label": "SAY SOMETHING", "sub": "Optional: type once per fight", "run": func(): open_talk()})
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
	main_menu(sys("%s seems %s. Its kind likes %s and hates %s. This one may differ." % [esc(m.name), " and ".join(traits), ", ".join(likes), esc(sp.dislikes[0])]))


## One round of the mind: how it feels about `act` ("fight" or a list of { intent, w }), whether it would accept
## mercy, and how hard it attacks. Applies the feeling to its meters.
func decide(m: Dictionary, act, act_label: String, words = null) -> Dictionary:
	var feeling := Rules.ask_feeling(m, act)
	var em := Rules.apply_feeling(m, feeling.choice)
	var mercy := Rules.ask_mercy(m)
	var pressure := Rules.ask_pressure(m)
	var rows := []
	if words != null:
		rows.append({"id": "words", "label": "WHAT DID YOUR WORDS MEAN?", "a": words})
	rows.append({"id": "feeling", "label": "HOW DOES IT FEEL? (%s)" % act_label, "a": feeling})
	rows.append({"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "a": mercy})
	rows.append({"id": "pressure", "label": "HOW HARD DOES IT ATTACK?", "a": pressure})
	render_mind(m, rows)
	return {"em": em, "id": feeling.choice, "pressure": pressure.score, "pacified": Emotions.PACIFYING.has(em.get("cond"))}


func do_act(act: Dictionary) -> void:
	var m: Dictionary = G.foe
	var r := decide(m, [{"intent": act.intent, "w": 1}], act.label)
	judge(act.intent)
	_sfx_play("good" if r.em.tone == "good" else ("bad" if r.em.tone == "bad" else "odd"))
	after_player("%s %s is %s: %s." % [sys("You %s." % esc(act.label.to_lower())), esc(m.name), bold(r.em.label), esc(r.em.effect.to_lower())], r)


# ---------------------------------------------------------------- talking (optional, once per fight)

func open_talk() -> void:
	G.mode = "talk"
	_talk.visible = true
	_talk_in.text = ""
	set_menu([], "TYPE ANYTHING " + kbd("ENTER") + " SAY IT " + kbd("ESC") + " NEVER MIND · NONSENSE COUNTS TOO")
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
	var parts := []
	for k in words.probabilities:
		if k != "other" and words.probabilities[k] >= 0.12:
			parts.append({"intent": k, "w": words.probabilities[k]})
	var r := decide(m, parts if not parts.is_empty() else [{"intent": "question", "w": 0.3}], "YOUR WORDS", words)
	var top: String = words.choice
	judge(null if top == "other" else top)
	var extra := ""
	if top == "gibberish":
		extra = "\n" + sys("It didn't understand a word of that.")
	elif words.probabilities.question >= 0.25 and r.em.tone != "bad":
		extra = "\n" + who(esc(m.name) + ":") + " " + esc(hint_for(m))
	after_player("%s %s is %s: %s.%s" % [sys('You say "%s".' % esc(text)), esc(m.name), bold(r.em.label), esc(r.em.effect.to_lower()), extra], r)


# Talking can pay off in information: where the stairs are, or what another monster can't stand
func hint_for(m: Dictionary) -> String:
	var s: Dictionary = G.map.stairs
	var dir: String
	if absi(s.x - m.x) > absi(s.y - m.y):
		dir = "east" if s.x > m.x else "west"
	else:
		dir = "south" if s.y > m.y else "north"
	var pool := ["...the way down is to the %s." % dir]
	for o in G.map.monsters:
		if J.truthy(o.gone) or is_same(o, m):
			continue
		var worst: String = ""
		var best: String = ""
		for k in Rules.AFF[o.species]:
			if worst == "" or Rules.aff(o, k) < Rules.aff(o, worst):
				worst = k
			if best == "" or Rules.aff(o, k) > Rules.aff(o, best):
				best = k
		pool.append("...%s the %s? it hates %s. loves %s." % [o.name[0] + o.name.substr(1).to_lower(), Species.SPECIES[o.species].label, Rules.INTENT_WORDS[worst], Rules.INTENT_WORDS[best]])
	return J.pick(pool)


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


func render_party() -> void:
	_clear(_party_box)
	if G.allies.is_empty():
		var empty := _rich(_term, 18, C_DIM)
		empty.text = "Spare a monster and it may ask to join. Allies ride along as passive charms, and they leave if you cross their values."
		_party_box.add_child(empty)
		return
	for i in G.allies.size():
		var a: Dictionary = G.allies[i]
		var c: Dictionary = Rules.CHARMS[a.species]
		var mood := "DEVOTED" if a.loyalty >= 70 else ("CONTENT" if a.loyalty >= 45 else ("UNEASY" if a.loyalty >= 30 else "MAY LEAVE"))
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)
		if i > 0:
			var rule := ColorRect.new()
			rule.color = Color(C_FAINT)
			rule.custom_minimum_size = Vector2(0, 1)
			_party_box.add_child(rule)
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 4)
			_party_box.add_child(gap)
		var head := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.color = Color(Species.SPECIES[a.species].color)
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(dot)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(8, 0)
		head.add_child(pad)
		var nm := _label(a.name, _term, 18, C_INK)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		head.add_child(_label(mood, _term, 16, C_WARN if a.loyalty < 30 else C_DIM))
		card.add_child(head)
		var row := BarRow.new()
		row.label = c.name
		row.p = a.loyalty / 100.0
		row.pick = false
		row.ink_label = true
		row.pct = str(J.round_js(a.loyalty))
		row.font = _term
		card.add_child(row)
		var note := _rich(_term, 16, C_DIM)
		var cares: String = str(Species.SPECIES[a.species].values).split(".")[0].to_lower()
		note.text = "%s. Cares about: %s." % [esc(c.text), esc(cares)]
		card.add_child(note)
		_party_box.add_child(card)


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
	after_player("%s %s is %s: %s." % [sys("%s%d damage." % ["A perfect strike! " if crit else "", dmg]), esc(m.name), bold(r.em.label), esc(r.em.effect.to_lower())], r)


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
	after_player("%s %s isn't ready to stop. (%d%% it would have)" % [sys("You offer mercy."), esc(m.name), J.round_js(mercy.noul * 100.0)], r)


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


func defeat(m: Dictionary, how: String) -> void:
	m.gone = how
	G.tally[how] += 1
	if m.boss:
		G.map.boss.defeated = true
	_sfx_play("good" if how == "spared" else "kill")
	if postfx != null:
		postfx.flash(C_MERCY if how == "spared" else BOSS_COLOR, 0.4)
	var text := sys("%s falls." % esc(m.name))
	var joined := false
	if how == "spared":
		var f: float = m.meters.friendliness
		var room: bool = G.allies.size() < 3
		var p := Rules.sigmoid((f - m.threshold - 4.0) / 7.0 + Rules.aff(m, "join") * 0.4) if room else 0.0
		joined = randf() < p
		var rows := [{"id": "join", "label": "DOES IT WANT TO COME ALONG?" if room else "DOES IT WANT TO COME ALONG? (PARTY FULL)", "a": {"type": "noul", "noul": p, "yes": joined}}]
		render_mind(m, rows + pending_judgement.rows if pending_judgement != null else rows)
		if joined:
			G.allies.append({"species": m.species, "name": m.name, "loyalty": 60.0 + J.rnd(0, 20)})
			G.tally.recruited += 1
			_sfx_play("join")
			render_party()
		text = line(m, "join_party" if joined else "leave_peacefully")
	elif pending_judgement != null:
		render_mind(m, pending_judgement.rows)
	var notes := ""
	if pending_judgement != null and not pending_judgement.notes.is_empty():
		notes = "\n" + "\n".join(pending_judgement.notes)
	pending_judgement = null
	G.mode = "result"
	hud()
	var verdict: String
	if how == "spared":
		verdict = "SPARED. It joins you: %s, %s." % [Rules.CHARMS[m.species].name, Rules.CHARMS[m.species].text] if joined else "SPARED. It goes its own way."
	else:
		verdict = "SLAIN."
	say(text + "\n" + sys(verdict) + notes)
	set_menu([{"label": "CONTINUE", "run": func(): explore()}], kbd("ENTER") + " CONTINUE")


func after_player(msg: String, r: Dictionary) -> void:
	var m: Dictionary = G.foe
	if pending_judgement != null:
		msg += "\n" + "\n".join(pending_judgement.notes)
		render_mind_append(m, pending_judgement.rows)
		pending_judgement = null
	if r.pacified:
		main_menu(msg + "\n" + sys("It doesn't attack this turn."))
		return
	say(msg + "\n" + line(m, "attack"))
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
			G.shake = t + 200.0
			_sfx_play("hurt")
			hud()
			if G.hp <= 0:
				dead()
				return
	D.hazards = D.hazards.filter(func(h): return t < h.end)
	if t >= D.end:
		D = null
		G.foe.turn += 1
		main_menu(sys("%s pauses. %s" % [esc(G.foe.name), "It looks ready to stop." if spareable(G.foe) else "What now?"]))


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
		],
		kbd("ENTER") + " PICK",
	)


func retry_fight() -> void:
	G.hp = G.maxHp
	G.foe.hp = G.foe.maxHp
	G.foe.turn = 0
	G.foe.meters = Species.SPECIES[G.foe.species].start.duplicate()
	start_encounter(G.foe)


func ending() -> void:
	G.mode = "end"
	_sfx_play("stairs")
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
	set_menu([{"label": "NEW FLOOR", "run": func(): new_run()}], kbd("ENTER") + " PLAY AGAIN")


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
	ctx.save()
	if t < G.shake:
		ctx.translate((randf() - 0.5) * 6.0, (randf() - 0.5) * 6.0)
	if G.mode == "title":
		Render.draw_title(ctx, t, "PRESS ANY KEY")
		ctx.fill_style = C_YOU
		ctx.font = '8px "Press Start 2P", monospace'
		ctx.text_align = "center"
		ctx.fill_text("GENRE HALLS · PITCH DEMO", W / 2.0, H * 0.55)
		ctx.text_align = "left"
	elif G.mode == "explore" or G.mode == "end":
		var seen: Array = Render.draw_corridor(ctx, G.map, G.x, G.y, G.dir, t)
		for c in seen:
			G.seen[c[1] * G.map.n + c[0]] = true
		draw_monster_ahead(ctx, t)
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


func draw_monster_ahead(ctx, t: float) -> void:
	var a = monster_ahead()
	if a == null:
		return
	var m: Dictionary = a.m
	var z: float = a.d + 0.5
	var s := Render.scale_at(z)
	var by: float = H / 2.0 + ((H - 8) / 2.0) * s
	Art.draw_monster(ctx, m.species, t, 0.0, {"cx": W / 2.0, "s": s * 0.9, "by": by}, 1, {"color": BOSS_COLOR} if m.boss else {})
	ctx.fill_style = BOSS_COLOR if m.boss else Species.SPECIES[m.species].color
	ctx.font = '8px "Press Start 2P", monospace'
	ctx.text_align = "center"
	ctx.fill_text("CHAMPION" if m.boss else Rules.GENRES[m.genre].name, W / 2.0, by - 150 * s - 6)
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
	ctx.fill_text(str(m.name) + ("  (SPAREABLE)" if can_spare else ""), 12, 20)
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
	var key: String = KEYMAP.get(raw, KEYMAP.get(raw.to_lower(), raw))
	var t := now()
	if G.mode == "title":
		if raw == "Escape" and back_to_main():
			return
		new_run()
		return
	if G.mode == "explore":
		if key == "ArrowUp":
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
		if G.mode == "end" and raw == "Escape" and back_to_main():
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
		elif key.length() == 1 and key >= "1" and key <= "9" and int(key) - 1 < G.menu.size():
			G.sel = int(key) - 1
			G.menu[G.sel].run.call()


## Esc on the title / route screen: back to the main game, when it exists
func back_to_main() -> bool:
	if not ResourceLoader.exists(MAIN_SCENE) or not is_inside_tree():
		return false
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
	return true


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		on_key("Enter")
	elif event is InputEventScreenTouch and event.pressed:
		on_key("Enter")


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


func _section(title: String, small: String) -> Array:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(C_BG, C_FAINT, 2, 12, 10))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	var h := _label(title, _pix, 9, C_INK)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	var sm := _label(small, _pix, 9, C_DIM)
	head.add_child(sm)
	box.add_child(head)
	return [panel, box, sm]


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := ColorRect.new()
	bg.color = Color(C_FRAME)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# The 448x288 view: Canvas2D drawing in a SubViewport, shown scaled up
	_view_vp = SubViewport.new()
	_view_vp.size = Vector2i(W, H)
	_view_vp.disable_3d = true
	_view_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_view_vp)
	_view_canvas = DrawArea.new()
	_view_canvas.painter = _paint_view
	_view_canvas.custom_minimum_size = Vector2(W, H)
	_view_canvas.size = Vector2(W, H)
	_view_vp.add_child(_view_canvas)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var wrap := HBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 16)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(wrap)

	# ---- the CRT: bar, view, dock
	var crt := PanelContainer.new()
	crt.custom_minimum_size = Vector2(640, 0)
	crt.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	crt.add_theme_stylebox_override("panel", _style(C_BG, C_INK, 2, 12, 10))
	wrap.add_child(crt)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	crt.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_where = _rich(_pix, 9, C_DIM)
	_route = _rich(_pix, 9, C_DIM)
	_hp = _rich(_pix, 9, C_DIM)
	_route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for r in [_where, _route, _hp]:
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
		r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(_where)
	top.add_child(_stretch())
	top.add_child(_route)
	top.add_child(_stretch())
	top.add_child(_hp)
	col.add_child(top)
	var rule := ColorRect.new()
	rule.color = Color(C_INK)
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)

	_view_rect = TextureRect.new()
	_view_rect.texture = _view_vp.get_texture()
	_view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view_rect.custom_minimum_size = Vector2(612, 612.0 * H / W)
	_view_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_view_rect.gui_input.connect(_on_view_gui_input)
	col.add_child(_view_rect)

	var dock := VBoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	dock.custom_minimum_size = Vector2(0, 150)
	col.add_child(dock)
	_say = _rich(_term, 20, C_INK)
	_say.custom_minimum_size = Vector2(0, 66)
	dock.add_child(_say)

	_talk = HBoxContainer.new()
	_talk.add_theme_constant_override("separation", 8)
	_talk.visible = false
	dock.add_child(_talk)
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
	_menu_grid.columns = 2
	_menu_grid.add_theme_constant_override("h_separation", 6)
	_menu_grid.add_theme_constant_override("v_separation", 6)
	dock.add_child(_menu_grid)
	_keys = _rich(_pix, 8, C_DIM)
	_keys.add_theme_constant_override("line_separation", 6)
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

	# ---- the side panels: automap, party, mind
	var aside := ScrollContainer.new()
	aside.custom_minimum_size = Vector2(330, 0)
	aside.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	aside.size_flags_vertical = Control.SIZE_FILL
	wrap.add_child(aside)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aside.add_child(side)

	var automap := _section("AUTOMAP", "B1F")
	side.add_child(automap[0])
	var mapbox := HBoxContainer.new()
	mapbox.add_theme_constant_override("separation", 12)
	automap[1].add_child(mapbox)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_theme_stylebox_override("panel", _style(C_BG, C_FAINT, 1))
	mapbox.add_child(frame)
	_map_canvas = DrawArea.new()
	_map_canvas.painter = _paint_map
	_map_canvas.custom_minimum_size = Vector2(105, 105)
	frame.add_child(_map_canvas)
	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 3)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mapbox.add_child(legend)
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
		legend.add_child(li)

	var party := _section("PARTY", "CHARMS")
	side.add_child(party[0])
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 4)
	party[1].add_child(_party_box)

	var mind := _section("JEV MIND", "NOBODY YET")
	side.add_child(mind[0])
	_mind_who = mind[2]
	_mind_box = VBoxContainer.new()
	_mind_box.add_theme_constant_override("separation", 8)
	mind[1].add_child(_mind_box)
	var empty := _rich(_term, 18, C_DIM)
	empty.text = "Meet a monster. Every choice it makes shows up here as a typed decision with its odds."
	_mind_box.add_child(empty)
	var note := _rich(_term, 16, C_DIM)
	note.text = "Offline stand-in with the same question shapes (choice, score, yes/no): typed words are read by keyword cues here. In [url=main][color=%s]the main game[/color][/url] these questions go to Jev." % C_YOU
	note.meta_clicked.connect(func(_m): back_to_main())
	mind[1].add_child(note)


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
		draw_string(font, Vector2(0, base), label, HORIZONTAL_ALIGNMENT_LEFT, 92, 16, Color("#e8e8e8") if (pick or ink_label) else Color("#e8e8e8"))
		var x0 := 98.0
		var x1 := size.x - 46.0
		var ty := floorf(size.y / 2.0 - 4.0)
		draw_rect(Rect2(x0, ty, maxf(0.0, x1 - x0), 8), Color("#2e2e33"))
		draw_rect(Rect2(x0, ty, maxf(0.0, x1 - x0) * clampf(p, 0.0, 1.0), 8), Color("#8fd3ff") if pick else Color("#8a8a8a"))
		draw_string(font, Vector2(size.x - 40.0, base), pct, HORIZONTAL_ALIGNMENT_RIGHT, 40, 16, Color("#8a8a8a"))


## A command button: [> ] number label, and a dim line under it
class MenuItem:
	extends Control
	signal picked(i: int)
	var index := 0
	var label := ""
	var sub := ""
	var on := false
	var hover := false
	var pix: Font
	var term: Font

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_entered.connect(func(): hover = true; queue_redraw())
		mouse_exited.connect(func(): hover = false; queue_redraw())

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 56 if sub != "" else 34)

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
		var base := 10.0 + (14.0 - (asc + pix.get_descent(10))) / 2.0 + asc
		var x := 12.0
		if on:
			draw_string(pix, Vector2(x, base), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8fd3ff"))
			x += 20.0
		draw_string(pix, Vector2(x, base), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8a8a8a"))
		x += 10.0 + 8.0
		draw_string(pix, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#e8e8e8"))
		if sub != "":
			var sa := term.get_ascent(16)
			draw_string(term, Vector2(12.0, 10.0 + 14.0 + 4.0 + sa), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 16, Color("#8a8a8a"))
