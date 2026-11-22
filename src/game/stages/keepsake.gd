## A champion is out of your way and leaves three keepsakes, of which you take one (rules/keepsakes.gd): it is yours for the rest
## of the run. There is no way past this but to choose, and the fight's end goes on from there (encounter.leave_fight): back to
## the walk, or on to the next fight when one is queued. The Hoard's vault offers its three the same way, out of the walk (#161):
## there the choice goes back to the walk directly (`args.then` = "walk").
extends "res://src/game/stages/list_stage.gd"

const Keepsakes = preload("res://src/rules/keepsakes.gd")
const State = preload("res://src/game/state.gd")

var _offered: Array = []
var _then := "fight" # where the choice goes on to: the fight's end, or the walk a vault stopped
var _vault := false # offered by the Hoard's vault rather than a champion, which changes the words and nothing else


## `args.offered` is the ids (Keepsakes.offer), `args.from` the champion's name, `args.lines` what the log said as the fight
## ended, `args.vault` and `args.then` a vault out of the walk.
func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	s.foe = null
	_offered = args.get("offered", [])
	_then = str(args.get("then", "fight"))
	_vault = bool(args.get("vault", false))
	s.menu = _offered.map(func(id): return {"label": Keepsakes.name_of(id), "sub": sentence(Keepsakes.text_of(id)), "gold": true})
	s.selected = 0
	s.vignette = "keepsakes"
	s.hint = "ENTER TAKE"
	var ended: Array = args.get("lines", []).filter(func(l): return l.kind == "sys").slice(-1) # how the fight ended
	var ask := str(Keepsakes.table().vault.ask) if _vault else str(Keepsakes.table().ask) % str(args.get("from", "The champion"))
	s.say(ended + [State.sys_line(ask)])
	print("keepsake: %s offers %s%s" % ["the vault" if _vault else str(args.get("from", "?")), _offered, " (the walk goes on from it)" if _then == "walk" else ""])


func pick(flow, index: int) -> void:
	var s = flow.state
	var id: String = _offered[index]
	Keepsakes.take(s, id)
	print("keepsake: took %s (%s)" % [id, s.summary()])
	flow.event("keepsake", {"id": id})
	flow.announce(Keepsakes.name_of(id), sentence(Keepsakes.text_of(id)))
	var lines := [State.sys_line(str(Keepsakes.table().taken) % [Keepsakes.name_of(id), Keepsakes.text_of(id)])]
	if _then == "walk": # the vault was met on the walk, and the walk is where the choice leaves you
		await flow.go("explore", {"lines": lines})
		return
	await flow.encounter.leave_fight(lines)


## Esc is the pause menu, as on the walk: the choice waits.
func cancel(flow) -> void:
	flow.event("pause_requested")


## "every hit costs 1 less" -> "Every hit costs 1 less."
static func sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1) + "."
