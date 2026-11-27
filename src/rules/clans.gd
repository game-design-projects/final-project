## Who feels what about whom, and what the run has done to them. Every kind of monster belongs to a clan (data/clans.json); what
## you do to one changes how its clan thinks of you, and how the clans with a feeling about it do: one that likes it takes your
## deed as its own clan does, by half; one that dislikes it is glad of a killing and sore when you take one in. The dragon's hoard
## hears a little of everything. A monster hears of it when it meets you: it starts in a different mood, and says so. No rolls
## here: the same deeds always mean the same.
##
## The feelings (the owner's lore): the Old Stone dislikes the Burrow, which is too soft; the Burrow adores the Hoard, which once
## saved it from a fire and never noticed, and is friends with the Coil, who share the Wet Caves; the Crew hunts the Coil for
## sport, and the Coil wants that paid back; the Crew dislikes the Old Stone, whose rocks keep falling on it; the Hoard hates the
## Crew, who are thieves.
##
## Killing climbs a clan's hostility (`hostility`): angry, then furious (two of its own dead, nothing made up for it: the floors
## made after that send its elites), then enraged (four: none of its own will take mercy). Its standing is the one number behind
## all of it, so sparing its own or its friends, or doing one of its kind a favour, brings it back down. The other way, a clan
## that likes you does things for you (`favour`, #290): friendly, its own don't hunt you; trusted, one shows you the floor;
## devoted, they take mercy readily, until you strike one and its faith breaks.
extends RefCounted

const Content = preload("res://src/rules/content.gd")

const STANDING_MAX := 100.0
const MOOD_MAX := 25.0 # how far a clan's opinion can move a monster's starting mood
const DEEDS_MAX := 40
const HEARD_SHOWN := 5 # how many deeds a monster repeats to the mind
const NEWS_AT := 1.0 # how far its clan's opinion must have moved for a monster to mention it


static func _table() -> Dictionary:
	return Content.table("clans")


## The clan of a kind of monster, or "".
static func of(species: String) -> String:
	var clans: Dictionary = _table().clans
	for id in clans:
		if clans[id].species.has(species):
			return id
	return ""


static func title(clan: String) -> String:
	return str(_table().clans[clan].name)


static func is_clan(clan: String) -> bool:
	return _table().clans.has(clan)


## How `clan` feels about `about`: "likes", "dislikes", "ignores", or "" when it has no feeling of its own.
static func feeling(clan: String, about: String) -> String:
	return str(_table().clans[clan].get("feels", {}).get(about, {}).get("how", ""))


## Why `clan` feels as it does about `about`, in a few words that end a sentence ("slimes are too soft"), or "".
static func why(clan: String, about: String) -> String:
	return str(_table().clans[clan].get("feels", {}).get(about, {}).get("why", ""))


## The clans `clan` feels this way about ("likes", "dislikes").
static func felt_by(clan: String, how: String) -> Array:
	return _table().clans.keys().filter(func(c): return feeling(clan, c) == how)


## The clans that feel this way about `about` ("likes", "dislikes"): the other side of `felt_by`.
static func who_feels(how: String, about: String) -> Array:
	return _table().clans.keys().filter(func(c): return feeling(c, about) == how)


## How much of a deed done to `from` reaches `to`, and which way: all of it within a clan; by its feeling where it has one (a
## friend's share, or a rival's, which is negative: glad of what hurts the other); else what the clan hears of everything.
static func reach(from: String, to: String, deed: String) -> float:
	if from == to:
		return 1.0
	var how := feeling(to, from)
	if how != "":
		return float(_table().feelings[how][deed])
	return float(_table().clans[to].get("hears_all", 0.0))


