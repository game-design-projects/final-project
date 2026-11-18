## A champion is out of your way and leaves three keepsakes, of which you take one (rules/keepsakes.gd): it is yours for the rest
## of the run. There is no way past this but to choose, and the fight's end goes on from there (encounter.leave_fight): back to
## the walk, or on to the next fight when one is queued.
extends "res://src/game/stages/list_stage.gd"

const Keepsakes = preload("res://src/rules/keepsakes.gd")
const State = preload("res://src/game/state.gd")

var _offered: Array = []


## `args.offered` is the ids (Keepsakes.offer), `args.from` the champion's name, `args.lines` what the log said as the fight ended.
func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	s.foe = null
	_offered = args.get("offered", [])
	s.menu = _offered.map(func(id): return {"label": Keepsakes.name_of(id), "sub": sentence(Keepsakes.text_of(id)), "gold": true})
	s.selected = 0
	s.vignette = "keepsakes"
	s.hint = "ENTER TAKE"
	var ended: Array = args.get("lines", []).filter(func(l): return l.kind == "sys").slice(-1) # how the fight ended
	s.say(ended + [State.sys_line(str(Keepsakes.table().ask) % str(args.get("from", "The champion")))])
	print("keepsake: %s leaves %s" % [args.get("from", "?"), _offered])


func pick(flow, index: int) -> void:
	var s = flow.state
	var id: String = _offered[index]
	Keepsakes.take(s, id)
	print("keepsake: took %s (%s)" % [id, s.summary()])
	flow.event("keepsake", {"id": id})
	flow.announce(Keepsakes.name_of(id), sentence(Keepsakes.text_of(id)))
	await flow.encounter.leave_fight([State.sys_line(str(Keepsakes.table().taken) % [Keepsakes.name_of(id), Keepsakes.text_of(id)])])


## Esc is the pause menu, as on the walk: the choice waits.
func cancel(flow) -> void:
	flow.event("pause_requested")


## "every hit costs 1 less" -> "Every hit costs 1 less."
static func sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1) + "."
