## Recruited monsters judge the party after each encounter. One Jev request covers every ally:
##   - approval Score per ally (how it feels about the events, by its own values)
##   - a reaction line Choice per ally
##   - for allies whose loyalty is already shaky, a speculative Choice: stay, leave, or turn on the party
##   - which event it reacted to most, so the log can say what pleased or upset it ("can't stomach how you...")
## Code turns approval into loyalty and decides whether leaving or betrayal is allowed.
## Load it with `const Allies = preload("res://src/jev/allies.gd")`. Failures return {"error": String}.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Q = preload("res://src/jev/q.gd")
const U = preload("res://src/jev/util.gd")
const Jev = preload("res://src/jev/jev.gd")
const Species = preload("res://src/rules/species.gd")
const Narrate = preload("res://src/rules/narrate.gd")

const LOYALTY_DELTA := [-18, -9, 0, 7, 12]  # by approval level 0..4
const SHAKY := 45  # ask the stay/leave/betray question below this (before the change)
const LEAVE_BELOW := 30
const BETRAY_BELOW := 15


static func loyalty_word(v) -> String:
	if v >= 75:
		return "devoted"
	if v >= 50:
		return "content"
	if v >= 30:
		return "uneasy"
	if v >= 15:
		return "resentful"
	return "on the verge of leaving"


## { allies, events, trace = null } → { reactions, ms, inputTokens, questionCount, model, request, answers }
static func ally_reactions(req: Dictionary) -> Dictionary:
	var allies: Array = req["allies"]
	var events: Array = req["events"]
	var trace = req.get("trace")
	var ally_states := {}
	for al in allies:
		var sp: Dictionary = Species.SPECIES[al["species"]]
		var personality := [sp["nature"]]
		personality.append_array(J.nz(al.get("traits"), []))
		ally_states[al["id"]] = {
			"name": al["name"],
			"kind": sp["label"],
			"personality": personality,
			"values": sp["values"],
			"loyalty": loyalty_word(J.nz(al.get("loyalty"), 0)),
		}
	var state := {"events": events, "allies": ally_states}

	var questions := {}
	for al in allies:
		var sp: Dictionary = Species.SPECIES[al["species"]]
		var id: String = al["id"]
		var judge_by := ["`allies.%s.values`" % id, "`allies.%s.personality`" % id]
		questions["approval__" + id] = Q.score(
			{"question": "How does `allies.%s.name` feel about what the party did in `events`?" % id, "judge_by": judge_by},
			["Strongly disapproves", "Disapproves", "Doesn't care", "Approves", "Strongly approves"],
		)
		var lines := _reaction_lines(sp)
		var fitted := {}
		for i in lines.size():
			fitted["line_%d" % i] = Species.fill(lines[i], {"name": al["name"]})
		questions["line__" + id] = Q.choice(
			{"question": "What does `allies.%s.name` say or do in reaction to `events`?" % id, "judge_by": judge_by},
			fitted,
		)
		if events.size() > 1:
			var moments := {}
			for i in events.size():
				moments["event_%d" % i] = events[i]
			questions["moment__" + id] = Q.choice(
				{"question": "Which event in `events` does `allies.%s.name` react to most strongly, for better or worse?" % id, "judge_by": judge_by},
				moments,
			)
		if J.nz(al.get("loyalty"), 0) < SHAKY:
			questions["decision__" + id] = Q.choice(
				{
					"question": "After `events`, what does `allies.%s.name` do?" % id,
					"consider": ["`allies.%s.values`" % id, "`allies.%s.loyalty`" % id, "`allies.%s.personality`" % id],
				},
				{
					"stay": "Stays with the party, perhaps grumbling",
					"leave_party": "Leaves the party and goes its own way",
					"turn_on_party": "Turns on the party and attacks them",
				},
			)

	var res := await Jev.jev(state, questions, trace)
	if res.has("error"):
		return res
	var a = res.get("answers")
	if not a is Dictionary:
		return {"error": "Jev reply has no answers"}
	for al in allies:
		var approval = a.get("approval__" + al["id"])
		if not (approval is Dictionary) or approval.get("score") == null:
			return {"error": "Jev left approval__%s unanswered" % al["id"]}

	var reactions := []
	for al in allies:
		var sp: Dictionary = Species.SPECIES[al["species"]]
		var id: String = al["id"]
		var approval: Dictionary = a["approval__" + id]
		var level := J.round_js(approval["score"])
		var delta: int = LOYALTY_DELTA[clampi(level, 0, 4)]
		var loyalty = U.norm(maxf(0.0, minf(100.0, float(J.nz(al.get("loyalty"), 0) + delta))))

		var decision_answer = a.get("decision__" + id)
		var picked = decision_answer.get("choice") if decision_answer is Dictionary else null
		if picked == null:
			picked = "stay"
		var decision := "stay"
		var blocked = null
		if picked == "turn_on_party":
			if loyalty < BETRAY_BELOW:
				decision = "turn_on_party"
			elif loyalty < LEAVE_BELOW:
				decision = "leave_party"
				blocked = "betrayal needs loyalty < %d (is %s); leaving instead" % [BETRAY_BELOW, J.num(loyalty)]
			else:
				blocked = "betrayal needs loyalty < %d (is %s); stays" % [BETRAY_BELOW, J.num(loyalty)]
		elif picked == "leave_party":
			if loyalty < LEAVE_BELOW:
				decision = "leave_party"
			else:
				blocked = "leaving needs loyalty < %d (is %s); stays" % [LEAVE_BELOW, J.num(loyalty)]

		var line: String
		if decision == "stay":
			# A grumbling stay (it wanted out) sounds unhappy whatever the score says
			var lines := _reaction_lines(sp)
			var line_answer = a.get("line__" + id)
			var probs = line_answer.get("probabilities") if line_answer is Dictionary else null
			line = lines[Narrate.reaction_line_index(probs, sp["reactions"], level if picked == "stay" else mini(level, 1))]
		else:
			var bank: Array = sp["reactions"]["leave"] if decision == "leave_party" else sp["reactions"]["betray"]
			line = J.pick(bank)

		var moment = null
		if events.size() > 1:
			var moment_answer = a.get("moment__" + id)
			var choice = moment_answer.get("choice") if moment_answer is Dictionary else null
			if choice is String and (choice as String).contains("_"):
				var part: String = (choice as String).split("_")[1]
				if part.is_valid_int() and int(part) >= 0 and int(part) < events.size():
					moment = events[int(part)]
		elif not events.is_empty():
			moment = events[0]
		reactions.append({
			"id": id,
			"name": al["name"],
			"approval": approval["score"],
			"delta": delta,
			"loyalty": loyalty,
			"picked": picked,
			"decision": decision,
			"blocked": blocked,
			"level": level,
			"moment": moment,
			"line": Species.fill(line, {"name": al["name"]}),
		})

	var usage = res.get("usage")
	return {
		"reactions": reactions,
		"ms": res.get("ms"),
		"inputTokens": usage.get("input_tokens") if usage is Dictionary else null,
		"questionCount": questions.size(),
		"model": res.get("model"),
		"request": {"state": state, "questions": questions},
		"answers": a,
	}


static func _reaction_lines(sp: Dictionary) -> Array:
	var r: Dictionary = sp["reactions"]
	return r["approve"] + r["neutral"] + r["disapprove"]