## What the other clans make of a deed ("spared", "recruited", "slain") done to one of `species`, for the log: [{clan, glad,
## text}], only the clans with a feeling about its clan that this deed moves, the sore ones first.
static func felt(species: String, deed: String) -> Array:
	var from := of(species)
	var out := []
	if from == "":
		return out
	var words: Dictionary = _table().felt
	for clan in _table().clans:
		if clan == from or feeling(clan, from) == "":
			continue
		var part: float = float(_table().deeds[deed]) * reach(from, clan, deed)
		if part == 0.0:
			continue
		var glad := part > 0.0
		out.append({"clan": clan, "glad": glad, "text": str(words.glad if glad else words.sore) % [title(clan), str(words.deeds[deed]), "a %s" % species, why(clan, from)]})
	out.sort_custom(func(a, b): return not a.glad and b.glad)
	return out


## Write a deed into the run: "spared", "slain" or "recruited" against monster `m`. Returns how it moved the clans' hostility,
## [{clan, from, to}] (hostility ids, "" for none), the monster's own clan first.
static func record(state, m, deed: String) -> Array:
	var from := of(m.species)
	if from == "":
		push_error("clans: %s has no clan" % m.species)
		return []
	var moved := _spread(state, from, float(_table().deeds[deed]) * (float(_table().champion_weight) if m.boss else 1.0), deed)
	state.deeds.append({"clan": from, "species": m.species, "who": m.name, "deed": deed})
	if state.deeds.size() > DEEDS_MAX:
		state.deeds = state.deeds.slice(-DEEDS_MAX)
	print("clans: %s %s (%s), standing now %s" % [deed, m.name, from, state.reputation])
	moved.sort_custom(func(a, b): return a.clan == from and b.clan != from)
	return moved


## A kindness to this kind of monster that isn't a deed in a fight: it moves opinions, and nobody tells the tale. Returns how it
## moved the clans' hostility, as `record` does. The other clans take a kindness as a sparing and a wrong (`worth` under 0) as a
## killing.
static func favour(state, species: String, worth: float) -> Array:
	var from := of(species)
	if from == "":
		return []
	return _spread(state, from, worth, "spared" if worth >= 0.0 else "slain")


## A friend of yours butchered (rules/survival.gd), or the word of it getting out. To its clan that is a death, and a worse one
## than any in a fight: the clan takes `worth` in full, and the clans that like it their share of that. A clan that dislikes it
## is glad of the death as it would be of any other, one kill's worth and no more: nobody is pleased by the treachery, and the
## word getting out (no `who`) is of the same death, so it pleases nobody again. With a name (`who`) the deed is kept as a
## killing, so its kin speak of it, by name, when they meet you. Returns the changes of
## hostility, the clan's own first, as `record` does.
static func betrayed(state, species: String, worth: float, who := "") -> Array:
	var from := of(species)
	if from == "":
		return []
	var moved := _spread(state, from, worth, "slain", 1.0 if who != "" else 0.0) # the telling is of the same death
	if who != "":
		state.deeds.append({"clan": from, "species": species, "who": who, "deed": "slain"})
		if state.deeds.size() > DEEDS_MAX:
			state.deeds = state.deeds.slice(-DEEDS_MAX)
	print("clans: betrayed %s (%s), %.0f, standing now %s" % [who if who != "" else "a friend", from, worth, state.reputation])
	moved.sort_custom(func(a, b): return a.clan == from and b.clan != from)
	return moved


