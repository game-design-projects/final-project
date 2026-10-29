## A round for a group of 1–3 monsters. Code decides what each one MAY do; Jev reads the situation and picks.
##
## One request per round. For every monster (questions are prefixed with its id) it asks, in parallel:
##   - perception of the party's message from that monster's point of view
##   - its action, over the actions code marks feasible (including turning on another monster)
##   - which party member it would attack, and which other monster it would attack
##   - one speculative line per feasible action, from that species' approved lines
## Code folds perception and damage into each monster's friendliness / anger / fear, gates risky picks
## (a monster can only turn on another when they're on opposite sides or one hit the other), and returns.
##
## When the party talks, gives gold, or asks a monster to join, Jev also picks how that monster FEELS
## (emotions.gd). Every feeling moves its mood and has a mechanical effect, so words always matter.
##
## Whenever joining is possible, Jev also says whether it wants to, and (speculatively, both ways) its main reason
## to say yes and to say no. Code settles the answer from the mood AFTER this round's pitch, words and feeling
## (resolve_join), then keeps the reason that matches it, so the narration in the log never contradicts the outcome.
##
## Load it with `const Enemy = preload("res://src/jev/enemy.gd")`. Failures return {"error": String}.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Q = preload("res://src/jev/q.gd")
const U = preload("res://src/jev/util.gd")
const Jev = preload("res://src/jev/jev.gd")
const Species = preload("res://src/rules/species.gd")
const Emotions = preload("res://src/rules/emotions.gd")
const Narrate = preload("res://src/rules/narrate.gd")

# Structured, contrastive options: what each action is, and when it fits. Plain one-liners made Jev
# over-pick "defend" in groups.
const DESCRIBE := {
	"attack": {"what": "Attack one member of the party", "when": "It is hostile or angry at the party, or the party just attacked it"},
	# "special" is built per species, see describe()
	"attack_monster": {
		"what": "Turn on another monster in this fight and attack it",
		"when": "That monster is on the other side (friendly with the party while it is hostile, or the reverse), or that monster hurt it",
	},
	"defend": {"what": "Brace and guard itself instead of acting", "when": "It is badly hurt or expects a heavy blow and wants to wait it out"},
	"flee": {"what": "Run away from the fight", "when": "It is scared or badly hurt, or the other monsters have turned against it"},
	"converse": {"what": "Talk instead of fighting this round", "when": "It is curious or undecided and wants to answer or chat rather than act"},
	"demand_tribute": {"what": "Demand gold from the party in exchange for not fighting", "when": "It is greedy and sees a chance to get paid"},
	"accept_tribute": {"what": "Accept the gold the party is offering", "when": "The offer satisfies it"},
	"refuse_tribute": {"what": "Refuse the gold the party is offering", "when": "The offer is too small or it doesn't want their gold"},
	"join_party": {"what": "Agree to join the party and travel with them", "when": "It likes the party enough and they invited it"},
	"leave_peacefully": {
		"what": "End its part in the encounter peacefully and let the party go on its way",
		"when": "It has no quarrel with the party and would rather go",
	},
}

const LABELS := {
	"threat": "Threatens it",
	"insult": "Insults it",
	"kindness": "Kindness (0–3)",
	"joke": "Tells a joke",
	"offers_gold": "Offers gold",
	"asks_to_join": "Asks it to join",
	"asks_for_peace": "Asks for peace",
}

# Which side a monster is on, from its meters. Code owns this; Jev sees the words.
const FRIENDLY := 55
const HOSTILE := 40
const JOIN_ANGER := 30  # at or above this, a monster won't join anyone
const WILLING := 0.5  # Jev's "wants to say yes" needed to accept an invitation
const GLAD := {"touched": true, "delighted": true}  # feelings strong enough to make it ask to come along unasked
const ANGRY_REASONS := {"still_angry": true, "bad_pitch": true, "burned": true, "pride": true}  # fit a refusal made in anger

# Jev's probabilities are calibrated, so monsters roll on them: any action at ≥15% can happen, in proportion
# to its odds. This is what lets a 20% "turn on the traitor" actually occur sometimes.
const ROLL_FLOOR := 0.15

static var _re_provoked := RegEx.create_from_string("(?i)attack|hit|cast")


static func describe(a: String, sp: Dictionary) -> Dictionary:
	if a == "special":
		return {"what": "Use its special attack: %s" % sp["special"]["desc"], "when": "It is hostile and wants to hit hard"}
	return (DESCRIBE[a] as Dictionary).duplicate()


static func describe_short(a: String, sp: Dictionary) -> String:
	return describe(a, sp)["what"]


static func _clamp(v) -> int:
	return J.round_js(maxf(0.0, minf(100.0, float(v))))


static func _bucket(v, words: Array) -> String:
	return words[mini(words.size() - 1, floori(float(v) / (100.0 / words.size())))]


static func _health_word(hp, max_hp) -> String:
	var r: float = float(hp) / max_hp
	return "healthy" if r > 0.7 else ("wounded" if r > 0.35 else "badly wounded")


## x.toFixed(2). printf rounds an exact tie (0.125) to even where JS rounds it up.
static func _to_fixed2(x: float) -> String:
	var e := x * 8.0
	if x >= 0.0 and e == floor(e) and int(e) % 2 == 1:
		var n := int(floor(e * 12.5)) + 1
		return "%d.%02d" % [n / 100, n % 100]
	return "%.2f" % x


