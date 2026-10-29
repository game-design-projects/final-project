## How monsters' minds reach the player: body language and short narrated reactions in the log, never meters.
## Shared by the game (which prints these) and Jev's fallback lines. Pure, no UI.
##
## Every sentence is built so it reads right for "it" and "they" (bandits are people): the monster's name is the
## subject of each verb, and clauses after a pronoun use only modal verbs or the past tense ("it won't", "they'd").
extends RefCounted

const J = preload("res://src/core/js.gd")

## Body language per species. Each tell is a predicate with the monster's name as subject ("Grak <tell>").
const VOICE = {
	"slime": {
		"sub": "it",
		"obj": "it",
		"pos": "its",
		"speak": "burbles",
		"warm": "jiggles softly, its blank stare gone gentle",
		"wary": "quivers a little",
		"cold": "goes stiff, its blank stare turning hard",
		"scared": "shrinks into a trembling puddle",
		"sad": "sags, its glow dimming",
		"laugh": "wobbles all over with silent giggles",
		"puzzled": "tilts its whole body sideways",
		"proud": "puffs up, glistening",
		"curious": "leans in, staring blankly",
		"yes": "wobbles closer",
		"no": "wobbles from side to side",
	},
	"goblin": {
		"sub": "it",
		"obj": "it",
		"pos": "its",
		"speak": "grunts",
		"warm": "grins, showing crooked teeth",
		"wary": "eyes you sideways",
		"cold": "bares its teeth and grips its club",
		"scared": "backs off a step, eyes darting",
		"sad": "lets its big ears droop",
		"laugh": "slaps its knee and guffaws",
		"puzzled": "scratches its head",
		"proud": "thumps its chest",
		"curious": "squints, ears perked",
		"yes": "shoulders its club",
		"no": "shakes its big head",
	},
	"dragon": {
		"sub": "it",
		"obj": "it",
		"pos": "its",
		"speak": "rumbles",
		"warm": "lowers its great head, eyes softening",
		"wary": "watches you down its long snout",
		"cold": "lets smoke curl from its nostrils",
		"scared": "draws its wings in close",
		"sad": "lets its crest sink",
		"laugh": "rumbles with deep laughter",
		"puzzled": "cocks its great head",
		"proud": "preens its gleaming scales",
		"curious": "narrows its eyes thoughtfully",
		"yes": "inclines its head",
		"no": "turns its head away",
	},
	"snake": {
		"sub": "it",
		"obj": "it",
		"pos": "its",
		"speak": "hisses",
		"warm": "loosens its coils, tongue flicking lazily",
		"wary": "sways, watching you without blinking",
		"cold": "flares its hood with a sharp hiss",
		"scared": "coils tight, tongue flickering fast",
		"sad": "lowers its head",
		"laugh": "lets out a dry, hissing chuckle",
		"puzzled": "tastes the air, baffled",
		"proud": "admires its own scales",
		"curious": "sways closer",
		"yes": "uncoils slowly",
		"no": "sways its head from side to side",
	},
	"rock": {
		"sub": "it",
		"obj": "it",
		"pos": "its",
		"speak": "grinds out",
		"warm": "rumbles, low and warm",
		"wary": "keeps its distance",
		"cold": "grinds its stones together",
		"scared": "pulls its limbs in, cracks flickering",
		"sad": "settles heavily, its cracks dimming",
		"laugh": "shakes loose a little gravel, chuckling",
		"puzzled": "goes still, thinking very slowly",
		"proud": "stands a little taller",
		"curious": "turns its glowing cracks toward you",
		"yes": "rises with a long rumble",
		"no": "does not move",
	},
	"bandit": {
		"sub": "they",
		"obj": "them",
		"pos": "their",
		"speak": "says",
		"warm": "cracks a crooked smile",
		"wary": "keeps a hand near their knife",
		"cold": "narrows their eyes, hand on a blade",
		"scared": "glances at the exits",
		"sad": "looks away",
		"laugh": "snorts a laugh",
		"puzzled": "frowns, lost",
		"proud": "smirks",
		"curious": "raises an eyebrow",
		"yes": "sheathes their knife",
		"no": "shakes their head",
	},
}


