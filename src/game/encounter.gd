## The parts of a fight that more than one stage needs: asking the mind how the monster feels, what the allies think of
## a deed, how a fight ends, trying it again. Stages call these and then say which stage comes next.
extends RefCounted

const Ally = preload("res://src/game/ally.gd")
const Allies = preload("res://src/rules/allies.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Monster = preload("res://src/rules/monster.gd")
const Odds = preload("res://src/rules/odds.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

var flow
## Allies' reactions to the last deed, said with the next message.
var pending_notes: Array = []
var pending_rows: Array = []


func _init(owner) -> void:
	flow = owner


## The genre the monster fights in this turn: a champion cycles through all of them.
func foe_genre(m) -> String:
	if not m.boss:
		return m.genre
	var genres: Array = Content.table("encounter").boss.genres
	return genres[m.turn % genres.size()]


## A line of speech from the monster ({kind: "say", who, text}), or null if its species has none of that kind.
## Tells the sound to voice it.
func foe_line(m, kind: String):
	var pool: Array = Content.species(m.species).lines.get(kind, [])
	if pool.is_empty():
		return null
	var text := Content.fill(flow.rng.pick(pool), {"name": m.name.left(1) + m.name.substr(1).to_lower(), "target": "you"})
	flow.event("shout", {"text": text, "species": m.species, "boss": m.boss})
	return State.speech(m.name, text)


func spareable(m) -> bool:
	return await flow.mind.mercy(m) >= 0.5


## One round of the mind: how `m` feels about `act` ("fight", or [{intent, w}] for an ACT button or typed words), and how
## hard it will attack. Applies the feeling to its meters. `words` is what read_words said, for typed lines.
func decide(m, act, act_label: String, words = null) -> Dictionary:
	if words != null:
		m.last_intent = Odds.top(words)
	elif act is String:
		m.last_intent = act
	elif not act.is_empty():
		m.last_intent = act[0].intent
	var feelings: Dictionary
	if act is String:
		feelings = await flow.mind.feeling_when_hit(m)
	else:
		feelings = await flow.mind.feeling_when_told(m, act)
	var id := Odds.pick_by_odds(flow.rng, feelings)
	var feeling := Feelings.apply(m, id)
	var mercy: float = await flow.mind.mercy(m)
	var pressure: float = await flow.mind.pressure(m)
	print_verbose("encounter: %s (%s) %s -> %s, mercy %d%%, pressure %.2f" % [m.name, ", ".join(m.traits), m.last_intent, id, roundi(mercy * 100.0), pressure])
	var rows := []
	if words != null:
		rows.append({"id": "words", "label": "WHAT DID YOUR WORDS MEAN?", "answer": words})
	rows.append({"id": "feeling", "label": "HOW DOES IT FEEL? (%s)" % act_label, "answer": feelings, "picked": id})
	rows.append({"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "answer": mercy})
	rows.append({"id": "pressure", "label": "HOW HARD DOES IT ATTACK?", "answer": pressure})
	flow.state.mind_rows = rows + pending_rows
	pending_rows = []
	return {"id": id, "feeling": feeling, "pressure": pressure, "pacified": Feelings.pacifies(id)}


## After the player acts: show what happened, then the monster either holds back or winds up its attack.
func after_player(lines: Array, decision: Dictionary, show_attack_line := true) -> void:
	lines = lines + _take_notes()
	if decision.pacified:
		lines.append(State.sys_line(Texts.NOT_ATTACKING))
		flow.state.say(lines)
		await flow.go("menu")
		return
	if show_attack_line:
		var attack = foe_line(flow.state.foe, "attack")
		if attack != null:
			lines.append(attack)
	flow.state.say(lines)
	await flow.go("wait", {"pressure": decision.pressure})


func _take_notes() -> Array:
	var out := []
	for n in pending_notes:
		out.append(State.speech(n.who, n.text))
	pending_notes = []
	return out


## Each ally with an opinion judges a deed ("slay", "spare", "flee", or a kind of words). Their reactions wait in
## pending_notes to be said with the next message.
func judge(deed: String) -> void:
	var s = flow.state
	for a in s.allies.duplicate():
		if deed == "" or not Allies.has_opinion(a.species, deed):
			continue
		var verdict := Allies.judge(a, deed, flow.rng)
		pending_rows.append({"id": "judge-" + a.name, "label": "%s JUDGES IT (0 HATES - 4 LOVES)" % a.name, "answer": verdict.score, "odds": verdict.odds})
		var reactions: Dictionary = Content.species(a.species).reactions
		if verdict.reaction != "":
			pending_notes.append({"who": a.name, "text": Content.fill(flow.rng.pick(reactions[verdict.reaction]), {"name": a.name, "target": "you"})})
		if verdict.leaves:
			s.allies.erase(a)
			s.tally.left += 1
			flow.event("ally_left", {"species": a.species})
			pending_notes.append({"who": a.name, "text": Content.fill(flow.rng.pick(reactions.leave), {"name": a.name}) + " " + Texts.ally_gone(a.charm().name)})


## The monster is out of the fight, spared or slain. A spared one may ask to come along (unless `allow_join` is off, as
## when it took a cut of gold and left), if there's room. `settlement` replaces the usual verdict line.
func defeat(m, how: String, allow_join := true, settlement := "") -> void:
	var s = flow.state
	m.gone = how
	s.tally[how] += 1
	flow.event(how, {"boss": m.boss})
	var joined := false
	var line = null
	var rows := []
	if how == "spared" and allow_join:
		var room: bool = s.allies.size() < Combat.PARTY_MAX
		var wants: float = await flow.mind.join(m) if room else 0.0
		joined = flow.rng.chance(wants)
		rows.append({"id": "join", "label": "DOES IT WANT TO COME ALONG?" if room else "DOES IT WANT TO COME ALONG? (PARTY FULL)", "answer": wants, "picked": joined})
		if joined:
			s.allies.append(Ally.make(m.species, m.name, Allies.start_loyalty(flow.rng)))
			s.tally.recruited += 1
			flow.event("recruited", {"species": m.species})
		line = foe_line(m, "join_party" if joined else "leave_peacefully")
	elif how == "spared":
		line = foe_line(m, "leave_peacefully")
	var verdict: String
	if how == "spared":
		verdict = settlement if settlement != "" else Texts.verdict_spared(joined, Content.table("encounter").charms[m.species])
	else:
		verdict = Texts.VERDICT_SLAIN
	var lines := [line if line != null else State.sys_line(Texts.falls(m)), State.sys_line(verdict)] + _take_notes()
	s.mind_rows = rows + pending_rows
	pending_rows = []
	s.say(lines)
	await flow.go("result")


## A fair cut of gold to stand down (bandits and snakes). `label` names the offer; `words` is what was read from a typed one.
func offer_cut(m, label: String, words = null) -> void:
	var s = flow.state
	if s.gold < Combat.CUT_COST:
		s.say([State.sys_line(Texts.cut_too_poor(s.gold, words != null))])
		await flow.go("menu")
		return
	var accepted := Odds.succeeds(flow.rng, Odds.cut_odds(m), flow.fixed_roll)
	var refusal := Texts.cut_refused(m) # worded from how it felt before this offer shifts its mood
	var decision := await decide(m, [{"intent": "gold", "w": 1.0}], label, words)
	judge("gold")
	if accepted:
		s.gold -= Combat.CUT_COST
		print("encounter: %s took a %d gold cut; %d gold left" % [m.name, Combat.CUT_COST, s.gold])
		await defeat(m, "spared", false, Texts.cut_accepted(m))
		return
	flow.event("sound", {"name": "bad"})
	await after_player([State.sys_line(refusal)], decision)


## Dying: start the same fight again from how it began (healed, with the purse and party it began with).
func retry_fight() -> void:
	var s = flow.state
	var snap: Dictionary = s.encounter_start
	var fresh = Monster.from_dict(snap.foe)
	s.floor_map.monsters[s.floor_map.monsters.find(s.foe)] = fresh
	s.hp = s.max_hp
	s.gold = snap.gold
	s.allies = snap.allies.map(func(a): return Ally.from_dict(a))
	s.tally = snap.tally.duplicate()
	pending_notes = []
	pending_rows = []
	print("encounter: trying %s again" % fresh.name)
	await flow.go("intro", {"foe": fresh})