## `glad_deaths`, when it is not negative, is how many such deeds a clan that is glad of this one may be glad of: 1 for a
## butchering (glad of the death, as of any other, and of nothing more), 0 for the word of it getting out (the death it was
## glad of is the same one).
static func _spread(state, from: String, worth: float, deed: String, glad_deaths := -1.0) -> Array:
	var moved := []
	for clan in _table().clans:
		var part: float = worth * reach(from, clan, deed)
		if glad_deaths >= 0.0 and worth < 0.0 and part > 0.0:
			part = minf(part, glad_deaths * float(_table().deeds[deed]) * reach(from, clan, deed))
		if part != 0.0:
			var was := hostility(float(state.reputation.get(clan, 0.0)))
			var liked_was := favour_level(float(state.reputation.get(clan, 0.0)))
			var lowest := -STANDING_MAX
			var sworn = state.get("lords_sworn")
			if sworn is Array and (sworn as Array).has(clan): # sworn: its own never turn on you past angry
				lowest = float(_table().hostility[0].at) # the first level is the mildest, as `hostility` reads them
			state.reputation[clan] = clampf(float(state.reputation.get(clan, 0.0)) + part, lowest, STANDING_MAX)
			var now := hostility(float(state.reputation[clan]))
			if now != was:
				moved.append({"clan": clan, "from": was, "to": now})
				print("clans: %s %s -> %s (standing %.0f)" % [clan, was if was != "" else "calm", now if now != "" else "calm", state.reputation[clan]])
			var liked_now := favour_level(float(state.reputation[clan]))
			if liked_now != liked_was:
				moved.append({"clan": clan, "from": liked_was, "to": liked_now, "favour": true})
				print("clans: %s favour %s -> %s (standing %.0f)" % [clan, liked_was if liked_was != "" else "calm", liked_now if liked_now != "" else "calm", state.reputation[clan]])
	return moved


# ---------------------------------------------------------------- hostility

## How hostile a clan with this standing is: "" (not at all), "angry", "furious" or "enraged".
static func hostility(standing: float) -> String:
	var out := ""
	for level in _table().hostility:
		if standing <= float(level.at):
			out = str(level.id)
	return out


## How far up the levels a hostility is: 0 for none, then 1, 2, 3.
static func rank(id: String) -> int:
	if id == "":
		return 0
	var levels: Array = _table().hostility
	for i in levels.size():
		if levels[i].id == id:
			return i + 1
	return 0


static func _level(id: String) -> Dictionary:
	for level in _table().hostility:
		if level.id == id:
			return level
	return {}


## How the clan of this kind of monster stands with you now.
static func standing_of(state, species: String) -> float:
	return float(state.reputation.get(of(species), 0.0))


## How hostile the clan of this kind of monster is now.
static func hostility_of(state, species: String) -> String:
	return hostility(standing_of(state, species))


## Whether its clan has gone so far that `m` won't take mercy, nor join: enraged. Nothing in a fight changes this; only the next
## deed or favour does.
static func enraged(state, m) -> bool:
	return rank(hostility_of(state, m.species)) >= rank(str(_table().no_mercy.from))


## Whether a floor made now sends this kind's elites: its clan is furious or worse.
static func sends_elites(state, species: String) -> bool:
	return of(species) != "" and rank(hostility_of(state, species)) >= rank(str(_table().elite.from))


## What being elite does: {hp_scale, intensity, damage, pace, tag, rule, arrival}.
static func elite() -> Dictionary:
	return _table().elite


## The words of the no-mercy rule: {spare, rule, cut}.
static func no_mercy() -> Dictionary:
	return _table().no_mercy


## A clan's mood in a word, for the map's legend and the cards: its favour's title (FRIENDLY, TRUSTED, DEVOTED), CALM, or its
## hostility's title.
static func mood_word(standing: float) -> String:
	var level := _level(hostility(standing))
	if not level.is_empty():
		return str(level.title)
	var liked := _favour_level(favour_level(standing))
	return str(liked.title) if not liked.is_empty() else "CALM"


# ---------------------------------------------------------------- favour (#290)

## How much a clan with this standing likes you: "" (not especially), "friendly", "trusted" or "devoted".
static func favour_level(standing: float) -> String:
	var out := ""
	for level in _table().favour:
		if standing >= float(level.at):
			out = str(level.id)
	return out


## How far up the favour levels: 0 for none, then 1, 2, 3.
static func favour_rank(id: String) -> int:
	var levels: Array = _table().favour
	for i in levels.size():
		if levels[i].id == id:
			return i + 1
	return 0


static func _favour_level(id: String) -> Dictionary:
	for level in _table().favour:
		if level.id == id:
			return level
	return {}


