## The rules and flow of Donjon: game.js without its drawing and DOM. The run, exploring, fights (D&D 5e-style
## dice), talking and recruiting, vows, boons, the Roll of Fate, test runs, debug hooks, and every Jev request.
##
## `G` is the run's state, a Dictionary with exactly the JS shape; the ui (src/ui/) draws it and turns input into
## `key(k)`. The game reaches the ui only through `ui.<hook>()` and sound only through the objects main hands it
## before `start()`: ui, music, sfx, narrator, voice, tips, ach (and optionally store).
## The presentation state the ui draws and subscribes to lives here: `fx` (the juice bus), `floaters`, `dice`,
## `hurt_until`, `api_log`.
extends Node

const J = preload("res://src/core/js.gd")
const Flags = preload("res://src/core/flags.gd")
const Species = preload("res://src/rules/species.gd")
const Dnd = preload("res://src/rules/dnd.gd")
const Status = preload("res://src/rules/status.gd")
const Tutorial = preload("res://src/rules/tutorial.gd")
const Narrate = preload("res://src/rules/narrate.gd")
const Juice = preload("res://src/rules/juice.gd")
const Dice = preload("res://src/rules/dice.gd")
const Render = preload("res://src/view/render.gd")
const Art = preload("res://src/view/art.gd")
const JevApi = preload("res://src/jev/api.gd")
const JevConfig = preload("res://src/jev/config.gd")
const Floors = preload("res://src/game/floors.gd")

## askText's `undefined`: the talk box was cancelled (Esc), as opposed to `null`, submitted empty
static var UNDEFINED := Cancelled.new()


class Cancelled:
	extends RefCounted

	func _to_string() -> String:
		return "<cancelled>"


# ---------------------------------------------------------------- handed in by main before start()
var ui = null
var music = null
var sfx = null
var narrator = null
var voice = null
var tips = null
var ach = null
## localStorage: the Store autoload unless set (tests pass Store.Memory)
var store = null

# ---------------------------------------------------------------- presentation state (the ui draws it)
## The rules announce combat moments and moves as events (juice.gd FX_EVENTS); the ui answers them
var fx = Juice.create_bus()
## Numbers and words that float up from monsters and party members: {text, x, y, color, size, t0}
var floaters := []
## Every d20 the player sees tumbles on the view (dice.gd)
var dice = Dice.DicePops.new()
## Hurt flash windows by enemy id: [until - 300, until)
var hurt_until := {}
## In debug mode every API call, newest first, for the Jev panel's REQUESTS tab
var api_log := []
var api_seq := 0
## Developer mode: the Jev mind panel (J), [DEBUG] log lines, the debug_* hooks
var DEBUG := false

# ---------------------------------------------------------------- state
var G = null
var uid := 0
var started := false
## What the ui's keyboard handler maps before calling key(): e.key.toLowerCase() -> the game's names
const KEYMAP = {
	"arrowup": "fwd",
	"w": "fwd",
	"arrowdown": "back",
	"s": "back",
	"arrowleft": "turnL",
	"a": "turnL",
	"arrowright": "turnR",
	"d": "turnR",
}

## Dice: what a roll causes is held back by fx_lag so it lands together with the die, not before it
var fx_lag := 0.0
var last_rattle := -INF
## Test seam: every sleep is multiplied by this (tests set 0, so a fight plays out in frames, not seconds)
var sleep_scale := 1.0
## Test seam: replaces JevApi.handle (path, body, opts) -> {status, body} when valid
var api_handler := Callable()

const SHINY_CHANCE := 0.15 # each monster you meet has this chance to be a rare shiny gold variant
const MAX_VOWS := 6

const VERBS = [
	{"id": "kill", "label": "KILL"},
	{"id": "talk", "label": "TALK TO"},
	{"id": "give", "label": "GIVE GOLD TO"},
	{"id": "run", "label": "RUN FROM"},
	{"id": "befriend", "label": "BEFRIEND"},
]
const TARGETS = [
	{"id": "slime", "label": "SLIMES"},
	{"id": "goblin", "label": "GOBLINS"},
	{"id": "dragon", "label": "DRAGONS"},
	{"id": "snake", "label": "SNAKE PEOPLE"},
	{"id": "rock", "label": "ROCK ENTITIES"},
	{"id": "bandit", "label": "BANDITS"},
	{"id": "monsters", "label": "ANYONE"},
]
## Which game events break a vow. Vows are structured, so code checks them exactly.
const BREAKS = {
	"kill": {"will": ["spare"], "wont": ["kill"]},
	"talk": {"will": ["attack_unspoken"], "wont": ["talk"]},
	"give": {"will": ["kill"], "wont": ["give"]},
	"run": {"will": ["attack"], "wont": ["flee"]},
	"befriend": {"will": ["kill"], "wont": ["recruit"]},
}

## The Roll of Fate's boons: {name, weight, target: member|caster|party|global, valid?: Callable(m), apply: Callable(x, tier)}
var BOONS := []
## Only a champion's great roll can land these.
var LEGENDARY := []


func _init() -> void:
	BOONS = [
		{"name": "WHETSTONE", "weight": 5, "target": "member", "apply": _boon_whetstone},
		{"name": "KEEN EYE", "weight": 4, "target": "member", "valid": func(m): return m.mods.critMin > 15, "apply": _boon_keen_eye},
		{"name": "TRUE AIM", "weight": 3, "target": "member", "apply": _boon_true_aim},
		{"name": "FLURRY", "weight": 3, "target": "member", "valid": _strikes_more, "apply": _boon_flurry},
		{"name": "IRON SKIN", "weight": 3, "target": "member", "apply": _boon_iron_skin},
		{"name": "VAMPIRIC EDGE", "weight": 2, "target": "member", "valid": func(m): return m.get("clsId") != "wizard", "apply": _boon_vampiric},
		{"name": "ARCANE SURGE", "weight": 3, "target": "caster", "apply": _boon_arcane_surge},
		{"name": "VIGOR", "weight": 4, "target": "party", "apply": _boon_vigor},
		{"name": "GOLDEN TOUCH", "weight": 2, "target": "global", "apply": _boon_golden_touch},
	]
	LEGENDARY = [
		{"name": "PHOENIX FEATHER", "weight": 3, "target": "global", "apply": _boon_phoenix},
		{"name": "LEGENDARY ARMS", "weight": 3, "target": "party", "apply": _boon_legendary_arms},
		{"name": "ARCHMAGE'S CROWN", "weight": 2, "target": "caster", "apply": _boon_archmage},
		{"name": "TITAN'S BLOOD", "weight": 3, "target": "party", "apply": _boon_titans_blood},
		{"name": "TWIN SOUL", "weight": 2, "target": "member", "valid": _strikes_more, "apply": _boon_twin_soul},
	]


func _ready() -> void:
	if store == null:
		store = _default_store()
	init_debug()


func _default_store():
	var loop := Engine.get_main_loop() as SceneTree
	var s = loop.root.get_node_or_null("Store") if loop else null
	if s == null:
		push_warning("game: no Store autoload, keeping this session's data in memory")
		s = preload("res://src/core/store.gd").Memory.new()
	return s


## Debug mode: on with ?debug / #debug (or `debug` on the command line), localStorage donjon.debug = "1", or the
## build's Jev config; `nodebug` turns it off for one run.
func init_debug() -> void:
	var cfg_debug: bool = _jev_config().get("debug") == true
	DEBUG = not Flags.test("nodebug") and (Flags.test("debug") or (store != null and store.get_item("donjon.debug") == "1") or cfg_debug)
	print_verbose("debug mode %s" % ("on" if DEBUG else "off"))


# ---------------------------------------------------------------- small helpers (JS idioms)

func _sleep(ms: float) -> void:
	await J.sleep(ms * sleep_scale)


## setTimeout(fn, ms)
func _later(ms: float, fn: Callable) -> void:
	await _sleep(ms)
	fn.call()


static func UP(s) -> String:
	return str(s).to_upper()


## A string the player typed (not null, not cancelled, not empty)
static func _said(t) -> bool:
	return t is String and t != ""


## arr.indexOf(x) by identity (party members and enemies are Dictionaries, compared by value otherwise)
static func index_of(arr: Array, x) -> int:
	for i in arr.size():
		if is_same(arr[i], x):
			return i
	return -1


static func _without(arr: Array, x) -> Array:
	return arr.filter(func(m): return not is_same(m, x))


## String.prototype.replace with a string pattern: the first occurrence only
static func _replace_first(s: String, what: String, with: String) -> String:
	var at := s.find(what)
	return s if at < 0 else s.substr(0, at) + with + s.substr(at + what.length())


## Number.prototype.toFixed(d)
static func to_fixed(x, d: int) -> String:
	return ("%." + str(d) + "f") % float(x)


static func signed(n) -> String:
	return "+%s" % J.num(n) if n >= 0 else J.num(n)


## Math.max(...arr, floor_value)
static func _max_of(arr: Array, floor_value = -INF):
	var best = floor_value
	for v in arr:
		if v > best:
			best = v
	return best


## The talk box's number: Number(text) || 0
static func _js_number(t) -> float:
	if not (t is String):
		return 0.0
	var s := (t as String).strip_edges()
	if s == "":
		return 0.0
	return s.to_float() if s.is_valid_float() else 0.0


## Meters and loyalty stay within 0..100, whole numbers
static func clamp100(v) -> int:
	return maxi(0, mini(100, J.round_js(v)))


## A number from Jev as JS would show it: 45.0 -> 45 (JSON numbers are floats in Godot)
static func _n(x):
	return int(x) if x is float and is_finite(x) and x == floor(x) else x


## JSON.stringify drops undefined: a key only when there's a value
static func _put(d: Dictionary, k: String, v) -> Dictionary:
	if v != null:
		d[k] = v
	return d


func hint(id: String) -> void:
	tips.hint(id)


## Log lines for developers only, e.g. the numbers behind a feeling or a loyalty change.
func dbg(text: String) -> void:
	if DEBUG:
		say("[DEBUG] %s" % text, "dim")


# ---------------------------------------------------------------- Jev

## How Jev is reached (src/jev/config.gd decides once): {provider, debug, warning, ...}
func _jev_config() -> Dictionary:
	return JevConfig.setup()


## One call to the game's API. In debug mode every call is recorded for the REQUESTS tab, with the raw Jev calls
## behind it. Returns the reply body, or {error, status} where the JS threw (callers say JEV UNREACHABLE).
func api(path: String, body = null) -> Dictionary:
	if body == null:
		body = {}
	var entry = null
	if DEBUG:
		api_seq += 1
		entry = {"n": api_seq, "path": path, "at": J.date_ms(), "request": body.duplicate(true), "status": null, "ms": null, "jev": null}
	var t0 := J.now_ms()
	if entry != null:
		record_request(entry)
	var opts := {"debug": DEBUG}
	var res
	if api_handler.is_valid():
		res = await api_handler.call(path, body.duplicate(true), opts)
	else:
		res = await JevApi.handle(path, body.duplicate(true), opts)
	var out = res.get("body") if res is Dictionary else null
	var result: Dictionary
	if not (res is Dictionary) or not (out is Dictionary):
		result = {"error": "no reply from %s" % path, "status": "FAILED"}
		if entry != null:
			entry.merge({"status": "FAILED", "ms": J.round_js(J.now_ms() - t0), "error": result.error}, true)
	else:
		var clean: Dictionary = out.duplicate()
		clean.erase("_debug")
		var status = res.get("status", 200)
		var trace = out.get("_debug")
		if entry != null:
			entry.merge({"status": status, "ms": J.round_js(J.now_ms() - t0), "response": clean, "jev": trace.get("jev") if trace is Dictionary else null}, true)
		if status is int and status >= 200 and status < 300:
			result = clean
		else:
			result = {"error": str(out.get("error")) if J.truthy(out.get("error")) else "HTTP %s" % J.num(status), "status": status}
			if entry != null:
				entry.error = result.error
	if entry != null:
		var calls = entry.jev
		print_verbose("api #%d %s %s %sms, %s jev calls" % [entry.n, path, entry.status, entry.ms, str(calls.size()) if calls is Array else "no"])
		ui.render_requests()
	if result.has("error"):
		push_warning("api %s: %s" % [path, result.error])
	return result


func record_request(entry: Dictionary) -> void:
	api_log.push_front(entry)
	if api_log.size() > 100:
		api_log.pop_back()
	ui.render_requests()


# ---------------------------------------------------------------- the party

## A D&D-style adventurer: ability modifiers, armor class, a weapon, and spell slots if they cast.
func human(name: String, cls_id: String) -> Dictionary:
	var c: Dictionary = Dnd.CLASSES[cls_id]
	var hp: int = c.hitDie + c.abil.con
	var m := {
		"id": "h%d" % uid,
		"name": name,
		"kind": "human",
		"clsId": cls_id,
		"cls": c.code,
		"hp": hp,
		"maxHp": hp,
		"ac": c.ac,
		"abil": c.abil.duplicate(),
		"dead": false,
		"down": false,
		"level": 1,
		"xp": 0,
		"mods": base_mods(),
		"cond": {},
		"uses": {},
	}
	uid += 1
	if c.caster != null:
		m.bonusSlots = [0, 0, 0]
		refresh_slots(m, true)
	restore_uses(m)
	return m


## Fighters get Second Wind and Action Surge back on a rest.
static func restore_uses(m: Dictionary) -> void:
	if m.get("clsId") == "fighter":
		m.uses = {"second_wind": 1, "action_surge": 1}


## Spell slots follow the 5e table for the caster's level, plus any extra slots from boons.
static func refresh_slots(m: Dictionary, fill := false) -> void:
	var old: Array = m.get("maxSlots", [])
	var prev: Array = m.get("slots", [])
	var table: Array = Dnd.slots_for(m.level)
	var max_slots := []
	for i in table.size():
		max_slots.append(table[i] + (m.bonusSlots[i] if i < m.bonusSlots.size() else 0))
	m.maxSlots = max_slots
	var slots := []
	for i in max_slots.size():
		var n: int = max_slots[i]
		if fill:
			slots.append(n)
		else:
			slots.append(mini(n, (prev[i] if i < prev.size() else 0) + maxi(0, n - (old[i] if i < old.size() else 0))))
	m.slots = slots


static func slot_total(m: Dictionary) -> int:
	var t := 0
	for n in m.maxSlots:
		t += n
	return t


## A spell slot count, 0 where the caster has no slots of that circle
static func _slot(m: Dictionary, i: int) -> int:
	var s = m.get("slots")
	return s[i] if s is Array and i < s.size() else 0


## Per-member modifiers from the Roll of Fate. They compound as you go deeper.
static func base_mods() -> Dictionary:
	return {"dmg": 1, "critMin": 20, "hits": 1, "lifesteal": 0, "spell": 1, "hitBonus": 0}


# ---------------------------------------------------------------- depth scaling and levels
# Enemies get much tougher each floor, to balance compounding boons; damage grows more gently.

static func hp_scale(f) -> float:
	return pow(1.3, f - 1)


static func dmg_scale(f) -> float:
	return pow(1.1, f - 1)


static func xp_for(level) -> int:
	return J.round_js(30 * pow(level, 1.6))


func level_up(m: Dictionary) -> void:
	m.xp -= xp_for(m.level)
	m.level += 1
	var notes := []
	if m.kind == "human":
		var c: Dictionary = Dnd.CLASSES[m.clsId]
		var gain: int = floori(c.hitDie / 2.0) + 1 + m.abil.con
		m.maxHp += gain
		if not m.down:
			m.hp = mini(m.maxHp, m.hp + gain + ceili(m.maxHp * 0.25))
		if m.clsId == "fighter" and m.level == 5:
			notes.append("EXTRA ATTACK: SWINGS TWICE A TURN")
		if c.caster != null:
			var before: Array = Dnd.spells_known(m.clsId, m.level - 1)
			refresh_slots(m)
			var learned: Array = Dnd.spells_known(m.clsId, m.level).filter(func(k): return not before.has(k))
			if not learned.is_empty():
				notes.append("LEARNS %s" % ", ".join(learned.map(func(k): return Dnd.SPELLS[k].name)))
			if m.level == 5:
				notes.append("FREE SPELLS NOW ROLL 2 DICE OF DAMAGE")
		if m.level % 4 == 1:
			notes.append("TRAINING BONUS +%d TO ATTACKS, SPELLS AND TALKING" % Dnd.prof(m.level))
	else:
		var gain: int = 3 + floori(m.level / 2.0)
		m.maxHp += gain
		if not m.down:
			m.hp = mini(m.maxHp, m.hp + gain + ceili(m.maxHp * 0.25))
		m.dmg = [m.dmg[0] + (0 if m.level % 2 else 1), m.dmg[1] + 1]
	say("%s REACHES LEVEL %d!%s" % [m.name, m.level, (" %s." % ". ".join(notes)) if not notes.is_empty() else ""], "big", color_of(m) if m.kind == "monster" else null)
	sfx.play("levelup")


