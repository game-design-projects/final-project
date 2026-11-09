## Feature flags: switches for testing and debugging, not settings the player sees.
## They come from the command line after `--` (godot --path . -- nofx seed=7 floor=3) and, on the web build,
## from the address (?nofx&seed=7). A flag is `name` (on) or `name=value`.
## Every flag is declared in KNOWN. Asking for one that isn't is a bug in the caller and is reported at once,
## and an unknown word on the command line is warned about, so a typo never silently does nothing.
##
## The game's features are declared in FEATURES and are on unless switched off: `no-<name>` or `<name>=off` turns one off,
## `classic` turns them all off (`classic <name>` then brings that one back), which is the game as it was before they came.
extends RefCounted

## name -> what it does. Add a line here when a feature gets a switch.
const KNOWN := {
	"debug": "keep the foe's mind panel open (every row of the mind's last answers) in a fight, and log every game event",
	"mock": "monsters think with the seeded mind instead of calling Jev (not in the personality slice, which always uses the local rules)",
	"jev": "jev=<url>: ask Jev through the proxy at this address (without it the rule-based mind answers)",
	"seed": "seed=N: fixed random seed for the floor and the monsters (0 to 9223372036854775807, as the game prints it)",
	"floor": "floor=N: start the run on floor N (with no-real-floors, only call it B<N>F)",
	"meet": "meet=<species>: start in a fight with that monster",
	"personality-slice": "the two-bandit playtest (ROOK, then VEX) at fixed rolls; seed=N picks the seed (default 7042)",
	"nofx": "no post-processing shader",
	"pacifist": "for tools/autoplay.gd: never strike, only ACT and SPARE",
	"practice": "for tools/autoplay.gd: start each game on the practice floor (the feature tutorial-floor), as a first run does",
	"pad": "show the touch pad (arrows, INFO, BACK, OK) without a touch screen",
	"nosound": "no sound effects and no music",
	"nosfx": "no sound effects and no monster voices (the music still plays)",
	"nomusic": "no music (the effects and voices still play)",
	"nosave": "never touch saved data: the slots live in memory for this run and the player's saves stay as they are",
	"frames": "frames=off: skip animation frame exports in tools/panel_reveal_demo.gd",
	"out": "out=<dir>: where the screenshot tool writes its pictures",
	"motif": "motif=N: with the feature motifs, try only that section of the audition (from 1)",
	"only": "only=<species>: for tools/flicker_check.gd, measure that monster alone",
	"classic": "every feature in FEATURES off (name one after it to bring it back)",
}

