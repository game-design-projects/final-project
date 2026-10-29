## Achievements: rewards for the things that make Donjon what it is (talking a monster down, winning one over,
## keeping a vow, a natural 20 when it counts), not for grinding. Earned once, kept forever in the store,
## across runs and deaths, with the moment each was earned.
##
## game.gd only sends events from one-line hooks, e.g. ach.on("recruit", {"species": ..., "shiny": ..., "boss": ..., "allies": ...}).
## `create_achievements` is the pure part (no UI): the list, the rules that turn events into unlocks, counters,
## persistence. The unlock toast and the K screen live in src/ui and are built from `list()`, `count()`,
## `color_of` and `glyph_of`.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")

const ACH_KEY = "donjon.achievements"
const TOAST_MS = 3500 # how long an unlock toast stays up
const MAX_TOASTS = 2 # more than this at once wait their turn (keeps the middle of the view clear)
const STAGGER_MS = 220 # toasts that unlock together slide in one after another
const JINGLE_GAP_MS = 700 # one jingle for a burst of unlocks

## Groups, in screen order, each with its own color (an earned badge glows in it).
const GROUPS = {
	"words": {"label": "WORDS", "color": "#ff9de2"},
	"friends": {"label": "FRIENDS", "color": "#6bd36b"},
	"vows": {"label": "VOWS", "color": "#c79cff"},
	"dice": {"label": "DICE", "color": "#ffe03a"},
	"depths": {"label": "DEPTHS", "color": "#ff5a4a"},
	"oddities": {"label": "ODDITIES", "color": "#ffb347"},
}

## 7x7 pixel glyphs, drawn like status.gd's icons ("#" is a lit pixel).
const GLYPHS = {
	"trophy": ["#######", "#.###.#", "#.###.#", ".#####.", "..###..", "...#...", ".#####."],
	"secret": [".####..", "#....#.", "....#..", "...#...", "...#...", ".......", "...#..."],
	"up": ["...#...", "..###..", ".#####.", "#######", "...#...", "...#...", "...#..."],
	"down": ["...#...", "...#...", "...#...", "#######", ".#####.", "..###..", "...#..."],
	"heart": [".##.##.", "#######", "#######", ".#####.", "..###..", "...#...", "......."],
	"smile": [".#####.", "#.....#", "#.#.#.#", "#.....#", "#.#.#.#", "#..#..#", ".#####."],
	"peace": [".#####.", "#..#..#", "#..#..#", "#.###.#", "##.#.##", "#..#..#", ".#####."],
	"bubble": ["#######", "#.....#", "#.#.#.#", "#.....#", "###.###", "..##...", "..#...."],
	"boo": ["#.#.#.#", ".......", "#.....#", "..###..", ".#...#.", "..###..", "#.....#"],
	"eye": [".......", "..###..", ".#...#.", "#..#..#", ".#...#.", "..###..", "......."],
	"paw": [".#...#.", "...#...", ".#...#.", "..###..", ".#####.", ".#####.", "..#.#.."],
	"gem": [".#####.", "#.#.#.#", "#######", ".#####.", "..###..", "...#...", "......."],
	"trio": ["#..#..#", ".......", "##.#.##", "##.#.##", ".......", "#######", "#######"],
	"crown": [".......", "#..#..#", "##.#.##", "#######", "#######", "#######", "......."],
	"globe": [".#####.", "#.#.#.#", "#######", "#.#.#.#", "#######", "#.#.#.#", ".#####."],
	"scroll": ["#######", ".#...#.", ".#.#.#.", ".#...#.", ".#.#.#.", ".#...#.", "#######"],
	"mended": [".##.##.", "###.###", "####.##", ".##.##.", "..#.#..", "...#...", "......."],
	"door": [".#####.", ".#...#.", ".#...#.", ".#..##.", ".#...#.", ".#...#.", ".#####."],
	"dagger": ["......#", ".....#.", "....#..", "#..#...", ".##....", ".##....", "#..#..."],
	"bag": ["..###..", "...#...", ".#####.", "##.#.##", "#..##.#", "##.#.##", ".#####."],
	"d20": ["#######", "#.#.#.#", "#.....#", "#..#..#", "#.....#", "#.#.#.#", "#######"],
	"mic": ["..###..", "..###..", "..###..", "#.###.#", "#.....#", ".#####.", "...#..."],
	"d1": ["#######", "#.....#", "#.....#", "#..#..#", "#.....#", "#.....#", "#######"],
	"plus": ["..###..", "..###..", "#######", "#######", "#######", "..###..", "..###.."],
	"rise": ["...#...", "..###..", ".#####.", "...#...", "#.....#", ".#...#.", "..###.."],
	"stairs": ["......#", ".....##", "....###", "...####", "..#####", ".######", "#######"],
	"pit": ["#.....#", "#.....#", ".#...#.", ".#...#.", "..#.#..", "..#.#..", "...#..."],
	"skull": ["..###..", ".#####.", "#..#..#", "#######", ".##.##.", "..#.#..", "..#.#.."],
	"wave": [".......", "##...##", "##...##", ".......", "#######", ".#####.", "......."],
	"star": ["...#...", "...#...", "#######", ".#####.", "..###..", ".##.##.", ".#...#."],
	"coin": ["..###..", ".#####.", "##.####", "##.####", "##.####", ".#####.", "..###.."],
	"mirror": ["..###..", ".#...#.", ".#.#.#.", ".#...#.", "..###..", "...#...", "..###.."],
	"swords": ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", "##...##", "##...##"],
	"tomb": [".#####.", "##...##", "#..#..#", "#.###.#", "#..#..#", "#.....#", "#######"],
}