## Everyone still alive learns from the fight.
func grant_xp(xp: int) -> void:
	for m in living():
		m.xp += xp
		while m.xp >= xp_for(m.level):
			level_up(m)
			hint("levelup")


func living() -> Array:
	return G.party.filter(func(m): return not m.dead)


func conscious() -> Array:
	return G.party.filter(func(m): return not m.dead and not m.down)


func allies() -> Array:
	return G.party.filter(func(m): return m.kind == "monster" and not m.dead)


func humans_alive() -> bool:
	return G.party.any(func(m): return m.kind == "human" and not m.dead)


func leader():
	var up := conscious()
	for m in up:
		if m.kind == "human":
			return m
	if not up.is_empty():
		return up[0]
	var alive := living()
	return alive[0] if not alive.is_empty() else null


## The party's best talker who is still standing does the talking (Charisma checks).
func face():
	var best = null
	for m in conscious():
		if m.kind == "human" and (best == null or m.abil.cha > best.abil.cha):
			best = m
	return best


static func color_of(m: Dictionary) -> String:
	if m.get("boss"):
		return Art.BOSS_COLOR
	if m.get("shiny"):
		return Art.SHINY_COLOR
	return Species.SPECIES[m.species].color


static func a_label(species: String) -> String:
	var label: String = Species.SPECIES[species].label
	return "%s %s" % ["an" if label.left(1) in ["a", "e", "i", "o", "u"] else "a", label]


static func loyalty_word(l) -> String:
	return Status.loyalty_state(l).word


## What the party panel shows on hover for a member: level, experience, boons. "" when it has no boon mods.
static func boon_title(m: Dictionary) -> String:
	var md = m.get("mods")
	if md == null:
		return ""
	var level = J.nz(m.get("level"), 1)
	var bits := [
		"LEVEL %s" % J.num(level),
		"EXPERIENCE %s OF %d TO THE NEXT LEVEL" % [J.num(J.nz(m.get("xp"), 0)), xp_for(level)],
		"DAMAGE X%s" % to_fixed(md.dmg, 2),
		"CRITICAL HITS ON A %s" % ("20" if md.critMin == 20 else "%s-20" % J.num(md.critMin)),
	]
	if md.hits > 1:
		bits.append("STRIKES %s TIMES A TURN" % J.num(md.hits))
	if m.get("abil") != null:
		var words := []
		for k in m.abil:
			words.append("%s %s" % [Dnd.ABILITY_WORDS[k], signed(m.abil[k])])
		bits.append(" ".join(words))
	if J.truthy(md.hitBonus):
		bits.append("+%s TO HIT" % J.num(md.hitBonus))
	if J.truthy(md.lifesteal):
		bits.append("HEALS %d%% OF THE DAMAGE IT DEALS" % J.round_js(md.lifesteal * 100))
	if m.get("phoenix"):
		bits.append("WILL CHEAT DEATH ONCE")
	return " · ".join(bits)


# ---------------------------------------------------------------- waiting for the player (prompt / menu / text)

## A yes/no question. It shows as a lit-up box over the view, and any other key shakes it rather than being
## silently ignored. `walkAway`: moving answers no and moves. `no: null`: yes is the only answer (the guided first
## fight's recruit); N and Esc shake it too. Returns true / false.
func ask(text: String, opts := {}):
	var w := J.Waiter.new()
	G.prompt = {"text": text, "waiter": w, "yes": opts.get("yes", "YES"), "no": opts.get("no", "NO"), "walkAway": opts.get("walkAway", false)}
	print_verbose("prompt: ", text)
	render()
	return await w.wait()


## A list to pick from, shown in the command dock. Options: {label, value, hint?, cost? (spell circle, 0 = free),
## who? (a member: shows health)}. `opts.who` shows that member's spell slots next to the title.
## Returns the option's value, or null (Esc).
func choose(title: String, options: Array, opts := {}):
	var w := J.Waiter.new()
	G.menu = {"title": title, "options": options, "waiter": w, "sel": 0, "who": opts.get("who")}
	print_verbose("menu: ", title, " ", options.size())
	render()
	return await w.wait()


## The talk box. Returns the words (trimmed, at most 240 characters), null when sent empty, UNDEFINED when cancelled.
func ask_text(label: String, numeric := false):
	var w := J.Waiter.new()
	G.input = {"label": label, "waiter": w, "numeric": numeric, "listening": null}
	ui.open_input(label, numeric)
	render()
	return await w.wait()


## Closes the talk box with its answer: words, null (sent empty) or UNDEFINED (cancelled, the default)
func close_input(value = UNDEFINED) -> void:
	var inp = G.input if G != null else null
	if G != null:
		G.input = null
	voice.cancel()
	ui.close_input()
	if inp != null:
		inp.waiter.resolve(value)


## The talk box was sent (Enter, or the form's submit): what's in it, trimmed to 240, or null when empty
func submit_input() -> void:
	var text: String = str(ui.input_text()).strip_edges().left(240)
	close_input(text if text != "" else null)


## Esc in the talk box
func cancel_input() -> void:
	close_input(UNDEFINED)
	render()


## "PRESS ANY KEY"
func wait_key() -> void:
	var w := J.Waiter.new()
	G.waitKey = w
	render()
	await w.wait()


# ---------------------------------------------------------------- dungeon generation

func announce_floor(f: int) -> void:
	if Floors.NEWS.has(f):
		say(Floors.NEWS[f], "dim" if f == 1 else "big", null if f == 1 else G.map.palette.accent)
	if G.map.boss != null:
		hint("boss")
		say("A RED CHAMPION WAITS AT THE HEART OF THIS FLOOR (RED ON YOUR MAP). DEFEAT IT, WIN IT OVER OR TALK IT DOWN FOR A GREAT ROLL OF FATE.", "big", Art.BOSS_COLOR)


func enter_floor(n: int) -> void:
	G.floor = n
	var previous = G.map.palette if G.get("map") != null else null
	G.map = Floors.gen_floor(n)
	G.map.palette = J.pick(Render.PALETTES.filter(func(p): return p != previous))
	G.map.seed = randi() % 1000000000
	G.x = 1
	G.y = 1
	G.dir = -1
	for i in Render.DIRS.size():
		if Floors.cell(G.map.grid, 1 + Render.DIRS[i][0], 1 + Render.DIRS[i][1]) == 1:
			G.dir = i
			break
	G.seen = {}
	G.visited = {1 * G.map.n + 1: true}
	var raw = store.get_item("hallsOfJev.deepest")
	var best := str(raw).to_float() if raw != null and str(raw) != "" else 0.0
	if n > best:
		store.set_item("hallsOfJev.deepest", str(n))
	print("floor %d: %s" % [n, G.map.palette.name])


# ---------------------------------------------------------------- log + presentation state

func say(text: String, cls := "", color = null) -> void:
	G.log.append({"text": text, "cls": cls, "color": color})
	if G.log.size() > 150:
		G.log.pop_front()


## A monster's spoken line gets its voice (RAAH, a hiss, a blorp...), chosen from the wording and the species.
func speak(who, line: String) -> void:
	var species = who.get("species") if who is Dictionary else null
	var plan = null
	if species:
		plan = sfx.shout(line, species, {"key": who.id, "boss": J.truthy(who.get("boss"))})
	if plan:
		print_verbose("shout ", species, " ", plan.get("kind") if plan is Dictionary else plan, " ", JSON.stringify(line))
	narrator.say(line, species) # read aloud, if voices are on


## Redraw everything (the ui). The floor cells in view go on the automap first (JS: drawView, every frame).
func render() -> void:
	if G == null:
		return
	mark_seen()
	ui.render()


## The floor cells you can see from here join the automap
func mark_seen() -> void:
	if G == null or G.combat != null or G.get("map") == null:
		return
	for c in Render.visible_cells(G.map, G.x, G.y, G.dir):
		G.seen[c[1] * G.map.n + c[0]] = true


func fx_now() -> float:
	return J.now_ms() + fx_lag


func float_text(text: String, x: float, y: float, color := "#e8e8e8", size := 10) -> void:
	var now := fx_now()
	var stacked := 0
	for f in floaters:
		if absf(f.x - x) < 30 and now - f.t0 < 350:
			stacked += 1
	floaters.append({"text": text, "x": x, "y": y + stacked * 14, "color": color, "size": size, "t0": now})


## A die tumbles at `spot` ({x, y}); what it causes waits for it to land. opts: {total, label}
## (The small total under a die is skipped in the party row, which is busy with floating numbers.)
func roll_fx(r: Dictionary, spot: Dictionary, opts := {}) -> void:
	var total = opts.get("total")
	var label = opts.get("label", ("=%s" % J.num(total)) if total != null and spot.y < 200 else "")
	var now := J.now_ms()
	var pop: Dictionary = spot.duplicate()
	pop.merge({"rolls": r.rolls, "kept": r.roll, "label": label, "now": now}, true)
	dice.add(pop)
	if now - last_rattle > 60:
		sfx.play("dice", {"delay": 0}) # several dice thrown together rattle once
	last_rattle = now
	sfx.play("diceLand", {"delay": Dice.DIE_TUMBLE_MS / 1000.0, "tier": Dice.die_tier(r.roll)})
	fx_lag = Dice.DIE_TUMBLE_MS
	sfx.lag = Dice.DIE_TUMBLE_MS / 1000.0
	_reset_fx_lag.call_deferred()
	print_verbose("roll %s kept %d %s %s" % ["/".join(r.rolls.map(func(v): return str(v))), r.roll, JSON.stringify(label), JSON.stringify(spot)])


func _reset_fx_lag() -> void:
	fx_lag = 0.0
	sfx.lag = 0.0


## Where a die sits: on the monster that is the target, or in the party row (the bottom of the view).
func spot_of(x: Dictionary) -> Dictionary:
	var i := index_of(G.party, x)
	if i >= 0:
		return {"x": (448.0 / (G.party.size() + 1)) * (i + 1), "y": 226}
	return {"x": slot_of(x).cx, "y": 160}


func slot_of(e: Dictionary) -> Dictionary:
	var here := present()
	var i := maxi(0, index_of(here, e))
	return Art.SLOTS[mini(3, maxi(1, here.size()))][mini(i, 2)]


func float_on(e: Dictionary, text: String, color := "#ffffff", size := 11) -> void:
	float_text(text, slot_of(e).cx, 110, color, size)


func float_party(m: Dictionary, text: String, color := "#e8e8e8") -> void:
	var i := maxi(0, index_of(G.party, m))
	float_text("%s %s" % [m.name, text], (448.0 / (G.party.size() + 1)) * (i + 1), 262, color, 8)


## What the tips may show over right now (tutorial.gd's context): off, roll, prompt, combat or explore.
## A menu or the talk box counts as a question: keys mean something else there.
func tips_context() -> String:
	if G == null or G.mode == "over":
		return "off"
	if G.roll != null or G.waitKey != null:
		return "roll"
	if G.prompt != null or G.menu != null or G.input != null:
		return "prompt"
	if G.combat != null:
		return "combat"
	return "explore"


## main wires this as the achievements' onUnlock
func on_achievement_unlocked(a: Dictionary) -> void:
	if G == null:
		return
	say("ACHIEVEMENT UNLOCKED: %s.%s" % [a.name, " PRESS K TO SEE THEM ALL." if ach.count().earned == 1 else ""], "", "#ffd27a")


## main wires this as the voice listener's onError
func on_voice_error(err) -> void:
	if G == null:
		return
	var blocked: bool = err == "not-allowed" or err == "service-not-allowed"
	say("THE MICROPHONE IS BLOCKED. TYPE INSTEAD, OR ALLOW IT IN THE BROWSER." if blocked else "COULDN'T HEAR YOU (%s). TYPE INSTEAD." % UP(err), "warn")
	render()


# ---------------------------------------------------------------- the run

func new_run() -> void:
	G = {
		"mode": "explore",
		"floor": 1,
		"party": [human("HORTENSE", "fighter"), human("ROLF", "cleric"), human("EUGENE", "wizard")],
		"gold": 30,
		"boons": [],
		"goldMult": 1,
		"combat": null,
		"busy": false,
		"prompt": null,
		"menu": null,
		"input": null,
		"vows": [],
		"pendingBreaks": [],
		"graceSteps": 4,
		"log": [],
		"map": null,
		"roll": null,
		"waitKey": null,
	}
	print("new run")
	enter_floor(1)
	say("You descend into the Donjon. The monsters here listen, if you talk to them.", "dim")
	say("HORTENSE IS A FIGHTER, ROLF A CLERIC WHO HEALS, EUGENE A WIZARD. EVERY SWING, SPELL AND PLEA IS A DICE ROLL.", "dim")
	if not tips.on():
		say("MOVE WITH THE ARROW KEYS OR WASD. EVERYTHING ELSE IS ON THE BAR UNDER THE VIEW: PRESS ITS KEY OR CLICK IT.", "dim")
	say("FIND THE STAIRS ON EACH FLOOR. EVERY FLOOR YOU CLEAR EARNS A ROLL OF FATE.", "dim")
	say_jev_warning()
	announce_floor(1)
	hint("move")
	render()


## How Jev is reached, when the run should know: no key means the mock, whose monsters act at random
func say_jev_warning() -> void:
	var warning = _jev_config().get("warning")
	if J.truthy(warning):
		say(UP(warning), "warn")


func start() -> void:
	if started:
		return
	started = true
	if store == null:
		store = _default_store()
	init_debug()
	ui.start_audio()
	_start_music()
	new_run()
	# Test runs: open the game with #floor5 (any number) to start that deep, with a party that got there
	var test := Flags.capture("floor(\\d+)")
	if test != "":
		test_run(maxi(2, mini(30, int(test))))


func _start_music() -> void:
	var r = await music.start()
	if r is Dictionary and r.has("error"):
		push_warning("music: %s" % r.error)


## A party as if it had played down to floor n: level n, one boon per floor cleared, some gold, fully rested.
func test_run(n: int) -> void:
	var sound = sfx.on
	sfx.on = false
	for m in G.party:
		while m.level < n:
			m.xp = xp_for(m.level)
			level_up(m)
	for f in range(1, n):
		draw_boon(f)
	for m in G.party:
		m.hp = m.maxHp
		m.xp = 0
		if m.has("maxSlots"):
			m.slots = m.maxSlots.duplicate()
	G.gold = 30 + 45 * (n - 1)
	enter_floor(n)
	G.log = []
	sfx.on = sound
	print("test run: floor %d" % n)
	say("TEST RUN: STARTING ON %s WITH A LEVEL %d PARTY, %d BOONS AND %s GOLD." % [Status.floor_name(n), n, n - 1, J.num(G.gold)], "big", G.map.palette.accent)
	for b in G.boons:
		say("%s: %s: %s" % [Status.floor_name(b.floor), b.name, b.text], "dim")
	say_jev_warning()
	announce_floor(n)
	render()


# ---------------------------------------------------------------- exploring

func step(dir: int) -> void:
	var d: Array = Render.DIRS[dir]
	var nx: int = G.x + d[0]
	var ny: int = G.y + d[1]
	if Floors.cell(G.map.grid, nx, ny) != 1:
		say("OUCH! A WALL.", "dim")
		sfx.play("bump")
		fx.emit("view:bump")
		render()
		return
	fx.emit("view:step", {"dir": 1 if dir == G.dir else -1})
	G.x = nx
	G.y = ny
	var k: int = ny * G.map.n + nx
	G.visited[k] = true
	if G.map.gold.erase(k):
		var g: int = J.rnd(3, 10) * G.floor
		G.gold += g
		say("YOU FIND %d GOLD." % g)
		sfx.play("gold")
	if G.visited.size() >= 6:
		hint("map")
	if G.seen.has(G.map.stairs.y * G.map.n + G.map.stairs.x):
		hint("stairs")
	var b = G.map.boss
	if b != null and not b.defeated and nx == b.x and ny == b.y:
		boss_encounter()
		return
	if nx == G.map.stairs.x and ny == G.map.stairs.y:
		_ask_descend()
		return
	G.graceSteps -= 1
	if G.graceSteps <= 0 and randf() < Floors.floor_rules(G.floor).encounter:
		# A new player's first fight is the lesson: one shy slime, talked to and then recruited (tutorial.gd GUIDE)
		if Tutorial.should_guide({"floor": G.floor, "tipsOn": tips.on(), "seen": func(id): return tips.seen(id)}):
			encounter([make_enemy("slime")], {"guide": true})
			return
		encounter()
		return
	render()


