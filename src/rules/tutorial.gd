## Tips: a just-in-time tutorial. Each hint is one or two short lines, shown once, at the moment it
## matters, in a framed note over the bottom of the dungeon view. While it's up, the things it talks about
## (the keys' buttons, the automap, the party) are lit up too.
##
## Hints never take input away. The key you press still does its job and also clears the hint; a key the
## game ignores nudges the hint instead of vanishing silently. H turns tips off; H again starts them over.
##
## game.gd only calls tips.hint(id) at each trigger point, plus tips.ignored(key) where a key does nothing.
## `create_tutorial` is the pure part (no UI); the box that shows a hint lives in src/ui, which hands in the
## `show` / `hide` / `nudge` callbacks.
extends RefCounted

const J = preload("res://src/core/js.gd")

const SEEN_KEY = "hallsOfJev.tipsSeen"
const OFF_KEY = "hallsOfJev.tipsOff"
const GRACE_MS = 900 # keys this soon after a hint appears don't clear it (a held key, or the one that triggered it)
const MIN_READ_MS = 2500 # a hint pushed aside sooner than this gets another turn
const GAP_MS = 700 # a breath between one hint and the next
const TTL_MS = 30000 # a hint nobody clears fades on its own
const REMIND_WINDOW_MS = 4000 # two ignored keys this close together bring back the reminder
const REMIND_COOLDOWN_MS = 20000

## Where the game is. Hints only show while you're exploring or fighting, never over a question or a roll.
const GAMEPLAY = {"explore": true, "combat": true}
## What to remind a flailing player of, by where they are.
const PRIMER = {"explore": "move", "combat": "combat"}
## Keys a player means as commands (single characters plus the game's names for the arrows).
const COMMAND_KEYS = {"fwd": true, "back": true, "turnL": true, "turnR": true, "enter": true, "escape": true}
## The arrow glyphs in hint text and the key each one stands for.
const ARROWS = {"↑": "fwd", "↓": "back", "←": "turnL", "→": "turnR"}

## {K} is a keycap, {!K} the one to press (it blinks). ctx: when it may show ("explore", "combat" or "any").
## focus: extra things to light up; keys: false when a keycap's key means something else where the hint shows.
const HINTS = {
	"move": {"ctx": "explore", "lines": ["{!↑} STEP  {←}{→} TURN  {↓} BACK", "OR WASD. FIND THE STAIRS DOWN."]},
	"map": {"ctx": "explore", "focus": ["#map"], "lines": ["YOUR MAP DRAWS ITSELF AS YOU WALK.", "{!M} SHOWS OR HIDES IT."]},
	"stairs": {
		"ctx": "explore",
		"focus": ["#map"],
		"lines": ["STAIRS! THEY'RE ON YOUR MAP NOW.", "GOING DOWN EARNS A ROLL OF FATE."],
	},
	"boss": {
		"ctx": "explore",
		"focus": ["#map"],
		"lines": ["THE RED MARK ON YOUR MAP: A CHAMPION.", "OPTIONAL. BRUTAL. CAN BE TALKED DOWN."],
	},
	"combat": {"ctx": "combat", "lines": ["{F} QUICK ATTACK  {C} CHOOSE MOVES", "{E} ESCAPE, OR {!T} TALK. IT LISTENS."]},
	"target": {"ctx": "combat", "lines": ["{!1}{2}{3} PICK WHICH ONE YOU AIM AT.", "WHEN YOU TALK, THEY ALL HEAR IT."]},
	"feeling": {
		"ctx": "combat",
		"focus": ["#log"],
		"lines": ["IT FEELS SOMETHING, AND FEELINGS BITE:", "EACH ONE CHANGES HOW IT FIGHTS."],
	},
	"recruit": {"ctx": "combat", "lines": ["IT'S WARMING TO YOU. {!R} ASKS IT TO JOIN.", "THE FRIENDLIER IT IS, THE EASIER."]},
	"ally": {
		"ctx": "explore",
		"focus": ["#party"],
		"lines": ["YOUR ALLY FIGHTS ON ITS OWN, AND JUDGES", "WHAT YOU DO. {!E} TALKS TO IT."],
	},
	"camp": {
		"ctx": "explore",
		"focus": ["#party"],
		"lines": ["HURT? {!C} MAKES CAMP: HEALTH AND SPELLS", "COME BACK. SOMETHING MAY FIND YOU."],
	},
	"levelup": {
		"ctx": "any",
		"keys": false,
		"focus": ["#party"],
		"lines": ["LEVEL UP! MORE HEALTH. CASTERS MAY LEARN", "SPELLS: {C} CHOOSE MOVES IN A FIGHT."],
	},
	"down": {
		"ctx": "combat",
		"focus": ["#party .dying"],
		"lines": ["DOWN, NOT DEAD: A DEATH SAVE EACH TURN.", "HEAL THEM BEFORE THREE SAVES FAIL."],
	},
	"talkFirst": {"ctx": "combat", "lines": ["MONSTERS HERE LISTEN. THIS ONE IS SHY.", "{!T} TALK TO IT. SAY SOMETHING KIND."]},
	"recruitNow": {"ctx": "combat", "lines": ["IT HEARD YOU. NOW {!R} RECRUIT:", "ASK IT TO JOIN YOUR PARTY."]},
}