## How much the clan of this kind of monster likes you now.
static func favour_of(state, species: String) -> String:
	return favour_level(standing_of(state, species)) if of(species) != "" else ""


## Whether its clan is friendly or better: its own don't hunt you.
static func befriended(state, species: String) -> bool:
	return favour_rank(favour_of(state, species)) >= favour_rank("friendly")


## Whether its clan trusts you or better: one of its own shows you the floor.
static func trusts(state, species: String) -> bool:
	return favour_rank(favour_of(state, species)) >= favour_rank("trusted")


## Whether its clan is devoted to you: its own take mercy readily, until you strike one.
static func devoted(state, m) -> bool:
	return not m.boss and favour_rank(favour_of(state, m.species)) >= favour_rank("devoted")


## The least mercy one of a devoted clan takes, or 0.
static func mercy_floor(state, m) -> float:
	return float(_favour_level("devoted").mercy) if devoted(state, m) else 0.0


## You struck one of a devoted clan: its faith breaks, and its standing falls back to calm. Returns the move, as `record` does.
static func break_faith(state, species: String) -> Array:
	var clan := of(species)
	var was := favour_level(standing_of(state, species))
	state.reputation[clan] = minf(float(state.reputation.get(clan, 0.0)), float(_table().faith.broken))
	print("clans: %s's faith breaks (standing %.0f)" % [clan, state.reputation[clan]])
	return [{"clan": clan, "from": was, "to": favour_level(float(state.reputation[clan])), "favour": true, "broken": true}]


## The words for a clan showing you the floor: {title, line}.
static func shown(clan: String) -> Dictionary:
	var w: Dictionary = _table().shown
	return {"title": str(w.title) % title(clan).to_upper(), "line": str(w.line)}


## What a move of hostility says: {title, text} for the picture's banner, and `line` for the log when the picture is taken. The level
## it reached and what that means, or that it cooled.
static func moved_words(change: Dictionary) -> Dictionary:
	var name := title(change.clan)
	if change.get("favour", false): # a move of favour, not of hostility (#290)
		if change.get("broken", false):
			var faith: Dictionary = _table().faith
			return {"title": str(faith.title) % name.to_upper(), "text": str(faith.text), "line": str(faith.line) % name}
		if favour_rank(change.to) > favour_rank(change.from):
			var liked := _favour_level(change.to)
			return {"title": "%s IS %s" % [name.to_upper(), liked.title], "text": str(liked.effect), "line": str(liked.line) % name}
		var warmer: Dictionary = _table().warmer
		var now := str(_favour_level(change.to).get("title", "calm")).to_lower()
		var was := str(_favour_level(change.from).get("title", "calm")).to_lower()
		return {"title": str(warmer.title) % name.to_upper(), "text": "Now %s, no longer %s." % [now, was], "line": str(warmer.line) % [name, now, was]}
	if rank(change.to) > rank(change.from):
		var level := _level(change.to)
		return {"title": "%s IS %s" % [name.to_upper(), level.title], "text": str(level.effect), "line": str(level.line) % name}
	var calmer: Dictionary = _table().calmer
	var now: String = str(_level(change.to).get("title", "calm")).to_lower()
	var was: String = str(_level(change.from).get("title", "calm")).to_lower()
	return {"title": str(calmer.title) % name.to_upper(), "text": str(calmer.effect) % [now, was], "line": str(calmer.line) % [name, now]}


## How much a clan's opinion moves a monster's starting mood.
static func mood(standing: float) -> Dictionary:
	var shift: Dictionary = _table().mood
	return {
		"friendliness": clampf(standing * float(shift.friendliness), -MOOD_MAX, MOOD_MAX),
		"anger": clampf(standing * float(shift.anger), -MOOD_MAX, MOOD_MAX),
	}