func _ask_descend() -> void:
	var yes = await ask("STAIRS DOWN TO %s. DESCEND?" % Status.floor_name(G.floor + 1), {"yes": "DESCEND", "no": "STAY", "walkAway": true})
	if yes:
		await descend()
	else:
		render()


func boss_encounter() -> void:
	var b = G.map.boss
	if b.enemy == null:
		b.enemy = make_boss(b.species)
	say("THE AIR TURNS RED. %s RISES TO MEET YOU." % UP(b.enemy.name), "big", Art.BOSS_COLOR)
	await encounter([b.enemy], {"boss": true})


func descend() -> void:
	sfx.play("stairs")
	music.sting("fanfare")
	await roll_of_fate(G.floor)
	enter_floor(G.floor + 1)
	var kept: int = G.vows.filter(func(v): return v.status == "active" and G.party.any(func(m): return m.id == v.toId and not m.dead)).size()
	ach.on("descend", {"floor": G.floor, "keptVows": kept})
	G.graceSteps = 4
	say("YOU DESCEND TO %s: THE %s. THE MONSTERS HERE ARE TOUGHER." % [Status.floor_name(G.floor), G.map.palette.name], "", G.map.palette.accent)
	announce_floor(G.floor)
	if not allies().is_empty():
		say("YOUR ALLIES WILL HEAR YOU OUT AGAIN ON THIS FLOOR (E).", "dim")
	render()


## A long rest: wounds half close, spell slots and fighter skills come back, conditions clear.
func camp() -> void:
	for m in living():
		m.hp = mini(m.maxHp, m.hp + ceili(m.maxHp / 2.0))
		m.cond = {}
		if m.has("maxSlots"):
			m.slots = m.maxSlots.duplicate()
		restore_uses(m)
	say("THE PARTY RESTS. WOUNDS CLOSE; SPELL SLOTS AND SKILLS RETURN.")
	sfx.play("heal")
	# A cleric who knows Revivify can bring back the dead while you rest
	var cleric = null
	for m in conscious():
		if m.get("slots") != null and Dnd.spells_known(m.clsId, m.level).has("revivify"):
			cleric = m
			break
	for dead in G.party.filter(func(m): return m.dead):
		if cleric == null or not (_slot(cleric, 2) > 0):
			break
		render()
		if not await ask("%s CAN CAST REVIVIFY ON %s (USES A THIRD-CIRCLE SPELL SLOT). DO IT?" % [cleric.name, dead.name], {"yes": "REVIVE", "no": "NOT NOW"}):
			continue
		cleric.slots[2] -= 1
		revive(dead)
	if randf() < 0.25:
		say("...SOMETHING FINDS YOUR CAMP!", "warn")
		await encounter()
		return
	render()


func pick_ally(title: String):
	var list := allies()
	if list.is_empty():
		say("YOU HAVE NO MONSTER ALLIES YET.", "dim")
		render()
		return null
	if list.size() == 1:
		return list[0]
	return await choose(title, list.map(func(a): return {"label": a.name, "value": a}))


## Talk to an ally: once per ally per floor, so it stays a special moment rather than a chatbot.
## Every talk has a result: it can sulk, get distracted, steady itself, power up, or be inspired.
func talk_to_ally() -> void:
	var ally = await pick_ally("TALK TO WHOM?")
	if ally == null:
		return
	if ally.get("talkedFloor") == G.floor:
		say("%s HAS SAID ALL IT WANTS TO SAY ON THIS FLOOR." % ally.name, "dim")
		render()
		return
	var text = await ask_text("SAY TO %s:" % ally.name)
	if not _said(text):
		render()
		return
	ally.talkedFloor = G.floor
	say('YOU, TO %s: "%s"' % [ally.name, text], "you")
	G.busy = true
	render()
	var r := await api("/api/ally-talk", {
		"ally": {"id": ally.id, "species": ally.species, "name": ally.name, "traits": ally.traits, "loyalty": ally.loyalty},
		"message": text,
		"vows": G.vows.filter(func(v): return v.toId == ally.id).map(func(v): return {"text": v.text, "status": v.status}),
	})
	if r.has("error"):
		say("(JEV UNREACHABLE: %s)" % r.error, "dim")
	else:
		ally.loyalty = clamp100(ally.loyalty + r.loyaltyDelta)
		var color := color_of(ally)
		say("%s: %s" % [ally.name, r.line], "npc", color)
		speak(ally, r.line)
		var tell = Narrate.reaction_tell(ally.species, ally.name, r.level)
		if J.truthy(tell):
			say(tell, "", color)
		if J.truthy(r.get("buff")):
			ally.buff = r.buff
			say("%s IS %s: %s." % [ally.name, r.buff.id, UP(r.buff.desc)], "big", color)
		if J.truthy(r.get("outcome")):
			if r.outcome.id == "INSPIRED":
				ally.hp = ally.maxHp
				ally.xp += xp_for(ally.level)
				level_up(ally)
			else:
				ally.mood = r.outcome
			say("%s %s." % [ally.name, UP(r.outcome.desc)], "big warn" if r.level <= 1 else "big", null if r.level <= 1 else color)
		dbg("LANDED %s/4, LOYALTY %s%s → %s (%s)" % [to_fixed(r.resonance, 1), "+" if r.loyaltyDelta >= 0 else "", J.num(r.loyaltyDelta), J.num(ally.loyalty), loyalty_word(ally.loyalty)])
		sfx.play("bad" if r.level <= 0 else ("sad" if r.level == 1 else ("levelup" if r.level >= 4 else "good")))
		ui.show_jev({"kind": "talk", "ally": ally, "r": r})
	G.busy = false
	render()


func list_boons() -> void:
	if G.boons.is_empty():
		say("NO BOONS YET. CLEAR A FLOOR AND ROLL FOR ONE.", "dim")
	else:
		for b in G.boons:
			say("%s: %s%s: %s" % [Status.floor_name(b.floor), "GREAT " if b.great else ("SHINY " if b.kind == "shiny" else ""), b.name, b.text], "dim")
	render()


# ---------------------------------------------------------------- vows

func make_vow() -> void:
	var in_combat: bool = G.combat != null
	var to
	if in_combat:
		to = target_enemy()
		if G.combat.vowed:
			say("YOU'VE ALREADY SWORN SOMETHING IN THIS FIGHT.", "dim")
			render()
			return
	else:
		to = await pick_ally("SWEAR TO WHOM?")
		if to == null:
			render()
			return
		if to.get("vowFloor") == G.floor:
			say("YOU'VE ALREADY SWORN TO %s ON THIS FLOOR." % to.name, "dim")
			render()
			return
	if G.vows.filter(func(v): return v.status == "active").size() >= MAX_VOWS:
		say("YOU CAN'T KEEP TRACK OF MORE PROMISES THAN THIS.", "dim")
		render()
		return
	var will = await choose("I...", [{"label": "WILL", "value": true}, {"label": "WON'T", "value": false}])
	if will == null:
		render()
		return
	var verb = await choose("I WILL..." if will else "I WON'T...", VERBS.map(func(v): return {"label": v.label, "value": v}))
	if verb == null:
		render()
		return
	var target = await choose("%s %s..." % ["I WILL" if will else "I WON'T", verb.label], TARGETS.map(func(t): return {"label": t.label, "value": t}))
	if target == null:
		render()
		return

	var text := "I %s %s %s" % ["WILL" if will else "WON'T", verb.label, target.label]
	var vow := {"id": "v%d" % uid, "will": will, "verb": verb.id, "target": target.id, "text": text, "toId": to.id, "toName": to.name, "toSpecies": to.species, "status": "active", "floor": G.floor}
	uid += 1
	G.vows.append(vow)
	if in_combat:
		G.combat.vowed = true
	else:
		to.vowFloor = G.floor
	say('YOU SWEAR TO %s: "%s"' % [UP(to.name), text], "you")
	print("vow: %s, to %s" % [text, to.name])
	if in_combat:
		history('The party swore to %s: "%s".' % [to.name, text.to_lower()])

	G.busy = true
	render()
	var r := await api("/api/vow", {"monster": {"species": to.species, "name": to.name, "traits": to.traits}, "vow": {"text": text.to_lower()}})
	if r.has("error"):
		say("(JEV UNREACHABLE: %s)" % r.error, "dim")
	else:
		var color := color_of(to)
		say("%s: %s" % [UP(to.name), r.line], "npc", color)
		speak(to, r.line)
		var tell = Narrate.reaction_tell(to.species, to.name, r.level)
		if J.truthy(tell):
			say(tell, "", color)
		dbg("%s LIKES THE VOW %s/4" % [UP(to.name), to_fixed(r.liking, 1)])
		var shift = r.level - 2
		if in_combat:
			to.meters.friendliness = clamp100(to.meters.friendliness + shift * 9)
			to.meters.anger = clamp100(to.meters.anger - shift * 5)
			to.impressions.append('The party swore to you: "%s".' % text.to_lower())
		else:
			to.loyalty = clamp100(to.loyalty + shift * 5)
		ui.show_jev({"kind": "vow", "to": to, "vow": vow, "r": r})
	G.busy = false
	render()


## Something happened that could break a vow (kill, spare, talk, give, flee, attack, recruit a species).
func vow_event(type: String, species: String, how: String) -> void:
	for v in G.vows:
		if v.status != "active":
			continue
		if v.target != "monsters" and v.target != species:
			continue
		if not BREAKS[v.verb]["will" if v.will else "wont"].has(type):
			continue
		v.status = "broken"
		v.fresh = true
		v.justBroken = true
		v.brokenHow = how
		G.pendingBreaks.append(v)
		print("vow broken: %s (%s)" % [v.text, type])


## Deal with broken vows: the wronged monster answers (Jev picks how), code applies it.
func flush_breaks() -> void:
	while not G.pendingBreaks.is_empty():
		var v = G.pendingBreaks.pop_front()
		say('YOU BROKE YOUR VOW: "%s"' % v.text, "big warn")
		sfx.play("slash")
		render()
		var ally = null
		for m in G.party:
			if m.id == v.toId and not m.dead:
				ally = m
				break
		var enemy = null
		if G.combat != null:
			for e in G.combat.enemies:
				if e.id == v.toId and e.status == "here":
					enemy = e
					break
		if enemy != null:
			enemy.meters.anger = clamp100(enemy.meters.anger + 35)
			enemy.meters.friendliness = clamp100(enemy.meters.friendliness - 35)
			enemy.impressions.append('The party broke the promise it made to you: "%s".' % v.text.to_lower())
			enemy.thisRound.append('The party just broke its promise to you: "%s".' % v.text.to_lower())
			say("%s SAW THAT." % UP(enemy.name), "warn", color_of(enemy))
			continue
		if ally == null:
			say("...BUT NO ONE IS LEFT TO HOLD YOU TO IT.", "dim")
			continue
		G.busy = true
		render()
		var r := await api("/api/vow-broken", {
			"monster": {"species": ally.species, "name": ally.name, "traits": ally.traits, "loyalty": ally.loyalty},
			"vow": {"text": v.text.to_lower()},
			"how": v.brokenHow,
			"gold": G.gold,
		})
		if r.has("error"):
			say("(JEV UNREACHABLE: %s)" % r.error, "dim")
			G.busy = false
			continue
		G.busy = false
		ui.show_jev({"kind": "broken", "ally": ally, "v": v, "r": r})
		var color := color_of(ally)
		# It wanted to forgive, but the wound runs too deep: say so, or the walk-out reads like a contradiction
		if r.picked == "forgive" and r.response != "forgive":
			say(Narrate.cant_forgive_line(ally.species, ally.name), "", color)
		say("%s: %s" % [ally.name, r.line], "npc", color)
		speak(ally, r.line)
		ally.loyalty = _n(r.loyalty)
		ach.on("vow-broken", {"response": r.response, "stolen": J.truthy(r.get("stolen"))})
		print("vow broken: %s answers %s" % [ally.name, r.response])
		if r.response == "forgive":
			say("%s STAYS. FOR NOW." % ally.name, "dim", color)
		if r.response == "leave_party":
			G.party = _without(G.party, ally)
			say("%s LEAVES THE PARTY." % ally.name, "warn", color)
		if r.response == "steal_gold":
			if J.truthy(r.get("stolen")):
				var took := mini(G.gold, int(r.stolen))
				G.gold -= took
				G.party = _without(G.party, ally)
				say("%s RUNS OFF WITH %d GOLD!" % [ally.name, took], "big warn", color)
			else:
				say("%s TRIES TO STEAL YOUR GOLD, BUT YOU CATCH IT. IT STAYS, SULKING." % ally.name, "warn", color)
		if r.response == "attack_party":
			G.party = _without(G.party, ally)
			var foe := enemy_from_ally(ally, 'The party broke its promise to you: "%s". You turned on them.' % v.text.to_lower())
			if G.combat != null:
				add_enemy(foe)
				say("%s TURNS ON YOU!" % ally.name, "big", color)
			else:
				render()
				await encounter([foe])
				return
		render()


# ---------------------------------------------------------------- roll of fate
# Clearing a floor earns one random boon. Strength scales with the floor you cleared, and boons compound.
# Beating a floor's red champion earns a GREAT roll: double strength, with a chance at legendary boons.

static func _strikes_more(m) -> bool:
	return m.mods.hits < 8 and m.get("clsId") != "wizard"


func _boon_whetstone(m, tier) -> String:
	var add: float = 0.12 * tier
	m.mods.dmg *= 1 + add
	return "%s DEALS +%d%% DAMAGE (NOW X%s)" % [m.name, J.round_js(add * 100), to_fixed(m.mods.dmg, 2)]


func _boon_keen_eye(m, tier) -> String:
	m.mods.critMin = maxi(15, m.mods.critMin - maxi(1, J.round_js(tier / 3.0)))
	return "%s NOW SCORES CRITICAL HITS ON A %d-20 (CRITICAL HITS ROLL DOUBLE DAMAGE DICE)" % [m.name, m.mods.critMin]


func _boon_true_aim(m, tier) -> String:
	var add := maxi(1, J.round_js(tier / 2.0))
	m.mods.hitBonus += add
	return "%s GETS +%d TO HIT (NOW +%s FROM BOONS)" % [m.name, add, J.num(m.mods.hitBonus)]


func _boon_flurry(m, _tier) -> String:
	m.mods.hits = {1: 2, 2: 3, 3: 4, 4: 8}.get(int(m.mods.hits), 8)
	return "%s NOW STRIKES %d TIMES EVERY TURN" % [m.name, m.mods.hits]


func _boon_iron_skin(m, tier) -> String:
	var add := maxi(1, J.round_js(tier / 3.0))
	m.ac += add
	return "%s'S ARMOR RISES BY %d TO %s. MONSTERS MISS IT MORE" % [m.name, add, J.num(m.ac)]


func _boon_vampiric(m, tier) -> String:
	m.mods.lifesteal += 0.08 * tier
	return "%s HEALS %d%% OF THE DAMAGE IT DEALS" % [m.name, J.round_js(m.mods.lifesteal * 100)]


func _boon_arcane_surge(m, tier) -> String:
	m.bonusSlots[0] += 1 + floori(tier / 3.0)
	if tier >= 3:
		m.bonusSlots[1] += 1
	if tier >= 6:
		m.bonusSlots[2] += 1
	refresh_slots(m, true)
	m.mods.spell *= 1 + 0.2 * tier
	return "%s GETS MORE SPELL SLOTS (NOW %d) AND SPELLS HIT X%s" % [m.name, slot_total(m), to_fixed(m.mods.spell, 2)]


func _boon_vigor(party, tier) -> String:
	var add: int = 2 * tier
	for m in party:
		m.maxHp += add
		m.hp += add
	return "THE WHOLE PARTY GAINS +%d MAX HEALTH" % add


func _boon_golden_touch(_x, tier) -> String:
	G.goldMult *= 1 + 0.15 * tier
	return "ALL GOLD FROM MONSTERS IS NOW X%s" % to_fixed(G.goldMult, 2)


func _boon_phoenix(_x, _tier) -> String:
	for m in G.party:
		if m.dead:
			revive(m, m.maxHp)
		m.phoenix = true
	return "THE FALLEN RISE AT FULL HEALTH, AND EVERYONE WILL CHEAT DEATH ONCE"


func _boon_legendary_arms(party, _tier) -> String:
	for m in party:
		m.mods.dmg *= 1.5
		m.mods.critMin = maxi(15, m.mods.critMin - 1)
	return "THE WHOLE PARTY DEALS X1.5 DAMAGE AND LANDS CRITICAL HITS MORE OFTEN"


func _boon_archmage(m, _tier) -> String:
	m.bonusSlots = m.bonusSlots.map(func(n): return n + 2)
	refresh_slots(m, true)
	m.mods.spell *= 1.5
	return "%s GAINS 2 SPELL SLOTS OF EVERY CIRCLE (NOW %d) AND SPELLS HIT X%s" % [m.name, slot_total(m), to_fixed(m.mods.spell, 2)]


