## A clan's asker (rules/envoys.gd): what it wants of you, a line for each of its requests still to do, and the handing over of
## the ones that are done at it. In a clan's hall the one you walk into is its lord, which says its piece a line at a time and
## then pays. Nothing here takes a turn.
extends "res://src/game/stages/list_stage.gd"

const Clans = preload("res://src/rules/clans.gd")
const Envoys = preload("res://src/rules/envoys.gd")
const State = preload("res://src/game/state.gd")

var _who := {} # the asker or the lord, as the floor holds it
var _rows: Array = [] # what each line of the menu does: {do: "take" | "give" | "say" | "next" | "leave", request}
var _page := 0 # how far into its piece a lord is


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	if args.has("who"):
		_who = args.who
		_page = int(args.get("page", 0))
	s.hint = "ENTER CHOOSE · ESC LEAVE"
	if _who.get("lord", false):
		_lord(flow)
		return
	var t := Envoys.table()
	var clan := str(_who.clan)
	var heavy: bool = flow.feature("heavy-strike") and not flow.feature("skill-combat") # the menu's HEAVY (stages/menu.gd)
	var open := Envoys.open_for(s, clan).filter(func(r): return Envoys.can_do(r, heavy))
	var said := []
	_rows = []
	s.menu = []
	for r in open:
		var words := Envoys.speak(s, r)
		said.append(State.speech(str(_who.name), words))
		var now := Envoys.status(s, r)
		if now == "new":
			_add(s, str(r.label), str(r.sub), "take", r)
		elif now == "ready" and str(r.kind) in Envoys.SAID_AT:
			_add(s, str(r.label), str(r.sub), "say", r)
		elif now == "ready":
			var friend = Envoys.friend_for(s, r)
			var label := str(r.give) % (friend.name if friend != null else int(r.count))
			_add(s, label, str(t.lines.pay_sub) % [int(t.pays.gold), int(t.pays.heal)], "give", r)
		else:
			_add(s, str(r.label), str(r.sub), "leave", r)
	if open.is_empty():
		said.append(State.sys_line(str(t.lines.nothing_left) % str(_who.name)))
		if s.gates.has(clan):
			said.append(State.sys_line(str(t.lines.open_line)))
	if not said.is_empty() and said[0].kind == "say":
		flow.event("shout", {"text": said[0].text, "species": str(_who.species), "boss": false})
	s.say(said)
	_add(s, str(t.lines.leave if open.is_empty() else t.lines.not_now), str(t.lines.not_now_sub), "leave", {})
	print("envoy: %s of %s, %d to do" % [_who.name, clan, open.size()])


func _add(s, label: String, sub: String, what: String, r: Dictionary) -> void:
	s.menu.append({"label": label, "sub": sub})
	_rows.append({"do": what, "request": r})


func pick(flow, index: int) -> void:
	var s = flow.state
	var row: Dictionary = _rows[index]
	var r: Dictionary = row.request
	match str(row.do):
		"take":
			Envoys.take(s, str(r.id))
			flow.event("sound", {"name": "good"})
			if str(r.kind) in Envoys.SAID_AT:
				await flow.go("envoy_say", {"who": _who, "request": r})
			elif Envoys.status(s, r) == "ready":
				await flow.go("envoy", {"who": _who}) # the friend or the gold is here already: the line to hand it over
			else:
				await flow.go("explore", {"lines": [State.sys_line(str(r.sub) + ".")]})
		"say":
			await flow.go("envoy_say", {"who": _who, "request": r})
		"give":
			await _give(flow, r)
		"next":
			await flow.go("envoy", {"who": _who, "page": _page + 1})
		_:
			await cancel(flow)


func cancel(flow) -> void:
	if _who.get("lord", false):
		await flow.go("explore", {"lines": []})
		return
	await flow.go("explore", {"lines": [State.sys_line(str(Envoys.table().lines.farewell) % str(_who.name))]})


## A friend or the gold is handed over, and the request is done.
func _give(flow, r: Dictionary) -> void:
	var s = flow.state
	var lines := []
	var done_words := str(r.done)
	if str(r.kind) == "bring":
		var friend = Envoys.friend_for(s, r)
		if friend == null:
			await cancel(flow)
			return
		if done_words.contains("%s"):
			done_words = done_words % Envoys.spoken(friend.name)
		s.allies.erase(friend)
		flow.event("ally_left", {"species": friend.species})
		var gone := str(Envoys.table().lines[str(r.gone)])
		lines.append(State.sys_line(gone % ([friend.name, str(_who.name)] if gone.count("%s") == 2 else [friend.name])))
		print("envoy: %s is handed over" % friend.name)
	elif str(r.kind) == "gold":
		s.gold -= int(r.count)
		print("envoy: %d gold handed over" % int(r.count))
	lines.push_front(State.speech(str(_who.name), done_words))
	await finished(flow, r, lines)


## A request is done, here or anywhere: it pays, the picture says so, and the log carries `lines` and what it opened. Goes back
## to the walk when it was done at the asker (`to_walk`); a fight's end carries the lines itself.
static func finished(flow, r: Dictionary, lines: Array, to_walk := true) -> Array:
	var s = flow.state
	var t := Envoys.table()
	var got := Envoys.finish(s, str(r.id))
	if got.is_empty():
		return lines
	var clan_name := Clans.title(str(r.clan))
	flow.event("sound", {"name": "good"})
	var paid := str(t.lines.done_line) % [int(got.gold), int(got.healed), clan_name]
	if not flow.banner_up():
		flow.announce(str(t.lines.done_title), paid)
	else:
		lines.append(State.sys_line(paid))
	if str(got.opened) != "":
		lines.append(State.sys_line("%s. %s" % [str(t.lines.open_title) % clan_name.to_upper(), str(t.lines.open_line)]))
	if to_walk:
		await flow.go("explore", {"lines": lines})
	return lines


# ---------------------------------------------------------------- the lord, in its hall

func _lord(flow) -> void:
	var s = flow.state
	var t := Envoys.table()
	var clan := str(_who.clan)
	var piece: Array = Envoys.entry(clan).lord_says
	_rows = []
	s.menu = []
	if s.lords_met.has(clan) and _page == 0:
		s.say([State.sys_line(str(t.hall.again) % str(_who.name))])
		_add(s, str(t.lines.leave), str(t.lines.not_now_sub), "leave", {})
		return
	var said := []
	if _page == 0:
		said.append(State.sys_line("%s, %s." % [_who.name, _who.title]))
	var words := str(piece[mini(_page, piece.size() - 1)])
	said.append(State.speech(str(_who.name), words))
	flow.event("shout", {"text": words, "species": str(_who.species), "boss": false})
	if _page >= piece.size() - 1: # its piece is said: it pays, and the clan stands with you
		var got := Envoys.meet_lord(s, clan)
		if not got.is_empty():
			flow.event("sound", {"name": "good"})
			flow.announce(str(t.hall.met_title) % str(_who.name), str(t.hall.met_line) % [int(got.gold), int(got.healed), Clans.title(clan)])
		s.say(said)
		_add(s, str(t.lines.leave), str(t.lines.not_now_sub), "leave", {})
		return
	s.say(said)
	_add(s, str(t.hall.hear), str(t.hall.hear_sub), "next", {})
	_add(s, str(t.lines.not_now), str(t.lines.not_now_sub), "leave", {})