## name -> what it does. On by default: `no-<name>` or `<name>=off` turns it off. Add a line here for each new feature.
const FEATURES := {
	"dungeon-reveal": "solid floor, wall and ceiling light panels cascade through visible corridors on every step",
	"real-floors": "the stairs lead down to the next floor, with HP, gold, allies and the tally carried over; the run ends at the last floor",
	"piece-icons": "chess attacks show a piece's shape and lines to the squares it reaches, not a letter, and every attack's rule is in plain words",
	"gentle-dodge": "dodges run slower, and their pace follows the foe's friendliness, the floor, how you are doing and the EASY DODGE setting",
	"mini-games": "every third attack is a mini-game: fly through the gaps in the walls, catch the falling stars, or dance on the light to the beat",
	"story": "a run opens with why you are here, each floor says who holds it, and the header counts the floors left",
	"tutorial": "short tips the first time something comes up (remembered, and the TIPS setting skips them), and the first fights of a run go slower",
	"tutorial-floor": "your first run starts on a short practice floor above B1F: one corridor, something to pick up, a small slime and the stairs (with real-floors; the TIPS setting skips it, and once is enough)",
	"walk-heal": "walking the halls slowly brings health back",
	"mood-cues": "a monster shows how a deed landed in a bubble over its head, and asks to join (with a chime) once mercy is likely",
	"show-mind": "the foe's card shows the mind's answers; no-show-mind leaves its mood and clues only, for an A/B test",
	"clear-hp": "the foe's health sits over its head with a number and a trail behind the damage, its mood is named, and your bar shows an arrow as it moves",
	"reveal": "CHECK reads one thing at a time; what a monster likes and hates is found by trying it, and it answers in its own words",
	"chat": "what you type flies to the monster and it listens; its words get a box of their own on the picture, and the info key keeps the talk so far",
	"boss-at-exit": "the champion stands on the stairs: no way down without facing it, and the map hides it until seen",
	"flee-cost": "backing away costs gold, and the monster keeps its wounds and holds a grudge",
	"boss-reward": "a champion you beat or win over leaves you stronger: more max HP and some healing",
	"branching": "the stairs offer two ways down to compare: a tougher floor with a purse on the way, a market with a trader, a quiet one with a longer rest, or a single kind's territory",
	"clans": "monsters belong to clans that remember what you did: later ones say so and start in a different mood, and Jev is told the history",
	"recruit-step": "a spared monster asks to come along and you answer, with no second roll; peace leaves a gift, a refused SPARE no longer angers, and champions are presented as winnable",
	"mercy-link": "the mercy odds show as a gauge beside the monster's health, and each deed says how far it moved them",
	"party-aid": "each ally adds to your strikes, and two or more take the edge off every hit",
	"map-gen": "floors come in biomes with their own generator, size, colours and monsters, and grow as you go down, with a scrolling automap",
	"secrets": "floors hide chests behind cracked walls, which break when you walk into them, and pads that carry you across the floor",
	"items": "floors have things lying about, and ITEM in a fight heals, sharpens, slips away or gives a gift a monster may love",
	"shop": "some floors have a trader who sells items for gold",
	"lurkers": "something stirs in plain sight on a floor: walk round it, or walk into it for a fight and its purse",
	"npcs": "some floors have a monster with a request instead of a fight: fetch something, spare its kin, or get someone off the floor",
	"roaming": "monsters take a turn each step you take: slimes drift, bandits patrol, snakes follow, and an angry or wronged one hunts you",
	"boss-chase": "a champion you have seen comes after you, unless it is holding the stairs (boss-at-exit)",
	"input-cooldown": "for a moment after a fight keys do nothing, and a key still held from it stays dropped until it is pressed again, so a mash can't walk you on",
	"smooth-fight": "in a fight your soul glides between squares, and the battle screen fades back to the halls instead of cutting",
	"heavy-strike": "HEAVY in a fight: a faster line and a smaller mark for a harder hit, which some monsters take worse than others, and a miss leaves you off balance",
	"combat-grid": "larger fight commands in a navigable three-column grid",
	"choice-grid": "larger grid buttons for camp and other choice menus",
	"ambush-prompt": "wait for confirmation after enemy dialogue before continuing combat",
	"dialogue-buffer": "queue early confirmation until the enemy's dialogue has been shown for 0.3 seconds",
	"close-camera": "the camera stands nearer the middle of your cell, so a wall or a monster one cell away reads as close",
	"wide-view": "the 3D picture follows the panel's shape instead of keeping 448:288 with black on both sides",
	"sprite-look": "the walk models are shaped after the fight sprites, outline and face, so a monster looks the same in both views",
	"motifs": "exploring takes turns with Abdulla's motifs (issue #49), if tools/music/cut_motifs.sh has put them in build/motifs/: nothing ships, so without those files nothing changes",
	"achievements": "deeds worth keeping go up on the picture and stay earned across runs, with a page in the main menu",
	"legacy": "a run that ends leaves embers, which buy boons between runs that every later run starts with",
	"hunger": "walking wears on you: hungry, the walk stops healing; starving, it costs health. Enter makes camp to eat, and floors have food",
	"butcher": "at camp a friend can become roasts: eat them, sell them to a trader, or feed them to the others, who like you for it until one works it out",
	"ambush": "a monster that catches you strikes first: its attack comes before your first turn",
	"toll": "the gate on the third stairs drops unless someone holds its chain and stays: you pay in health, or leave a friend, which the Last Door may make you regret",
	"hand-drawn": "the halls are drawn by hand: brick and flagstone lines, torches with eyes, and the monsters' faces and hops, walking and fighting",
	"warmth": "the halls answer what you do: torches look at you, look away, then shut their eyes, and faces go blank as you kill, until the set is cold wire",
	"wick": "a run opens with a very small witch hopping out of the dark to hand you a heart, and she is your first friend until you lose her",
	"text-size": "a TEXT SIZE setting: the log and the speech box write larger wherever they still fit",
	"last-door": "the last stairs open only for someone with a friend; alone you can turn back, or take the lonely ending",
}