func _boon_titans_blood(party, tier) -> String:
	var add: int = 3 * tier
	for m in party:
		m.maxHp += add
		m.hp = m.maxHp
	return "THE WHOLE PARTY GAINS +%d MAX HEALTH AND HEALS FULLY" % add


func _boon_twin_soul(m, _tier) -> String:
	m.mods.hits = mini(8, m.mods.hits * 2)
	return "%s NOW STRIKES %d TIMES EVERY TURN" % [m.name, m.mods.hits]


func targets_for(boon: Dictionary) -> Array:
	for m in living():
		if m.get("mods") == null:
			m.mods = base_mods()
	if boon.target == "party":
		return [living()]
	if boon.target == "global":
		return [null]
	var valid = boon.get("valid")
	return living().filter(func(m): return (m.has("maxSlots") if boon.target == "caster" else true) and (valid.call(m) if valid is Callable else true))


## kind: "floor" (took the stairs), "shiny" (recruited a shiny), or a great roll from a champion.
## Picks and applies a random boon (no animation). The Roll of Fate shows it; test runs use it directly.
func draw_boon(tier: int, great := false, kind := "floor") -> Dictionary:
	var pool: Array = LEGENDARY if great and randf() < 0.6 else BOONS
	var options := pool.filter(func(b): return not targets_for(b).is_empty())
	if options.is_empty():
		options = BOONS.filter(func(b): return not targets_for(b).is_empty())
	var total := 0.0
	for b in options:
		total += b.weight
	var r := randf() * total
	var boon = options[0]
	for b in options:
		r -= b.weight
		if r < 0:
			boon = b
			break
	var text: String = boon.apply.call(J.pick(targets_for(boon)), tier * 2 if great else tier)
	G.boons.append({"name": boon.name, "text": text, "floor": tier, "great": great, "kind": kind})
	print("boon: %s (%s): %s" % [boon.name, "great" if great else kind, text])
	return {"boon": boon, "text": text}


func roll_of_fate(tier: int, great := false, kind := "floor") -> void:
	var drawn := draw_boon(tier, great, kind)
	var boon: Dictionary = drawn.boon
	var text: String = drawn.text
	var names: Array = ((LEGENDARY + BOONS) if great else BOONS).map(func(b): return b.name)
	G.roll = {"start": J.now_ms(), "names": names, "result": {"name": boon.name, "text": text, "tier": tier}, "landed": false, "landedAt": null, "great": great, "kind": kind, "lastIdx": -1}
	G.busy = true
	render()
	await _sleep(2800 if great else 1900)
	G.roll.landed = true
	G.roll.landedAt = J.now_ms()
	print_verbose("roll of fate landed ", boon.name, " ", "great" if great else kind)
	sfx.play("great" if great else "land")
	var lead := "GREAT " if great else ("SHINY " if kind == "shiny" else "")
	say("%sROLL OF FATE: %s! %s." % [lead, boon.name, text], "big", Art.BOSS_COLOR if great else (Art.SHINY_COLOR if kind == "shiny" else G.map.palette.accent))
	ach.on("boon", {"name": boon.name, "great": great, "legendary": index_of(LEGENDARY, boon) >= 0})
	render()
	await wait_key()
	G.roll = null
	G.busy = false


# ---------------------------------------------------------------- encounters & combat
# D&D-style: initiative, d20 attack rolls against armor class, damage dice, critical hits, saving throws,
# spell slots, conditions, and death saving throws at 0 HP. Jev still decides what every monster does.

static func species_for_floor(f: int) -> String:
	return Floors.pick_weighted(Floors.floor_rules(f).pool)


static func group_size(f: int) -> int:
	var mx: int = Floors.floor_rules(f).maxGroup
	var r := randf()
	if mx == 1:
		return 1
	if mx == 2:
		return 1 if r < 0.6 else 2
	if f == 3:
		return 1 if r < 0.4 else (2 if r < 0.85 else 3)
	return 1 if r < 0.3 else (2 if r < 0.7 else 3)


func make_enemy(species: String, taken_names := []) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[species]
	var st: Dictionary = Dnd.MONSTER_STATS[species]
	var f: int = G.floor
	var elite: bool = randf() < Floors.floor_rules(f).elite
	var shiny := randf() < SHINY_CHANCE
	var hp := J.round_js(J.rnd(sp.hp[0], sp.hp[1]) * hp_scale(f) * (1.5 if elite else 1.0) * (1.3 if shiny else 1.0))
	var kin := allies().any(func(m): return m.species == species)
	var names: Array = sp.names.filter(func(n): return not taken_names.has(n))
	var traits: Array = sp.traits.duplicate()
	traits.shuffle()
	traits = traits.slice(0, 2)
	if shiny:
		traits.append("a rare shiny gold one of its kind, and proud of it")
	if elite:
		traits.append("a battle-scarred veteran, tougher than most of its kind")
	# Shinies are rarer and stronger: +30% HP, +1 AC, +1 to hit and saves, +10% damage
	var sh := 1 if shiny else 0
	var meters: Dictionary = sp.start.duplicate()
	meters.friendliness = sp.start.friendliness + (15 if kin else 0)
	var dmg_mult := dmg_scale(f) * (1.1 if shiny else 1.0)
	return {
		"species": species,
		"shiny": shiny,
		"elite": elite,
		"name": J.pick(names if not names.is_empty() else sp.names),
		"traits": traits,
		"hp": hp,
		"maxHp": hp,
		# Bounded accuracy, as in 5e: armor and to-hit creep up slowly; HP and damage carry the scaling
		"ac": st.ac + mini(3, floori((f - 1) / 4.0)) + sh,
		"hit": st.hit + floori((f - 1) / 3.0) + (2 if elite else 0) + sh,
		"dc": st.special.dc + floori((f - 1) / 2.0) + sh,
		"saveBonus": floori((f - 1) / 3.0) + (1 if elite else 0) + sh,
		"dmgMult": dmg_scale(f) * (1.2 if elite else 1.0) * (1.1 if shiny else 1.0),
		"dmg": sp.dmg.map(func(x): return J.round_js(x * dmg_mult)), # its damage range if it ever joins the party
		"legendary": 0,
		"multiattack": 1,
		"recharge": 3,
		"meters": meters,
		"cooldown": 0,
		"paid": false,
		"demanded": false,
		"impressions": ["One of your own kind travels with this party."] if kin else [],
		"formerAlly": false,
		"cond": {},
	}


## The floor's red champion: a normal monster of its kind, but far harder. Two attacks a turn, a faster
## special, and Legendary Resistance (it shrugs off the first two spells that would sleep or hold it).
func make_boss(species: String) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[species]
	var e := make_enemy(species)
	var hp := J.round_js(J.rnd(sp.hp[0], sp.hp[1]) * hp_scale(G.floor) * 2.2)
	var traits: Array = e.traits.filter(func(t): return not ("shiny" in t or "veteran" in t)).slice(0, 2)
	traits.append("the towering red champion of this floor, far stronger than others of its kind")
	e.merge({
		"boss": true,
		"shiny": false,
		"elite": false,
		"name": "%s the Red" % e.name,
		"traits": traits,
		"hp": hp,
		"maxHp": hp,
		"ac": e.ac + 1,
		"hit": e.hit + 2,
		"dc": e.dc + 2,
		"saveBonus": e.saveBonus + 3,
		"dmgMult": e.dmgMult * 1.2,
		"dmg": e.dmg.map(func(x): return J.round_js(x * 1.2)),
		"legendary": 2,
		"multiattack": 2,
		"recharge": 2,
		"meters": {"friendliness": maxi(0, sp.start.friendliness - 15), "anger": sp.start.anger + 10, "fear": 0},
	}, true)
	return e


func make_group() -> Array:
	var n := group_size(G.floor)
	var group := []
	for i in n:
		var species := species_for_floor(G.floor)
		if species == "dragon" and group.any(func(e): return e.species == "dragon"):
			species = "goblin"
		group.append(make_enemy(species, group.map(func(e): return e.name)))
	return group


func enemy_from_ally(ally: Dictionary, why: String) -> Dictionary:
	var st: Dictionary = Dnd.MONSTER_STATS[ally.species]
	var mods = ally.get("mods")
	var boss: bool = J.truthy(ally.get("boss"))
	return {
		"species": ally.species,
		"shiny": J.truthy(ally.get("shiny")),
		"boss": boss,
		"name": ally.name,
		"traits": ally.traits,
		"hp": maxi(1, ally.hp),
		"maxHp": ally.maxHp,
		"ac": ally.ac,
		"hit": 2 + Dnd.prof(ally.level) + (mods.hitBonus if mods != null else 0),
		"dc": st.special.dc + floori((G.floor - 1) / 2.0),
		"saveBonus": floori(ally.level / 3.0),
		"dmgMult": dmg_scale(G.floor),
		"dmg": ally.dmg,
		"legendary": 2 if boss else 0,
		"multiattack": 2 if boss else 1,
		"recharge": 3,
		"meters": {"friendliness": 10, "anger": 75, "fear": 5},
		"cooldown": 0,
		"paid": true,
		"demanded": false,
		"impressions": [why],
		"formerAlly": true,
		"cond": {},
	}


func present() -> Array:
	if G == null or G.combat == null:
		return []
	return G.combat.enemies.filter(func(e): return e.status == "here" and e.hp > 0)


func target_enemy():
	var here := present()
	for e in here:
		if e.id == G.combat.target:
			return e
	return here[0] if not here.is_empty() else null


func add_enemy(e: Dictionary) -> void:
	var c = G.combat
	e.merge({"id": "e%d" % c.nextId, "status": "here", "grudges": [], "thisRound": [], "damageTaken": 0, "side": "hostile to the party", "cond": {}}, true)
	c.nextId += 1
	c.enemies.append(e)
	if target_enemy() == null:
		c.target = e.id
	history("%s, %s, joined the fight%s." % [e.name, a_label(e.species), " against the party" if e.formerAlly else ""])


func encounter(group = null, opts := {}) -> void:
	if group == null:
		group = make_group()
	var boss: bool = J.truthy(opts.get("boss"))
	sfx.play("boss" if boss else "encounter")
	fx.emit("combat:start", {"boss": boss})
	music.set_mood("battle")
	G.combat = {
		"enemies": [],
		"nextId": 0,
		"target": null,
		"round": 0,
		"conversation": [],
		"history": [],
		"rounds": {},
		"spoken": {},
		"vowed": false,
		"kills": 0,
		"recruits": [],
		"boss": boss,
		"guide": "talk" if opts.get("guide") else null,
	}
	ach.on("fight-start")
	G.mode = "combat"
	G.graceSteps = 5
	print("encounter: %s%s" % [", ".join(group.map(func(e): return "%s (%s)" % [e.name, e.species])), " (boss)" if boss else ""])
	for e in group:
		add_enemy(e)
		var sp: Dictionary = Species.SPECIES[e.species]
		var article := "AN" if sp.label.left(1) in ["a", "e", "i", "o", "u"] else "A"
		if e.get("boss"):
			say("%s, CHAMPION OF %s! %d HEALTH, ARMOR %d, TWO ATTACKS A TURN." % [UP(e.name), Status.floor_name(G.floor), e.maxHp, e.ac], "big", Art.BOSS_COLOR)
		else:
			var line: String
			if e.formerAlly:
				line = "%s TURNS ON YOU!" % UP(e.name)
			elif e.shiny:
				line = "A SHINY %s APPEARS! IT GLITTERS GOLD!" % UP(sp.label)
			else:
				line = "%s %s APPEARS!" % ["A VETERAN" if e.elite else article, UP(sp.label)]
			say(line, "big", color_of(e))
		if not e.formerAlly and not e.get("boss"):
			say("IT IS %s, %s. ARMOR %d." % [UP(e.name), UP(" and ".join(e.traits.slice(0, 2))), e.ac], "dim")
	G.combat.target = G.combat.enemies[0].id
	G.combat.history = G.combat.history.map(func(h): return _replace_first(h, "joined the fight", "was met by the party"))
	apply_opening_buffs()
	if G.combat.guide:
		# The lesson starts with you: no initiative roll, and the usual fight tips wait for the next fight
		print("guide: first fight, talk then recruit")
		say("IT HASN'T NOTICED YOU YET. YOU ACT FIRST.")
		hint(Tutorial.GUIDE.talk.hint)
		G.combat.opening = "The party just came face to face with you in a dungeon corridor. You froze, and they haven't attacked."
		await begin_party_turn()
		return
	# Initiative: the party's quickest member against the quickest monster
	var p_dex = _max_of(conscious().map(func(m): return m.abil.dex if m.get("abil") != null else 1))
	var m_dex = _max_of(present().map(func(e): return Dnd.MONSTER_STATS[e.species].dex + (2 if e.get("boss") else 0)), -5)
	var pd := Dnd.d20()
	var md := Dnd.d20()
	var pr: int = pd.roll + p_dex
	var mr: int = md.roll + m_dex
	var first := pr >= mr
	roll_fx(pd, {"x": 112, "y": 226}, {"label": "PARTY %d" % pr})
	roll_fx(md, {"x": 336, "y": 226}, {"label": "FOES %d" % mr})
	say("WHO MOVES FIRST: PARTY ROLLED %d, MONSTERS %d. %s" % [pr, mr, "YOU ACT FIRST!" if first else "THEY ACT FIRST!"], "" if first else "warn")
	hint("combat")
	if present().size() > 1:
		hint("target")
	render()
	if present().is_empty():
		await end_combat()
		return
	if first:
		G.combat.opening = "The party just came face to face with you in a dungeon corridor, and moved before you could."
		await begin_party_turn()
		return
	await monsters_turn({"type": "start"}, ["The party just came face to face with you in a dungeon corridor."], {})


## Buffs earned by talking to allies: they fire on the next fight, then they're spent.
func apply_opening_buffs() -> void:
	var c = G.combat
	c.pumped = {}
	for a in allies():
		if not J.truthy(a.get("buff")):
			continue
		var color := color_of(a)
		var id: String = a.buff.id
		if id == "STORMING":
			say("%s OPENS WITH A STORM OF LIGHTNING!" % a.name, "big", color)
			sfx.play("fireball")
			for e in present():
				var dmg := _buff_damage(a, "3d6")
				hit_enemy(e, dmg, "%s's lightning hit you for %d." % [a.name, dmg], "#ffe03a")
				say("%s TAKES %d." % [UP(e.name), dmg], "", color)
			reap_enemies(a)
		if id == "BOUNCY":
			c.bouncy = a
			c.soaks = 1
			say("%s BOUNCES IN FRONT OF THE PARTY, READY TO SOAK A BLOW." % a.name, "", color)
		if id == "BULWARK":
			c.bouncy = a
			c.soaks = 2
			say("%s PLANTS ITSELF IN FRONT OF THE PARTY LIKE A WALL." % a.name, "", color)
		if id == "VENOMOUS":
			var here := present()
			if not here.is_empty():
				var e = here[0]
				var dmg := _buff_damage(a, "2d6+2")
				say("%s STRIKES FIRST WITH A VENOMOUS BITE! %s TAKES %d." % [a.name, UP(e.name), dmg], "big", color)
				sfx.play("hit")
				hit_enemy(e, dmg, "%s's venom hit you for %d." % [a.name, dmg], "#9ed36b")
				reap_enemies(a)
		if id == "SNEAKY":
			c.goldBonus = 1.5
			say("%s IS ALREADY EYEING THE LOOT. +50%% GOLD THIS FIGHT." % a.name, "", color)
		if id == "PUMPED":
			c.pumped[a.id] = true
			say("%s IS PUMPED. DOUBLE DAMAGE THIS FIGHT!" % a.name, "", color)
		a.buff = null


func _buff_damage(a: Dictionary, spec: String) -> int:
	var mods = a.get("mods")
	return J.round_js(Dnd.roll_dice(spec) * dmg_scale(G.floor) * (mods.dmg if mods != null else 1))


func history(text: String) -> void:
	var h: Array = G.combat.history
	if h.is_empty() or h[h.size() - 1] != text:
		h.append(text)


func hit_enemy(e: Dictionary, dmg: int, note: String, color := "#ffffff", opts := {}) -> void:
	var crit: bool = opts.get("crit", false)
	e.hp -= dmg
	fx.emit("enemy:hit", {"dmg": dmg, "maxHp": e.maxHp, "crit": crit, "at": fx_now()})
	e.damageTaken = J.nz(e.get("damageTaken"), 0) + dmg
	e.thisRound.append(note)
	hurt_until[e.id] = fx_now() + 300
	float_on(e, "-%d" % dmg, color, 13)
	if e.cond.get("asleep"):
		e.cond.erase("asleep")
		if e.hp > 0:
			say("%s WAKES UP!" % UP(e.name), "dim")