static func _voice(species) -> Dictionary:
	return VOICE.get(species, VOICE.slime)


static func _has_others(x) -> bool:
	var o = x.get("others")
	return o != null and not o.is_empty()


static func _has_kin(x) -> bool:
	var k = x.get("kin")
	return k != null and not k.is_empty()


static func _is_former_ally(x) -> bool:
	return J.truthy(x.get("formerAlly"))


## What Jev is offered as the reason behind its answer to "join us?". `when` (a Callable taking the context) limits a
## reason to situations where it can be true; code passes the context. The narration clause follows the subject
## pronoun ("it" / "they").
static var JOIN_NO = {
	"not_yet": {"what": "It doesn't know or trust the party well enough yet", "clause": "'d need to know you better first"},
	"wants_more": {
		"what": "It wants something more first: gold, proof, or a better offer",
		"clause": "'ll want more than words first",
	},
	"still_angry": {
		"what": "It is still angry or hurt about what the party did to it",
		"clause": "can't forgive what you did. Not yet",
	},
	"bad_pitch": {"what": "It didn't like the way the party asked", "clause": "didn't like how you asked"},
	"loyal": {
		"what": "It won't abandon the other monsters here with it",
		"clause": "won't leave {others}",
		"when": _has_others,
	},
	"pride": {"what": "It is too proud to follow anyone", "clause": "'ll follow no one"},
	"home": {"what": "It won't leave its home on this floor", "clause": "won't leave {pos} home on this floor"},
	"afraid": {"what": "It is afraid of the dangers deeper in the dungeon", "clause": "won't go any deeper. Too scared"},
	"burned": {
		"what": "It traveled with this party before, and they let it down",
		"clause": "won't be let down by you twice",
		"when": _is_former_ally,
	},
	"confused": {"clause": "can't make sense of what you're asking", "code": true},
}

static var JOIN_YES = {
	"likes_you": {"what": "It likes and trusts the party", "clause": "can't help liking you"},
	"strength": {"what": "It respects the party's strength", "clause": "'ll follow strength like yours"},
	"gold": {"what": "It expects a share of gold and loot", "clause": "'ll take a share of your gold and loot"},
	"company": {"what": "It is lonely and wants companions", "clause": "won't be alone down here anymore"},
	"kin": {"what": "Its own kind already travels with the party", "clause": "won't be parted from {kin}", "when": _has_kin},
	"safety": {"what": "It feels safer with the party than against it", "clause": "'d rather be on your side than in your way"},
	"curious": {"what": "It is curious about the adventure ahead", "clause": "can't resist seeing where you're going"},
	"grateful": {"what": "It is grateful for the party's kindness or mercy", "clause": "won't forget your kindness"},
}


## The reasons Jev may pick from in this situation, as Jev criteria ({id: description}).
static func reason_options(table: Dictionary, ctx := {}) -> Dictionary:
	var out := {}
	for id in table:
		var r: Dictionary = table[id]
		if r.get("code", false):
			continue
		var when = r.get("when")
		if when != null and not when.call(ctx):
			continue
		out[id] = r.what
	return out


static func _list(names: Array) -> String:
	if names.size() <= 1:
		return str(names[0]) if names.size() == 1 and names[0] != null else ""
	return "%s and %s" % [", ".join(names.slice(0, -1)), names[-1]]


static func _cap(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1)


static func _lc(s: String) -> String:
	return s.left(1).to_lower() + s.substr(1)


## String.prototype.replace with a string pattern: the first occurrence only.
static func _replace_first(s: String, what: String, with: String) -> String:
	var at := s.find(what)
	return s if at < 0 else s.substr(0, at) + with + s.substr(at + what.length())