static func _stance(m: Dictionary) -> String:
	var meters: Dictionary = m["meters"]
	if meters["friendliness"] >= FRIENDLY and meters["anger"] < 40:
		return "friendly with the party"
	if meters["friendliness"] < HOSTILE:
		return "hostile to the party"
	return "undecided about the party"


static func _join_threshold(m: Dictionary) -> int:
	return Species.SPECIES[m["species"]]["joinThreshold"] + (15 if J.truthy(m.get("formerAlly")) else 0) + (20 if J.truthy(m.get("boss")) else 0)


static func _offer_words(gold, expected, name: String) -> String:
	var r: float = float(J.nz(gold, 0)) / expected
	if r < 0.5:
		return "far less than %s expects as tribute" % name
	if r < 0.9:
		return "a bit less than %s expects as tribute" % name
	if r < 1.3:
		return "about the tribute %s expects" % name
	return "more than the tribute %s expects: a generous offer" % name


static func _party_condition(living: Array) -> String:
	var hp := 0.0
	var max_hp := 0.0
	for p in living:
		hp += float(p["hp"])
		max_hp += float(p["maxHp"])
	if max_hp == 0.0:
		max_hp = 1.0
	var size := "a large group" if living.size() >= 4 else ("a small group" if living.size() >= 2 else "a lone adventurer")
	var r := hp / max_hp
	return "%s, %s" % [size, "fresh" if r > 0.7 else ("battered" if r > 0.35 else "nearly dead")]


static func _describe_member(p: Dictionary) -> String:
	var who: String
	if p.get("kind") == "monster":
		who = "a %s ally" % Species.SPECIES[p["species"]]["label"]
	else:
		who = "a human %s" % ("mage" if p.get("cls") == "N-MAG" else "fighter")
	var did := "; this round: %s" % str(p["didThisRound"]) if J.truthy(p.get("didThisRound")) else ""
	return "%s, %s%s" % [who, _health_word(p["hp"], p["maxHp"]), did]


# Damage is a plain fact, so code turns it into anger and fear before Jev sees the mood.
static func _apply_damage(m: Dictionary) -> void:
	var meters: Dictionary = m["meters"]
	var frac: float = float(J.nz(m.get("damageTaken"), 0)) / m["maxHp"]
	meters["anger"] += frac * 55
	meters["fear"] += frac * 30 + (10 if float(m["hp"]) / m["maxHp"] < 0.35 else 0)
	for k in meters:
		meters[k] = _clamp(meters[k])


# The party asked this monster to join. The Charisma roll (made by the game) decides how the pitch
# landed; code applies that to its mood before Jev sees it.
static func _apply_pitch(req: Dictionary, m: Dictionary) -> void:
	var pa: Dictionary = req["playerAction"]
	if pa.get("type") != "recruit" or pa.get("targetId") != m["id"] or not Emotions.PITCH.has(pa.get("pitch")):
		return
	var p: Dictionary = Emotions.PITCH[pa["pitch"]]
	var meters: Dictionary = m["meters"]
	meters["friendliness"] += p["friendliness"]
	meters["anger"] += p["anger"]
	# A pitch that beat the DC brings it up to its bar for joining: now it's open to it, and Jev says yes or no
	if p.get("reach") != null:
		meters["friendliness"] = maxi(meters["friendliness"], _join_threshold(m) + p["reach"])
		meters["anger"] = mini(meters["anger"], JOIN_ANGER - 5 - p["reach"])
	for k in meters:
		meters[k] = _clamp(meters[k])
	var then: Array = (J.nz(m.get("thisRound"), []) as Array).duplicate()
	then.append("The party asked you to join them, with %s." % p["words"])
	m["thisRound"] = then


static func _context(req: Dictionary, m: Dictionary, monsters: Array) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[m["species"]]
	var pa: Dictionary = req["playerAction"]
	var type = pa.get("type")
	var message = pa["message"] if (type == "talk" or type == "recruit") and J.truthy(pa.get("message")) else null
	var explicit_gold = pa.get("gold") if type == "give" and pa.get("targetId") == m["id"] else null
	var recruit_me: bool = type == "recruit" and pa.get("targetId") == m["id"]
	var living := []
	var kin := []
	for p in req["party"]:
		if not J.truthy(p.get("dead")):
			living.append(p)
			if p.get("kind") == "monster" and p.get("species") == m["species"]:
				kin.append(p["name"])
	var others := []
	for o in monsters:
		if o["id"] != m["id"]:
			others.append(o)
	var party_gold = J.nz(req.get("partyGold"), 0)
	return {
		"m": m,
		"sp": sp,
		"message": message,
		"explicitGold": explicit_gold,
		"recruitMe": recruit_me,
		# Feelings are asked whenever the party's action was aimed at this monster's heart
		"feels": message != null or recruit_me or (explicit_gold != null and explicit_gold > 0),
		"delivery": clampf(float(U.num_or(pa.get("delivery"), 1)), 0.5, 2.0),
		"speechOfferPossible": message != null and party_gold > 0,
		"room": req["party"].size() < 6,
		"readyToJoin": m["meters"]["friendliness"] >= _join_threshold(m) and m["meters"]["anger"] < 30,
		"living": living,
		"others": others,
		# Monsters of its own kind already traveling with the party
		"kin": kin,
	}