## Anyone brought to 0 HP by the last action dies now (after the attack lines are logged).
func reap_enemies(killer) -> void:
	if G.combat == null:
		return
	for e in G.combat.enemies:
		if e.status == "here" and e.hp <= 0:
			kill_enemy(e, killer)


func xp_of(e: Dictionary) -> int:
	var rank := 4.0 if e.get("boss") else (1.5 if e.get("elite") else 1.0)
	return J.round_js(Species.SPECIES[e.species].xp * (1 + 0.25 * (G.floor - 1)) * (1.5 if e.get("shiny") else 1.0) * rank)


## An enemy dies. `by` is a party member (or an ally's buff); monster-on-monster kills pass `by_monster`.
func kill_enemy(e: Dictionary, _by, by_monster = null) -> void:
	var c = G.combat
	var sp: Dictionary = Species.SPECIES[e.species]
	e.status = "dead"
	var depth: float = 1 + 0.3 * (G.floor - 1)
	var rank := 5.0 if e.get("boss") else (1.5 if e.get("elite") else 1.0)
	var bonus: float = (2.0 if e.get("shiny") else 1.0) * rank * J.nz(c.get("goldBonus"), 1) * G.goldMult
	var gold := J.round_js(J.rnd(sp.gold[0], sp.gold[1]) * depth * bonus * (0.5 if by_monster != null else 1.0))
	var xp := J.round_js(xp_of(e) * (0.5 if by_monster != null else 1.0))
	G.gold += gold
	sfx.play("kill")
	fx.emit("enemy:kill", {"boss": J.truthy(e.get("boss")), "at": fx_now()})
	print("kill: %s%s, +%d xp, +%d gold" % [e.name, " by %s" % by_monster.name if by_monster != null else "", xp, gold])
	if by_monster != null:
		say("%s IS KILLED BY %s! +%d EXPERIENCE, +%d GOLD." % [UP(e.name), UP(by_monster.name), xp, gold], "big", color_of(e))
		history("%s killed %s." % [by_monster.name, e.name])
		for o in present():
			o.thisRound.append("%s killed %s." % [by_monster.name, e.name])
	else:
		c.kills += 1
		say("%s IS SLAIN! +%d EXPERIENCE, +%d GOLD." % [UP(e.name), xp, gold], "big", color_of(e))
		var last = c.lastLines.get(e.id) if c.get("lastLines") != null else null
		var said := J.truthy(last)
		history("The party killed %s, the %s, and took %d gold.%s" % [e.name, sp.label, gold, (' Its last words were: "%s"' % last) if said else ""])
		vow_event("kill", e.species, "The party killed %s, %s%s." % [e.name, a_label(e.species), (', whose last words were "%s"' % last) if said else ""])
		for o in present():
			o.thisRound.append("The party killed %s." % e.name)
	grant_xp(xp)
	if c.target == e.id:
		var here := present()
		c.target = here[0].id if not here.is_empty() else null


# ---- dice helpers for the party

## Advantage (+1), disadvantage (-1) or neither (0) when `attacker` attacks monster `e`. Both cancel, as in 5e.
static func adv_vs(e: Dictionary, attacker: Dictionary) -> int:
	var c: Dictionary = e.cond
	var a: Dictionary = J.nz(attacker.get("cond"), {})
	var adv := 1 if (c.get("asleep") or c.get("held") or c.get("exposed") or c.get("lit")) else 0
	var dis := 1 if (c.get("dodging") or a.get("poisoned") or a.get("restrained")) else 0
	return adv - dis


static func eff_ac(e: Dictionary) -> int:
	return e.ac - (3 if e.cond.get("enraged") else 0)


static func mood_hit(m: Dictionary) -> int:
	var mood = m.get("mood")
	var id = mood.get("id") if mood is Dictionary else null
	return -2 if id == "DISTRACTED" else (1 if id == "STEADY" else 0)


static func attack_bonus(m: Dictionary) -> int:
	if m.kind == "human":
		return Dnd.prof(m.level) + m.abil[Dnd.CLASSES[m.clsId].weapon.stat] + m.mods.hitBonus
	return 2 + Dnd.prof(m.level) + m.mods.hitBonus + mood_hit(m)


func weapon_damage(m: Dictionary, crit: bool) -> int:
	var dmg
	if m.kind == "human":
		var w: Dictionary = Dnd.CLASSES[m.clsId].weapon
		dmg = Dnd.roll_dice(w.dice, {"crit": crit}) + m.abil[w.stat]
	else:
		dmg = J.rnd(m.dmg[0], m.dmg[1]) + (J.rnd(m.dmg[0], m.dmg[1]) if crit else 0)
	if G.combat.get("pumped", {}).has(m.id):
		dmg *= 2
	return maxi(1, J.round_js(dmg * m.mods.dmg))


static func attack_count(m: Dictionary) -> int:
	return (2 if m.get("clsId") == "fighter" and m.level >= 5 else 1) * m.mods.hits


static func spell_dc(m: Dictionary) -> int:
	return 8 + Dnd.prof(m.level) + m.abil[Dnd.CLASSES[m.clsId].caster]


static func spell_attack(m: Dictionary) -> int:
	return Dnd.prof(m.level) + m.abil[Dnd.CLASSES[m.clsId].caster] + m.mods.hitBonus


static func spell_damage(m: Dictionary, total) -> int:
	return maxi(1, J.round_js(total * m.mods.spell * m.mods.dmg))


func monster_save(e: Dictionary, stat: String) -> int:
	var r := Dnd.d20()
	var total: int = r.roll + Dnd.MONSTER_STATS[e.species].saves[stat] + e.saveBonus
	roll_fx(r, spot_of(e), {"total": total})
	return total


## "ROLLED 12, NEEDED 14": a saving throw in the log, without DC jargon
static func save_text(sv, dc) -> String:
	return "ROLLED %s, NEEDED %s" % [J.num(sv), J.num(dc)]


func party_save(v: Dictionary, stat: String) -> int:
	var bless := Dnd.d(4) if G.combat != null and G.combat.get("blessed") else 0
	var r := Dnd.d20()
	var mod: int
	if v.kind == "human":
		mod = v.abil[stat] + (Dnd.prof(v.level) if Dnd.CLASSES[v.clsId].saves.has(stat) else 0)
	else:
		mod = 2 + floori(v.level / 4.0)
	var total: int = r.roll + bless + mod
	roll_fx(r, spot_of(v), {"total": total})
	return total


## Bosses can refuse to fail: the first two times a spell would sleep or hold them.
func use_legendary(e: Dictionary) -> bool:
	if not (e.get("legendary", 0) > 0):
		return false
	e.legendary -= 1
	say("%s SHRUGS IT OFF! (LEGENDARY RESISTANCE, %d LEFT)" % [UP(e.name), e.legendary], "warn", color_of(e))
	float_on(e, "RESISTED", color_of(e), 9)
	return true


## One creature's weapon attacks this turn. Up to three attacks are logged one by one; more get a summary.
func weapon_attacks(m: Dictionary, attacks: int) -> String:
	var c = G.combat
	var color = color_of(m) if m.kind == "monster" else null
	var results := []
	for i in attacks:
		var e = target_enemy()
		if e == null:
			break
		if m.kind == "monster" and m.species == e.species:
			say("%s WON'T ATTACK ITS OWN KIND." % m.name, "dim", color)
			return "refused to fight %s, one of its own kind" % e.name
		var r := Dnd.d20(adv_vs(e, m))
		var bonus: int = attack_bonus(m) + (2 if e.cond.get("weakspot") else 0) + (Dnd.d(4) if c.get("blessed") else 0)
		if attacks <= 3:
			roll_fx(r, spot_of(e), {"total": r.roll + bonus})
		var ac := eff_ac(e)
		var helpless = e.cond.get("asleep") or e.cond.get("held")
		var meets: bool = r.roll + bonus >= ac
		var crit: bool = r.roll != 1 and (r.roll >= m.mods.critMin or (helpless and meets))
		var hit: bool = r.roll != 1 and (crit or meets)
		e.cond.erase("lit")
		var dmg := 0
		if hit:
			dmg = weapon_damage(m, crit)
			if J.truthy(m.mods.lifesteal):
				m.hp = mini(m.maxHp, m.hp + ceili(dmg * m.mods.lifesteal))
			hit_enemy(e, dmg, "%s hit you%s for %d." % [m.name, " with a critical blow" if crit else "", dmg], "#ffe03a" if crit else "#ffffff", {"crit": crit})
			if crit:
				float_on(e, "CRITICAL!", "#ffe03a", 9)
		else:
			float_on(e, "FUMBLE" if r.roll == 1 else "MISS", "#8a8a8a", 9)
		sfx.play("crit" if crit else ("hit" if hit else "miss"))
		ach.on("attack-roll", {"roll": r.roll})
		results.append({"e": e, "hit": hit, "crit": crit, "dmg": dmg})
		if attacks <= 3:
			var verdict: String
			if not hit:
				verdict = "A 1 ALWAYS MISSES. FUMBLE!" if r.roll == 1 else "MISS."
			else:
				verdict = "%s%d DAMAGE." % ["A PERFECT 20! CRITICAL HIT! " if r.roll == 20 else ("CRITICAL HIT! " if crit else "HIT! "), dmg]
			say("%s ATTACKS %s: %s VS ARMOR %d. %s" % [m.name, UP(e.name), Dnd.fmt_roll(r, bonus), ac, verdict], ("big" if crit else "") if hit else "dim", color)
			render()
			if i < attacks - 1:
				await _sleep(240)
	if attacks > 3 and not results.is_empty():
		var hits := results.filter(func(x): return x.hit)
		var crits := hits.filter(func(x): return x.crit).size()
		var total := 0
		for x in hits:
			total += x.dmg
		say("%s STRIKES %d TIMES: %d HIT%s FOR %d DAMAGE." % [m.name, attacks, hits.size(), (" (%d CRITICAL)" % crits) if crits else "", total], "big" if crits else "", color)
	reap_enemies(m)
	var sum := 0
	var names := []
	for x in results:
		sum += x.dmg
		if not names.has(x.e.name):
			names.append(x.e.name)
	var who := " and ".join(names)
	return "hit %s for %d" % [who, sum] if sum else "swung at %s and missed" % (who if who != "" else "the monsters")


func cast_spell(m: Dictionary, key: String, ally = null) -> String:
	var s: Dictionary = Dnd.SPELLS[key]
	var c = G.combat
	if s.lvl:
		m.slots[s.lvl - 1] -= 1
	var dice_spec = s.get("dice")
	if s.get("cantrip") and dice_spec != null:
		dice_spec = "%d%s" % [Dnd.cantrip_dice(m.level), dice_spec.substr(1)]
	say("%s CASTS %s!" % [m.name, s.name], "you")
	sfx.play(s.sfx)
	render()
	await _sleep(220)
	var parts := []
	var note := "cast %s" % s.name.to_lower()
	match s.kind:
		"attack":
			for i in s.get("rays", 1):
				var e = target_enemy()
				if e == null:
					break
				var r := Dnd.d20(adv_vs(e, m))
				var bonus: int = spell_attack(m) + (2 if e.cond.get("weakspot") else 0) + (Dnd.d(4) if c.get("blessed") else 0)
				roll_fx(r, spot_of(e), {"total": r.roll + bonus})
				var ac := eff_ac(e)
				var crit: bool = r.roll != 1 and r.roll >= m.mods.critMin
				var hit: bool = r.roll != 1 and (crit or r.roll + bonus >= ac)
				ach.on("attack-roll", {"roll": r.roll})
				e.cond.erase("lit")
				var who := "%s " % UP(e.name)
				if hit:
					var dmg := spell_damage(m, Dnd.roll_dice(dice_spec, {"crit": crit}))
					hit_enemy(e, dmg, "%s's %s hit you for %d." % [m.name, s.name.to_lower(), dmg], "#ffe03a" if crit else "#ff9a3d", {"crit": crit})
					if s.get("effect") == "lit":
						e.cond.lit = 2
					parts.append("%s%s VS ARMOR %d: %s%d DAMAGE%s" % [who, Dnd.fmt_roll(r, bonus), ac, "CRITICAL HIT, " if crit else "", dmg, ". IT GLOWS: THE NEXT ATTACK ON IT IS BETTER" if s.get("effect") == "lit" else ""])
					sfx.play("crit" if crit else "hit")
				else:
					float_on(e, "MISS", "#8a8a8a", 9)
					parts.append("%s%s VS ARMOR %d: MISS" % [who, Dnd.fmt_roll(r, bonus), ac])
		"auto":
			var tally := {}
			for i in s.darts:
				var e = target_enemy()
				if e == null:
					break
				var dmg := spell_damage(m, Dnd.roll_dice(dice_spec))
				hit_enemy(e, dmg, "%s's magic dart hit you for %d." % [m.name, dmg], "#b79cf0")
				var n := UP(e.name)
				if not tally.has(n):
					tally[n] = []
				tally[n].append(dmg)
				await _sleep(90)
			for n in tally:
				var sum := 0
				for x in tally[n]:
					sum += x
				parts.append("%s TAKES %s = %d" % [n, " + ".join(tally[n].map(func(x): return str(x))), sum])
		"save":
			var dc := spell_dc(m)
			var targets: Array
			if s.target == "all":
				targets = present()
			else:
				var t = target_enemy()
				targets = [t] if t != null else []
			for e in targets:
				var sv := monster_save(e, s.save)
				if s.get("effect") == "held":
					if sv >= dc or use_legendary(e):
						parts.append("%s RESISTS (%s)" % [UP(e.name), save_text(sv, dc)])
					else:
						e.cond.held = 1
						e.holdDC = dc
						float_on(e, "PARALYZED", "#8fd3ff", 9)
						parts.append("%s IS PARALYZED (%s)! IT LOSES TURNS AND YOUR HITS ARE CRITICAL" % [UP(e.name), save_text(sv, dc)])
					continue
				var saved := sv >= dc
				var dmg := spell_damage(m, Dnd.roll_dice(dice_spec))
				if saved:
					dmg = floori(dmg / 2.0) if s.get("half") else 0
				if dmg > 0:
					hit_enemy(e, dmg, "%s's %s hit you for %d." % [m.name, s.name.to_lower(), dmg], "#ff9a3d")
				else:
					float_on(e, "DODGED", "#8a8a8a", 9)
				parts.append("%s %s (%s): %d DAMAGE" % [UP(e.name), ("DODGES HALF" if s.get("half") else "DODGES IT") if saved else "IS HIT", save_text(sv, dc), dmg])
		"sleep":
			# A pool of hit points: the weakest monsters drop off first. Grows with depth so it stays useful.
			var pool := J.round_js(Dnd.roll_dice(dice_spec) * m.mods.spell * hp_scale(G.floor) * 0.7)
			parts.append("SLEEP STRONG ENOUGH FOR %d HEALTH" % pool)
			var slept := []
			var here := present()
			var order := range(here.size())
			order.sort_custom(func(a, b): return here[a].hp < here[b].hp or (here[a].hp == here[b].hp and a < b))
			for i in order:
				var e = here[i]
				if e.hp > pool:
					break
				if use_legendary(e):
					continue
				pool -= e.hp
				e.cond.asleep = 10
				float_on(e, "ASLEEP", "#8fd3ff", 9)
				slept.append(UP(e.name))
			parts.append("%s FALL%s ASLEEP" % [" AND ".join(slept), "" if slept.size() > 1 else "S"] if not slept.is_empty() else "NO ONE IS WEAK ENOUGH TO SLEEP")
			note = ("put %s to sleep" % " and ".join(slept)) if not slept.is_empty() else "tried to cast a sleep spell"
		"heal":
			for x in (living() if s.target == "party" else [ally]):
				var amt := maxi(1, J.round_js((Dnd.roll_dice(dice_spec) + m.abil.wis) * m.mods.spell))
				heal(x, amt)
				parts.append("%s +%d" % [x.name, amt])
			note = "healed %s" % ("the party" if s.target == "party" else ally.name)
		"bless":
			c.blessed = true
			parts.append("THE PARTY GETS +1 TO 4 ON ATTACKS AND SAVES THIS FIGHT")
			note = "blessed the party"
		"revive":
			revive(ally)
			note = "brought %s back from the dead" % ally.name
	if not parts.is_empty():
		say("%s: %s." % [s.name, " · ".join(parts)], "", "#8fd3ff")
	reap_enemies(m)
	return note


func heal(x: Dictionary, amt: int) -> void:
	if x.dead:
		return
	if x.down:
		x.down = false
		x.stable = false
		x.hp = 0
		say("%s GETS BACK UP!" % x.name, "big")
	x.hp = mini(x.maxHp, x.hp + amt)
	float_party(x, "+%d" % amt, "#9ed36b")


