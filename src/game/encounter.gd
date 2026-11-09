## The parts of a fight that more than one stage needs: asking the mind how the monster feels, what the allies think of
## a deed, how a fight ends, trying it again. Stages call these and then say which stage comes next.
extends RefCounted

const Ally = preload("res://src/game/ally.gd")
const Allies = preload("res://src/rules/allies.gd")
const Clans = preload("res://src/rules/clans.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Floors = preload("res://src/rules/floors.gd")
const Moods = preload("res://src/rules/moods.gd")
const Monster = preload("res://src/rules/monster.gd")
const Odds = preload("res://src/rules/odds.gd")
const Reveal = preload("res://src/rules/reveal.gd")
const Roaming = preload("res://src/rules/roaming.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const REACTION_LINES := {"good": "pleased", "bad": "stung", "sad": "hurt", "fear": "scared", "odd": "puzzled"} # how a deed landed -> what it says about it

var flow
## Allies' reactions to the last deed, said with the next message.
var pending_notes: Array = []
var pending_rows: Array = []
## The mercy odds as the player last saw them, so a deed can say how far it moved them. Below 0 when not known yet.
var known_mercy := -1.0


func _init(owner) -> void:
	flow = owner


## The genre the monster fights in this turn.
func foe_genre(m) -> String:
	return flow.state.genre_of(m)


## A line of speech from the monster ({kind: "say", who, text}), or null if its species has none of that kind.
## Tells the sound to voice it.
func foe_line(m, kind: String, who := ""):
	var pool: Array = Content.species(m.species).lines.get(kind, [])
	if pool.is_empty():
		return null
	var text := Content.fill(flow.rng.pick(pool), {"name": _spoken(m.name), "target": "you", "kin": _spoken(who)})
	flow.event("shout", {"text": text, "species": m.species, "boss": m.boss})
	return State.speech(m.name, text)


## A NAME as it is said out loud: Name.
static func _spoken(a_name: String) -> String:
	return a_name.left(1) + a_name.substr(1).to_lower()


## `m` meets you, having heard what you did to its clan. Its mood has moved by the time this returns. The line it says about
## it, or its usual greeting when it has heard nothing new.
func greeting(m):
	if not flow.feature("clans"):
		return foe_line(m, "converse")
	var news: Dictionary = Clans.hear(m, flow.state)
	if news.is_empty():
		return foe_line(m, "converse")
	flow.event("word_spread", {"clan": news.clan, "tone": news.tone})
	if flow.feature("mood-cues"):
		flow.event("mood", {"tone": news.tone})
	if not flow.banner_up():
		flow.announce("WORD HAS SPREAD", Clans.news(news))
	return foe_line(m, news.kind, news.who)


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
	var id := Odds.pick_by_odds(flow.dice, feelings)
	var feeling := Feelings.apply(m, id)
	if not act is String and flow.feature("recruit-step"):
		Feelings.warm_up(m, feeling)
	var after: Dictionary = await flow.mind.mercy_and_pressure(m) # one request for Jev: both are about the monster as it is now
	var mercy: float = after.mercy
	var pressure: float = after.pressure
	if not act is String and flow.feature("reveal"):
		var learned := Reveal.learn(m, m.last_intent, str(feeling.get("tone", "")))
		if not learned.is_empty():
			print("encounter: found out about %s: %s" % [m.name, " ".join(learned)])
			if not flow.banner_up():
				flow.announce("YOU FOUND OUT", " ".join(learned))
	if flow.feature("mood-cues"):
		flow.event("mood", {"tone": str(feeling.get("tone", "odd"))})
		if known_mercy >= 0.0 and known_mercy < Odds.LIKELY and mercy >= Odds.LIKELY:
			flow.event("wants_join")
	var note := _mercy_moved(mercy)
	print_verbose("encounter: %s (%s) %s -> %s, mercy %d%%, pressure %.2f" % [m.name, ", ".join(m.traits), m.last_intent, id, roundi(mercy * 100.0), pressure])
	var rows := []
	if words != null:
		rows.append({"id": "words", "label": "WHAT DID YOUR WORDS MEAN?", "answer": words})
	rows.append({"id": "feeling", "label": "HOW DOES IT FEEL? (%s)" % act_label, "answer": feelings, "picked": id})
	rows.append({"id": "mercy", "label": "WILL IT ACCEPT MERCY?", "answer": mercy})
	rows.append({"id": "pressure", "label": "HOW HARD DOES IT ATTACK?", "answer": pressure})
	flow.state.mind_rows = rows + pending_rows
	pending_rows = []
	return {"id": id, "feeling": feeling, "pressure": pressure, "pacified": Feelings.pacifies(id), "note": note, "told": not act is String}


## Says that the mercy odds moved, and returns the words for it for the log ("" when they stayed, or the feature is off).
func _mercy_moved(mercy: float) -> String:
	var before := known_mercy
	known_mercy = mercy
	if before < 0.0 or not flow.feature("mercy-link") or roundi(before * 100.0) == roundi(mercy * 100.0):
		return ""
	flow.event("mercy_changed", {"from": before, "to": mercy})
	return Texts.mercy_moved(before, mercy)


## After the player acts: show what happened, then the monster either holds back or winds up its attack.
func after_player(lines: Array, decision: Dictionary, show_attack_line := true) -> void:
	if flow.state.skill_fight != null:
		flow.state.skill_fight.turn_over = true # the next menu is a new turn (skill-combat)
	if flow.feature("dynamic-moods"):
		var cue := Moods.advance(flow.state.foe, flow.dice)
		if cue != "":
			lines.append(State.sys_line(cue))
		# Mood bounds apply to the monster; missing a heavy strike still adds its full penalty.
		var bonus := float(decision.get("pressure_bonus", 0.0))
		decision.pressure = clampf(float(decision.pressure) - bonus + Moods.shift(flow.state.foe, "pressure"), 0.0, 3.0) + bonus
	if decision.get("note", "") != "" and not lines.is_empty():
		lines[0].text += " " + decision.note
	lines = lines + _take_notes()
	var reaction = _reaction(decision)
	if reaction != null:
		lines.append(reaction)
		show_attack_line = false
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
	var foe_spoke: bool = lines.any(func(line): return line.kind == "say" and line.who == flow.state.foe.name)
	await flow.go("wait", {"pressure": decision.pressure, "prompt": foe_spoke and flow.feature("ambush-prompt")})


## What the monster says about what was just done to it, in its own words (reveal): null when it has no strong opinion.
func _reaction(decision: Dictionary):
	if not decision.get("told", false) or not flow.feature("reveal"):
		return null
	var kind: String = REACTION_LINES.get(str(decision.feeling.get("tone", "")), "")
	return null if kind == "" else foe_line(flow.state.foe, kind)


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
		var verdict := Allies.judge(a, deed, flow.dice)
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
	if flow.feature("clans"):
		Clans.record(s, m, how)
	if m.boss and flow.feature("boss-reward"):
		_reward_for_champion(m)
	_open_purse(m)
	if how == "spared" and allow_join and flow.feature("recruit-step"):
		await flow.go("ask")
		return
	var joined := false
	var line = null
	var rows := []
	if how == "spared" and allow_join:
		var room: bool = s.party_size() < Combat.PARTY_MAX
		var wants: float = await flow.mind.join(m) if room else 0.0
		joined = Odds.succeeds(flow.dice, wants)
		rows.append({"id": "join", "label": "DOES IT WANT TO COME ALONG?" if room else "DOES IT WANT TO COME ALONG? (PARTY FULL)", "answer": wants, "picked": joined})
		if joined:
			s.allies.append(Ally.make(m.species, m.name, Allies.start_loyalty(flow.dice)))
			s.tally.recruited += 1
			flow.event("recruited", {"species": m.species})
			if flow.feature("clans"):
				Clans.record(s, m, "recruited")
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
	await leave_fight(lines)


## Whatever it was carrying is yours, however it ended.
func _open_purse(m) -> void:
	if m.purse <= 0:
		return
	var s = flow.state
	var numbers: Dictionary = Content.table("npcs").lurkers
	s.gold += m.purse
	print("encounter: %s leaves %d gold" % [m.name, m.purse])
	if not flow.banner_up():
		flow.announce(numbers.purse_title, numbers.purse_line % [m.name, m.purse])
	m.purse = 0


## A champion beaten or won over leaves you stronger, however it ended.
func _reward_for_champion(m) -> void:
	var s = flow.state
	var reward: Dictionary = Floors.boss_reward()
	s.max_hp += int(reward.max_hp)
	var healed := _heal(reward.heal)
	flow.announce(Texts.champion_down(m), Texts.stronger(int(reward.max_hp), healed))
	print("encounter: %s is out of the way: max HP %d, healed %d" % [m.name, s.max_hp, healed])


## The answer at the ask stage: it comes along. Nothing is rolled: it asked and you said yes.
func take_along(m, wants: float) -> void:
	var s = flow.state
	s.allies.append(Ally.make(m.species, m.name, Allies.eager_loyalty(flow.dice, wants)))
	s.tally.recruited += 1
	flow.event("recruited", {"species": m.species})
	if flow.feature("clans"):
		Clans.record(s, m, "recruited")
	var charm: Dictionary = Content.table("encounter").charms[m.species]
	var healed := _heal(Allies.gift(m.species).heal)
	flow.announce(Texts.joined_title(m), "%s: %s" % [charm.name, charm.text])
	print("encounter: %s joins, loyalty %.0f, healed %d" % [m.name, s.allies.back().loyalty, healed])
	await leave_fight([State.sys_line(Texts.joined(m, charm, healed))] + _take_notes())


## The answer at the ask stage: it goes its own way, and leaves you something.
func part_ways(m) -> void:
	var s = flow.state
	var gift: Dictionary = Allies.gift(m.species)
	s.gold += int(gift.gold)
	var healed := _heal(gift.heal)
	print("encounter: %s leaves a gift: %d gold, healed %d" % [m.name, gift.gold, healed])
	var line = foe_line(m, "leave_peacefully")
	var lines := [line] if line != null else []
	await leave_fight(lines + [State.sys_line(Texts.parted(int(gift.gold), healed))] + _take_notes())


## Up to `amount` health back; returns how much it was.
func _heal(amount) -> int:
	var s = flow.state
	var before: int = s.hp
	s.hp = mini(s.max_hp, s.hp + int(amount))
	return s.hp - before


## The fight is over: the log says how, and the party is back to walking, or in the personality slice on to its second
## bandit (the intro keeps the line that says how this fight ended). There is no screen to confirm in between.
func leave_fight(lines: Array) -> void:
	if not flow.slice_queue.is_empty():
		await flow.go("intro", {"foe": flow.slice_queue.pop_front(), "before": lines})
		return
	flow.end_slice()
	await flow.go("explore", {"lines": lines})


## Out of the fight with nothing owed: no gold, no grudge, and it heals up as if you were never there.
func slip_away(m, line: String) -> void:
	var s = flow.state
	s.tally.fled += 1
	flow.event("sound", {"name": "flee"})
	judge("flee")
	flow.end_slice()
	m.hp = m.max_hp
	Roaming.hold(m)
	print("encounter: slipped away from %s" % m.name)
	await flow.go("explore", {"lines": [State.sys_line(line)] + _take_notes()})


## A fair cut of gold to stand down (bandits and snakes). `label` names the offer; `words` is what was read from a typed one.
func offer_cut(m, label: String, words = null) -> void:
	var s = flow.state
	if s.gold < Combat.CUT_COST:
		s.say([State.sys_line(Texts.cut_too_poor(s.gold, words != null))])
		await flow.go("menu")
		return
	var accepted := Odds.succeeds(flow.dice, Odds.cut_odds(m))
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
	s.items = snap.get("items", []).duplicate()
	s.sharpened = snap.get("sharpened", 0)
	s.allies = snap.allies.map(func(a): return Ally.from_dict(a))
	s.tally = snap.tally.duplicate()
	pending_notes = []
	pending_rows = []
	print("encounter: trying %s again" % fresh.name)
	await flow.go("intro", {"foe": fresh})
