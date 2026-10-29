## Social moments outside the combat round: talking to an ally, making a vow, and breaking one.
## Jev judges feelings and picks from approved lines/responses; code owns the numbers and the odds.
## Load it with `const Bonds = preload("res://src/jev/bonds.gd")`. Failures return {"error": String}.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Q = preload("res://src/jev/q.gd")
const U = preload("res://src/jev/util.gd")
const Jev = preload("res://src/jev/jev.gd")
const Allies = preload("res://src/jev/allies.gd")
const Species = preload("res://src/rules/species.gd")
const Narrate = preload("res://src/rules/narrate.gd")

const BUFFS := {
	"slime": {"id": "BOUNCY", "desc": "absorbs the next hit on anyone in the party"},
	"goblin": {"id": "PUMPED", "desc": "deals double damage next fight"},
	"dragon": {"id": "STORMING", "desc": "opens the next fight with free lightning on every enemy"},
	"snake": {"id": "VENOMOUS", "desc": "opens the next fight with a poisoned bite"},
	"rock": {"id": "BULWARK", "desc": "soaks the next two hits on the party"},
	"bandit": {"id": "SNEAKY", "desc": "brings in 50% more gold from the next fight"},
}
# Every talk does something, good or bad. By how the words landed (0..4): loyalty change and what happens.
const TALK_DELTA := [-15, -6, 3, 8, 14]
const TALK_OUTCOME := [
	{"id": "SULKING", "desc": "sulks and sits out the next fight"},
	{"id": "DISTRACTED", "desc": "is distracted: -2 to hit next fight"},
	{"id": "STEADY", "desc": "feels steady: +1 to hit next fight"},
	null,  # its species buff
	{"id": "INSPIRED", "desc": "is inspired: heals fully and grows a level"},
]
const STEAL_CHANCE := 0.6
const BREAK_PENALTY := 20

const RESPONSES := {
	"forgive": "Forgive the party, grudgingly, and stay",
	"leave_party": "Leave the party for good",
	"attack_party": "Turn on the party and attack them",
	"steal_gold": "Steal the party's gold and run off with it",
}


static func _persona(m: Dictionary) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[m["species"]]
	var personality := [sp["nature"]]
	personality.append_array(J.nz(m.get("traits"), []))
	return {"name": m["name"], "kind": sp["label"], "personality": personality, "likes": sp["likes"].duplicate(), "dislikes": sp["dislikes"].duplicate(), "values": sp["values"]}


static func _reaction_lines(sp: Dictionary) -> Array:
	var r: Dictionary = sp["reactions"]
	return r["approve"] + r["neutral"] + r["disapprove"]


static func _pick_line(answer, lines: Array, name: String) -> String:
	var i := 0
	var choice = answer.get("choice") if answer is Dictionary else null
	if choice is String and (choice as String).contains("_"):
		var part: String = (choice as String).split("_")[1]
		if part.is_valid_int():
			i = int(part)
	return Species.fill(lines[i] if i >= 0 and i < lines.size() else lines[0], {"name": name})


# A reaction line that agrees with how the words or promise landed (level 0..4), not just Jev's overall favorite.
static func _reaction_line(answer, sp: Dictionary, level: int, name: String) -> String:
	var probs = answer.get("probabilities") if answer is Dictionary else null
	return Species.fill(_reaction_lines(sp)[Narrate.reaction_line_index(probs, sp["reactions"], level)], {"name": name})


static func _line_choice(question, lines: Array, name: String) -> Dictionary:
	var fitted := {}
	for i in lines.size():
		fitted["line_%d" % i] = Species.fill(lines[i], {"name": name})
	return Q.choice(question, fitted)


static func _level(score) -> int:
	return clampi(J.round_js(float(score)), 0, 4)


## The once-per-floor talk with an ally. Lands well → loyalty and a species buff for the next fight.
## { ally, message, vows, trace = null } → { resonance, level, loyaltyDelta, buff, outcome, line, ms }
static func ally_talk(req: Dictionary) -> Dictionary:
	var ally: Dictionary = req["ally"]
	var sp: Dictionary = Species.SPECIES[ally["species"]]
	var lines := _reaction_lines(sp)
	var persona := _persona(ally)
	persona["loyalty"] = Allies.loyalty_word(J.nz(ally.get("loyalty"), 0))
	var promises := []
	for v in J.nz(req.get("vows"), []):
		promises.append("\"%s\" (%s)" % [str(v.get("text")), str(v.get("status"))])
	var state := {"ally": persona, "promises_party_made_to_it": promises, "party_says": req.get("message")}
	var questions := {
		"resonance": Q.score(
			{"question": "How do the words in `party_says` land with `ally.name`?", "judge_by": ["`ally.values`", "`ally.personality`", "`ally.likes`", "`ally.dislikes`"]},
			["Hurt or offend it", "Leave it cold", "Fine, nothing special", "Please it", "Move it deeply"],
		),
		"line": _line_choice({"question": "What does `ally.name` say or do in reply to `party_says`?", "judge_by": "`ally.personality`"}, lines, ally["name"]),
	}
	var res := await Jev.jev(state, questions, req.get("trace"))
	if res.has("error"):
		return res
	var a = res.get("answers")
	if not (a is Dictionary) or not (a.get("resonance") is Dictionary) or a["resonance"].get("score") == null:
		return {"error": "Jev left resonance unanswered"}
	var level := _level(a["resonance"]["score"])
	var outcome = TALK_OUTCOME[level]
	return {
		"resonance": a["resonance"]["score"],
		"level": level,
		"loyaltyDelta": TALK_DELTA[level],
		"buff": (BUFFS[ally["species"]] as Dictionary).duplicate() if level >= 3 and BUFFS.has(ally["species"]) else null,
		"outcome": (outcome as Dictionary).duplicate() if outcome != null else null,
		"line": _reaction_line(a.get("line"), sp, level, ally["name"]),
		"ms": res.get("ms"),
	}