func revive(x: Dictionary, hp := 1) -> void:
	x.dead = false
	x.down = false
	x.stable = false
	x.cond = {}
	x.hp = hp
	say("%s GASPS BACK TO LIFE WITH %d HEALTH!" % [x.name, hp], "big", "#ffd27a")
	sfx.play("revive")
	if G.combat != null:
		history("%s was brought back from the dead." % x.name)


# ---- the party's turn

## What a member does on QUICK ATTACK: weapons for most, the free Fire Bolt for the wizard.
static func default_plan(m: Dictionary) -> Dictionary:
	var cond = m.get("cond")
	if cond is Dictionary and cond.get("prone"):
		return {"m": m, "act": "prone"}
	if m.kind == "monster":
		return {"m": m, "act": "ally"}
	if m.clsId == "wizard":
		return {"m": m, "act": "spell", "spell": "fire_bolt"}
	return {"m": m, "act": "attack"}


## CHOOSE MOVES: pick an action for each adventurer in turn (allies act on their own). ESC cancels the turn.
## Each menu shows the member's spell slots by the title; spells show the slots they'd spend, or FREE.
func plan_turn():
	var plans := []
	var orderable := conscious().filter(func(m): return m.kind == "human" and not m.cond.get("prone"))
	for m in conscious():
		if m.kind != "human" or m.cond.get("prone"):
			plans.append(default_plan(m))
			continue
		var w: Dictionary = Dnd.CLASSES[m.clsId].weapon
		var swings := attack_count(m)
		var opts := [{"label": "ATTACK WITH %s" % w.name, "value": {"act": "attack"}, "hint": "HIT YOUR TARGET WITH THE %s%s. ROLLS TO HIT AGAINST ITS ARMOR" % [w.name, (", %d TIMES" % swings) if swings > 1 else ""]}]
		if m.uses.get("second_wind"):
			opts.append({"label": "SECOND WIND", "value": {"act": "second_wind"}, "hint": "HEAL %s, THEN ATTACK. ONCE PER CAMP" % Dnd.dice_range("1d10+%d" % m.level)})
		if m.uses.get("action_surge"):
			opts.append({"label": "ACTION SURGE", "value": {"act": "action_surge"}, "hint": "ATTACK TWICE AS MANY TIMES THIS TURN. ONCE PER CAMP"})
		if m.get("slots") != null:
			for k in Dnd.spells_known(m.clsId, m.level):
				var s: Dictionary = Dnd.SPELLS[k]
				if s.lvl and not (_slot(m, s.lvl - 1) > 0):
					continue
				if s.target == "dead" and not G.party.any(func(x): return x.dead):
					continue
				if s.kind == "bless" and G.combat.get("blessed"):
					continue
				var cost: String = ("USES A %s-CIRCLE SLOT" % Status.CIRCLE_WORDS[s.lvl - 1]) if s.lvl else "FREE, USES NO SLOT"
				opts.append({"label": s.name, "value": {"act": "spell", "spell": k}, "cost": s.lvl, "hint": "%s. %s" % [Dnd.spell_text(k, m.level), cost]})
		var nth := (" (%d OF %d)" % [index_of(orderable, m) + 1, orderable.size()]) if orderable.size() > 1 else ""
		var choice = await choose("WHAT WILL %s DO?%s" % [m.name, nth], opts, {"who": m})
		if choice == null:
			return null
		var plan := {"m": m}
		plan.merge(choice)
		var s = Dnd.SPELLS.get(plan.get("spell", ""))
		if s != null and s.target == "ally":
			var whom := []
			for x in living():
				var st: Dictionary = Status.hp_state(x)
				whom.append({"label": x.name, "value": x, "who": x, "hint": "%s: %d OF %d HEALTH, %s" % [x.name, maxi(0, x.hp), x.maxHp, st.word]})
			plan.ally = await choose("%s: HEAL WHOM?" % s.name, whom)
			if plan.ally == null:
				return null
		if s != null and s.target == "dead":
			plan.ally = await choose("REVIVIFY: BRING WHOM BACK?", G.party.filter(func(x): return x.dead).map(func(x): return {"label": x.name, "value": x}))
			if plan.ally == null:
				return null
		plans.append(plan)
	return plans


func act(p: Dictionary) -> String:
	var m: Dictionary = p.m
	match p.act:
		"prone":
			m.cond.erase("prone")
			say("%s STRUGGLES BACK UP AND LOSES THE TURN." % m.name, "dim", color_of(m) if m.kind == "monster" else null)
			return "got back up after being knocked down"
		"ally":
			return await ally_turn(m)
		"attack":
			return await weapon_attacks(m, attack_count(m))
		"second_wind":
			m.uses.second_wind = 0
			var amt: int = Dnd.d(10) + m.level
			say("%s CATCHES A SECOND WIND!" % m.name, "you")
			sfx.play("heal")
			heal(m, amt)
			var then: String = await weapon_attacks(m, attack_count(m))
			return "caught a second wind, then %s" % then
		"action_surge":
			m.uses.action_surge = 0
			say("%s SURGES INTO ACTION!" % m.name, "big")
			sfx.play("buff")
			return await weapon_attacks(m, attack_count(m) * 2)
		"spell":
			return await cast_spell(m, p.spell, p.get("ally"))
	return ""


## Monster allies fight on their own: their species' special every few rounds, otherwise their attack.
func ally_turn(a: Dictionary) -> String:
	var e = target_enemy()
	if e == null:
		return ""
	var mood = a.get("mood")
	if mood is Dictionary and mood.get("id") == "SULKING":
		say("%s SULKS AND SITS THIS FIGHT OUT." % a.name, "dim", color_of(a))
		return "sulked and refused to fight"
	a.cooldown = J.nz(a.get("cooldown"), 0) - 1
	if a.cooldown <= 0 and a.species != e.species and randf() < 0.5:
		a.cooldown = 3
		var sp: Dictionary = Species.SPECIES[a.species]
		var st: Dictionary = Dnd.MONSTER_STATS[a.species].special
		var dc: int = st.dc + floori((a.level - 1) / 2.0)
		var targets: Array = present().filter(func(x): return x.species != a.species) if sp.special.all else [e]
		var parts := []
		sfx.play("fireball" if a.species == "dragon" else "crit")
		for t in targets:
			var sv := monster_save(t, st.save)
			var dmg := maxi(1, J.round_js(Dnd.roll_dice(st.dice) * (1 + 0.15 * (a.level - 1)) * a.mods.dmg))
			if sv >= dc:
				dmg = floori(dmg / 2.0)
			hit_enemy(t, dmg, "%s's special attack hit you for %d." % [a.name, dmg], color_of(a))
			parts.append("%s %s (%s): %d DAMAGE" % [UP(t.name), "DODGES HALF" if sv >= dc else "IS HIT", save_text(sv, dc), dmg])
		var desc := _replace_first(_replace_first(UP(sp.special.desc), "ONE PARTY MEMBER", "THE FOE"), "THE WHOLE PARTY", "THE MONSTERS")
		say("%s USES ITS SPECIAL: %s! %s." % [a.name, desc, " · ".join(parts)], "big", color_of(a))
		reap_enemies(a)
		return "used its special attack on %s" % " and ".join(targets.map(func(t): return t.name))
	return await weapon_attacks(a, a.mods.hits)


func party_turn(plans: Array) -> void:
	var c = G.combat
	G.busy = true
	render()
	var target = target_enemy()
	var offensive := plans.any(func(p): return p.act != "prone" and not (p.get("spell") and ["heal", "bless", "revive"].has(Dnd.SPELLS[p.spell].kind)))
	if offensive:
		ach.on("attack")
	if offensive and target != null:
		if not c.spoken.has(target.species):
			vow_event("attack_unspoken", target.species, "The party attacked %s without saying a word to it first." % target.name)
		vow_event("attack", target.species, "The party attacked %s, %s." % [target.name, a_label(target.species)])
	var did := {}
	for p in plans:
		if present().is_empty():
			break
		if p.m.dead or p.m.down:
			continue
		did[p.m.id] = await act(p)
		render()
		await _sleep(380)
	# Poison and bindings wear off over a few of your turns
	for m in G.party:
		for k in ["poisoned", "restrained"]:
			var cond = m.get("cond")
			if cond is Dictionary and cond.get(k):
				cond[k] -= 1
				if cond[k] <= 0:
					cond.erase(k)
					say("%s IS NO LONGER %s." % [m.name, Status.CONDITIONS[k].word], "dim")
	var cast := plans.any(func(p): return p.act == "spell" and not Dnd.SPELLS[p.spell].get("cantrip", false))
	if target != null and offensive:
		c.rounds[target.id] = J.nz(c.rounds.get(target.id), 0) + 1
		var n: int = c.rounds[target.id]
		var line := "The party attacked %s%s." % [target.name, (" for %d rounds" % n) if n > 1 else ""]
		var at := -1
		for i in c.history.size():
			if c.history[i].begins_with("The party attacked %s" % target.name):
				at = i
				break
		if at >= 0:
			c.history[at] = line
		else:
			history(line)
	var events := []
	for id in did:
		var who = "Someone"
		for m in G.party:
			if m.id == id:
				who = m.name
				break
		events.append("%s %s." % [who, did[id]])
	await after_party_action(_put({"type": "cast" if cast else "fight"}, "targetId", target.id if target != null else null), events.slice(0, 8), did)


## A Charisma check for whoever does the talking. Good delivery makes words land harder, either way.
func charisma_check() -> float:
	var f = face()
	if f == null:
		return 1
	var r := Dnd.d20()
	var bonus: int = f.abil.cha + Dnd.prof(f.level)
	var total: int = r.roll + bonus
	var mult: float
	var word: String
	if r.roll == 20:
		mult = 2; word = "AN INSPIRED"
	elif r.roll == 1:
		mult = 0.5; word = "A TONGUE-TIED"
	elif total >= 20:
		mult = 1.5; word = "A MAGNETIC"
	elif total >= 15:
		mult = 1.25; word = "A CONFIDENT"
	elif total >= 10:
		mult = 1; word = "A STEADY"
	else:
		mult = 0.75; word = "A SHAKY"
	roll_fx(r, spot_of(f), {"total": total})
	ach.on("talk-roll", {"roll": r.roll})
	say("HOW WELL %s SAYS IT (CHARISMA): %s. %s DELIVERY: WORDS LAND X%s." % [f.name, Dnd.fmt_roll(r, bonus), word, J.num(mult)], "dim")
	return mult


## Ask the targeted monster to join: a Persuasion roll against a DC set by how it feels about you.
func recruit_ask() -> void:
	var c = G.combat
	var e = target_enemy()
	if G.party.size() >= Status.PARTY_MAX:
		say("YOUR PARTY IS FULL (6).", "dim")
		render()
		return
	var f = face()
	if f == null:
		say("NO ONE IS IN ANY STATE TO TALK.", "dim")
		render()
		return
	var text = await ask_text("ASK %s TO JOIN YOU. ADD WORDS, OR JUST PRESS ENTER:" % UP(e.name))
	if text is Cancelled:
		render()
		return
	var need: int = Species.SPECIES[e.species].joinThreshold + (15 if e.formerAlly else 0) + (20 if e.get("boss") else 0)
	# Harder when it dislikes or is angry at you; easier once it is losing the fight
	var losing := 3 if float(e.hp) / e.maxHp < 0.35 else 0
	var dc := maxi(5, mini(25, 8 + J.round_js((need - e.meters.friendliness) / 4.0) + J.round_js(e.meters.anger / 15.0) - losing))
	var r := Dnd.d20()
	var bonus: int = f.abil.cha + Dnd.prof(f.level)
	var margin: int = r.roll + bonus - dc
	var pitch: String
	if r.roll == 20 or margin >= 8:
		pitch = "great"
	elif r.roll == 1 or margin <= -12:
		pitch = "botch"
	elif margin >= 0:
		pitch = "success"
	elif margin >= -4:
		pitch = "close"
	else:
		pitch = "fail"
	var WORD := {"great": "AN IRRESISTIBLE PITCH!", "success": "A CONVINCING PITCH.", "close": "SO CLOSE...", "fail": "A CLUMSY PITCH.", "botch": "A DISASTROUS PITCH!", "lucky": "BEGINNER'S LUCK: IT LANDS ANYWAY."}
	# The guided first fight: the first invitation always lands (and says so when the dice alone wouldn't have)
	var lucky: bool = J.truthy(c.guide) and not ["great", "success"].has(pitch)
	if lucky:
		pitch = "success"
	say(('YOU, TO %s: "%s"' % [UP(e.name), text]) if _said(text) else "YOU ASK %s TO JOIN YOUR PARTY." % UP(e.name), "you")
	roll_fx(r, spot_of(e), {"total": r.roll + bonus})
	ach.on("talk-roll", {"roll": r.roll})
	say("PERSUASION (%s): %s, NEEDED %d. %s" % [f.name, Dnd.fmt_roll(r, bonus), dc, WORD["lucky" if lucky else pitch]], "big" if ["great", "success"].has(pitch) else ("" if pitch == "close" else "warn"))
	print("recruit %s: dc %d, %s" % [e.name, dc, pitch])
	for x in present():
		c.spoken[x.species] = true
		vow_event("talk", x.species, "The party talked to %s, %s." % [x.name, a_label(x.species)])
	history("The party asked %s to join them%s." % [e.name, (', saying: "%s"' % text) if _said(text) else ""])
	var delivery: float = 2.0 if r.roll == 20 else (1.5 if pitch == "great" else (1.25 if pitch == "success" else (0.5 if pitch == "botch" else 1.0)))
	await after_party_action({"type": "recruit", "targetId": e.id, "pitch": pitch, "message": text if _said(text) else null, "delivery": delivery}, ["The party asked %s to join them." % e.name], {f.id: "asked %s to join the party" % e.name})


func command(cmd: String) -> void:
	var c = G.combat
	if c == null or G.busy:
		return
	var here := present()
	if not Tutorial.guide_allows(c.guide, cmd):
		# The lesson: only its one key works. Shake the dock and the tip so the eye goes to the lit key.
		print_verbose('guide: %s step, "%s" waits' % [c.guide, cmd])
		tips.insist(Tutorial.GUIDE[c.guide].hint)
		ui.nudge_dock()
		return
	if cmd in ["1", "2", "3"]:
		var i := int(cmd) - 1
		if i < here.size():
			c.target = here[i].id
		render()
		return
	var target = target_enemy()
	if target == null:
		return

	if cmd == "f":
		await party_turn(conscious().map(default_plan))
		return
	if cmd == "c":
		var plans = await plan_turn()
		if plans == null:
			render()
			return
		await party_turn(plans)
		return

	if cmd == "t":
		var text = await ask_text("WHAT DO YOU SAY? (ALL OF THEM HEAR)" if here.size() > 1 else "WHAT DO YOU SAY?")
		if not _said(text):
			render()
			return
		say('YOU: "%s"' % text, "you")
		if c.guide == "talk":
			c.guide = Tutorial.GUIDE.talk.next
		var delivery := charisma_check()
		history('The party said: "%s"' % text)
		for e in here:
			c.spoken[e.species] = true
			vow_event("talk", e.species, "The party talked to %s, %s." % [e.name, a_label(e.species)])
		await after_party_action({"type": "talk", "message": text, "delivery": delivery}, ["The party spoke."], {leader().id: "spoke on behalf of the party"})
		return

	if cmd == "r":
		await recruit_ask()
		return

	if cmd == "g":
		if G.gold <= 0:
			say("YOU HAVE NO GOLD.", "dim")
			render()
			return
		var text = await ask_text("GIVE %s HOW MUCH GOLD? (HAVE %s)" % [UP(target.name), J.num(G.gold)], true)
		var gold := mini(G.gold, maxi(0, floori(_js_number(text))))
		if not gold:
			render()
			return
		say("YOU OFFER %s %d GOLD." % [UP(target.name), gold], "you")
		sfx.play("gold")
		history("The party offered %s %d gold." % [target.name, gold])
		await after_party_action({"type": "give", "gold": gold, "targetId": target.id}, ["The party offered %s %d gold." % [target.name, gold]], {leader().id: "held out %d gold to %s" % [gold, target.name]})
		return

	if cmd == "v":
		await make_vow()
		return

	if cmd == "e":
		var dex = _max_of(conscious().map(func(m): return m.abil.dex if m.get("abil") != null else 1))
		var dc: int = 10 + (5 if here.any(func(e): return e.get("boss")) else 0) + (3 if here.any(func(e): return e.species == "dragon") else 0) + floori(G.floor / 3.0)
		var r := Dnd.d20()
		var ok: bool = r.roll + dex >= dc
		roll_fx(r, {"x": 224, "y": 150}, {"total": r.roll + dex})
		say("ESCAPE: %s, NEEDED %d. %s" % [Dnd.fmt_roll(r, dex), dc, "YOU FLEE!" if ok else "YOU CAN'T GET AWAY!"], "" if ok else "warn")
		if ok:
			sfx.play("flee")
			for e in here:
				history("The party ran away from %s." % e.name)
				vow_event("flee", e.species, "The party ran away from %s, %s." % [e.name, a_label(e.species)])
			await flush_breaks()
			await end_combat()
			return
		sfx.play("miss")
		await after_party_action({"type": "run_failed"}, ["The party tried to run away, but failed."], {})
		return
	tips.ignored(cmd) # not a fight command: nudge the hint rather than swallow the key silently