## The answer to "join us?", settled from the mood after this round's pitch, words and feeling, and Jev's own
## willingness. Returns null when nobody asked and it isn't moved to ask itself.
##   { asked, accepted, moved, reason }: reason is a JOIN_YES id when accepted, a JOIN_NO id otherwise
## sure: the guided first fight, where the invitation is the lesson and always lands.
## opts: { invited, meters, threshold, room = true, emotion = null, willing = 0, rolledJoin = false, yesWhy, noWhy,
##         pitch = null, sure = false }
static func resolve_join(opts: Dictionary):
	var room: bool = opts.get("room", true)
	if not room:
		return null
	var meters: Dictionary = opts["meters"]
	var invited: bool = J.truthy(opts.get("invited"))
	var emotion = opts.get("emotion")
	var emotion_id = emotion.get("id") if emotion != null else null
	var eligible: bool = meters["friendliness"] >= opts["threshold"] and meters["anger"] < JOIN_ANGER
	var willing = J.nz(opts.get("willing"), 0)
	var rolled_join: bool = J.truthy(opts.get("rolledJoin"))
	# Jev's explicit answer decides; its action roll landing on "join" tips a near-even answer
	var wants: bool = willing >= WILLING or (rolled_join and willing >= 0.3)
	var yes_why = opts.get("yesWhy")
	var yes = yes_why if yes_why != null and Narrate.JOIN_YES.has(yes_why) else "likes_you"
	if invited and J.truthy(opts.get("sure")):
		return {"asked": true, "accepted": true, "moved": false, "reason": yes}
	if not invited:
		var moved: bool = eligible and GLAD.has(emotion_id) and wants
		return {"asked": true, "accepted": true, "moved": true, "reason": yes} if moved else null
	# Feeling offended, enraged or baffled this very round rules out a yes, whatever the meters say
	var soured: bool = (emotion != null and emotion.get("tone") == "bad") or emotion_id == "confused"
	if eligible and wants and not soured:
		return {"asked": true, "accepted": true, "moved": false, "reason": yes}
	var no_why = opts.get("noWhy")
	var reason: String = no_why if no_why != null and Narrate.JOIN_NO.has(no_why) and not Narrate.JOIN_NO[no_why].get("code", false) else "not_yet"
	if emotion_id == "confused":
		reason = "confused"
	elif (soured or meters["anger"] >= JOIN_ANGER) and not ANGRY_REASONS.has(reason):
		reason = "bad_pitch" if ["fail", "botch"].has(opts.get("pitch")) else "still_angry"
	return {"asked": true, "accepted": false, "moved": false, "reason": reason}


static func _feasible_actions(c: Dictionary) -> Dictionary:
	var m: Dictionary = c["m"]
	var offer_possible: bool = (c["explicitGold"] != null and c["explicitGold"] > 0) or c["speechOfferPossible"]
	var has_living: bool = not c["living"].is_empty()
	return {
		"attack": has_living,
		"special": J.truthy(m.get("specialReady")) and has_living,
		"attack_monster": not c["others"].is_empty(),
		"defend": true,
		"flee": true,
		"converse": true,
		"demand_tribute": not J.truthy(m.get("paid")),
		"accept_tribute": offer_possible,
		"refuse_tribute": offer_possible,
		"join_party": c["room"] and (c["message"] != null or c["recruitMe"] or c["readyToJoin"]),
		"leave_peacefully": true,
	}


static func _monster_state(req: Dictionary, c: Dictionary) -> Dictionary:
	var m: Dictionary = c["m"]
	var sp: Dictionary = c["sp"]
	var kin: Array = c["kin"]
	var meters: Dictionary = m["meters"]
	var impressions: Array = m["impressions"]
	var this_round: Array = J.nz(m.get("thisRound"), [])
	var state := {
		"name": m["name"],
		"kind": sp["label"],
		"nature": sp["nature"],
		"traits": J.nz(m.get("traits"), []),
		"likes": sp["likes"].duplicate(),
		"dislikes": sp["dislikes"].duplicate(),
		"health": _health_word(m["hp"], m["maxHp"]),
	}
	if J.truthy(m.get("boss")):
		state["rank"] = "the champion of this floor: proud, powerful, and hard to impress"
	state["mood"] = {
		"friendliness": _bucket(meters["friendliness"], ["hostile", "unfriendly", "wary", "friendly", "very friendly"]),
		"anger": _bucket(meters["anger"], ["calm", "annoyed", "angry", "furious"]),
		"fear": _bucket(meters["fear"], ["unafraid", "uneasy", "scared", "terrified"]),
	}
	state["side"] = _stance(m)
	state["impressions"] = U.last(impressions, 6) if not impressions.is_empty() else ["No strong impressions of this party yet."]
	state["this_round"] = this_round if not this_round.is_empty() else ["Nothing happened to it directly."]
	state["tribute"] = "the party already paid it tribute" if J.truthy(m.get("paid")) else ("it demanded tribute, not yet paid" if J.truthy(m.get("demanded")) else "not discussed")
	state["kin_in_party"] = (
		"%s, %s like it, travel%s with this party" % [" and ".join(kin), sp["plural"] if kin.size() > 1 else "a %s" % sp["label"], "" if kin.size() > 1 else "s"]
		if not kin.is_empty()
		else "none"
	)
	if c["readyToJoin"]:
		state["ready_to_join_party"] = "yes: %s now likes this party enough to join them if they invite it" % m["name"]
	elif J.truthy(m.get("formerAlly")):
		state["ready_to_join_party"] = "not yet: %s left this party once, and it would take a lot to win it back" % m["name"]
	else:
		state["ready_to_join_party"] = "not yet: %s doesn't like or trust this party enough to join them" % m["name"]
	var promises := []
	for v in J.nz(req.get("vows"), []):
		if v.get("toId") == m["id"]:
			promises.append("\"%s\" (%s)" % [str(v.get("text")), str(v.get("status"))])
	state["promises_party_made_to_it"] = promises
	var grudges := []
	for id in J.nz(m.get("grudges"), []):
		for o in c["others"]:
			if o["id"] == id:
				if J.truthy(o.get("name")):
					grudges.append(o["name"])
				break
	state["grudges"] = grudges
	return state