## Monster names arrive in caps from the game ("GRAK"); narration reads better as "Grak". (/\b[a-z]/g)
static func nice(name) -> String:
	var s := ("" if name == null else str(name)).to_lower()
	var out := ""
	var prev_word := false
	for i in s.length():
		var c := s[i]
		var is_lower := c >= "a" and c <= "z"
		out += c.to_upper() if is_lower and not prev_word else c
		prev_word = is_lower or (c >= "0" and c <= "9") or c == "_"
	return out


## "it" + "'ll follow no one" → "it'll follow no one"; "it" + "won't..." → "it won't..."
static func _clause_with(sub: String, clause: String, ctx: Dictionary, v: Dictionary) -> String:
	var others := _list((J.nz(ctx.get("others"), []) as Array).map(nice))
	var kin := _list((J.nz(ctx.get("kin"), []) as Array).map(nice))
	var own: String = "%s own kind" % v.pos
	var filled := _replace_first(clause, "{others}", others if others != "" else own)
	filled = _replace_first(filled, "{kin}", kin if kin != "" else own)
	filled = _replace_first(filled, "{pos}", v.pos)
	return sub + filled if filled.begins_with("'") else sub + " " + filled


## Mood as body language reads it: what a player could see, derived from the meters and this round's feeling.
static func mood_of(meters = null, emotion = null) -> String:
	var tone = emotion.get("tone") if emotion != null else null
	if tone == "good":
		return "warm"
	if tone == "bad":
		return "cold"
	if tone == "fear":
		return "scared"
	if tone == "sad":
		return "sad"
	var m: Dictionary = meters if meters != null else {}
	var f = J.nz(m.get("friendliness"), 50)
	var a = J.nz(m.get("anger"), 0)
	if a >= 45 or f < 25:
		return "cold"
	if J.nz(m.get("fear"), 0) >= 60:
		return "scared"
	if f >= 60 and a < 30:
		return "warm"
	return "wary"


## The visible reaction to a feeling Jev picked (emotions.gd). One sentence.
const FEELING_TELL = {
	"delighted": ["warm", ""],
	"amused": ["laugh", ""],
	"touched": ["warm", ". Your words reached {obj}"],
	"flattered": ["proud", ""],
	"intrigued": ["curious", ""],
	"confused": ["puzzled", ""],
	"sad": ["sad", ""],
	"offended": ["cold", ""],
	"enraged": ["cold", ", shaking with rage"],
	"terrified": ["scared", ""],
}


static func feeling_line(species, name, emotion_id):
	var t = FEELING_TELL.get(emotion_id)
	if t == null:
		return null
	var v := _voice(species)
	return "%s %s%s." % [nice(name), v[t[0]], _replace_first(t[1], "{obj}", v.obj)]


## The answer to "join us?" as one narrated sentence that always agrees with what the monster does.
##   join: { accepted, moved, reason, others, kin }  (from the server)
##   opts: { meters, emotion, afterFeeling = false }: afterFeeling means a feeling line was already printed this
##   round, so lead with a gesture, not a second mood tell
static func join_line(species, name, join, opts := {}):
	if join == null or not J.truthy(join.get("asked")):
		return null
	var after_feeling: bool = opts.get("afterFeeling", false)
	var v := _voice(species)
	var N := nice(name)
	var accepted := J.truthy(join.get("accepted"))
	var table: Dictionary = JOIN_YES if accepted else JOIN_NO
	var r = table.get(join.get("reason"))
	if r == null:
		r = JOIN_YES.likes_you if accepted else JOIN_NO.not_yet
	var said: String = "%s that %s" % [v.speak, _clause_with(v.sub, r.clause, join, v)]
	var mood := mood_of(opts.get("meters"), opts.get("emotion"))
	if J.truthy(join.get("moved")):
		return "%s %s and asks to come with you. %s." % [N, v.yes, _cap(_clause_with(v.sub, r.clause, join, v))]
	if accepted:
		# Joining while it still looks wary: say so, then say why it comes anyway
		if mood != "warm":
			return "Even so, %s %s and %s." % [N, v.yes, said] if after_feeling else "%s still %s, but %s." % [N, v.wary, said]
		return "%s %s and %s." % [N, v.yes, said]
	# Refusing while it plainly likes you: show the warmth, then the reason it still says no
	if mood == "warm":
		return "Still, %s %s and %s." % [N, v.no, said] if after_feeling else "%s %s, but %s." % [N, v.warm, said]
	return "%s %s and %s." % [N, v.no, said]