func after_party_action(player_action: Dictionary, events: Array, did: Dictionary) -> void:
	render()
	await flush_breaks()
	if G.combat == null:
		return
	if present().is_empty():
		await end_combat()
		return
	await monsters_turn(player_action, events, did)


## Start of the party's turn: anyone at 0 HP makes a death saving throw.
func begin_party_turn() -> void:
	if G.combat == null:
		return
	for m in G.party:
		if not m.down or m.dead or m.get("stable"):
			continue
		var dr := Dnd.d20()
		var r: int = dr.roll
		roll_fx(dr, spot_of(m))
		if r == 20:
			m.down = false
			m.hp = 1
			say("%s'S DEATH SAVE: A PERFECT 20! BACK UP WITH 1 HEALTH!" % m.name, "big")
			sfx.play("revive")
		elif r >= 10:
			m.saves.s += 1
			say("%s'S DEATH SAVE: ROLLED %d, NEEDED 10. SUCCESS, %d OF 3." % [m.name, r, m.saves.s], "dim")
			sfx.play("save")
			if m.saves.s >= 3:
				m.stable = true
				say("%s IS STABLE, BUT STILL OUT COLD." % m.name, "dim")
		else:
			death_fail(m, 2 if r == 1 else 1, "'S DEATH SAVE: ROLLED %d, NEEDED 10%s. FAILURE" % [r, " (A 1 COUNTS TWICE)" if r == 1 else ""])
		ach.on("death-save", {"roll": r, "stable": J.truthy(m.get("stable"))})
	if not humans_alive() or conscious().is_empty():
		game_over()
		return
	G.busy = false
	if G.combat.guide:
		hint(Tutorial.GUIDE[G.combat.guide].hint)
	render()


func death_fail(m: Dictionary, n: int, why: String) -> void:
	m.saves.f += n
	say("%s%s (%d OF 3 FAILURES)." % [m.name, why, mini(3, m.saves.f)], "warn")
	if m.saves.f >= 3:
		die(m)


func die(m: Dictionary) -> void:
	m.dead = true
	m.down = false
	say("%s DIES." % m.name, "big warn")
	sfx.play("death")
	print("death: %s" % m.name)
	if G.combat != null:
		history("%s died." % m.name)
	if m.kind == "monster":
		G.party = _without(G.party, m)


## A party member takes damage. At 0 HP they fall unconscious and start making death saves;
## hits while down count as failed saves (a critical hit counts as two).
func damage(m: Dictionary, dmg: int, opts := {}) -> void:
	var crit: bool = opts.get("crit", false)
	if m.dead:
		return
	if m.down:
		death_fail(m, 2 if crit else 1, " IS HIT WHILE DOWN")
		return
	m.hp = maxi(0, m.hp - dmg)
	float_party(m, "-%d" % dmg, "#ff5a4a")
	fx.emit("party:hurt", {"dmg": dmg, "hp": m.hp, "maxHp": m.maxHp, "at": fx_now()})
	sfx.play("hurt")
	if m.hp > 0:
		return
	if m.get("phoenix"):
		m.phoenix = false
		m.hp = ceili(m.maxHp / 2.0)
		say("%s FALLS... AND RISES AGAIN IN A BURST OF PHOENIX FIRE!" % m.name, "big", "#ffb347")
		sfx.play("revive")
		return
	m.down = true
	m.stable = false
	m.saves = {"s": 0, "f": 0}
	m.cond = {}
	say("%s FALLS UNCONSCIOUS! HEAL THEM, OR THEY ROLL TO SURVIVE EACH TURN (DEATH SAVES)." % m.name, "big warn")
	fx.emit("party:down", {"at": fx_now()})
	hint("down")
	sfx.play("down")
	if G.combat != null:
		history("%s was knocked unconscious." % m.name)


# ---- the monsters' turn

## One Jev request for the whole group, then apply each monster's feeling and move in order.
func monsters_turn(player_action: Dictionary, events: Array, did: Dictionary) -> void:
	var c = G.combat
	G.busy = true
	c.round += 1
	if c.get("opening"):
		events = [c.opening] + events
		c.opening = null
	render()
	# Sleeping and paralyzed monsters can't act, or listen
	var here := present()
	for e in here:
		if e.cond.get("asleep"):
			say("%s SNORES." % UP(e.name), "dim", color_of(e))
		elif e.cond.get("held"):
			var sv := monster_save(e, "wis")
			if sv >= J.nz(e.get("holdDC"), 13):
				e.cond.erase("held")
				e.justFreed = true
				say("%s BREAKS THE HOLD (WISDOM ROLL %d)! IT CAN ACT NEXT ROUND." % [UP(e.name), sv], "warn", color_of(e))
			else:
				say("%s STRAINS AGAINST THE MAGIC (WISDOM ROLL %d), STILL PARALYZED." % [UP(e.name), sv], "dim", color_of(e))
	var acting := here.filter(func(e): return not e.cond.get("asleep") and not e.cond.get("held") and not e.get("justFreed"))
	if acting.is_empty():
		end_monster_round()
		await begin_party_turn()
		return
	var monsters := []
	for e in acting:
		monsters.append({
			"id": e.id,
			"species": e.species,
			"name": e.name,
			"traits": e.traits,
			"boss": J.truthy(e.get("boss")),
			"hp": maxi(0, e.hp),
			"maxHp": e.maxHp,
			"meters": e.meters,
			"specialReady": e.cooldown <= 0,
			"paid": e.paid,
			"demanded": e.demanded,
			"impressions": e.impressions,
			"formerAlly": e.formerAlly,
			"grudges": e.grudges,
			"thisRound": e.thisRound,
			"damageTaken": e.damageTaken,
		})
	var party := []
	for m in G.party:
		var p := {"id": m.id, "name": m.name, "kind": m.kind}
		_put(p, "species", m.get("species"))
		p.merge({"cls": m.cls, "hp": maxi(0, m.hp), "maxHp": m.maxHp, "dead": m.dead or m.down})
		_put(p, "didThisRound", did.get(m.id))
		party.append(p)
	var out := await api("/api/group-turn", {
		"monsters": monsters,
		"party": party,
		"round": c.round,
		"playerAction": player_action,
		"events": events,
		"conversation": c.conversation,
		"partyGold": G.gold,
		"guided": J.truthy(c.guide),
		"vows": G.vows.map(func(v): return {"text": v.text.to_lower(), "toId": v.toId, "status": v.status}),
	})
	if G.combat == null or not is_same(G.combat, c):
		push_warning("group-turn: the fight ended while Jev was deciding")
		return
	if out.has("error"):
		say("(JEV UNREACHABLE: %s. THE MONSTERS HESITATE.)" % out.error, "dim")
		end_monster_round()
		await begin_party_turn()
		return
	for e in acting:
		e.thisRound = []
		e.damageTaken = 0
	if J.truthy(player_action.get("message")):
		c.conversation.append({"speaker": "Party", "text": player_action.message})
	ui.show_jev({"kind": "group", "out": out, "here": acting})

	var joins := []
	if c.get("lastLines") == null:
		c.lastLines = {}
	for r in out.results:
		var e = null
		for x in c.enemies:
			if x.id == r.id:
				e = x
				break
		if e == null or e.status != "here" or e.hp <= 0:
			continue
		var before: String = e.side
		e.meters = r.meters.duplicate()
		e.impressions = r.impressions.duplicate()
		e.side = r.side
		if r.side == "friendly with the party" and not G.combat.guide:
			hint("recruit") # the lesson has its own recruit tip
		# Its reply as the player meets it: how it reacts, what it says, and why it said yes or no to joining
		# A monster's side starts as a placeholder, so only a change after its first reply is news
		var told: Array = Narrate.group_log(r, {"name": e.name, "species": e.species, "sideBefore": before if e.get("replied") else null, "debug": DEBUG})
		e.replied = true
		var answer = null
		for l in told:
			if l.kind == "join":
				answer = l.text
				break
		var unspoken: bool = r.get("spoken") is bool and r.spoken == false
		c.lastLines[e.id] = r.line
		c.conversation.append({"speaker": e.name, "text": J.nz(answer, r.line) if unspoken else r.line})
		print("%s: %s → %s%s" % [e.name, r.get("picked"), r.action, " (blocked: %s)" % r.blocked if J.truthy(r.get("blocked")) else ""])
		for l in told:
			say(l.text, l.cls, null if l.kind == "debug" else color_of(e))
		if not unspoken:
			speak(e, r.line)
		if J.truthy(r.get("emotion")):
			show_emotion(e, r.emotion)
		if e.cooldown > 0:
			e.cooldown -= 1
		# Someone switching sides is news to the rest of the group
		if before != r.side and r.side == "friendly with the party":
			for o in present():
				if not is_same(o, e):
					o.thisRound.append("%s just sided with the party against you." % e.name)
					o.impressions.append("%s turned traitor and sided with the party." % e.name)
		await apply_monster_action(e, r, joins)
		render()
		await _sleep(340)
		if not humans_alive() or conscious().is_empty():
			break
	if not humans_alive() or conscious().is_empty():
		game_over()
		return
	end_monster_round()
	G.busy = false
	render()
	await flush_breaks()
	if G.combat == null:
		return
	for e in joins:
		if e.status != "here":
			continue
		if G.party.size() >= Status.PARTY_MAX:
			say("%s WANTS TO JOIN, BUT YOUR PARTY IS FULL." % UP(e.name), "dim")
			continue
		var guided: bool = G.combat != null and J.truthy(G.combat.guide)
		var yes = await ask("%s WANTS TO JOIN. ACCEPT?" % UP(e.name), {"yes": "WELCOME IT", "no": null if guided else "TURN IT AWAY"})
		if yes:
			recruit(e)
		else:
			e.status = "left"
			say("YOU TURN %s AWAY. IT WANDERS OFF." % UP(e.name))
			history("%s offered to join, but the party turned it away." % e.name)
			vow_event("spare", e.species, "The party let %s, %s, walk away alive." % [e.name, a_label(e.species)])
		await flush_breaks()
		if G.combat == null:
			return
	if present().is_empty():
		await end_combat()
		return
	await begin_party_turn()


## Each round of conditions on monsters ticks down after they act (a held monster stays held until it saves).
func end_monster_round() -> void:
	if G.combat == null:
		return
	for e in G.combat.enemies:
		e.erase("justFreed")
		for k in e.cond.keys():
			if k != "held":
				e.cond[k] -= 1
				if e.cond[k] <= 0:
					e.cond.erase(k)


## What a feeling does once it's been told in the log (group_log): float, sound, condition, dropped gold.
## Every feeling has teeth.
func show_emotion(e: Dictionary, em: Dictionary) -> void:
	var color := color_of(e)
	float_on(e, "%s!" % em.label, color, 10)
	hint("feeling")
	ach.on("feel", {"feeling": em.id, "species": e.species})
	sfx.play({"good": "good", "bad": "bad", "fear": "fear", "sad": "sad", "odd": "odd"}.get(em.get("tone"), "good"))
	if J.truthy(em.get("cond")):
		e.cond[em.cond] = maxi(J.nz(e.cond.get(em.cond), 0), int(em.rounds))
	if em.id == "terrified":
		var sp: Dictionary = Species.SPECIES[e.species]
		var gold := maxi(1, J.round_js(J.rnd(sp.gold[0], sp.gold[1]) * 0.5 * (1 + 0.3 * (G.floor - 1))))
		G.gold += gold
		say("%s DROPS %d GOLD IN ITS PANIC!" % [UP(e.name), gold], "", color)
		sfx.play("gold")


## A blow aimed at the party, soaked by a BOUNCY or BULWARK ally if one is guarding.
func soak(victim: Dictionary, head := "") -> bool:
	var c = G.combat
	var b = c.get("bouncy")
	if b == null or b.dead or b.down or not (c.get("soaks", 0) > 0):
		return false
	say(("%s %s %s FOR %s!" % [head, b.name, "TAKES THE BLOW ON ITS STONE HIDE" if b.species == "rock" else "BOUNCES THE BLOW AWAY", victim.name]).strip_edges(), "", color_of(b))
	sfx.play("save")
	c.soaks -= 1
	if c.soaks <= 0:
		c.bouncy = null
	return true


func monster_attack(e: Dictionary, t: Dictionary) -> void:
	var tc: Dictionary = J.nz(t.get("cond"), {})
	var adv := 1 if (e.cond.get("enraged") or tc.get("restrained") or tc.get("prone")) else 0
	var dis := 1 if (e.cond.get("demoralized") or e.cond.get("frightened")) else 0
	var r := Dnd.d20(adv - dis)
	roll_fx(r, spot_of(t), {"total": r.roll + e.hit})
	var crit: bool = r.roll == 20
	var hit: bool = r.roll != 1 and (crit or r.roll + e.hit >= t.ac)
	var head := "%s ATTACKS %s: %s VS ARMOR %s." % [UP(e.name), t.name, Dnd.fmt_roll(r, e.hit), J.num(t.ac)]
	if not hit:
		say("%s %s" % [head, "FUMBLE!" if r.roll == 1 else "MISS."], "dim")
		float_party(t, "MISS", "#8a8a8a")
		sfx.play("miss")
		return
	var dmg: int = maxi(1, J.round_js(Dnd.roll_dice(Dnd.MONSTER_STATS[e.species].dmg, {"crit": crit}) * e.dmgMult)) + (2 if e.cond.get("spiteful") else 0) + (3 if e.cond.get("enraged") else 0)
	if soak(t, head):
		return
	say("%s %s%s TAKES %d." % [head, "CRITICAL HIT! " if crit else "HIT! ", t.name, dmg], "warn")
	damage(t, dmg, {"crit": crit})


func _pick_target(preferred):
	var up := conscious()
	for m in up:
		if m.id == preferred:
			return m
	return J.pick(up)