## The list. `goal` makes it a counter (`values`: the distinct things to see, which mirror emotions.gd's feelings for
## EMPATH and species.gd's kinds for MENAGERIE); `secret` hides its name and line until it's earned.
## Each line says what to do in the game's own words; the trigger is noted beside it (event → condition).
const ACHIEVEMENTS = [
	# WORDS: talking always matters
	{"id": "charmed", "group": "words", "icon": "heart", "name": "CHARMER", "desc": "SAY SOMETHING THAT LEAVES A MONSTER DELIGHTED."}, # feel delighted
	{"id": "stitches", "group": "words", "icon": "smile", "name": "OPEN MIC NIGHT", "desc": "LEAVE A MONSTER IN STITCHES, TOO BUSY LAUGHING TO FIGHT."}, # feel amused
	{"id": "peacemaker", "group": "words", "icon": "peace", "name": "PEACEMAKER", "desc": "TALK A MONSTER INTO LETTING YOU PASS IN PEACE."}, # peace
	{"id": "all_talk", "group": "words", "icon": "bubble", "name": "ALL TALK", "desc": "WIN A FIGHT WITHOUT A SINGLE ATTACK."}, # fight-end: won, no attack, no kill
	{"id": "boo", "group": "words", "icon": "boo", "name": "BOO!", "desc": "SCARE A MONSTER SO BADLY IT DROPS ITS GOLD."}, # feel terrified
	{"id": "empath", "group": "words", "icon": "eye", "name": "EMPATH", "desc": "SEE MONSTERS FEEL ALL 10 FEELINGS, OVER ALL YOUR RUNS.", "goal": 10, "values": ["delighted", "amused", "touched", "flattered", "intrigued", "confused", "sad", "offended", "enraged", "terrified"]}, # feel *
	# FRIENDS: recruiting
	{"id": "first_friend", "group": "friends", "icon": "paw", "name": "FIRST FRIEND", "desc": "WIN A MONSTER OVER TO YOUR PARTY."}, # recruit
	{"id": "shiny", "group": "friends", "icon": "gem", "name": "ALL THAT GLITTERS", "desc": "RECRUIT A SHINY. FATE OWES YOU A ROLL."}, # recruit shiny
	{"id": "mash", "group": "friends", "icon": "trio", "name": "MONSTER MASH", "desc": "TRAVEL WITH THREE MONSTER ALLIES AT ONCE."}, # recruit, allies >= 3
	{"id": "red_carpet", "group": "friends", "icon": "crown", "name": "RED CARPET", "desc": "WIN A RED CHAMPION OVER TO YOUR SIDE."}, # recruit boss
	{"id": "menagerie", "group": "friends", "icon": "globe", "name": "MENAGERIE", "desc": "RECRUIT EVERY KIND OF MONSTER, OVER ALL YOUR RUNS.", "goal": 6, "values": ["slime", "goblin", "dragon", "snake", "rock", "bandit"]}, # recruit *
	# VOWS
	{"id": "word_is_bond", "group": "vows", "icon": "scroll", "name": "WORD IS BOND", "desc": "TAKE THE STAIRS WITH A VOW TO AN ALLY UNBROKEN."}, # descend, keptVows > 0
	{"id": "second_chance", "group": "vows", "icon": "mended", "name": "SECOND CHANCES", "desc": "BREAK A VOW TO AN ALLY, AND BE FORGIVEN."}, # vow-broken forgive
	{"id": "walked_out", "group": "vows", "icon": "door", "name": "IT'S YOU, NOT ME", "desc": "HAVE AN ALLY WALK OUT ON THE PARTY."}, # vow-broken leave / ally-decision leave
	{"id": "betrayed", "group": "vows", "icon": "dagger", "name": "ET TU?", "desc": "HAVE AN ALLY TURN ON YOU.", "secret": true}, # vow-broken attack / ally-decision turn_on_party
	{"id": "robbed", "group": "vows", "icon": "bag", "name": "LIGHT FINGERS", "desc": "HAVE AN ALLY RUN OFF WITH YOUR GOLD.", "secret": true}, # vow-broken steal_gold, got away
	# DICE
	{"id": "crit_happens", "group": "dice", "icon": "d20", "name": "CRIT HAPPENS", "desc": "ROLL A NATURAL 20 ON AN ATTACK."}, # attack-roll 20
	{"id": "mic_drop", "group": "dice", "icon": "mic", "name": "MIC DROP", "desc": "ROLL A NATURAL 20 WHILE TALKING. WORDS LAND DOUBLE."}, # talk-roll 20
	{"id": "fail_forward", "group": "dice", "icon": "d1", "name": "FAIL FORWARD", "desc": "FUMBLE YOUR WORDS ON A 1, THEN WIN THEM OVER ANYWAY."}, # talk-roll 1, then recruit/peace in that fight
	{"id": "still_breathing", "group": "dice", "icon": "plus", "name": "STILL BREATHING", "desc": "PULL THROUGH THREE DEATH SAVES AND STABILIZE."}, # death-save stable
	{"id": "not_today", "group": "dice", "icon": "rise", "name": "NOT TODAY", "desc": "ROLL A 20 ON A DEATH SAVE AND GET BACK UP."}, # death-save 20
	# DEPTHS: progression
	{"id": "deep5", "group": "depths", "icon": "stairs", "name": "INTO THE DARK", "desc": "REACH FLOOR 5."}, # descend floor >= 5
	{"id": "deep10", "group": "depths", "icon": "pit", "name": "ABYSS GAZER", "desc": "REACH FLOOR 10. IT GAZES BACK."}, # descend floor >= 10
	{"id": "seeing_red", "group": "depths", "icon": "skull", "name": "SEEING RED", "desc": "SLAY A RED CHAMPION."}, # fight-end boss dead
	{"id": "stand_down", "group": "depths", "icon": "wave", "name": "STAND DOWN", "desc": "TALK A RED CHAMPION INTO LETTING YOU PASS."}, # peace boss
	{"id": "legendary", "group": "depths", "icon": "star", "name": "LEGENDARY", "desc": "LAND A LEGENDARY BOON ON A GREAT ROLL OF FATE."}, # boon legendary
	# ODDITIES
	{"id": "goblin_tax", "group": "oddities", "icon": "coin", "name": "GOBLIN TAX", "desc": "PAY A GOBLIN. IT TAKES THE GOLD, OBVIOUSLY.", "secret": true}, # paid goblin
	{"id": "so_vain", "group": "oddities", "icon": "mirror", "name": "SO VAIN", "desc": "FLATTER A DRAGON. IT AGREES WITH EVERY WORD.", "secret": true}, # feel flattered, dragon
	{"id": "mutiny", "group": "oddities", "icon": "swords", "name": "MUTINY", "desc": "SEE A MONSTER TURN ON ITS OWN GROUP.", "secret": true}, # mutiny
	{"id": "permadeath", "group": "oddities", "icon": "tomb", "name": "PERMADEATH", "desc": "LOSE A WHOLE PARTY. IT HAPPENS TO THE BEST."}, # wipe
]

