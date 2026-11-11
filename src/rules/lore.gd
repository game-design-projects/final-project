## The writing on the walls: one piece on every floor of a run, on the closed end of a quiet corridor. Which piece you read depends
## on the floor and on how the halls feel about you when you step up to it (rules/warmth.gd): warm, wary or cold. So a kind run,
## a mixed one and a cruel one each read their own five, and it takes about three runs to read all fifteen. What has been read is
## kept across runs by the scene (menu/progress.gd), which hands it to the game. The words are in data/lore.json.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Warmth = preload("res://src/rules/warmth.gd")

const TONES := ["warm", "wary", "cold"]


static func table() -> Dictionary:
	return Content.table("lore")


## How many pieces there are in all.
static func total() -> int:
	var n := 0
	for depth in table().pieces:
		n += table().pieces[depth].size()
	return n


## The floors that have a piece, as ints.
static func depths() -> Array:
	return table().pieces.keys().map(func(k): return int(k))


## "warm", "wary" or "cold", from a warmth level (0 cold .. 4 beloved).
static func tone_of_level(level: int) -> String:
	var tones: Dictionary = table().tones
	for tone in tones:
		if tones[tone].any(func(v): return int(v) == level):
			return tone
	return "wary"


## How the halls feel about you now, as a tone.
static func tone(state) -> String:
	return tone_of_level(Warmth.level(Warmth.of(state)))


## The piece floor `depth` shows in this tone: {id, title, text}. A floor deeper than the deepest piece shows the deepest one.
static func piece(depth: int, of_tone: String) -> Dictionary:
	var pieces: Dictionary = table().pieces
	var key := str(clampi(depth, 1, depths().max()))
	var entry: Dictionary = pieces[key][of_tone]
	return {"id": id(int(key), of_tone), "title": str(entry.title), "text": str(entry.text)}


static func id(depth: int, of_tone: String) -> String:
	return "%d-%s" % [depth, of_tone]


## Whether `v` names a piece, for what a store held.
static func known(v: String) -> bool:
	var parts := v.split("-")
	return parts.size() == 2 and table().pieces.has(parts[0]) and table().pieces[parts[0]].has(parts[1])


## What the log says after reading: how many of all there are you have read now, over every run.
static func found_line(read: int) -> String:
	return str(table().found) % [read, total()]
