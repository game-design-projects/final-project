## What a monster lets slip when the player asks it something: which way the stairs lie, how the champion opens, what
## another monster dislikes. Everything it says comes from this run's floor and its living monsters, never made up.
## A monster only answers when the odds (odds.reveal_odds) say it will; this is what it says when it does.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

const COMPASS := ["north", "east", "south", "west"]

const STAIRS_WORDS := ["stair", "stairs", "exit", "way out"]
const CHAMPION_WORDS := ["champion", "boss", "dragon", "vexalith"]
const WHERE_WORDS := ["where", "way", "direction", "path", "route", "find", "reach"]
const OPENING_WORDS := ["opening", "openings", "genre", "genres", "attack", "attacks", "fight", "fights", "pattern", "patterns"]
const WANT_WORDS := ["want", "wants", "like", "likes", "dislike", "dislikes", "hate", "hates", "fear", "fears", "weakness", "trait", "traits", "behave", "behavior", "about", "avoid", "avoids"]

static var _non_word := RegEx.create_from_string("[^a-z0-9]+")


## `asker` is the monster being asked; `at` is where the player stands.
static func answer(floor_map, at: Vector2i, asker, question: String) -> String:
	var q := " " + _non_word.sub(question.to_lower(), " ", true).strip_edges() + " "
	var bare := q == "  "
	var asks_stairs := bare or _has_any(q, STAIRS_WORDS)
	var asks_champion := _has_any(q, CHAMPION_WORDS)
	if asks_stairs and asks_champion:
		return "...ask about the stairs or the champion, one at a time."
	var by_name := []
	var by_species := []
	for o in floor_map.monsters:
		if q.contains(" " + _non_word.sub(o.name.to_lower(), " ", true) + " "):
			by_name.append(o)
		if q.contains(" " + o.species + " "):
			by_species.append(o)
	if by_name.size() > 1:
		return "...which monster do you mean?"
	var asks_other := q.contains(" another monster ") or q.contains(" other monster ")
	if asks_stairs and (not by_name.is_empty() or not by_species.is_empty() or asks_other):
		return "...ask about one thing at a time."
	if asks_stairs:
		return _stairs_answer(floor_map, at, q)
	var champion = floor_map.monsters.back()
	if asks_champion:
		return _champion_answer(champion, q, by_name, by_species, asks_other)
	return _monster_answer(floor_map, asker, q, by_name, by_species, asks_other)


static func _stairs_answer(floor_map, at: Vector2i, q: String) -> String:
	var plain := q.strip_edges()
	if plain != "" and not _has_any(q, WHERE_WORDS) and not plain in STAIRS_WORDS:
		return "...ask which way the stairs lie."
	if at == floor_map.stairs:
		return "...you are standing on the stairs."
	return "...from here, take the corridor %s toward the stairs." % first_step_toward(floor_map, at, floor_map.stairs)


static func _champion_answer(champion, q: String, by_name: Array, by_species: Array, asks_other: bool) -> String:
	var names_someone_else: bool = not by_name.is_empty() and by_name[0] != champion
	if names_someone_else or by_species.any(func(o): return o != champion) or asks_other:
		return "...ask about one monster at a time."
	if not _has_any(q, OPENING_WORDS) and not q.strip_edges() in CHAMPION_WORDS:
		return "...ask about the champion's opening genres."
	if champion.is_gone():
		return "...the champion has already fallen."
	var enc := Content.table("encounter")
	var genres: Array = enc.boss.genres
	return "...%s starts with %s, then shifts to %s." % [champion.name, str(enc.genres[genres[0]].name).to_lower(), str(enc.genres[genres[1]].name).to_lower()]


static func _monster_answer(floor_map, asker, q: String, by_name: Array, by_species: Array, asks_other: bool) -> String:
	var target = null
	if not by_name.is_empty():
		target = by_name[0]
	elif by_species.size() > 1:
		return "...which %s do you mean?" % by_species[0].species
	elif not by_species.is_empty():
		target = by_species[0]
	if target == null and asks_other:
		for o in floor_map.monsters:
			if not o.is_gone() and o != asker:
				target = o
				break
	if target == null:
		return "...I know no one else left on this floor." if asks_other else "...ask me about the stairs, the champion, or another monster."
	if target.is_gone():
		return "...that monster is gone from this floor."
	if target == asker:
		return "...you can see how I behave for yourself."
	var plain := q.strip_edges()
	if not _has_any(q, WANT_WORDS) and not asks_other and plain != target.name.to_lower() and plain != target.species:
		return "...ask what %s wants or avoids." % target.name
	var acts: Array = Content.table("encounter").acts[target.species]
	var worst: String = acts[0].intent
	for a in acts:
		if target.affinity(a.intent) < target.affinity(worst):
			worst = a.intent
	var clues: Array = target.clues()
	var clue := " It %s." % clues[0] if not clues.is_empty() else ""
	return "...%s seems uneasy around %s.%s" % [target.name, Content.table("words").intent_words[worst], clue]


## The compass direction of the first step on the shortest way from `from` to `to`, or "now" if already there.
static func first_step_toward(floor_map, from: Vector2i, to: Vector2i) -> String:
	if from == to:
		return "now; you are on them"
	var queue: Array = [from]
	var first := {from: -1}
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for i in 4:
			var next: Vector2i = at + FloorMap.DIRS[i]
			if not floor_map.is_open(next) or first.has(next):
				continue
			first[next] = i if at == from else first[at]
			if next == to:
				return COMPASS[first[next]]
			queue.append(next)
	return "unknown"


static func _has_any(q: String, terms: Array) -> bool:
	for term in terms:
		if q.contains(" " + term + " "):
			return true
	return false