static func _build_state(req: Dictionary, monsters: Array, ctxs: Array) -> Dictionary:
	var by_id := {}
	for c in ctxs:
		by_id[c["m"]["id"]] = _monster_state(req, c)
	var group := []
	for m in monsters:
		group.append("%s (%s): %s" % [m["name"], Species.SPECIES[m["species"]]["label"], _stance(m)])
	var c0: Dictionary = ctxs[0]
	var members := []
	for p in c0["living"]:
		members.append("%s: %s" % [p["name"], _describe_member(p)])
	var events: Array = req["events"]
	var pa: Dictionary = req["playerAction"]
	var offering := "nothing"
	if pa.get("type") == "give":
		for t in monsters:
			if t["id"] == pa.get("targetId"):
				offering = "%s gold to %s, %s" % [J.num(pa.get("gold")), t["name"], _offer_words(pa.get("gold"), Species.SPECIES[t["species"]]["minTribute"], t["name"])]
				break
	var conversation: Array = req["conversation"]
	var recent := []
	for l in U.last(conversation, 8):
		recent.append("%s: %s" % [str(l.get("speaker")), str(l.get("text"))])
	return {
		"monsters": by_id,
		"group": group,
		"party": {
			"condition": _party_condition(c0["living"]),
			"members": members,
			"this_round": events if not events.is_empty() else ["The party did nothing notable."],
			"latest_message": c0["message"] if c0["message"] != null else "(the party said nothing this round)",
			"offering": offering,
		},
		"recent_conversation": recent if not conversation.is_empty() else ["(no conversation yet)"],
	}


static func _lines_for(action: String, c: Dictionary) -> Array:
	var lines: Array = c["sp"]["lines"].get(action, [])
	if action == "converse" and c["message"] != null and not c["readyToJoin"]:
		return lines + c["sp"]["lines"]["not_ready"]
	return lines


# Adds this monster's questions (ids prefixed with its id) to the shared request; returns its feasible actions.
static func _build_questions(c: Dictionary, feasible: Dictionary, q: Dictionary) -> Array:
	var m: Dictionary = c["m"]
	var sp: Dictionary = c["sp"]
	var mid: String = m["id"]
	var name: String = m["name"]
	var me := "`monsters.%s`" % mid
	if c["message"] != null:
		q[mid + "__threat"] = Q.noul("Does `party.latest_message` threaten to hurt or kill %s?" % name, {
			"true": "An explicit or implied threat of violence toward it",
			"false": "No threat of violence toward it (rudeness alone does not count)",
		})
		q[mid + "__insult"] = Q.noul("Does `party.latest_message` insult, mock, or belittle %s?" % name)
		q[mid + "__kindness"] = Q.score("How kind, friendly, or flattering is `party.latest_message` toward %s?" % name, [
			"Hostile or contemptuous toward it",
			"Cold, businesslike, or not about it",
			"Polite and friendly toward it",
			"Warm, kind, or openly complimentary toward it",
		])
		q[mid + "__joke"] = Q.noul("Does `party.latest_message` contain a joke, pun, or deliberately silly remark?")
		q[mid + "__asks_to_join"] = Q.noul("In `party.latest_message`, does the party invite %s to join them or travel with them?" % name)
		q[mid + "__asks_for_peace"] = Q.noul("In `party.latest_message`, does the party ask %s to stop fighting, make peace, or let them pass?" % name)
		if c["speechOfferPossible"]:
			q[mid + "__offers_gold"] = Q.noul("In `party.latest_message`, is the party offering gold or money to %s right now?" % name)
	# Joining is its own narrow judgment, plus its reason either way, so the log can say why it agreed or refused.
	# Asked whenever joining is possible: this round's pitch and feelings can carry it over its bar.
	if feasible["join_party"]:
		q[mid + "__would_join"] = Q.noul({
			"question": "If the party is inviting %s to join them, does %s want to say yes?" % [name, name],
			"consider": ["`monsters.%s.ready_to_join_party`" % mid, me, "`party.latest_message`", "`party.this_round`"],
		})
		var why := {"others": c["others"].map(func(o): return o["name"]), "kin": c["kin"], "formerAlly": J.truthy(m.get("formerAlly"))}
		var consider := ["Its nature, traits, mood, impressions and kin in %s" % me, "`monsters.%s.this_round`" % mid, "`group`", "`party`"]
		q[mid + "__join_yes"] = Q.choice(
			{"question": "If %s agrees to join the party now, what is its main reason?" % name, "consider": consider},
			Narrate.reason_options(Narrate.JOIN_YES, why),
		)
		q[mid + "__join_no"] = Q.choice(
			{"question": "If %s turns down an invitation to join the party now, what is its main reason?" % name, "consider": consider},
			Narrate.reason_options(Narrate.JOIN_NO, why),
		)
	if c["feels"]:
		var feelings := {}
		for id in Emotions.EMOTIONS:
			feelings[id] = {"what": Emotions.EMOTIONS[id]["what"], "when": Emotions.EMOTIONS[id]["when"]}
		q[mid + "__emotion"] = Q.choice(
			{
				"question": "How does %s feel about what the party just said or did to it this round?" % name,
				"consider": [
					"What happened in `party.this_round` and `monsters.%s.this_round`" % mid,
					"`party.latest_message`",
					"Its nature, likes, dislikes and mood in %s" % me,
				],
			},
			feelings,
		)

	var options := []
	for a in feasible:
		if feasible[a]:
			options.append(a)
	var action_options := {}
	for a in options:
		action_options[a] = describe(a, sp)
	q[mid + "__action"] = Q.choice(
		{
			"question": "What does %s do this round?" % name,
			"consider": [
				"Its nature, traits, likes, dislikes, mood and impressions in %s" % me,
				"What happened to it this round in `monsters.%s.this_round`" % mid,
				"Which side the other monsters are on in `group`",
				"What the party did and said in `party`",
			],
		},
		action_options,
	)

	if (feasible["attack"] or (feasible["special"] and not sp["special"]["all"])) and c["living"].size() > 1:
		var targets := {}
		for p in c["living"]:
			targets[p["id"]] = "%s: %s" % [p["name"], _describe_member(p)]
		q[mid + "__target"] = Q.choice({"question": "If %s attacks the party, which member does it go after?" % name, "consider": ["`party.members`", me]}, targets)
	if feasible["attack_monster"] and c["others"].size() > 1:
		var victims := {}
		for o in c["others"]:
			victims[o["id"]] = "%s, %s: %s" % [o["name"], Species.SPECIES[o["species"]]["label"], _stance(o)]
		q[mid + "__monster_target"] = Q.choice({"question": "If %s turns on another monster, which one?" % name, "consider": ["`group`", me]}, victims)

	for a in options:
		var lines := _lines_for(a, c)
		if lines.size() < 2:
			continue
		var fitted := {}
		for i in lines.size():
			fitted["line_%d" % i] = Species.fill(lines[i], {"name": name, "target": "the target"})
		q["%s__line__%s" % [mid, a]] = Q.choice(
			{
				"question": "%s is about to do what `planned_action` describes. Which line fits best right now?" % name,
				"planned_action": describe_short(a, sp),
				"respond_to": ["`party.latest_message`", "`monsters.%s.this_round`" % mid],
			},
			fitted,
		)
	return options