## The guided first fight: a new player's first fight is a lone shy slime, and it teaches the game's heart by
## doing it. Only one key works at each step (TALK, then RECRUIT); every other fight key waits, and pressing
## one nudges the dock instead of doing nothing. The invitation is a sure yes (the server is told `guided`).
const GUIDE = {
	"talk": {
		"key": "t",
		"hint": "talkFirst",
		"next": "recruit",
		"say": "YOUR FIRST FIGHT: TALK TO IT FIRST. MONSTERS HERE LISTEN",
	},
	"recruit": {"key": "r", "hint": "recruitNow", "next": null, "say": "IT HEARD YOU. NOW ASK IT TO JOIN YOUR PARTY"},
}

static var _line_re := RegEx.create_from_string("\\{(!?)([^}]+)\\}")


static func guide_allows(step, k) -> bool:
	var g = GUIDE.get(step)
	return g == null or g.key == k


## Guided once: floor 1, tips on, and the lesson's first tip never shown (H starts tips over, and the lesson too).
## opts: {floor, tipsOn, seen: Callable(id) -> bool}
static func should_guide(opts: Dictionary) -> bool:
	return opts.floor == 1 and J.truthy(opts.tipsOn) and not opts.seen.call(GUIDE.talk.hint)


## "PRESS {!T} NOW" → [{text: "PRESS "}, {key: "T", hot: true}, {text: " NOW"}]
static func parse_line(line: String) -> Array:
	var out := []
	var last := 0
	for m in _line_re.search_all(line):
		if m.get_start() > last:
			out.append({"text": line.substr(last, m.get_start() - last)})
		out.append({"key": m.get_string(2), "hot": m.get_string(1) == "!"})
		last = m.get_end()
	if last < line.length():
		out.append({"text": line.substr(last)})
	return out


## CSS-style selectors for everything a hint should light up: its keys' buttons (anything with that data-key,
## so it follows the buttons wherever the layout puts them) and the hint's own extras.
static func focus_of(id) -> Array:
	var h = HINTS.get(id)
	if h == null:
		return []
	var out := []
	if h.get("keys", true) != false:
		for line in h.lines:
			for t in parse_line(line):
				if t.has("key"):
					var sel := '[data-key="%s"]' % ARROWS.get(t.key, t.key.to_lower())
					if not out.has(sel):
						out.append(sel)
	for sel in h.get("focus", []):
		if not out.has(sel):
			out.append(sel)
	return out


static func _fits(h: Dictionary, ctx) -> bool:
	return GAMEPLAY.has(ctx) and (h.ctx == "any" or h.ctx == ctx)


