## The monster attacks: move the soul around the box to stay out of the lit squares. How long and how fast depends on
## how hard it presses. Health at zero is the end of the fight; surviving the time brings the menu back.
extends "res://src/game/stages/stage.gd"

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Pace = preload("res://src/rules/pace.gd")
const Skills = preload("res://src/rules/skills.gd")
const DodgeRun = preload("res://src/rules/dodge_run.gd")
const Social = preload("res://src/rules/social.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const MOVES := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}

var _hits := 0 # how many hits this dodge has landed
var _rule := {} # the attack's rule, for the hint


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	var m = s.foe
	var genre: String = flow.encounter.foe_genre(m)
	if flow.feature("initiated-dialogue") and int(m.social.get("trial", 0)) > 0:
		genre = "gates" # the dragon's telegraphed walls trial, even on a mini-game turn
	var pace := Pace.of(m, s.depth, s.struggle, s.party_size(), flow.easy_dodge)
	if flow.coach.active(): # the TIPS setting: someone who knows the game gets no slow start either
		pace = maxf(Pace.LOWEST, pace * Pace.opening(s.tally.spared + s.tally.slain + s.tally.fled))
	print("dodge: pace %.2f (B%dF, friendliness %d, struggle %.0f, %d allies)" % [pace, s.depth, m.meters.friendliness, s.struggle, s.allies.size()])
	s.dodge = DodgeRun.start(genre, float(args.get("pressure", 1.0)), m.boss, m.turn, flow.clock, s.charms(), pace)
	s.dodge.guard = Combat.party_guard(s.allies.size())
	_hits = 0
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
		flow.state.dodge.move(MOVES[key].x, MOVES[key].y)


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
				_hits += 1
				flow.event("player_hurt", {"damage": e.damage})
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
			"beat":
				flow.event("beat")
			"sound":
				if e.name != "":
					flow.event("sound", {"name": e.name})
	if run.is_over(t):
		s.dodge = null
		s.foe.turn += 1
		s.struggle = Pace.after_dodge(s.struggle, _hits)
		var spareable: bool = await flow.encounter.spareable(s.foe)
		var trial := Social.trial_over(s.foe, s) if flow.feature("initiated-dialogue") else ""
		s.say([State.sys_line(trial if trial != "" else Texts.pauses(s.foe, spareable))])
		await flow.go("menu")