## a[`${id}__${x}`]?.noul ?? 0
static func _noul(a: Dictionary, key: String) -> float:
	var ans = a.get(key)
	if ans is Dictionary and ans.get("noul") != null:
		return float(ans["noul"])
	return 0.0


static func _apply_perception(c: Dictionary, a: Dictionary, meters: Dictionary, impressions: Array) -> void:
	if c["message"] == null:
		return
	var mid: String = c["m"]["id"]
	var w: Dictionary = c["sp"]["weights"]
	var n := func(id: String) -> float: return _noul(a, "%s__%s" % [mid, id])
	var note := func(t: String) -> void:
		if not impressions.has(t):
			impressions.append(t)
	var kindness: float = float(a[mid + "__kindness"]["score"])
	var kind := kindness / 3
	var x: float = c["delivery"]  # how well the words were delivered (the Charisma roll) scales how hard they land
	meters["friendliness"] += x * (w["kindness"] * (kind - 0.35) + w["joke"] * n.call("joke") + w["peace"] * n.call("asks_for_peace") - w["insult"] * n.call("insult") - 10 * n.call("threat"))
	meters["anger"] += x * (w["insult"] * n.call("insult") + w["threatAnger"] * n.call("threat") - 8 * kind - 5 * n.call("asks_for_peace"))
	meters["fear"] += x * w["threatFear"] * n.call("threat")
	if n.call("threat") >= 0.7:
		note.call("The party threatened you.")
	if n.call("insult") >= 0.7:
		note.call("The party insulted you.")
	if n.call("joke") >= 0.7:
		note.call("The party told you a joke.")
	if kindness >= 2.5:
		note.call("The party spoke kindly to you.")
	if n.call("asks_for_peace") >= 0.7:
		note.call("The party asked you for peace.")


# The feeling Jev picked moves the mood (scaled by delivery when the party was talking). Code owns the numbers.
static func _apply_emotion(c: Dictionary, emotion_id, meters: Dictionary, impressions: Array):
	if emotion_id == null or not Emotions.EMOTIONS.has(emotion_id):
		return null
	var e: Dictionary = Emotions.EMOTIONS[emotion_id]
	var x = c["delivery"] if c["message"] != null else 1
	var delta := {}
	var shifts: Dictionary = e.get("meters", {})
	for k in shifts:
		var before = meters[k]
		meters[k] = _clamp(meters[k] + shifts[k] * x)
		delta[k] = meters[k] - before
	var t := "The party left you feeling %s." % (e["label"] as String).to_lower()
	if not impressions.has(t):
		impressions.append(t)
	return {"id": emotion_id, "label": e["label"], "cond": e.get("cond"), "rounds": J.nz(e.get("rounds"), 0), "effect": e["effect"], "tone": e["tone"], "delta": delta}