## opts: {store, context: Callable() -> "explore"|"combat"|..., show: Callable(id, hint), hide: Callable(id),
## nudge: Callable(id), now: Callable() -> ms, log: Callable(String)}. `store` has get_item / set_item (Store or
## Store.Memory); every callback is optional.
static func create_tutorial(opts := {}) -> Tutorial:
	return Tutorial.new(opts)


class Tutorial:
	extends RefCounted
	const T = preload("res://src/rules/tutorial.gd")

	var _store
	var _context: Callable
	var _show: Callable
	var _hide: Callable
	var _nudge: Callable
	var _now: Callable
	var _log: Callable
	var _seen := {} # Set of hint ids
	var _on := true
	var _queue: Array = [] # { id, wait }: wait = it was asked for elsewhere and waits for its own context
	var _cur = null # { id, wait, shownAt, reminder }
	var _last_hide := -INF
	var _ignored_key := false # the game ignored the key being handled right now
	var _strays: Array = [] # times of recent ignored keys
	var _last_remind := -INF

	func _init(opts := {}) -> void:
		_store = opts.get("store")
		_context = opts.get("context", func(): return "explore")
		_show = opts.get("show", Callable())
		_hide = opts.get("hide", Callable())
		_nudge = opts.get("nudge", Callable())
		_now = opts.get("now", Callable(J, "date_ms"))
		_log = opts.get("log", func(msg: String): print_verbose("[tips] " + msg))
		var raw = _store.get_item(T.SEEN_KEY) if _store != null else null
		var json := JSON.new()
		if json.parse(raw if raw != null else "[]") == OK and json.data is Array:
			for id in json.data:
				if T.HINTS.has(id):
					_seen[id] = true
		_on = (_store.get_item(T.OFF_KEY) if _store != null else null) != "1"

	func _save() -> void:
		if _store != null:
			_store.set_item(T.SEEN_KEY, JSON.stringify(_seen.keys()))

	func _say_log(parts: Array) -> void:
		if _log.is_valid():
			_log.call(" ".join(parts.map(func(p): return str(p))))

	func _show_entry(e: Dictionary, reminder := false) -> void:
		_cur = {"id": e.id, "wait": e.wait, "shownAt": _now.call(), "reminder": reminder}
		if not reminder:
			_seen[e.id] = true
			_save()
		_say_log(["remind" if reminder else "show", e.id])
		if _show.is_valid():
			_show.call(e.id, T.HINTS[e.id])

	func _hide_cur(why: String) -> void:
		if _cur == null:
			return
		var id = _cur.id
		_say_log(["hide", id, why])
		_cur = null
		_last_hide = _now.call()
		if _hide.is_valid():
			_hide.call(id)

	## Call it every ~250ms: ends hints whose moment is over or that timed out, and shows the next queued one.
	func tick() -> void:
		var ctx = _context.call()
		var t = _now.call()
		if _cur != null and not T._fits(T.HINTS[_cur.id], ctx):
			var entry: Dictionary = _cur
			var early: bool = t - entry.shownAt < T.MIN_READ_MS
			_hide_cur("context %s" % ctx)
			if early and not entry.reminder:
				# Cut short: it gets another go, unless its moment (a fight) is simply over
				if entry.wait or not T.GAMEPLAY.has(ctx):
					_queue.push_front({"id": entry.id, "wait": entry.wait})
				else:
					_seen.erase(entry.id)
					_save()
		elif _cur != null and t - _cur.shownAt > T.TTL_MS:
			_hide_cur("timeout")
		if not T.GAMEPLAY.has(ctx):
			return
		# Hints asked for in a moment that has passed (a fight that ended first) are dropped; they come back next time
		_queue = _queue.filter(func(q): return q.wait or T._fits(T.HINTS[q.id], ctx))
		if _cur != null or t - _last_hide < T.GAP_MS:
			return
		var i := _queue.find_custom(func(q): return T._fits(T.HINTS[q.id], ctx))
		if i >= 0:
			var q = _queue[i]
			_queue.remove_at(i)
			_show_entry(q)

	## A moment worth a tip has come. Returns true when the hint was queued (it shows now or when its context fits).
	func hint(id) -> bool:
		var h = T.HINTS.get(id)
		if h == null:
			_say_log(["unknown hint", id])
			return false
		if not _on or _seen.has(id) or (_cur != null and _cur.id == id) or _queue.any(func(q): return q.id == id):
			return false
		_queue.append({"id": id, "wait": not T._fits(h, _context.call())})
		tick()
		return true

	## Clears the hint that's up. A key inside the grace period doesn't; opts {force = true} does at once.
	func dismiss(opts := {}) -> bool:
		var force: bool = opts.get("force", false)
		if _cur == null or (not force and _now.call() - _cur.shownAt < T.GRACE_MS):
			return false
		_hide_cur("dismissed" if force else "key")
		return true

	## After every key: clear the hint, unless the game ignored that key (then ignored() already nudged it).
	func keyed() -> bool:
		if _ignored_key:
			_ignored_key = false
			return false
		return dismiss()

	## The game did nothing with this key. Nudge the hint that's up; if none is and the player keeps
	## pressing keys that do nothing, bring back the reminder for where they are.
	func ignored(k) -> void:
		if not (str(k).length() == 1 or T.COMMAND_KEYS.has(k)):
			return
		_ignored_key = true
		var t = _now.call()
		if _cur != null:
			_say_log(["nudge", _cur.id, k])
			if _nudge.is_valid():
				_nudge.call(_cur.id)
			return
		_strays = _strays.filter(func(s): return t - s < T.REMIND_WINDOW_MS)
		_strays.append(t)
		var primer = T.PRIMER.get(_context.call())
		if not _on or primer == null or _strays.size() < 2 or t - _last_remind < T.REMIND_COOLDOWN_MS:
			return
		_strays = []
		_last_remind = t
		_show_entry({"id": primer, "wait": false}, true)

	## A key the game holds back for a lesson (the guided first fight): keep that lesson's tip up and nudge it,
	## or bring it back if it was cleared. Never the generic reminder, which would point at the locked keys.
	func insist(id) -> void:
		if not T.HINTS.has(id):
			return
		_ignored_key = true
		if _cur != null and _cur.id == id:
			_say_log(["nudge", id, "insist"])
			if _nudge.is_valid():
				_nudge.call(id)
			return
		_hide_cur("insist")
		_queue = _queue.filter(func(q): return q.id != id)
		_show_entry({"id": id, "wait": false}, true)

	func set_enabled(value) -> void:
		_on = J.truthy(value)
		if _store != null:
			_store.set_item(T.OFF_KEY, "0" if _on else "1")
		_say_log(["tips on" if _on else "tips off"])
		if not _on:
			_queue = []
			_hide_cur("tips off")

	func reset() -> void:
		_seen.clear()
		_save()
		_queue = []
		_say_log(["reset"])

	## H: tips off; H again: back on from the very start (that's the reset). No menu, so nothing waits on you.
	## say: Callable(text, cls) for the log line. Returns whether tips are on now.
	func toggle(say := Callable()) -> bool:
		if _on:
			set_enabled(false)
			if say.is_valid():
				say.call("TIPS OFF. PRESS H TO START THEM OVER.", "dim")
			return false
		reset()
		set_enabled(true)
		if say.is_valid():
			say.call("TIPS ON, FROM THE START. PRESS H AGAIN TO TURN THEM OFF.", "dim")
		var primer = T.PRIMER.get(_context.call())
		_last_hide = -INF # you asked for them: no pause
		if primer != null:
			hint(primer)
		return true

	## Are tips on?
	func on() -> bool:
		return _on

	func seen(id) -> bool:
		return _seen.has(id)

	## The id of the hint that's up, or null.
	func current():
		return _cur.id if _cur != null else null

	## Ids waiting their turn, in order.
	func pending() -> Array:
		return _queue.map(func(q): return q.id)