## Which side a monster now takes, told as body language. Only for a change of side (from: the side it left).
static func side_line(species, name, side, from = null) -> String:
	var v := _voice(species)
	var N := nice(name)
	if side == "friendly with the party":
		return "%s %s; the fight has gone out of %s." % [N, v.warm, v.obj]
	if side == "hostile to the party":
		return "%s %s. You've made an enemy." % [N, v.cold]
	if from == "hostile to the party":
		return "%s %s, less sure %s'd like this fight." % [N, v.wary, v.sub]
	return "%s %s, no longer sure of you." % [N, v.wary]


## Why a monster turned down gold (from the server's tribute refusal reason).
static func tribute_line(species, name, reason) -> String:
	var v := _voice(species)
	var N := nice(name)
	if reason == "too_little":
		return "%s looks at the coins and %s that it's far too little." % [N, v.speak]
	if reason == "angry":
		return "%s %s: no amount of gold will fix this." % [N, v.cold]
	return "%s pushes the gold away. %s can't be bought." % [N, _cap(v.sub)]


static var _re_party_poss := RegEx.create_from_string("(?i)\\bthe party's\\b")
static var _re_joined_them := RegEx.create_from_string("\\bjoined them\\b")
static var _re_party := RegEx.create_from_string("(?i)\\bthe party\\b")
static var _re_final_dot := RegEx.create_from_string("\\.\\z")


## An event from the fight's history, retold to the player: "The party killed Drip." → "you killed Drip"
static func second_person(event) -> String:
	var s := _re_final_dot.sub(str(event).strip_edges(), "")
	s = _re_party_poss.sub(s, "your", true)
	s = _re_joined_them.sub(s, "joined you", true)
	s = _re_party.sub(s, "you", true)
	return _lc(s)


## An ally after a fight. opts: { level: approval 0..4, decision: stay / leave_party / turn_on_party, picked: what Jev
## wanted, moment: the event it reacted to most (from Jev) }. Returns a sentence, or null when there's nothing to tell.
static func ally_line(species, name, opts: Dictionary):
	var level = opts.get("level")
	var decision = opts.get("decision")
	var picked = opts.get("picked")
	var moment = opts.get("moment")
	var v := _voice(species)
	var N := nice(name)
	var why = second_person(moment) if J.truthy(moment) else null
	if decision == "leave_party":
		return "%s can't stomach how %s." % [N, why] if why != null else "%s has had enough of you." % N
	if decision == "turn_on_party":
		return "%s %s. %s won't forgive how %s." % [N, v.cold, _cap(v.sub), why] if why != null else "%s %s." % [N, v.cold]
	# It wanted out, but it isn't there yet: it stays, and the player should feel how close that was
	if J.truthy(picked) and picked != "stay":
		return "%s %s, but stays. For now." % [N, v.cold]
	if level <= 1:
		return "%s %s, still thinking about how %s." % [N, v.sad, why] if why != null else "%s %s." % [N, v.sad]
	if level >= 3:
		return "%s %s. %s liked how %s." % [N, v.warm, _cap(v.sub), why] if why != null else "%s %s." % [N, v.warm]
	return null


## Reaction lines come as [...approve, ...neutral, ...disapprove] and Jev rates them all at once, in parallel with
## the score. Take Jev's favorite among the lines that match the score (3-4 approve, 2 neutral, 0-1 disapprove), so a
## monster that "strongly disapproves" never says its happy line. Returns an index into that combined list.
## probabilities: {"line_0": p, ...} (null for none).
static func reaction_line_index(probabilities, reactions: Dictionary, level) -> int:
	var probs: Dictionary = probabilities if probabilities != null else {}
	var a: int = reactions.approve.size()
	var n: int = reactions.neutral.size()
	var d: int = reactions.disapprove.size()
	var start := 0
	var size := a
	if level < 3:
		start = a if level == 2 else a + n
		size = n if level == 2 else d
	var best := start
	for i in range(start, start + size):
		if J.nz(probs.get("line_%d" % i), 0) > J.nz(probs.get("line_%d" % best), 0):
			best = i
	return best