static func _policy(action: String, conf, req: Dictionary, c: Dictionary, a: Dictionary, meters: Dictionary, offer, target, emotion):
	var m: Dictionary = c["m"]
	var sp: Dictionary = c["sp"]
	var asks: float = 1.0 if c["recruitMe"] else _noul(a, m["id"] + "__asks_to_join")
	var emotion_id = emotion.get("id") if emotion != null else null
	if emotion != null and J.truthy(emotion.get("cond")) and Emotions.PACIFYING.has(emotion["cond"]) and ["attack", "special", "attack_monster"].has(action):
		return {"why": "it is %s: %s" % [(emotion["label"] as String).to_lower(), (emotion["effect"] as String).to_lower()], "fallback": "converse"}
	# "Its heart opens to you" followed by a club to the face would contradict what the log just said
	if emotion_id == "touched" and ["attack", "special"].has(action):
		return {"why": "it is touched: its heart opens to the party", "fallback": "converse"}
	match action:
		"join_party":
			if meters["friendliness"] < _join_threshold(m):
				return {"why": "friendliness %s < %s needed to join" % [J.num(meters["friendliness"]), J.num(_join_threshold(m))], "fallback": "converse"}
			if meters["anger"] >= 30:
				return {"why": "anger %s ≥ 30" % J.num(meters["anger"]), "fallback": "converse"}
			# Invited, or so moved that it asks to come along on its own
			if asks < 0.6 and not ["touched", "delighted"].has(emotion_id):
				return {"why": "the party never actually invited it", "fallback": "converse"}
			return null
		"accept_tribute":
			if not J.truthy(offer):
				return {"why": "no gold is actually being offered to it", "fallback": "converse"}
			if offer < sp["minTribute"] and not J.truthy(m.get("paid")):
				return {"why": "%s gold is below its minimum of %s" % [J.num(offer), J.num(sp["minTribute"])], "fallback": "refuse_tribute"}
			return null
		"refuse_tribute":
			return null if J.truthy(offer) else {"why": "no gold is actually being offered to it", "fallback": "converse"}
		"leave_peacefully":
			if meters["anger"] >= 45:
				return {"why": "anger %s ≥ 45; it won't just walk away" % J.num(meters["anger"]), "fallback": "defend"}
			return null
		"attack_monster":
			# Only turn on another monster when they're on opposite sides, or that monster hit it.
			if target == null:
				return null
			var tf = target["meters"]["friendliness"]
			var opposite: bool = (meters["friendliness"] < HOSTILE and tf >= FRIENDLY) or (meters["friendliness"] >= FRIENDLY and tf < HOSTILE)
			var grudge: bool = J.nz(m.get("grudges"), []).has(target["id"])
			if opposite or grudge:
				return null
			return {
				"why": "%s isn't on the other side and hasn't hit it" % target["name"],
				"fallback": "attack" if meters["friendliness"] < HOSTILE else "converse",
			}
		"attack", "special":
			if meters["friendliness"] >= 75 and meters["anger"] < 15 and not _provoked(req):
				return {"why": "friendliness %s with no provocation" % J.num(meters["friendliness"]), "fallback": "converse"}
			if (conf is float or conf is int) and conf < 0.25:
				return {"why": "confidence %s < 0.25 for an attack" % _to_fixed2(float(conf)), "fallback": "defend"}
			return null
	return null


static func _provoked(req: Dictionary) -> bool:
	for ev in req["events"]:
		if _re_provoked.search(str(ev)) != null:
			return true
	return false


static func _roll(probabilities: Dictionary) -> String:
	var live := []
	var total := 0.0
	for act in probabilities:
		if probabilities[act] >= ROLL_FLOOR:
			live.append(act)
			total += probabilities[act]
	if live.is_empty():
		# the most likely one (the first of equals)
		var best = null
		var best_p := -INF
		for act in probabilities:
			if probabilities[act] > best_p:
				best_p = probabilities[act]
				best = act
		return best
	var r := randf() * total
	for act in live:
		r -= probabilities[act]
		if r <= 0.0:
			return act
	return live[live.size() - 1]


## Entries of {id: p} as [{id, p}], highest p first (equal ones keep their order, like a stable sort)
static func _ranked(probabilities: Dictionary) -> Array:
	var out := []
	for id in probabilities:
		out.append({"id": id, "p": probabilities[id]})
	var order := range(out.size())
	order.sort_custom(func(i, j): return out[i]["p"] > out[j]["p"] or (out[i]["p"] == out[j]["p"] and i < j))
	return order.map(func(i): return out[i])


## A mandatory answer Jev left out, or "" when the reply is usable (the JS would throw a TypeError on these)
static func _missing(a: Dictionary, ctxs: Array) -> String:
	for c in ctxs:
		var mid: String = c["m"]["id"]
		var action = a.get(mid + "__action")
		if not (action is Dictionary) or not (action.get("probabilities") is Dictionary) or (action["probabilities"] as Dictionary).is_empty():
			return mid + "__action"
		if c["message"] != null:
			var kindness = a.get(mid + "__kindness")
			if not (kindness is Dictionary) or kindness.get("score") == null:
				return mid + "__kindness"
	return ""


