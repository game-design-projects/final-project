## The monster attacks: move the soul around the box to stay out of the lit squares. How long and how fast depends on
## how hard it presses, and how it feels shows in the attack (the feature mood-attacks, rules/dodge_run.gd). Health at zero is the
## end of the fight; surviving the time brings the menu back.
##
## Nerve (the feature nerve) is earned here: a point for every close call (dodge_run.gd) and one for a dodge with no hit in it; a
## hit shakes one out. A friendly monster's hearts heal you and please it.
extends "res://src/game/stages/stage.gd"

const Clans = preload("res://src/rules/clans.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Keepsakes = preload("res://src/rules/keepsakes.gd")
const Pace = preload("res://src/rules/pace.gd")
const Skills = preload("res://src/rules/skills.gd")
const DodgeRun = preload("res://src/rules/dodge_run.gd")
const Social = preload("res://src/rules/social.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const MOVES := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}

var _hits := 0 # how many hits this dodge has landed
var _hearts := 0 # how many hearts were caught
var _rule := {} # the attack's rule, for the hint


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	var m = s.foe
	var genre: String = flow.encounter.foe_genre(m)
	if int(m.social.get("trial", 0)) > 0:
		genre = "gates" # the dragon's telegraphed walls trial, even on a mini-game turn
	var pace := Pace.of(m, s.depth, s.struggle, s.party_size(), flow.easy_dodge)
	if flow.coach.active(): # the TIPS setting: someone who knows the game gets no slow start either
		pace = maxf(Pace.LOWEST, pace * Pace.opening(s.tally.spared + s.tally.slain + s.tally.fled))
	print("dodge: pace %.2f (B%dF, friendliness %d, struggle %.0f, %d allies%s)" % [pace, s.depth, m.meters.friendliness, s.struggle, s.allies.size(), ", elite" if m.elite else ""])
	var mood := Feelings.mood(m) if flow.feature("mood-attacks") else ""
	s.dodge = DodgeRun.start(genre, float(args.get("pressure", 1.0)), m.boss, m.turn, flow.clock, s.charms(), pace, Clans.elite() if m.elite else {}, mood)
	s.dodge.guard = Combat.party_guard(s.allies.size()) + (Keepsakes.THICK_GUARD if Keepsakes.has(s, "thick_hide") else 0)
	flow.encounter.think_ahead(m) # the mercy the menu after it needs, asked while you dodge (a heart caught changes it: then it asks again)
	if Keepsakes.has(s, "quick_feet"):
		s.dodge.nerve_window = Combat.NERVE_WINDOW_MS * Keepsakes.QUICK_WINDOW
	_hits = 0
	_hearts = 0
	if mood == "afraid":
		flow.coach.say("afraid")
	s.menu = []
	_rule = Content.table("encounter").genres[genre]
	_hint(flow)


## The keys and the attack's rule, and the block that is left (skill-combat).
func _hint(flow) -> void:
	var s = flow.state
	s.hint = "ARROWS MOVE · %s" % _rule.plain
	if s.skill_fight != null and int(s.skill_fight.block) > 0:
		s.hint += " · BLOCK %d" % s.skill_fight.block


func handle(flow, key: String) -> void:
	if flow.state.dodge != null and MOVES.has(key):
		flow.state.dodge.move(MOVES[key].x, MOVES[key].y, flow.clock if flow.feature("nerve") else -1.0)


func tick(flow, t: float) -> void:
	var s = flow.state
	var run = s.dodge
	if run == null:
		return
	for e in run.update(t, flow.rng):
		match e.type:
			"hurt":
				if s.skill_fight != null and int(s.skill_fight.block) > 0:
					e.damage = Skills.soak(s.skill_fight, e.damage)
					_hint(flow)
					if e.damage <= 0:
						run.hit_flash = -1e9 # the run flagged a hurt before the block took it whole: show the shield, not the red
						run.block_flash = t
						print("dodge: block took the hit whole")
						flow.event("shield")
						continue
				s.hp -= e.damage
				if s.hp <= 0 and Keepsakes.has(s, "second_wind") and not s.second_wind_used:
					s.second_wind_used = true
					s.hp = 1
					print("dodge: second wind, still standing on 1 HP")
					flow.event("second_wind")
				_hits += 1
				flow.event("player_hurt", {"damage": e.damage})
				if s.nerve > 0:
					s.nerve = maxi(0, s.nerve - Combat.NERVE_LOST_ON_HIT)
					flow.event("nerve", {"total": s.nerve, "how": "lost"})
				if s.hp <= 0:
					s.struggle = Pace.after_dodge(s.struggle, _hits)
					s.dodge = null
					await flow.go("dead")
					return
			"shield":
				flow.event("shield")
			"star":
				s.hp = mini(s.max_hp, s.hp + 1)
				flow.event("star")
			"heart":
				_hearts += 1
				s.hp = mini(s.max_hp, s.hp + Combat.HEART_HEAL)
				s.foe.meters.friendliness = clampf(s.foe.meters.friendliness + Combat.HEART_FRIENDLINESS, 0.0, 100.0)
				flow.event("heart")
				flow.coach.say("heart")
			"nerve":
				_earn(flow, "close")
			"beat":
				flow.event("beat")
			"sound":
				if e.name != "":
					flow.event("sound", {"name": e.name})
	if run.is_over(t):
		s.dodge = null
		s.foe.turn += 1
		s.struggle = Pace.after_dodge(s.struggle, _hits)
		if _hits == 0 and flow.feature("nerve"):
			_earn(flow, "clean")
		var odds: float = await flow.encounter.mercy(s.foe)
		var spareable: bool = odds >= 0.5
		if _hearts > 0: # it liked that: the gauge moves without a deed of yours
			flow.encounter.note_mercy(odds)
		var trial := Social.trial_over(s.foe, s)
		s.say([State.sys_line(trial if trial != "" else Texts.pauses(s.foe, spareable))])
		await flow.go("menu")


## A point of nerve, for a close call ("close") or a dodge with no hit in it ("clean").
func _earn(flow, how: String) -> void:
	var s = flow.state
	if s.nerve >= Combat.NERVE_MAX:
		return
	s.nerve += 1
	print_verbose("dodge: nerve %d (%s)" % [s.nerve, how])
	flow.event("nerve", {"total": s.nerve, "how": how})
	flow.coach.say("nerve_close" if how == "close" else "nerve")