## How an ally took a talk (level 0..4) or a vow (level 0..4). A tell, or null for a shrug.
static func reaction_tell(species, name, level):
	var v := _voice(species)
	if level <= 0:
		return "%s %s." % [nice(name), v.cold]
	if level == 1:
		return "%s %s." % [nice(name), v.sad]
	if level >= 4:
		return "%s %s, and stands a little closer to you." % [nice(name), v.warm]
	if level == 3:
		return "%s %s." % [nice(name), v.warm]
	return null


## A vow broken: Jev wanted it to forgive, but the betrayal cut too deep. Explains a leave the player didn't expect.
static func cant_forgive_line(species, name) -> String:
	var v := _voice(species)
	return "%s %s. %s'd like to forgive you, but not after this." % [nice(name), v.sad, _cap(v.sub)]


const _DELTA_NAMES = {"friendliness": "FRIENDLY", "anger": "ANGER", "fear": "FEAR"}


## Everything the log says about one monster's reply in a group round, in order, before its action plays out.
## r: a /api/group-turn result. ctx: { name, species, sideBefore, debug = false }.
## Returns [{ text, cls, kind }]; the caller adds color, sounds and the action itself.
static func group_log(r: Dictionary, ctx := {}) -> Array:
	var name = ctx.get("name")
	var species = ctx.get("species")
	var side_before = ctx.get("sideBefore")
	var debug: bool = ctx.get("debug", false)
	var out := []
	var N := str(name).to_upper()
	var em = r.get("emotion")
	var felt = feeling_line(species, name, em.get("id")) if em != null else null
	if felt != null:
		out.append({"text": felt, "cls": "", "kind": "feeling"})
	if em != null:
		var parts := []
		var delta: Dictionary = J.nz(em.get("delta"), {})
		for k in delta:
			var x = delta[k]
			if J.truthy(x):
				parts.append("%s %s%s" % [_DELTA_NAMES.get(k, "undefined"), "+" if x > 0 else "", J.num(x)])
		var delta_text := ", ".join(parts)
		var tail := " (%s)" % delta_text if debug and delta_text != "" else ""
		out.append({"text": "%s IS %s: %s.%s" % [N, em.label, em.effect, tail], "cls": "big", "kind": "emotion"})
	var spoken = r.get("spoken")
	if J.truthy(r.get("line")) and not (spoken is bool and not spoken):
		out.append({"text": "%s: %s" % [N, r.line], "cls": "npc", "kind": "line"})
	var answer = join_line(species, name, r.get("join"), {"meters": r.get("meters"), "emotion": em, "afterFeeling": felt != null})
	if answer != null:
		out.append({"text": answer, "cls": "", "kind": "join"})
	var action = r.get("action")
	if action == "refuse_tribute" and J.truthy(r.get("tributeRefusal")):
		out.append({"text": tribute_line(species, name, r.tributeRefusal), "cls": "", "kind": "tribute"})
	# A change of side the player hasn't already seen in a feeling or an answer, and that its action won't contradict
	var hostile_move: bool = action in ["attack", "special"]
	var side = r.get("side")
	if J.truthy(side_before) and J.truthy(side) and side_before != side and felt == null and answer == null and action != "join_party":
		if not (side == "friendly with the party" and hostile_move):
			out.append({"text": side_line(species, name, side, side_before), "cls": "", "kind": "side"})
	if debug and J.truthy(r.get("blocked")):
		out.append({"text": "[DEBUG] JEV PICKED %s; CODE: %s" % [str(r.get("picked")).to_upper(), r.blocked], "cls": "dim", "kind": "debug"})
	return out
