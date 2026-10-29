## initAchievements() from achievements.js: the achievements core (achievements.gd) with its screen parts, the
## unlock toasts over the view (at most two at once, staggered, one jingle for a burst) and the K list. game.gd
## uses it like the JS object: on(), count(), list(), is_open(), open(), close(), key(k).
extends RefCounted

const Achievements = preload("res://src/rules/achievements.gd")
const Css = preload("res://src/ui/css.gd")

## Keys a player means as commands: these nudge the open list; Shift, Tab and the like don't
const COMMAND_KEYS := {"fwd": true, "back": true, "turnL": true, "turnR": true, "enter": true, "escape": true}

var core
var toasts # toasts.gd
var screen # ach_screen.gd
var accent := Callable() # () -> the floor's accent (a CSS string or null)
var jingle := Callable()
var on_unlock := Callable() # (a) -> the game's own reaction (a line in the log)
var on_toggle := Callable() # (open) -> the top bar's K keycap lights up

var _queue: Array = []
var _showing := 0
var _next_at := 0.0
var _last_jingle := -INF


## opts: {store, toasts, screen, accent, jingle, onUnlock, onToggle}
func _init(opts := {}) -> void:
	toasts = opts.get("toasts")
	screen = opts.get("screen")
	accent = opts.get("accent", Callable())
	jingle = opts.get("jingle", Callable())
	on_unlock = opts.get("onUnlock", Callable())
	on_toggle = opts.get("onToggle", Callable())
	core = Achievements.create_achievements({
		"store": opts.get("store"),
		"onUnlock": _unlocked,
		"log": func(msg: String): print_verbose("[achievements] " + msg),
	})
	if toasts != null:
		toasts.on_gone = _toast_gone


func _unlocked(a: Dictionary) -> void:
	_queue.append({"a": a, "count": core.count() if core != null else null})
	_pump()
	if on_unlock.is_valid():
		on_unlock.call(a)
	if is_open():
		screen.refresh(core.list(), core.count())


func _pump() -> void:
	while not _queue.is_empty() and _showing < Achievements.MAX_TOASTS:
		var q: Dictionary = _queue.pop_front()
		var now := Time.get_ticks_usec() / 1000.0
		var wait := maxf(0.0, _next_at - now)
		_next_at = now + wait + Achievements.STAGGER_MS
		_showing += 1
		if wait <= 0.0:
			_show_toast(q.a, q.count)
		else:
			(Engine.get_main_loop() as SceneTree).create_timer(wait / 1000.0).timeout.connect(_show_toast.bind(q.a, q.count))


func _show_toast(a: Dictionary, count) -> void:
	if toasts != null:
		toasts.show_toast(a, count)
	var t := Time.get_ticks_usec() / 1000.0
	if t - _last_jingle > Achievements.JINGLE_GAP_MS:
		_last_jingle = t
		if jingle.is_valid():
			jingle.call()


func _toast_gone() -> void:
	_showing = maxi(0, _showing - 1)
	_pump()


func _accent() -> Color:
	var c = accent.call() if accent.is_valid() else null
	return Css.css(c) if c != null else Css.ACCENT


# ---------------------------------------------------------------- the core, as game.gd calls it

func on(event, data = null) -> void:
	core.on(event, data)


func unlock(id) -> bool:
	return core.unlock(id)


func has(id) -> bool:
	return core.has(id)


func earned_at(id):
	return core.earned_at(id)


func progress(id):
	return core.progress(id)


func count() -> Dictionary:
	return core.count()


func list() -> Array:
	return core.list()


func reset() -> void:
	core.reset()


# ---------------------------------------------------------------- the K screen

func is_open() -> bool:
	return screen != null and screen.visible


func open() -> void:
	if screen == null:
		return
	screen.open(core.list(), core.count(), _accent())
	print_verbose("[achievements] open")
	if on_toggle.is_valid():
		on_toggle.call(true)


func close() -> void:
	if screen == null:
		return
	screen.close()
	print_verbose("[achievements] close")
	if on_toggle.is_valid():
		on_toggle.call(false)


## While the list is open it takes every key: K or Esc closes, up/down scroll, anything else nudges it
func key(k) -> bool:
	if not is_open():
		return false
	if k == "k" or k == "escape":
		close()
	elif k == "fwd" or k == "back":
		screen.scroll_by(-90.0 if k == "fwd" else 90.0)
	elif str(k).length() == 1 or COMMAND_KEYS.has(k):
		screen.nudge()
	return true
