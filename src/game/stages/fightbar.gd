## FIGHT: a line sweeps along a bar and you stop it near the middle. Too early or too late is a miss; the middle is a
## perfect strike. A hit hurts the monster and sours its mood, and may end the fight.
##
## With friends (the feature follow-through) a strike that lands doesn't stop the line: each friend has a mark further along the
## bar, and each press after yours is the next friend's: on its mark it lands, off it that friend's moment is gone (so hammering
## the key gets nothing). None of it costs anything. A HEAVY blow is too quick for them to follow.
extends "res://src/game/stages/stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Keepsakes = preload("res://src/rules/keepsakes.gd")
const Social = preload("res://src/rules/social.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

var _landed := {} # your strike that landed, while the friends' marks are still to come: {result, found, betrayal, nerve}
var _followed: Array = [] # the friends whose strikes landed after it
var _follow_damage := 0 # and what they did in all
var _pressed_at := -1e9 # when the last press that counted was, to let a slip of the finger go
var _swept := 0 # how many of the bar's SWEEP_STEPS parts the line has been heard to cross

## The line is heard as it goes: a tick each time it crosses another of this many parts of the bar, a note higher the nearer
## the middle (the event "sweep", step 1 at the ends to SWEEP_STEPS / 2 in the middle), so the strike has a beat to land on.
const SWEEP_STEPS := 8


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	var heavy: bool = args.get("heavy", false)
	s.menu = []
	s.hint = "ENTER STRIKE INSIDE THE RED MARK" if heavy else "ENTER STRIKE WHEN THE LINE CROSSES THE MIDDLE"
	if s.party_size() > 0:
		s.hint += " · PARTY +%d" % Combat.party_aid(s.party_size())
	if s.sharpened > 0:
		s.hint += " · WHETTED +%d" % s.sharpened
	if s.nerve > 0 and flow.feature("nerve"):
		s.hint += " · %d/%d NERVE: +%d ON HIT" % [s.nerve, Combat.NERVE_MAX, Combat.nerve_damage(s.nerve)]
	if Keepsakes.has(s, "sharp_tooth"):
		s.hint += " · TOOTH +%d" % Keepsakes.TOOTH_DAMAGE
	_landed = {}
	_followed = []
	_follow_damage = 0
	_swept = 0
	var marks := []
	if not heavy and flow.feature("follow-through"):
		var friends: Array = s.allies.filter(func(a): return not Content.table("friends").has(a.species)) # the monsters among them, as party_size counts
		for i in mini(friends.size(), Combat.FOLLOW_MARKS.size()):
			marks.append({"at": Combat.FOLLOW_MARKS[i], "who": friends[i].name, "species": friends[i].species, "state": ""})
		if not marks.is_empty():
			s.hint += " · AGAIN ON EACH FRIEND'S MARK"
			flow.coach.say("follow")
	s.bar = {"t0": flow.clock, "dur": Combat.bar_ms(s.has_ally("rock")) * (Combat.HEAVY_BAR_SCALE if heavy else 1.0), "heavy": heavy, "marks": marks, "struck": -1.0}


func handle(flow, key: String) -> void:
	if key != "confirm" or flow.state.bar == null:
		return
	if _landed.is_empty():
		await _strike(flow, flow.clock)
	else:
		await _follow(flow, flow.clock)


func tick(flow, t: float) -> void:
	var bar = flow.state.bar
	if bar == null:
		return
	var p: float = (t - bar.t0) / bar.dur
	_sweep(flow, p)
	if _landed.is_empty():
		if p >= 1.0:
			await _strike(flow, t) # too late: it swings wide
		return
	for mark in bar.marks:
		if mark.state == "" and p > float(mark.at) + Combat.FOLLOW_EDGE:
			mark.state = "lost" # the line has left it behind
	if p >= 1.0 or bar.marks.all(func(mark): return mark.state != ""):
		await _finish(flow)


## The line has gone on to `p` of the bar: said once for each part it crosses (a slow frame that crosses two says the later).
func _sweep(flow, p: float) -> void:
	var crossed := mini(int(p * SWEEP_STEPS), SWEEP_STEPS - 1)
	if crossed <= _swept:
		return
	_swept = crossed
	flow.event("sweep", {"step": SWEEP_STEPS / 2 - absi(crossed - SWEEP_STEPS / 2)})


func _strike(flow, t: float) -> void:
	var s = flow.state
	var m = s.foe
	var x := clampf((t - s.bar.t0) / s.bar.dur, 0.0, 1.0)
	if Keepsakes.has(s, "steady_hand") and absf(x - 0.5) * 2.0 < Combat.CRIT_EDGE * Keepsakes.STEADY_SCALE:
		x = 0.5 # the steady hand: anywhere on the wider mark is the middle
	var heavy: bool = s.bar.heavy
	var aid: int = Combat.party_aid(s.party_size())
	var result: Dictionary
	if heavy:
		result = Combat.heavy_strike(x, m.boss, m.species, s.has_ally("dragon"), aid + s.sharpened)
		print("fightbar: heavy strike on %s at %.2f: %s" % [m.species, x, result])
	else:
		result = Combat.strike(x, m.boss, s.has_ally("dragon"), aid + s.sharpened)
	var nerve := 0 # what nerve added to this strike
	if not result.miss:
		s.sharpened = 0
		nerve = Combat.nerve_damage(flow.encounter.spend_nerve())
		result.damage += Social.strike_bonus(m) + nerve + (Keepsakes.TOOTH_DAMAGE if Keepsakes.has(s, "sharp_tooth") else 0)
	if result.miss:
		s.bar = null
		flow.event("miss")
		var swung: Dictionary = await flow.encounter.decide(m, "fight", "YOU SWUNG")
		if heavy:
			swung.pressure_bonus = Combat.HEAVY_MISS_PRESSURE
			swung.pressure += Combat.HEAVY_MISS_PRESSURE
		await flow.encounter.after_player([State.sys_line("%s %s is %s." % [Texts.HEAVY_MISS if heavy else Texts.miss(), m.name, swung.feeling.label])], swung)
		return
	var betrayal := Social.hit(m)
	m.hp = maxi(0, m.hp - result.damage)
	flow.event("strike", {"damage": result.damage, "crit": result.crit or heavy, "nerve": nerve}) # a heavy hit sounds and flashes like a big one
	var found: String = _learn_how_it_takes_it(flow, m) if heavy else ""
	_landed = {"result": result, "found": found, "betrayal": betrayal, "nerve": nerve}
	_pressed_at = t
	if m.hp <= 0 or s.bar.marks.is_empty():
		await _finish(flow)
		return
	s.bar.struck = x # the picture marks where it fell; the line runs on to the friends' marks


## A press after your strike landed is the next friend's: their strike if the line is on their mark, their moment gone if it is
## not. A press right on top of the last one is a slip of the finger and does nothing.
func _follow(flow, t: float) -> void:
	if t - _pressed_at < Combat.FOLLOW_SLIP_MS:
		return
	_pressed_at = t
	var s = flow.state
	var m = s.foe
	var p: float = (t - s.bar.t0) / s.bar.dur
	for mark in s.bar.marks:
		if mark.state != "":
			continue
		if absf(p - float(mark.at)) <= Combat.FOLLOW_EDGE:
			mark.state = "hit"
			m.hp = maxi(0, m.hp - Combat.FOLLOW_DAMAGE)
			_followed.append(mark.who)
			_follow_damage += Combat.FOLLOW_DAMAGE
			print_verbose("fightbar: %s follows through at %.2f" % [mark.who, p])
			flow.event("follow", {"who": mark.who, "species": mark.species, "damage": Combat.FOLLOW_DAMAGE})
		else:
			mark.state = "lost"
			flow.event("sound", {"name": "miss"})
		break
	if m.hp <= 0:
		await _finish(flow)


## The strike is over, yours and theirs: the monster takes it in, and falls or winds up its answer.
func _finish(flow) -> void:
	var s = flow.state
	var m = s.foe
	var landed := _landed
	_landed = {}
	s.bar = null
	s.hint = "" # the bar is gone: its "ENTER STRIKE" would be a lie while the mind takes it in
	Combat.apply_hit_to_mood(m)
	var begging: bool = flow.encounter.begging()
	if m.hp <= 0:
		flow.encounter.judge("slay_begging" if begging else "slay")
		await flow.encounter.defeat(m, "slain")
		return
	var decision: Dictionary = await flow.encounter.decide(m, "fight", "YOU HIT IT")
	if begging:
		flow.encounter.judge("slay_begging")
	var line := "%s %s%s%s" % [Texts.hit(landed.result.damage, landed.result.crit), Texts.followed(_followed, _follow_damage), landed.found, Texts.foe_feels(m, decision.feeling)]
	if landed.nerve > 0:
		line += " Nerve added %d damage." % landed.nerve
	if landed.betrayal != "":
		line = str(landed.betrayal) + " " + line
		decision.pacified = false
	await flow.encounter.after_player([State.sys_line(line)], decision)


## The first heavy blow to land on a kind of monster shows how it takes them, and the menu says so from then on. The words for
## the log, which reach you if a tip holds the banner ("" when there is nothing to tell).
func _learn_how_it_takes_it(flow, m) -> String:
	var s = flow.state
	if s.heavy_known.has(m.species):
		return ""
	s.heavy_known[m.species] = true
	var weak := Combat.heavy_weakness(m.species)
	print("fightbar: found out how a %s takes a heavy blow (%.2f)" % [m.species, weak])
	if weak == Combat.HEAVY_PLAIN: # the number a species takes when it says nothing of its own
		return ""
	var found := Texts.heavy_found(m, weak)
	if not flow.banner_up():
		flow.announce("YOU FOUND OUT", found)
	return found + " "