const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

static var _by_id := _index()


static func _index() -> Dictionary:
	var out := {}
	for a in ACHIEVEMENTS:
		out[a.id] = a
	return out


## Read the saved state, keeping only what still makes sense (known ids, numeric dates, known counter values).
## Returns {earned: {id: ms}, progress: {id: [values]}}.
static func _load(store) -> Dictionary:
	var earned := {}
	var progress := {}
	var raw = store.get_item(ACH_KEY) if store != null else null
	var json := JSON.new()
	if raw != null and json.parse(raw) == OK and json.data is Dictionary:
		var saved: Dictionary = json.data
		if saved.get("earned") is Dictionary:
			for id in saved.earned:
				var at = saved.earned[id]
				if _by_id.has(id) and (at is int or at is float) and is_finite(at):
					earned[id] = int(at)
		if saved.get("progress") is Dictionary:
			for id in saved.progress:
				var vals = saved.progress[id]
				if _by_id.has(id) and _by_id[id].has("values") and vals is Array:
					var kept := []
					for v in vals:
						if _by_id[id].values.has(v) and not kept.has(v):
							kept.append(v)
					progress[id] = kept
	return {"earned": earned, "progress": progress}


## opts: {store, now: Callable() -> ms, onUnlock: Callable(achievement view), log: Callable(String)}. `store` has
## get_item / set_item; every part is optional.
static func create_achievements(opts := {}) -> Achievements:
	return Achievements.new(opts)


