## The monster attacks: move the soul around the box to stay out of the lit squares. How long and how fast depends on
## how hard it presses. Health at zero is the end of the fight; surviving the time brings the menu back.
extends "res://src/game/stages/stage.gd"

const Content = preload("res://src/rules/content.gd")
const DodgeRun = preload("res://src/rules/dodge_run.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const MOVES := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	var m = s.foe
	var genre: String = flow.encounter.foe_genre(m)
	s.dodge = DodgeRun.start(genre, float(args.get("pressure", 1.0)), m.boss, m.turn, flow.clock, s.charms())
	s.menu = []
	s.hint = "ARROWS MOVE · %s" % Content.table("encounter").genres[genre].rule


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
				s.hp -= e.damage
				flow.event("player_hurt", {"damage": e.damage})
				if s.hp <= 0:
					s.dodge = null
					await flow.go("dead")
					return
			"shield":
				flow.event("shield")
			"beat":
				flow.event("beat")
			"sound":
				if e.name != "":
					flow.event("sound", {"name": e.name})
	if run.is_over(t):
		s.dodge = null
		s.foe.turn += 1
		var spareable: bool = await flow.encounter.spareable(s.foe)
		s.say([State.sys_line(Texts.pauses(s.foe, spareable))])
		await flow.go("menu")