## `m` meets you and hears what its clan has heard since it last did: its mood moves by the difference, and it remembers. Returns
## {clan, kind, deed, who, tone} for what it has to say (`kind` names its lines), or {} when there's no news for it. A clan that
## only heard of a kill on the other side hears it as `rival_slain`, and in good tone: the kill pleases it (#165). Its own last
## deed is always what it talks about; of the rest, it names the newest one with the sign its opinion moved in, so a kill of its own
## side is not the news when it is gladder of you.
static func hear(m, state) -> Dictionary:
	var clan := of(m.species)
	var standing: float = float(state.reputation.get(clan, 0.0))
	var before: float = float(m.heard.get("standing", 0.0))
	if clan == "" or absf(standing - before) < NEWS_AT:
		return {}
	var deed: Dictionary = _latest(state.deeds, clan, standing > before)
	if deed.is_empty():
		return {}
	var now := mood(standing)
	var was := mood(before)
	for k in now:
		m.meters[k] = clampf(float(m.meters.get(k, 0.0)) + now[k] - was[k], 0.0, 100.0)
	m.heard = {"clan": clan, "standing": standing, "deed": deed.deed, "who": deed.who, "heard": _retell(state.deeds, clan)}
	var news := {
		"clan": clan, "deed": deed.deed, "who": deed.who, "tone": "good" if standing > before else "bad",
		"kind": _news_kind(clan, deed),
	}
	print("clans: %s heard %s %s; friendliness %.0f, anger %.0f" % [m.name, deed.deed, deed.who, m.meters.friendliness, m.meters.anger])
	return news


## Which of its lines a monster of `clan` says about a deed (data/species.json `lines`): about its own kin, about a clan it
## dislikes ("rival_slain", glad; "rival_kept", sore that you took one in), or about anyone else it hears of.
static func _news_kind(clan: String, deed: Dictionary) -> String:
	var bad: bool = deed.deed == "slain"
	if deed.clan == clan:
		return "kin_slain" if bad else "kin_spared"
	if feeling(clan, deed.clan) == "dislikes":
		return "rival_slain" if bad else "rival_kept"
	return "friend_slain" if bad else "friend_spared"


## The deed a clan talks about: its own last one if it has one, or else the newest it heard of with the sign its opinion moved in
## — a clan that is glad of a kill of a clan it dislikes hears it with a plus, so a deed of its own is not the news when it is
## gladder of you — and, when nothing it heard has that sign, the newest it heard of, so a favour, which tells no tale, still
## leaves it one to tell (#165).
static func _latest(deeds: Array, clan: String, rose: bool) -> Dictionary:
	var heard := {}
	var newest := {}
	for i in range(deeds.size() - 1, -1, -1):
		var deed: Dictionary = deeds[i]
		if deed.clan == clan:
			return deed
		var part := reach(deed.clan, clan, str(deed.deed))
		if part == 0.0:
			continue
		if newest.is_empty():
			newest = deed
		if heard.is_empty() and (part < 0.0) == rose:
			heard = deed
	return heard if not heard.is_empty() else newest


## What a clan knows, in words a mind can read.
static func _retell(deeds: Array, clan: String) -> Array:
	var out := []
	for deed in deeds:
		if reach(deed.clan, clan, deed.deed) != 0.0:
			var whose := "one of its own" if deed.clan == clan else "of %s" % title(deed.clan)
			var how := feeling(clan, deed.clan)
			if how == "likes" or how == "dislikes":
				whose += ", which its clan %s because %s" % [how, why(clan, deed.clan)]
			var did := "killed" if deed.deed == "slain" else str(deed.deed)
			out.append("the player %s %s the %s, %s" % [did, deed.who, deed.species, whose])
	return out.slice(-HEARD_SHOWN)


## One line for the banner and the card: what was heard, and how the monster took it.
static func news(heard: Dictionary) -> String:
	var did: String = str(_table().felt.deeds.get(heard.deed, "spared"))
	return "%s heard you %s %s. It starts %s." % [title(heard.clan), did, heard.who, "friendlier" if heard.tone == "good" else "angrier"]