## One round for 1–3 monsters. req: { monsters, party, round, playerAction, events, conversation, partyGold, vows,
## guided, trace } (see api.gd for the sanitised shape). Returns { results, ms, inputTokens, questionCount, model }.
static func group_turn(req: Dictionary) -> Dictionary:
	req = req.duplicate()
	for key in ["events", "conversation", "party", "vows"]:
		req[key] = J.nz(req.get(key), [])
	req["playerAction"] = J.nz(req.get("playerAction"), {})
	var monsters := []
	for m in req["monsters"]:
		var copy: Dictionary = m.duplicate()
		var meters: Dictionary = (m["meters"] as Dictionary).duplicate()
		for k in ["friendliness", "anger", "fear"]:
			meters[k] = J.nz(meters.get(k), 0)
		copy["meters"] = meters
		copy["impressions"] = (J.nz(m.get("impressions"), []) as Array).duplicate()
		monsters.append(copy)
	for m in monsters:
		_apply_damage(m)
	for m in monsters:
		_apply_pitch(req, m)
	var ctxs := []
	var feasible := []
	for m in monsters:
		var c := _context(req, m, monsters)
		ctxs.append(c)
		feasible.append(_feasible_actions(c))
	var state := _build_state(req, monsters, ctxs)
	var questions := {}
	var options := []
	for i in ctxs.size():
		options.append(_build_questions(ctxs[i], feasible[i], questions))
	var res := await Jev.jev(state, questions, req.get("trace"))
	if res.has("error"):
		return res
	var a = res.get("answers")
	if not a is Dictionary:
		return {"error": "Jev reply has no answers"}
	var missing := _missing(a, ctxs)
	if missing != "":
		return {"error": "Jev left %s unanswered" % missing}

	var results := []
	for i in ctxs.size():
		results.append(_result_for(req, ctxs[i], feasible[i], options[i], a))
	var usage = res.get("usage")
	return {
		"results": results,
		"ms": res.get("ms"),
		"inputTokens": usage.get("input_tokens") if usage is Dictionary else null,
		"questionCount": questions.size(),
		"model": res.get("model"),
	}


