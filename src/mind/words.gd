## Reading the player's typed words with keyword cues: the local stand-in for a mind that understands language.
## The cues and the filler words live in data/words.json.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Odds = preload("res://src/rules/odds.gd")

## Each cue counts at most this many times, so repeating a word doesn't drown out the rest.
const CUE_CAP := 2
const CUE_WEIGHT := 1.5
const CUE_BIAS := -0.6
const OTHER_LOGIT := 0.3
const GIBBERISH_NO_WORDS := 0.95
const GIBBERISH_MIN := 0.02
const GIBBERISH_MAX := 0.97

static var _cues := {} # intent -> RegEx, built on first use
static var _money: RegEx
static var _word := RegEx.create_from_string("[a-z']+")
static var _vowel := RegEx.create_from_string("[aeiouy]")
static var _consonants := RegEx.create_from_string("[^aeiouy']+")
static var _triple := RegEx.create_from_string("(.)\\1\\1")
static var _mash := RegEx.create_from_string("asdf|qwer|zxcv|jkl|hjk")


static func _cue_patterns() -> Dictionary:
	if _cues.is_empty():
		var cues: Dictionary = Content.table("words").cues
		for intent in cues:
			_cues[intent] = RegEx.create_from_string(cues[intent])
	return _cues


## How many cues of each intent the text contains.
static func cue_counts(text: String) -> Dictionary:
	var t := text.to_lower()
	var out := {}
	var patterns := _cue_patterns()
	for intent in patterns:
		out[intent] = patterns[intent].search_all(t).size()
	return out


## How likely the text is nonsense (keyboard mashing, no vowels, repeated letters). Known cue words pull it down.
static func gibberish_odds(text: String) -> float:
	var t := text.to_lower().strip_edges()
	var words: Array[String] = []
	for m in _word.search_all(t):
		words.append(m.get_string())
	if words.is_empty():
		return GIBBERISH_NO_WORDS
	var common: Array = Content.table("words").common
	var bad := 0
	for w in words:
		if common.has(w) or w.length() <= 2:
			continue
		var vowels := _vowel.search_all(w).size()
		var run := 0
		for m in _consonants.search_all(w):
			run = maxi(run, m.get_string().length())
		if vowels == 0 or run >= 4 or _triple.search(w) != null or _mash.search(w) != null or float(vowels) / w.length() < 0.15:
			bad += 1
	var cue_total := 0
	for n in cue_counts(t).values():
		cue_total += n
	var odds := float(bad) / words.size() - cue_total * 0.15
	if words.size() == 1 and cue_total == 0:
		odds += 0.2
	return clampf(odds, GIBBERISH_MIN, GIBBERISH_MAX)


## Intent -> probability for what was typed: the cue intents, "other", and "gibberish". Adds up to 1.
static func read(text: String) -> Dictionary:
	var gibberish := gibberish_odds(text)
	var logits := {"other": OTHER_LOGIT}
	var counts := cue_counts(text)
	for intent in counts:
		logits[intent] = minf(counts[intent], CUE_CAP) * CUE_WEIGHT + CUE_BIAS
	var probs := {}
	var soft := Odds.softmax(logits)
	for k in soft:
		probs[k] = soft[k] * (1.0 - gibberish)
	probs["gibberish"] = gibberish
	return probs


## Does the text name money outright? "deal" or "offer" read as gold, but only these words make a typed line a paid truce.
static func mentions_money(text: String) -> bool:
	if _money == null:
		_money = RegEx.create_from_string(Content.table("words").money)
	return _money.search(text.to_lower()) != null
