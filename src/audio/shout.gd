## What a monster sounds like when it speaks: a pure line -> sound-plan classifier, no audio and no nodes.
## sfx.gd turns a plan into synthesised noise; the keyword table lives here so it can be tested without sound.
##
## Lines are mostly the approved ones in species.gd ("RAAH! *swings a knotted club at {target}*", "*hisses softly*",
## "...bloop?"), but a line can be any free text, so every rule is a loose regex and every path ends in a fallback.
## Load it with `const Shout = preload("res://src/audio/shout.gd")`.
extends RefCounted

# kind -> what the synth plays
const KINDS := ["roar", "bark", "grunt", "growl", "hiss", "squelch", "laugh", "squeal", "whimper", "sigh", "rumble", "zap", "babble"]

# Onomatopoeia and emote verbs, case-insensitive. The earliest match in the line decides.
# A kind named here is mapped through the species' `remap` before it is played (a slime's "grunt" is a squelch).
const KEYWORD_PATTERNS := [
	["roar", "\\b(?:r+a+h+|ra+g+h+|r+o+a+r+\\w*|a+r+g+h+|gra+h+|wa+gh+|bellow\\w*|bawl\\w*)\\b"],
	["growl", "\\b(?:g+r{2,}\\w*|growl\\w*|snarl\\w*|rasp\\w*)\\b"],
	["grunt", "\\b(?:grunt\\w*|hm+ph|hrm+ph?|ugh+|oof|pah+|bah+|huh+|snort\\w*|hm+|eh)\\b"],
	["hiss", "\\bhiss\\w*|s{3,}"],
	["squelch", "\\b(?:bl(?:o|oo)rp\\w*|bloop\\w*|splort\\w*|squelch\\w*|slorp\\w*|slurp\\w*|squish\\w*|plop\\w*|glop\\w*|gloop\\w*|ooze\\w*|gurgl\\w*)\\b"],
	["laugh", "\\b(?:laugh\\w*|giggl\\w*|chuckl\\w*|cackl\\w*|snicker\\w*|titter\\w*|(?:m[uw]+a+)?(?:ha){2,}h?|(?:he){2,}h?|hee+hee+|heh|hah?|hur(?: hur)*|ho ho)\\b"],
	["squeal", "\\b(?:squeal\\w*|squeak\\w*|scream\\w*|screech\\w*|shriek\\w*|yelp\\w*|yip\\w*|a{3,}h+)\\b"],
	["whimper", "\\b(?:whimper\\w*|whine\\w*|whining|sobs?|sobbing|cry|cries|crying|trembl\\w*|shiver\\w*|quiver\\w*|sniffl\\w*)\\b"],
	["sigh", "\\b(?:sigh\\w*|yawn\\w*|exhal\\w*)\\b"],
	["rumble", "\\b(?:rumbl\\w*|groan\\w*|grind\\w*|crumbl\\w*|rockslide|stone rains|thunder\\w*|boom\\w*|crash\\w*)\\b"],
	["zap", "\\b(?:crackl\\w*|lightning|zap\\w*|spark\\w*|sizzl\\w*)\\b"],
]

# Pure stage directions that make no sound at all (only used when the line has no spoken words and no keyword).
const SILENT_PATTERN := "\\b(?:stares?|staring|studies|watches|scratches|picks|tips|narrows|folds|dust|eyes?|coils?|waves?|ducks|backs off|shrinks|settles|pulls|spreads|departs|vanishes|melts|slips|weighs|hunkers|hardens|closes|tastes|stays)\\b"

# One voice per species: base pitch (Hz), formant scale (small throat = high formants), how breathy/gravelly,
# whether it is wet (blips instead of vowels), what its loud shout is, and what a wordless emote sounds like.
const VOICES := {
	"slime": {"f0": 250, "size": 1.15, "rasp": 0.05, "wet": true, "big": "squeal", "emote": "squelch", "remap": {"grunt": "squelch", "growl": "squelch", "bark": "squeal", "roar": "squeal", "rumble": "squelch", "zap": "squelch"}},
	"goblin": {"f0": 150, "size": 0.95, "rasp": 0.55, "wet": false, "big": "roar", "emote": "grunt", "remap": {}},
	"dragon": {"f0": 62, "size": 0.55, "rasp": 0.35, "wet": false, "big": "roar", "emote": "growl", "remap": {"squelch": "growl"}},
	"snake": {"f0": 170, "size": 1.0, "rasp": 0.8, "wet": false, "big": "hiss", "emote": "hiss", "remap": {"grunt": "hiss", "bark": "hiss", "roar": "hiss", "squeal": "hiss"}},
	"rock": {"f0": 48, "size": 0.5, "rasp": 0.7, "wet": false, "big": "rumble", "emote": "rumble", "remap": {"grunt": "rumble", "bark": "rumble", "roar": "rumble", "laugh": "rumble", "squeal": "rumble", "hiss": "rumble", "whimper": "sigh", "squelch": "rumble"}},
	"bandit": {"f0": 118, "size": 1.0, "rasp": 0.15, "wet": false, "big": "roar", "emote": "grunt", "remap": {}},
}
const DEFAULT_VOICE := {"f0": 130, "size": 1, "rasp": 0.3, "wet": false, "big": "roar", "emote": "grunt", "remap": {}}