static func _result_for(req: Dictionary, c: Dictionary, feasible: Dictionary, options: Array, a: Dictionary) -> Dictionary:
	var m: Dictionary = c["m"]
	var sp: Dictionary = c["sp"]
	var mid: String = m["id"]
	var meters: Dictionary = (m["meters"] as Dictionary).duplicate()
	var impressions: Array = (m["impressions"] as Array).duplicate()
	var before := meters.duplicate()
	_apply_perception(c, a, meters, impressions)
	for k in meters:
		meters[k] = _clamp(meters[k])
	var emotion_answer = a.get(mid + "__emotion")
	var emotion = _apply_emotion(c, emotion_answer.get("choice") if emotion_answer is Dictionary else null, meters, impressions)

	var offer = c["explicitGold"] if J.truthy(c["explicitGold"]) else 0
	if not J.truthy(offer) and _noul(a, mid + "__offers_gold") >= 0.6:
		var party_gold = J.nz(req.get("partyGold"), 0)
		var floor_gold := maxi(sp["minTribute"], 1)
		offer = party_gold if party_gold < floor_gold else floor_gold

	var monster_target = null
	var mt_answer = a.get(mid + "__monster_target")
	var mt_choice = mt_answer.get("choice") if mt_answer is Dictionary else null
	for o in c["others"]:
		if o["id"] == mt_choice:
			monster_target = o
			break
	if monster_target == null and not c["others"].is_empty():
		monster_target = c["others"][0]
	var action: Dictionary = a[mid + "__action"]
	var picked := _roll(action["probabilities"])
	# An invitation (the recruit command, or words that ask it along) gets a real answer; so does a monster so
	# touched or delighted that it asks to come along on its own. The answer overrides the rolled action.
	var invited: bool = c["recruitMe"] or _noul(a, mid + "__asks_to_join") >= 0.6
	var join = null
	if feasible["join_party"]:
		var yes_answer = a.get(mid + "__join_yes")
		var no_answer = a.get(mid + "__join_no")
		join = resolve_join({
			"invited": invited,
			"meters": meters,
			"threshold": _join_threshold(m),
			"room": c["room"],
			"emotion": emotion,
			"willing": _noul(a, mid + "__would_join"),
			"rolledJoin": picked == "join_party",
			"yesWhy": yes_answer.get("choice") if yes_answer is Dictionary else null,
			"noWhy": no_answer.get("choice") if no_answer is Dictionary else null,
			"pitch": req["playerAction"].get("pitch") if c["recruitMe"] else null,
			"sure": J.truthy(req.get("guided")),
		})
	if join != null:
		join["others"] = c["others"].map(func(o): return o["name"])
		join["kin"] = c["kin"]
		print_verbose(
			"[join] %s (%s) %s: %s | f%s/%s a%s feels %s would_join %s rolled %s" % [
				m["name"], m["species"],
				"asks to come" if join["moved"] else ("accepts" if join["accepted"] else "refuses"), join["reason"],
				J.num(meters["friendliness"]), J.num(_join_threshold(m)), J.num(meters["anger"]),
				emotion["id"] if emotion != null else "-", "%.2f" % _noul(a, mid + "__would_join"), picked,
			]
		)
	var final := picked
	var block = null
	if join != null and join["accepted"]:
		final = "join_party"
	else:
		if join != null and picked == "join_party":
			block = {"why": "it turned the invitation down (%s)" % join["reason"], "fallback": "converse"}
		# It likes the party and was asked: it says no, it doesn't swing at them
		elif join != null and ["attack", "special"].has(picked) and Narrate.mood_of(meters, emotion) == "warm":
			block = {"why": "it declined (%s) but likes the party too much to attack" % join["reason"], "fallback": "converse"}
		# The guided first fight: it stays to be asked, rather than slipping away before the lesson's second step
		elif J.truthy(req.get("guided")) and ["flee", "leave_peacefully"].has(picked):
			block = {"why": "the guided first fight: it stays to hear the party out", "fallback": "converse"}
		else:
			block = _policy(picked, action.get("confidence"), req, c, a, meters, offer, monster_target, emotion)
		if block != null:
			final = block["fallback"] if options.has(block["fallback"]) else "converse"

	if final == "accept_tribute":
		meters["friendliness"] = _clamp(meters["friendliness"] + sp["weights"]["gold"])
		meters["anger"] = _clamp(meters["anger"] - 25)
		impressions.append("The party paid you %s gold." % J.num(offer))

	var target_answer = a.get(mid + "__target")
	var target_choice = target_answer.get("choice") if target_answer is Dictionary else null
	var target = null
	for p in c["living"]:
		if p["id"] == target_choice:
			target = p
			break
	if target == null and not c["living"].is_empty():
		target = c["living"][0]
	var named = (monster_target["name"] if monster_target != null else null) if final == "attack_monster" else (target["name"] if target != null else null)
	var lines := _lines_for(final, c)
	var line_answer = a.get("%s__line__%s" % [mid, final])
	var probs: Dictionary = line_answer.get("probabilities", {}) if line_answer is Dictionary else {}
	var ranked := range(lines.size())
	ranked.sort_custom(func(x, y):
		var px: float = J.nz(probs.get("line_%d" % x), 0)
		var py: float = J.nz(probs.get("line_%d" % y), 0)
		return py < px or (py == px and x < y))
	var recent := []
	for l in U.last(req["conversation"], 3):
		recent.append(l.get("text"))
	var fill_vars := {"name": m["name"], "target": named if named != null else "someone"}
	var chosen := -1
	for j in ranked:
		if not recent.has(Species.fill(lines[j], fill_vars)):
			chosen = j
			break
	if chosen == -1 and not ranked.is_empty():
		chosen = ranked[0]
	# Turning down an invitation: say the reason. "Not yet" in its own words if the species has them; otherwise
	# the narrated answer is its reply (spoken: false), so no cheerful small-talk line undercuts the refusal.
	var line = Species.fill(lines[chosen], fill_vars) if chosen != -1 else ""
	var spoken := true
	if join != null and not join["accepted"] and final == "converse":
		var not_ready: Array = sp["lines"].get("not_ready", [])
		var own = not_ready[0] if ["not_yet", "wants_more"].has(join["reason"]) and not not_ready.is_empty() else null
		if own != null:
			line = Species.fill(own, {"name": m["name"], "target": "someone"})
		else:
			spoken = false
			line = Narrate.join_line(m["species"], m["name"], join, {"meters": meters, "emotion": emotion})
	var tribute_refusal = null
	if final == "refuse_tribute":
		if J.truthy(offer) and offer < sp["minTribute"] and not J.truthy(m.get("paid")):
			tribute_refusal = "too_little"
		elif meters["anger"] >= 45:
			tribute_refusal = "angry"
		else:
			tribute_refusal = "not_for_sale"

	var mood_delta := {}
	for k in meters:
		mood_delta[k] = meters[k] - before[k]
	var emotion_probabilities = null
	if emotion_answer is Dictionary and emotion_answer.get("probabilities") is Dictionary:
		emotion_probabilities = _ranked(emotion_answer["probabilities"]).slice(0, 3)
	var perception := []
	for p in LABELS:
		var ans = a.get("%s__%s" % [mid, p])
		if not (ans is Dictionary):
			continue
		if ans.get("type") == "noul":
			perception.append({"id": p, "label": LABELS[p], "type": "noul", "value": ans.get("noul")})
		else:
			perception.append({"id": p, "label": LABELS[p], "type": "score", "value": ans.get("score"), "max": 3})
	return {
		"id": mid,
		"action": final,
		"picked": picked,
		"blocked": block["why"] if block != null else null,
		"confidence": action.get("confidence"),
		"probabilities": _ranked(action["probabilities"]),
		"targetId": target["id"] if target != null else null,
		"monsterTargetId": monster_target["id"] if final == "attack_monster" and monster_target != null else null,
		"line": line,
		"spoken": spoken,
		"join": join,
		"tributeRefusal": tribute_refusal,
		"offer": offer if final == "accept_tribute" else 0,
		"meters": meters,
		"moodDelta": mood_delta,
		"emotion": emotion,
		"emotionProbabilities": emotion_probabilities,
		"side": _stance({"meters": meters}),
		"impressions": U.last(impressions, 8),
		"perception": perception,
	}


## Kept for builds that still call the single-monster endpoint (e.g. an already-uploaded itch.io zip).
static func enemy_turn(req: Dictionary) -> Dictionary:
	var m: Dictionary = (req["enemy"] as Dictionary).duplicate()
	m["id"] = "e0"
	m["grudges"] = []
	m["thisRound"] = []
	var forwarded := req.duplicate()
	forwarded["monsters"] = [m]
	forwarded["vows"] = []
	var out := await group_turn(forwarded)
	if out.has("error"):
		return out
	var r: Dictionary = (out["results"][0] as Dictionary).duplicate()
	r["targetProbabilities"] = null
	r["ms"] = out["ms"]
	r["inputTokens"] = out["inputTokens"]
	r["questionCount"] = out["questionCount"]
	r["model"] = out["model"]
	return r
