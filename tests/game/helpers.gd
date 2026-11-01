## Shared by the game tests: a game node wired to stub ui and audio objects (they record what the game asks of them),
## real tips and achievements (their pure cores), an in-memory store, and the seeded mock Jev. Every sleep is one
## frame (sleep_scale 0), so a whole fight plays out in a few hundred frames.
extends "res://tests/test_case.gd"

const Game = preload("res://src/game/game.gd")
const J = preload("res://src/core/js.gd")
const Flags = preload("res://src/core/flags.gd")
const StoreScript = preload("res://src/core/store.gd")
const Tutorial = preload("res://src/rules/tutorial.gd")
const Achievements = preload("res://src/rules/achievements.gd")
const JevApi = preload("res://src/jev/api.gd")
const JevConfig = preload("res://src/jev/config.gd")
const Jev = preload("res://src/jev/jev.gd")
const Floors = preload("res://src/game/floors.gd")
const Render = preload("res://src/view/render.gd")

var game = null
## Every API call the game made: {path, body, reply}
var requests := []


## Records every hook the game calls: calls[name] = [args, args, ...]
class StubUi:
	extends RefCounted
	var calls := {}
	var text := ""

	func _rec(name: String, args := []) -> void:
		if not calls.has(name):
			calls[name] = []
		calls[name].append(args)

	func count(name: String) -> int:
		return calls.get(name, []).size()

	func render() -> void:
		_rec("render")

	func render_bar() -> void:
		_rec("render_bar")

	func render_dock() -> void:
		_rec("render_dock")

	func nudge_dock() -> void:
		_rec("nudge_dock")

	func nudge_modal() -> void:
		_rec("nudge_modal")

	func show_jev(x) -> void:
		_rec("show_jev", [x])

	func render_requests() -> void:
		_rec("render_requests")

	func toggle_jev() -> void:
		_rec("toggle_jev")

	func start_audio() -> void:
		_rec("start_audio")

	func open_input(label: String, numeric: bool) -> void:
		_rec("open_input", [label, numeric])
		text = ""

	func close_input() -> void:
		_rec("close_input")

	func input_text() -> String:
		return text

	func focus_input() -> void:
		_rec("focus_input")

	func toggle_map() -> void:
		_rec("toggle_map")

	func reset_vows() -> void:
		_rec("reset_vows")


class StubSfx:
	extends RefCounted
	var on := true
	var lag = 0
	var played := []

	func play(name: String, _opts := {}) -> void:
		played.append(name)

	func shout(_line: String, _species: String, _opts := {}):
		return {"kind": "voice"}

	func toggle() -> bool:
		on = not on
		return on

	func duck(_on: bool) -> void:
		pass


class StubMusic:
	extends RefCounted
	var on := true
	var moods := []
	var stings := []
	var started := false

	func start():
		started = true
		return null

	func sting(name: String) -> void:
		stings.append(name)

	func set_mood(m: String) -> void:
		moods.append(m)

	func toggle():
		on = not on
		return on

	func duck(_on: bool) -> void:
		pass


class StubNarrator:
	extends RefCounted
	var supported := false
	var on := false
	var order := ["default"]  # the voices L steps through
	var label := "DEFAULT"
	var said := []

	func say(line: String, _species = null) -> void:
		said.append(line)

	func toggle() -> bool:
		on = not on
		return on

	func hush() -> void:
		pass

	func heard_player() -> void:
		pass


class StubVoice:
	extends RefCounted
	var supported := false
	var cancels := 0

	func cancel() -> void:
		cancels += 1


## achievements.js's non-DOM init: the real core plus open/close/is_open/key, and a record of every event
class StubAch:
	extends RefCounted
	var core
	var events := []
	var opened := false

	func _init(store, on_unlock: Callable) -> void:
		core = Achievements.create_achievements({"store": store, "onUnlock": on_unlock})

	func on(event, data = null) -> void:
		events.append([event, data])
		core.on(event, data)

	func count() -> Dictionary:
		return core.count()

	func is_open() -> bool:
		return opened

	func open() -> void:
		opened = true

	func close() -> void:
		opened = false

	func key(k) -> bool:
		if k == "k" or k == "escape":
			opened = false
		return true

	func names() -> Array:
		return events.map(func(e): return e[0])


func after_each():
	if game != null:
		game.queue_free()
		game = null
	Flags.override = null
	JevConfig.reset()
	Jev.configure_jev(null)


