## A spared monster asks to come along, and you answer: there is no second roll behind your back. Taking it adds its charm to
## the party; letting it go leaves you a parting gift. Either way a monster you made peace with leaves you a little healed.
## How much it wanted to come sets how loyal it starts out. A full party can only say goodbye.
extends "res://src/game/stages/list_stage.gd"

const Allies = preload("res://src/rules/allies.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const State = preload("res://src/game/state.gd")
const Texts = preload("res://src/game/texts.gd")

const TAKE := 0

var _wants := -1.0 # how much it wants to come along; below 0 while the mind is still thinking about it
var _room := false


## `args.lines` is what the fight said before this: a level the spare made, which the log keeps in front of the question.
func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	var m = s.foe
	_room = s.party_size() < Combat.PARTY_MAX
	_wants = -1.0
	var charm: Dictionary = Content.table("encounter").charms[m.species]
	var gift: Dictionary = Allies.gift(m.species)
	var lines: Array = args.get("lines", []).duplicate()
	var asks = flow.encounter.foe_line(m, "join_party")
	if asks != null:
		lines.append(asks)
	lines.append(State.sys_line(Texts.asks_along(m, charm, _room)))
	s.say(lines)
	s.menu = [{"label": "GO IN PEACE", "sub": Texts.gift_tip(gift)}]
	if _room:
		s.menu.push_front({"label": "COME ALONG", "sub": "%s: %s. %s" % [charm.name, charm.text, Texts.party_tip(s.party_size())]})
	s.hint = "ENTER ANSWER · 1-%d" % s.menu.size()
	s.mind_rows = flow.encounter.pending_rows
	flow.encounter.pending_rows = []
	_think_join(flow, m) # not awaited: the answer only sets how loyal it starts, so the choice is yours at once


## How much `m` wants to come along, asked while you choose; the mind card shows it when it comes.
func _think_join(flow, m) -> void:
	var wants: float = await flow.mind.join(m)
	if flow.state.foe != m or flow.state.stage != "ask":
		return
	_wants = wants
	flow.state.mind_rows = [{"id": "join", "label": "DOES IT WANT TO COME ALONG?", "answer": wants}] + flow.state.mind_rows
	print("ask: %s asks to join (wants %d%%, room: %s)" % [m.name, roundi(wants * 100.0), _room])


func pick(flow, index: int) -> void:
	if _wants < 0.0:
		_wants = await flow.mind.join(flow.state.foe) # chosen before the mind answered: the same question, already out
	if _room and index == TAKE:
		await flow.encounter.take_along(flow.state.foe, _wants)
	else:
		await flow.encounter.part_ways(flow.state.foe)


## An answer is owed: Esc is the pause menu here, as in the fight's own menu.
func cancel(flow) -> void:
	flow.event("pause_requested")