func apply_monster_action(e: Dictionary, r: Dictionary, joins: Array) -> void:
	var c = G.combat
	var sp: Dictionary = Species.SPECIES[e.species]
	match r.action:
		"attack":
			for i in e.multiattack:
				var t = _pick_target(r.get("targetId") if i == 0 else null)
				if t == null:
					break
				monster_attack(e, t)
				if i < e.multiattack - 1:
					render()
					await _sleep(260)
		"special":
			e.cooldown = e.recharge
			var st: Dictionary = Dnd.MONSTER_STATS[e.species].special
			var victims: Array
			if sp.special.all:
				victims = conscious()
			else:
				var t = _pick_target(r.get("targetId"))
				victims = [t] if t != null else []
			var with_cond: bool = st.get("cond") != null and Floors.floor_rules(G.floor).conditions
			say("%s'S SPECIAL! ROLL %d+ ON %s TO TAKE HALF%s." % [UP(e.name), e.dc, Dnd.ABILITY_WORDS[st.save], (" AND NOT BE %s" % Status.CONDITIONS[st.cond].word) if with_cond else ""], "warn", color_of(e))
			sfx.play("fireball" if e.species == "dragon" else "crit")
			for v in victims:
				if soak(v):
					continue
				var sv := party_save(v, st.save)
				var saved: bool = sv >= e.dc
				var dmg := maxi(1, J.round_js(Dnd.roll_dice(st.dice) * e.dmgMult))
				if saved:
					dmg = floori(dmg / 2.0)
				say("%s %s (ROLLED %d): %d DAMAGE%s." % [v.name, "MAKES IT" if saved else "FAILS", sv, dmg, (" AND IS %s" % Status.CONDITIONS[st.cond].word) if not saved and with_cond else ""], "" if saved else "warn")
				if not saved and with_cond:
					v.cond[st.cond] = st.rounds
				if dmg:
					damage(v, dmg)
		"attack_monster":
			var other = null
			for x in c.enemies:
				if x.id == r.get("monsterTargetId") and x.status == "here" and x.hp > 0:
					other = x
					break
			if other == null:
				return
			ach.on("mutiny", {"species": e.species})
			var roll := Dnd.d20()
			roll_fx(roll, spot_of(other), {"total": roll.roll + e.hit})
			var hit: bool = roll.roll != 1 and (roll.roll == 20 or roll.roll + e.hit >= other.ac)
			if not other.grudges.has(e.id):
				other.grudges.append(e.id)
			history("%s attacked %s." % [e.name, other.name])
			if not hit:
				say("%s TURNS ON %s: %s VS ARMOR %d. MISS!" % [UP(e.name), UP(other.name), Dnd.fmt_roll(roll, e.hit), other.ac], "big", color_of(e))
				sfx.play("miss")
				other.thisRound.append("%s attacked you, but missed." % e.name)
				return
			var dmg := maxi(1, J.round_js(Dnd.roll_dice(Dnd.MONSTER_STATS[e.species].dmg, {"crit": roll.roll == 20}) * e.dmgMult))
			hit_enemy(other, dmg, "%s attacked you for %d." % [e.name, dmg], color_of(e))
			say("%s TURNS ON %s: %s VS ARMOR %d. %d DAMAGE!" % [UP(e.name), UP(other.name), Dnd.fmt_roll(roll, e.hit), other.ac, dmg], "big", color_of(e))
			sfx.play("hit")
			if other.hp <= 0:
				kill_enemy(other, null, e)
		"defend":
			e.cond.dodging = 2
			float_on(e, "DODGING", color_of(e), 8)
		"demand_tribute":
			e.demanded = true
		"accept_tribute":
			var offer := int(r.offer)
			G.gold -= offer
			e.paid = true
			say("%s TAKES %d GOLD." % [UP(e.name), offer])
			sfx.play("gold")
			history("The party paid %s %d gold, and it accepted." % [e.name, offer])
			ach.on("paid", {"species": e.species, "gold": offer})
			vow_event("give", e.species, "The party gave %d gold to %s, %s." % [offer, e.name, a_label(e.species)])
		"refuse_tribute":
			history("%s refused the party's gold." % e.name)
		"flee":
			e.status = "fled"
			say("%s FLEES." % UP(e.name))
			sfx.play("flee")
			history("%s fled from the fight." % e.name)
			for o in present():
				o.thisRound.append("%s fled." % e.name)
		"leave_peacefully":
			e.status = "left"
			var xp := J.round_js(xp_of(e) / 2.0)
			say("%s LETS YOU PASS. +%d EXPERIENCE FOR A PEACEFUL END." % [UP(e.name), xp], "", color_of(e))
			sfx.play("good")
			grant_xp(xp)
			history("%s and the party parted peacefully." % e.name)
			ach.on("peace", {"species": e.species, "boss": J.truthy(e.get("boss"))})
			vow_event("spare", e.species, "The party let %s, %s, walk away alive." % [e.name, a_label(e.species)])
		"join_party":
			joins.append(e)


func recruit(e: Dictionary) -> void:
	var sp: Dictionary = Species.SPECIES[e.species]
	e.status = "joined"
	var ally := {
		"id": "m%d" % uid,
		"name": UP(e.name),
		"kind": "monster",
		"species": e.species,
		"cls": sp.cls,
		"hp": maxi(1, e.hp),
		"maxHp": e.maxHp,
		"ac": e.ac,
		"dmg": e.dmg.duplicate(),
		"traits": e.traits,
		"shiny": e.shiny,
		"boss": J.truthy(e.get("boss")),
		"level": maxi(1, G.floor),
		"xp": 0,
		"mods": base_mods(),
		"cond": {},
		"cooldown": 1,
		"loyalty": mini(80, 50 + J.round_js((e.meters.friendliness - sp.joinThreshold) / 2.0)),
		"dead": false,
		"down": false,
	}
	uid += 1
	G.party.append(ally)
	# Promises made to it mid-fight now belong to the ally
	for v in G.vows:
		if v.toId == e.id:
			v.toId = ally.id
			v.toName = ally.name
	ui.reset_vows()
	var xp := J.round_js(xp_of(e) / 2.0)
	say("%s JOINS THE PARTY! +%d EXPERIENCE FOR WINNING IT OVER." % [ally.name, xp], "big", color_of(ally))
	sfx.play("join")
	hint("ally")
	print("recruit: %s (%s) joins, loyalty %d" % [ally.name, ally.species, ally.loyalty])
	if e.shiny:
		G.combat.shinyRolls = J.nz(G.combat.get("shinyRolls"), 0) + 1
		say("A SHINY JOINED YOU! FATE OWES YOU A ROLL AFTER THIS FIGHT.", "big", Art.SHINY_COLOR)
	grant_xp(xp)
	history("The party befriended %s, who joined them." % e.name)
	G.combat.recruits.append(ally.id)
	ach.on("recruit", {"species": e.species, "shiny": J.truthy(e.shiny), "boss": J.truthy(e.get("boss")), "allies": allies().size()})
	vow_event("recruit", e.species, "The party recruited %s, %s, into the party." % [e.name, a_label(e.species)])
	vow_event("spare", e.species, "The party let %s, %s, live and join them." % [e.name, a_label(e.species)])


func end_combat() -> void:
	var c = G.combat
	if c == null:
		return
	G.combat = null
	G.mode = "explore"
	# Every foe killed, driven off, won over or let go: that's a win, and it sounds like one
	var won: bool = not c.enemies.is_empty() and c.enemies.all(func(e): return e.status != "here")
	if won:
		music.sting("victory")
	fx.emit("combat:end", {"won": won})
	music.set_mood("explore")
	G.busy = false # the party's turn may have ended the fight mid-action
	print("fight over: %s, %d kills" % ["won" if won else "not won", c.kills])
	# The fallen who still live come to; conditions and talk moods fade
	for m in G.party:
		if m.down and not m.dead:
			m.down = false
			m.stable = false
			m.hp = maxi(1, m.hp)
			say("%s COMES TO WITH %d HEALTH." % [m.name, m.hp], "dim")
		m.cond = {}
		m.mood = null
	# The floor's champion: beaten, won over, or talked down earns a great roll. If it fled, it waits.
	var great := false
	if c.boss and G.map.boss != null:
		var e = G.map.boss.enemy
		if e != null and ["dead", "joined", "left"].has(e.status):
			G.map.boss.defeated = true
			great = true
		elif e != null:
			say("%s STILL HOLDS THE HEART OF THIS FLOOR." % UP(e.name), "dim", Art.BOSS_COLOR)
	var boss_status = null
	if c.boss:
		boss_status = G.map.boss.enemy.status if G.map.boss != null and G.map.boss.enemy != null else null
	ach.on("fight-end", {"won": won, "kills": c.kills, "boss": boss_status})
	if living().any(func(m): return m.hp < m.maxHp / 2.0):
		hint("camp")
	render()
	await flush_breaks()
	var traitor = await ally_reactions_after(c)
	if great:
		say("THE CHAMPION IS OVERCOME. FATE OWES YOU A GREAT ROLL.", "big", Art.BOSS_COLOR)
		render()
		await _sleep(600)
		await roll_of_fate(G.floor, true)
	for i in J.nz(c.get("shinyRolls"), 0):
		render()
		await _sleep(500)
		await roll_of_fate(G.floor, false, "shiny")
	render()
	if traitor != null:
		_later(700, func(): encounter([enemy_from_ally(traitor, "You traveled with this party and grew to despise how they act. You just turned on them.")]))


## After a fight, your monster allies judge what they saw. Returns an ally that turned on you, if any.
func ally_reactions_after(c: Dictionary):
	var watchers := allies().filter(func(m): return not c.recruits.has(m.id))
	if watchers.is_empty() or c.history.size() < 2:
		return null
	G.busy = true
	render()
	var r := await api("/api/ally-reactions", {
		"allies": watchers.map(func(a): return {"id": a.id, "species": a.species, "name": a.name, "traits": a.traits, "loyalty": a.loyalty}),
		"events": c.history,
	})
	if r.has("error"):
		say("(JEV UNREACHABLE: %s)" % r.error, "dim")
		G.busy = false
		return null
	G.busy = false
	ui.show_jev({"kind": "allies", "r": r, "events": c.history})
	var traitor = null
	for x in r.reactions:
		var m = null
		for p in G.party:
			if p.id == x.id:
				m = p
				break
		if m == null:
			continue
		m.loyalty = _n(x.loyalty)
		var color := color_of(m)
		say("%s: %s" % [m.name, x.line], "npc", color)
		speak(m, x.line)
		# What it made of the fight, and the moment that tipped it, so a walk-out never comes out of nowhere
		var felt = Narrate.ally_line(m.species, m.name, x)
		if J.truthy(felt):
			say(felt, "", color)
		dbg("%s APPROVAL %s/4, LOYALTY %s%s → %s%s" % [m.name, to_fixed(x.approval, 1), "+" if x.delta >= 0 else "", J.num(x.delta), J.num(x.loyalty), ("; %s" % x.blocked) if J.truthy(x.get("blocked")) else ""])
		ach.on("ally-decision", {"decision": x.decision})
		print("ally reaction: %s → %s (loyalty %s)" % [m.name, x.decision, J.num(x.loyalty)])
		if x.decision == "leave_party":
			G.party = _without(G.party, m)
			say("%s LEAVES THE PARTY." % m.name, "warn", color)
			sfx.play("sad")
		elif x.decision == "turn_on_party" and traitor == null:
			G.party = _without(G.party, m)
			traitor = m
	return traitor


func game_over() -> void:
	G.mode = "over"
	G.combat = null
	music.set_mood("explore")
	G.busy = false
	sfx.play("death")
	print("game over on floor %d" % G.floor)
	say("YOUR PARTY HAS PERISHED ON %s." % Status.floor_name(G.floor), "big")
	ach.on("wipe", {"floor": G.floor})
	var deepest = store.get_item("hallsOfJev.deepest")
	say("DEEPEST FLOOR EVER REACHED: %s. PRESS ENTER FOR A NEW RUN." % (deepest if J.truthy(deepest) else J.num(G.floor)), "dim")
	render()


# ---------------------------------------------------------------- input

## Every key the player presses, as the JS names it ("fwd", "turnL", "enter", "escape", "y", "1", "pick:2"...).
## The ui maps raw keys with KEYMAP first; dock, top-bar and modal buttons pass their data-key.
func key(k: String) -> void:
	if G == null:
		return
	# The achievements list (K) takes every key while it's open: K/Esc close it, anything else nudges it
	if ach.is_open():
		ach.key(k)
		return
	if k == "k" and not (G.waitKey != null or G.prompt != null or G.menu != null or G.input != null or G.busy):
		ach.open()
		return
	if G.waitKey != null:
		var w = G.waitKey
		G.waitKey = null
		w.resolve()
		return
	if G.mode == "over":
		if k == "enter":
			new_run()
		else:
			ui.nudge_dock()
		return
	if G.prompt != null:
		var p = G.prompt
		var answer = null
		if k == "y" or k == "enter":
			answer = true
		elif J.truthy(p.no) and (k == "n" or k == "escape"):
			answer = false
		if answer != null:
			G.prompt = null
			p.waiter.resolve(answer)
			return
		if p.walkAway and k in ["fwd", "back", "turnL", "turnR"]:
			G.prompt = null
			p.waiter.resolve(false)
			key(k)
			return
		ui.nudge_modal()
		return
	if G.menu != null:
		# Up/down (or W/S) move the highlight, left/right jump columns, Enter picks it; 1-9 and 0 pick directly
		var m = G.menu
		var n: int = m.options.size()
		var rows: int = ceili(n / 2.0) if n > 4 else n
		var move: int = {"fwd": -1, "back": 1, "turnL": -rows, "turnR": rows}.get(k, 0)
		if move:
			var next: int = Status.menu_step(m.sel, move, n) if absi(move) == 1 else m.sel + move
			if next >= 0 and next < n and next != m.sel:
				m.sel = next
				ui.render_dock()
			elif absi(move) != 1:
				ui.nudge_dock()
			return
		if k == "escape":
			G.menu = null
			m.waiter.resolve(null)
			return
		var i := -1
		if k.begins_with("pick:"):
			i = int(k.substr(5))
		elif k == "enter":
			i = m.sel
		elif k == "0":
			i = 9
		elif k.length() == 1 and k >= "1" and k <= "9":
			i = int(k) - 1
		if i >= 0 and i < n:
			G.menu = null
			m.waiter.resolve(m.options[i].value)
		else:
			ui.nudge_dock()
		return
	if G.input != null:
		# The talk box lost focus: the dock's buttons still work, and any other key points back at the box
		if k == "escape":
			cancel_input()
			return
		if k == "enter":
			submit_input()
			return
		ui.focus_input()
		ui.nudge_dock()
		return
	if G.busy:
		tips.ignored(k) # the monsters are still moving: nudge the hint, don't drop it
		return
	if k == "j" and DEBUG:
		ui.toggle_jev()
		ui.render_bar()
		return
	if k == "h":
		tips.toggle(say)
		if G.combat != null and not tips.on():
			G.combat.guide = null # tips off: the first-fight lesson lets go too
		render()
		return
	if k == "p":
		_toggle_music()
		return
	if k == "o":
		say("SOUND EFFECTS %s." % ("ON" if sfx.toggle() else "OFF"), "dim")
		render()
		return
	if k == "l" and narrator.supported:
		say("VOICES %s." % ("ON: MONSTERS READ THEIR LINES ALOUD" if narrator.toggle() else "OFF"), "dim")
		render()
		return
	if G.combat != null:
		command(k)
		return
	if k == "m":
		ui.toggle_map()
		return
	if k == "c":
		camp()
		return
	if k == "e":
		talk_to_ally()
		return
	if k == "v":
		make_vow()
		return
	if k == "b":
		list_boons()
		return
	if k == "fwd":
		step(G.dir)
		return
	if k == "back":
		step((G.dir + 2) % 4)
		return
	if k == "turnL" or k == "turnR":
		fx.emit("view:turn", {"dir": -1 if k == "turnL" else 1})
	if k == "turnL":
		G.dir = (G.dir + 3) % 4
	if k == "turnR":
		G.dir = (G.dir + 1) % 4
	elif k != "turnL":
		tips.ignored(k) # not an exploring key: nudge the hint rather than swallow it silently
	render()


func _toggle_music() -> void:
	await music.toggle()
	ui.render_bar()


# ---------------------------------------------------------------- debug hooks (JS: window.halls, debug mode only)
# The ui wires them (a console, keys, the genre halls); e.g. debug_meet(["goblin", "slime"]).

## Fight this floor's champion (or a fresh one) right where you stand.
func boss_encounter_here() -> void:
	if G.map.boss == null:
		G.map.boss = {"x": -1, "y": -1, "species": Floors.pick_weighted(Floors.floor_rules(G.floor).pool), "defeated": false, "enemy": null}
	await boss_encounter()


func debug_hostile(species: String) -> void:
	var e := make_enemy(species)
	e.meters = {"friendliness": 0, "anger": 60, "fear": 0}
	await encounter([e])


## The guided first fight, on demand
func debug_lesson() -> void:
	await encounter([make_enemy("slime")], {"guide": true})


func debug_meet(species_list: Array) -> void:
	var group := []
	for s in species_list:
		group.append(make_enemy(s, group.map(func(e): return e.name)))
	await encounter(group)


func debug_state():
	return G


func debug_ally(species: String, name = null) -> void:
	var sp: Dictionary = Species.SPECIES[species]
	G.party.append({
		"id": "m%d" % uid,
		"name": UP(J.nz(name, sp.names[0])),
		"kind": "monster",
		"species": species,
		"cls": sp.cls,
		"hp": sp.hp[1],
		"maxHp": sp.hp[1],
		"ac": Dnd.MONSTER_STATS[species].ac,
		"dmg": sp.dmg.duplicate(),
		"traits": sp.traits.slice(0, 2),
		"loyalty": 60,
		"dead": false,
		"down": false,
		"level": 1,
		"xp": 0,
		"mods": base_mods(),
		"cond": {},
		"cooldown": 1,
	})
	uid += 1
	render()


func debug_boss() -> void:
	await boss_encounter_here()


func debug_floor(n: int) -> void:
	enter_floor(n)
	announce_floor(n)
	render()


func debug_xp(n: int) -> void:
	grant_xp(n)
	render()


func debug_roll(great := false, kind := "floor") -> void:
	await roll_of_fate(G.floor, great, kind)


func debug_shiny(species := "slime") -> void:
	var e := make_enemy(species)
	while not e.shiny:
		e = make_enemy(species)
	e.meters.friendliness = 90
	await encounter([e])


func debug_descend() -> void:
	await descend()


func debug_ask(text = null):
	return await ask(J.nz(text, "STAIRS DOWN TO %s. DESCEND?" % Status.floor_name(G.floor + 1)), {"yes": "DESCEND", "no": "STAY", "walkAway": true})
