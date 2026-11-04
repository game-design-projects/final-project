## Feature flags: switches for testing and debugging, not settings the player sees.
## They come from the command line after `--` (godot --path . -- nofx seed=7 floor=3) and, on the web build,
## from the address (?nofx&seed=7). A flag is `name` (on) or `name=value`.
## Every flag is declared in KNOWN. Asking for one that isn't is a bug in the caller and is reported at once,
## and an unknown word on the command line is warned about, so a typo never silently does nothing.
extends RefCounted

## name -> what it does. Add a line here when a feature gets a switch.
const KNOWN := {
	"debug": "keep the foe's mind panel open (every row of the mind's last answers) in a fight, and log every game event",
	"mock": "monsters think with the seeded mind instead of calling Jev (not in the personality slice, which always uses the local rules)",
	"jev": "jev=<url>: ask Jev through the proxy at this address (without it the rule-based mind answers)",
	"seed": "seed=N: fixed random seed for the floor and the monsters (0 to 9223372036854775807, as the game prints it)",
	"floor": "floor=N: call the floor B<N>F and give it floor N's colours (nothing else about the floor changes)",
	"meet": "meet=<species>: start in a fight with that monster",
	"personality-slice": "the two-bandit playtest (ROOK, then VEX) at fixed rolls; seed=N picks the seed (default 7042)",
	"nofx": "no post-processing shader",
	"pad": "show the touch pad (arrows, INFO, BACK, OK) without a touch screen",
	"nosound": "no sound effects and no music",
	"nosfx": "no sound effects and no monster voices (the music still plays)",
	"nomusic": "no music (the effects and voices still play)",
	"nosave": "never touch saved data: the slots live in memory for this run and the player's saves stay as they are",
	"out": "out=<dir>: where the screenshot tool writes its pictures",
}

static var _flags = null # Dictionary name -> value ("" for a bare flag); null until first use


## Replace the flags with these words (for tools and scenario scripts that pretend a different command line).
static func set_args(words: PackedStringArray) -> void:
	_flags = _parse(words)


## True when the flag is present.
static func on(name: String) -> bool:
	return _all().has(_declared(name))


## The flag's value (`seed=7` -> "7"), or `default` when it is absent or has no value.
static func value(name: String, default := "") -> String:
	var v: String = _all().get(_declared(name), "")
	return v if v != "" else default


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
			if not KNOWN.has(name):
				push_warning("flags: unknown flag '%s' ignored" % name)
				continue
			out[name] = "" if eq < 0 else t.substr(eq + 1)
	print_verbose("flags: %s" % [out])
	return out