## A game, started unless opts.start == false. opts: flags (the pretend address), store ({key: value}),
## tips (false: tips off), seed, jev (sources for JevConfig.setup, default the seeded mock), handler (api_handler)
func make_game(opts := {}):
	seed(opts.get("seed", 7))
	Flags.override = opts.get("flags", "")
	JevConfig.setup(opts.get("jev", {"flags_text": "mock seed=%d" % opts.get("seed", 7), "env": {}, "latency": 0}), true)
	var initial: Dictionary = opts.get("store", {})
	if opts.get("tips", true) == false:
		initial[Tutorial.OFF_KEY] = "1"
	game = Game.new()
	game.store = StoreScript.Memory.new(initial)
	game.ui = StubUi.new()
	game.sfx = StubSfx.new()
	game.music = StubMusic.new()
	game.narrator = StubNarrator.new()
	game.voice = StubVoice.new()
	game.tips = Tutorial.create_tutorial({"store": game.store, "context": Callable(game, "tips_context")})
	game.ach = StubAch.new(game.store, Callable(game, "on_achievement_unlocked"))
	game.sleep_scale = 0.0
	requests = []
	var handler: Callable = opts.get("handler", Callable())
	game.api_handler = func(path: String, body: Dictionary, o: Dictionary) -> Dictionary:
		var res: Dictionary
		if handler.is_valid():
			res = await handler.call(path, body, o)
		else:
			res = await JevApi.handle(path, body, o)
		requests.append({"path": path, "body": body, "reply": res})
		return res
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	if opts.get("start", true):
		game.start()
	return game


## Wraps the mock: group-turn monsters only ever do `action` (the mock's dice still decide meters, lines, feelings)
static func taming(action := "attack") -> Callable:
	return func(path: String, body: Dictionary, o: Dictionary) -> Dictionary:
		var res: Dictionary = await JevApi.handle(path, body, o)
		if path == "/api/group-turn" and res.status == 200:
			for r in res.body.results:
				r.action = action
				r.join = null
				r.spoken = true
		return res


func frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


## Waits until the game wants the player (a question, a menu, the talk box, any key, game over) or has gone quiet
## (not busy, nothing new in the log for a few frames). Returns false if it never settles.
func settle(max_frames := 4000) -> bool:
	var quiet := 0
	var last := -1
	for i in max_frames:
		await frame()
		var g: Dictionary = game.G
		if g.prompt != null or g.menu != null or g.input != null or g.waitKey != null or g.mode == "over":
			return true
		if not g.busy and g.log.size() == last:
			quiet += 1
			if quiet >= 8:
				return true
		else:
			quiet = 0
		last = g.log.size()
	fail("the game never settled")
	return false


func until(cond: Callable, max_frames := 4000) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await frame()
	fail("timed out waiting")
	return false


func lines() -> Array:
	return game.G.log.map(func(l): return l.text)


func logged(pattern: String) -> bool:
	var re := RegEx.create_from_string(pattern)
	for l in game.G.log:
		if re.search(l.text) != null:
			return true
	return false


## Asserts a log line matches `pattern`
func saw(pattern: String, msg := "") -> bool:
	assertions += 1
	if logged(pattern):
		return true
	failures.append("%sno log line matches /%s/; log tail: %s" % [(msg + ": ") if msg else "", pattern, JSON.stringify(lines().slice(-12))])
	return false


func sent(path: String) -> Array:
	return requests.filter(func(r): return r.path == path)


## Presses keys until the fight is over: every foe left at 1 health, quick attacks, any join turned away
func win_fight(max_rounds := 30) -> bool:
	for i in max_rounds:
		if game.G.combat == null or game.G.mode == "over":
			return true
		await settle()
		var g: Dictionary = game.G
		if g.combat == null or g.mode == "over":
			return true
		if g.prompt != null:
			game.key("n" if J.truthy(g.prompt.no) else "y")
			continue
		for e in game.present():
			e.hp = 1
		game.key("f")
	return game.G.combat == null


## A floor cell next to (x, y) and the direction from it to (x, y)
func neighbor_of(x: int, y: int) -> Array:
	for d in Render.DIRS.size():
		var dx: int = Render.DIRS[d][0]
		var dy: int = Render.DIRS[d][1]
		if Floors.cell(game.G.map.grid, x - dx, y - dy) == 1:
			return [x - dx, y - dy, d]
	return []