# Sounds a creature makes with its throat; they win over everything else in the line (earliest first).
# Effect words (a rockslide, lightning, a yawn) only count when nothing shouted or vocal is in the line.
const EFFECT := {"rumble": true, "zap": true, "sigh": true}

## KEYWORDS: [[kind, compiled RegEx]], the same table as KEYWORD_PATTERNS
static var KEYWORDS: Array = _compile_keywords()
static var _silent := _re("(?i)" + SILENT_PATTERN)
static var _braces := _re("\\{[^}]*\\}")
static var _stars := _re("\\*[^*]*\\*")
static var _letter := _re("(?i)[a-z]")
static var _two_letters := _re("(?i)[a-z]{2,}")
static var _caps := _re("\\b[A-Z]{3,}\\b")
static var _caps_emote := _re("\\*[^*]*\\b[A-Z]{3,}\\b[^*]*\\*")
static var _hushed := _re("^\\s*(?:\\.\\.\\.|\\*)")
static var _word := _re("(?i)[a-z']+")


static func _re(pattern: String) -> RegEx:
	var re := RegEx.create_from_string(pattern)
	assert(re != null and re.is_valid(), "shout: bad pattern " + pattern)
	return re


static func _compile_keywords() -> Array:
	var out := []
	for k in KEYWORD_PATTERNS:
		out.append([k[0], _re("(?i)" + k[1])])
	return out


## The line without {placeholders}, at most 400 characters ("" for anything that is not a string)
static func _clean(line) -> String:
	if not line is String:
		return ""
	return _braces.sub(line, " ", true).left(400)


## The loudness of a line: shouted (CAPS or !) beats whispered (leading "..." or a pure emote) beats normal.
static func _loudness(text: String, spoken: String) -> float:
	if _caps.search(text) != null or spoken.contains("!"):
		return 1.0
	if _hushed.search(text) != null:
		return 0.7
	return 0.85


## The earliest keyword in `text` whose kind passes `wanted` (a Callable on the kind), or null
static func _earliest(text: String, wanted: Callable):
	var best_kind = null
	var best_index := -1
	for k in KEYWORDS:
		if not wanted.call(k[0]):
			continue
		var m: RegExMatch = k[1].search(text)
		if m != null and (best_kind == null or m.get_start() < best_index):
			best_kind = k[0]
			best_index = m.get_start()
	return best_kind


## The kind of sound a line makes, before species adjustments, or null for a silent line.
## "big" and "emote" stand for the species' own loud shout and wordless noise.
static func classify_kind(line):
	var text := _clean(line)
	if _letter.search(text) == null:
		return null
	var spoken := _stars.sub(text, " ", true)
	var vocal = _earliest(text, func(k): return not EFFECT.has(k))
	if vocal != null:
		return vocal
	var caps_spoken := _caps.search(spoken) != null
	var caps_emote := _caps_emote.search(text) != null
	var bang := spoken.contains("!")
	if caps_emote or (caps_spoken and bang):
		return "big"
	var effect = _earliest(text, func(k): return EFFECT.has(k))
	if effect != null:
		return effect
	if caps_spoken or bang:
		return "bark"
	if _two_letters.search(spoken) != null:
		return "babble"
	return null if _silent.search(text) != null else "emote"


## A full plan for the synth, or null if the line makes no sound.
## { kind, f0, size, rasp, wet, vol, syll, species } where `kind` is one of KINDS.
static func shout_plan(line, species = null, opts := {}):
	var raw = classify_kind(line)
	if raw == null:
		return null
	var boss: bool = opts.get("boss", false)
	var v: Dictionary = VOICES.get(species, DEFAULT_VOICE)
	var text := _clean(line)
	var spoken := _stars.sub(text, " ", true)
	var kind: String
	if raw == "big":
		kind = v.big
	elif raw == "emote":
		kind = v.emote
	else:
		kind = v.remap.get(raw, raw)
	var words := _word.search_all(spoken).size()
	return {
		"kind": kind,
		"species": species if VOICES.has(species) else "other",
		"f0": v.f0 * (0.85 if boss else 1.0),
		"size": v.size * (0.9 if boss else 1.0),
		"rasp": v.rasp,
		"wet": v.wet,
		"vol": _loudness(text, spoken) * (1.1 if boss else 1.0),
		"syll": maxi(2, mini(6, ceili(words * 0.6))),
	}