class Achievements:
	extends RefCounted
	const A = preload("res://src/rules/achievements.gd")

	## This fight's notes {attacked, fumbled}, or null outside a fight.
	var fight = null
	var _store
	var _now: Callable
	var _on_unlock: Callable
	var _log: Callable
	var _earned := {}
	var _progress := {}

	func _init(opts := {}) -> void:
		_store = opts.get("store")
		_now = opts.get("now", Callable(J, "date_ms"))
		_on_unlock = opts.get("onUnlock", Callable())
		_log = opts.get("log", func(msg: String): print_verbose("[achievements] " + msg))
		var saved := A._load(_store)
		_earned = saved.earned
		_progress = saved.progress

	func _say_log(parts: Array) -> void:
		if _log.is_valid():
			_log.call(" ".join(parts.map(func(p): return str(p))))

	func _save() -> void:
		if _store != null:
			_store.set_item(A.ACH_KEY, JSON.stringify({"v": 1, "earned": _earned, "progress": _progress}))

	func _view(a: Dictionary) -> Dictionary:
		var got: bool = _earned.has(a.id)
		var hide: bool = a.get("secret", false) and not got
		var v := a.duplicate()
		v.name = "???" if hide else a.name
		v.desc = "???" if hide else a.desc
		v.earned = got
		v.at = _earned.get(a.id)
		v.progress = {"n": (_progress.get(a.id, []) as Array).size(), "goal": a.goal} if a.has("goal") else null
		return v

	## Earns an achievement once. Returns true when it was newly earned.
	func unlock(id) -> bool:
		var a = A._by_id.get(id)
		if a == null:
			_say_log(["unknown achievement", id])
			return false
		if _earned.has(id):
			return false
		_earned[id] = int(floor(float(_now.call())))
		_save()
		_say_log(["unlock", id])
		if _on_unlock.is_valid():
			_on_unlock.call(_view(a))
		return true

	## A counter: one more distinct value seen; unlocks when every value has been seen.
	func _count_value(id: String, value) -> void:
		var a = A._by_id.get(id)
		if a == null or not a.has("values") or not a.values.has(value):
			return
		if not _progress.has(id):
			_progress[id] = []
		var seen: Array = _progress[id]
		if seen.has(value):
			return
		seen.append(value)
		_save()
		_say_log(["progress", id, "%d/%d" % [seen.size(), a.goal]])
		if seen.size() >= a.goal:
			unlock(id)

	## One game event with its data (a Dictionary, or null): turns it into unlocks and counters.
	func on(event, data = null) -> void:
		var d: Dictionary = data if data is Dictionary else {}
		match event:
			"fight-start":
				fight = {"attacked": false, "fumbled": false}
			"attack":
				if fight != null:
					fight.attacked = true
			"fight-end":
				if fight != null and J.truthy(d.get("won")) and not J.truthy(d.get("kills")) and not fight.attacked:
					unlock("all_talk")
				if d.get("boss") == "dead":
					unlock("seeing_red")
				fight = null
			"feel":
				var feeling = d.get("feeling")
				if feeling == "delighted":
					unlock("charmed")
				if feeling == "amused":
					unlock("stitches")
				if feeling == "terrified":
					unlock("boo")
				if feeling == "flattered" and d.get("species") == "dragon":
					unlock("so_vain")
				_count_value("empath", feeling)
			"talk-roll":
				var roll = d.get("roll")
				if roll == 20:
					unlock("mic_drop")
				if roll == 1 and fight != null:
					fight.fumbled = true
			"attack-roll":
				if d.get("roll") == 20:
					unlock("crit_happens")
			"recruit":
				unlock("first_friend")
				if J.truthy(d.get("shiny")):
					unlock("shiny")
				if J.truthy(d.get("boss")):
					unlock("red_carpet")
				if J.nz(d.get("allies"), 0) >= 3:
					unlock("mash")
				if fight != null and fight.fumbled:
					unlock("fail_forward")
				_count_value("menagerie", d.get("species"))
			"peace":
				unlock("peacemaker")
				if J.truthy(d.get("boss")):
					unlock("stand_down")
				if fight != null and fight.fumbled:
					unlock("fail_forward")
			"death-save":
				if J.truthy(d.get("stable")):
					unlock("still_breathing")
				if d.get("roll") == 20:
					unlock("not_today")
			"descend":
				var floor_n = J.nz(d.get("floor"), 0)
				if floor_n >= 5:
					unlock("deep5")
				if floor_n >= 10:
					unlock("deep10")
				if J.nz(d.get("keptVows"), 0) > 0:
					unlock("word_is_bond")
			"boon":
				if J.truthy(d.get("legendary")):
					unlock("legendary")
			"vow-broken":
				var response = d.get("response")
				if response == "forgive":
					unlock("second_chance")
				if response == "leave_party":
					unlock("walked_out")
				if response == "attack_party":
					unlock("betrayed")
				if response == "steal_gold" and J.truthy(d.get("stolen")):
					unlock("robbed")
			"ally-decision":
				var decision = d.get("decision")
				if decision == "leave_party":
					unlock("walked_out")
				if decision == "turn_on_party":
					unlock("betrayed")
			"paid":
				if d.get("species") == "goblin":
					unlock("goblin_tax")
			"mutiny":
				unlock("mutiny")
			"wipe":
				unlock("permadeath")
			_:
				_say_log(["unknown event", event])

	func has(id) -> bool:
		return _earned.has(id)

	## When it was earned (ms), or null.
	func earned_at(id):
		return _earned.get(id)

	## {n, goal} for a counter, null for a one-off.
	func progress(id):
		var a = A._by_id.get(id)
		if a != null and a.has("goal"):
			return {"n": (_progress.get(id, []) as Array).size(), "goal": a.goal}
		return null

	## {earned, total}
	func count() -> Dictionary:
		return {"earned": _earned.size(), "total": A.ACHIEVEMENTS.size()}

	## Every achievement as the player sees it: its fields plus earned, at (ms or null) and progress ({n, goal} or null).
	## A secret reads "???" for name and desc until it's earned.
	func list() -> Array:
		return A.ACHIEVEMENTS.map(_view)

	func reset() -> void:
		_earned = {}
		_progress = {}
		fight = null
		_save()
		_say_log(["reset"])