## A vow is made to a monster (an enemy mid-fight or an ally). How much does it like the promise?
## { monster, vow, trace = null } → { liking, level, line, ms }
static func vow_made(req: Dictionary) -> Dictionary:
	var monster: Dictionary = req["monster"]
	var vow: Dictionary = req["vow"]
	var sp: Dictionary = Species.SPECIES[monster["species"]]
	var lines := _reaction_lines(sp)
	var state := {"monster": _persona(monster), "promise": "The party swears to %s: \"%s\"" % [monster["name"], str(vow.get("text"))]}
	var questions := {
		"liking": Q.score(
			{"question": "How does `monster.name` feel about the promise in `promise`?", "judge_by": ["`monster.values`", "`monster.likes`", "`monster.dislikes`"]},
			["Hates it", "Dislikes it", "Doesn't care", "Likes it", "Loves it"],
		),
		"line": _line_choice({"question": "How does `monster.name` react to `promise`?", "judge_by": "`monster.personality`"}, lines, monster["name"]),
	}
	var res := await Jev.jev(state, questions, req.get("trace"))
	if res.has("error"):
		return res
	var a = res.get("answers")
	if not (a is Dictionary) or not (a.get("liking") is Dictionary) or a["liking"].get("score") == null:
		return {"error": "Jev left liking unanswered"}
	var level := _level(a["liking"]["score"])
	return {"liking": a["liking"]["score"], "level": level, "line": _reaction_line(a.get("line"), sp, level, monster["name"]), "ms": res.get("ms")}


## A vow made to this ally was just broken. Jev picks the response; code applies penalties and the steal odds.
## { monster, vow, how, gold, trace = null } → { response, picked, blocked, loyalty, stolen, caught, line, probabilities, ms }
static func vow_broken(req: Dictionary) -> Dictionary:
	var monster: Dictionary = req["monster"]
	var vow: Dictionary = req["vow"]
	var gold = J.nz(req.get("gold"), 0)
	var sp: Dictionary = Species.SPECIES[monster["species"]]
	var loyalty = U.norm(maxf(0.0, float(J.nz(monster.get("loyalty"), 0) - BREAK_PENALTY)))
	var options := []
	for r in RESPONSES:
		if r != "steal_gold" or gold > 0:
			options.append(r)
	var persona := _persona(monster)
	persona["loyalty_now"] = Allies.loyalty_word(loyalty)
	var state := {
		"monster": persona,
		"broken_promise": "The party swore to %s: \"%s\"" % [monster["name"], str(vow.get("text"))],
		"how_it_was_broken": req.get("how"),
	}
	var responses := {}
	for r in options:
		responses[r] = RESPONSES[r]
	var questions := {
		"response": Q.choice(
			{
				"question": "How does `monster.name` respond to the party breaking `broken_promise`?",
				"consider": ["`how_it_was_broken`", "`monster.values`", "`monster.loyalty_now`", "`monster.personality`"],
			},
			responses,
		),
	}
	for r in options:
		questions["line__" + r] = _line_choice(
			{"question": "`monster.name` is about to %s. What does it say?" % (RESPONSES[r] as String).to_lower(), "about": "`how_it_was_broken`"},
			sp["broken"][r],
			monster["name"],
		)
	var res := await Jev.jev(state, questions, req.get("trace"))
	if res.has("error"):
		return res
	var a = res.get("answers")
	if not (a is Dictionary) or not (a.get("response") is Dictionary) or not (a["response"].get("choice") is String):
		return {"error": "Jev left response unanswered"}
	var picked: String = a["response"]["choice"]
	var response := picked
	var blocked = null
	# A loyal-enough ally can forgive; a resentful one can't just shrug it off.
	if response == "forgive" and loyalty < 35:
		response = "leave_party"
		blocked = "forgiving needs loyalty ≥ 35 after the betrayal (is %s)" % J.num(loyalty)
	var stolen := 0
	var caught := false
	if response == "steal_gold":
		if randf() < STEAL_CHANCE:
			stolen = maxi(1, J.round_js(gold * (0.25 + randf() * 0.25)))
		else:
			caught = true
	var final_loyalty = loyalty
	if response != "forgive" and caught:
		final_loyalty = U.norm(maxf(0.0, float(loyalty - 10)))
	var broken_lines: Array = sp["broken"].get(response, sp["broken"]["leave_party"])
	return {
		"response": response,
		"picked": picked,
		"blocked": blocked,
		"loyalty": final_loyalty,
		"stolen": stolen,
		"caught": caught,
		"line": _pick_line(a.get("line__" + response), broken_lines, monster["name"]),
		"probabilities": a["response"].get("probabilities"),
		"ms": res.get("ms"),
	}