const OFF_WORDS := ["off", "0", "false", "no"]

static var _flags = null # Dictionary name -> value ("" for a bare flag); null until first use


## Replace the flags with these words (for tools and scenario scripts that pretend a different command line).
## What the real command line says about features stays, so a test suite can run with `classic` however it sets its other flags.
static func set_args(words: PackedStringArray) -> void:
	_flags = _parse(words)
	var real := _parse(OS.get_cmdline_user_args())
	for name in real:
		if not _flags.has(name) and _is_feature_word(name):
			_flags[name] = real[name]


## True when the flag is present.
static func on(name: String) -> bool:
	return _all().has(_declared(name))


## The flag's value (`seed=7` -> "7"), or `default` when it is absent or has no value.
static func value(name: String, default := "") -> String:
	var v: String = _all().get(_declared(name), "")
	return v if v != "" else default


## Whether a feature is on: declared in FEATURES, and not switched off by `no-<name>`, `<name>=off` or `classic`.
static func enabled(name: String) -> bool:
	if not FEATURES.has(name):
		push_error("flags: '%s' is not a declared feature (see Flags.FEATURES)" % name)
		return false
	var all := _all()
	if all.has("no-" + name):
		return false
	if all.has(name):
		return not str(all[name]) in OFF_WORDS
	return not all.has("classic")


## Whether a feature was switched off by name: `no-<name>` or `<name>=off`, not by `classic`. For what the game did before the
## flag came, which `classic` must leave as it was.
static func switched_off(name: String) -> bool:
	var all := _all()
	return all.has("no-" + name) or (all.has(name) and str(all[name]) in OFF_WORDS)


## The features that are on now, for the logs.
static func enabled_features() -> Array:
	return FEATURES.keys().filter(func(f): return enabled(f))


static func _is_feature_word(name: String) -> bool:
	return name == "classic" or FEATURES.has(name) or (name.begins_with("no-") and FEATURES.has(name.substr(3)))


static func _declared(name: String) -> String:
	if not KNOWN.has(name):
		push_error("flags: '%s' is not a declared flag (see Flags.KNOWN)" % name)
	return name


static func _all() -> Dictionary:
	if _flags == null:
		var words := PackedStringArray()
		if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
			words.append(str(JavaScriptBridge.eval("location.search + location.hash", true)))
		words.append_array(OS.get_cmdline_user_args())
		_flags = _parse(words)
	return _flags


## Words may be joined by spaces, `&`, `?` or `#`, and may start with dashes: "--nofx", "?seed=7&nofx".
static func _parse(words: PackedStringArray) -> Dictionary:
	var out := {}
	var splitter := RegEx.create_from_string("[\\s&?#]+")
	for word in words:
		for token in splitter.sub(word, " ", true).split(" ", false):
			var t := token.lstrip("-").to_lower()
			var eq := t.find("=")
			var name := t if eq < 0 else t.substr(0, eq)
			if name == "":
				continue
			if not KNOWN.has(name) and not _is_feature_word(name):
				push_warning("flags: unknown flag '%s' ignored" % name)
				continue
			out[name] = "" if eq < 0 else t.substr(eq + 1)
	print_verbose("flags: %s" % [out])
	return out