## "JAN 31 2026", in the player's time zone.
static func fmt_date(ms) -> String:
	var offset_min: int = Time.get_time_zone_from_system().bias
	var d := Time.get_datetime_dict_from_unix_time(floori(float(ms) / 1000.0) + offset_min * 60)
	return "%s %d %d" % [MONTHS[d.month - 1], d.day, d.year]


## The accent color of an achievement's group.
static func color_of(a: Dictionary) -> String:
	return GROUPS.get(a.get("group"), {}).get("color", "#ffd27a")


## The glyph to show for an achievement: a secret that isn't earned yet shows the "secret" glyph.
static func glyph_of(a: Dictionary) -> String:
	return "secret" if a.get("secret", false) and not a.get("earned", false) else a.icon


static var _badge_images := {}
static var _badge_textures := {}


## A badge glyph as a 7x7 Image (1 pixel per dot) in the given color (CSS string or Color); unknown names show "secret".
static func badge_image(name: String, color = "#e8e8e8") -> Image:
	if not GLYPHS.has(name):
		name = "secret"
	var col := Canvas2D.css(color)
	var key := "%s|%s" % [name, col.to_html()]
	if _badge_images.has(key):
		return _badge_images[key]
	var rows: Array = GLYPHS[name]
	var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	for y in 7:
		for x in 7:
			if rows[y][x] == "#":
				img.set_pixel(x, y, col)
	_badge_images[key] = img
	return img


## A badge glyph as a crisp texture, 1 texel per dot; cached per name and color. Scale it with nearest filtering.
static func badge_texture(name: String, color = "#e8e8e8") -> Texture2D:
	if not GLYPHS.has(name):
		name = "secret"
	var key := "%s|%s" % [name, Canvas2D.css(color).to_html()]
	if _badge_textures.has(key):
		return _badge_textures[key]
	var tex := ImageTexture.create_from_image(badge_image(name, color))
	_badge_textures[key] = tex
	return tex
