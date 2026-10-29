## The command dock as data: what renderDock(), cmd(), capOf() and menuHtml() in game.js put in the dock, as
## blocks the dock widget lays out and paints. Pure (tested in tests/ui): it reads G and a few facts about the
## rest of the game passed in `ctx`.
##   ctx: voice (bool: hold to speak works), present (Array: monsters here), target (Dictionary or null),
##        color_of (Callable: a monster's colour), allies (int: living monster allies)
## The result: {waiting: bool, hint: String, blocks: Array}. Blocks:
##   {type: "wait", text, dots, echo, icon}        a status line (<p class="wait">)
##   {type: "ask", text, listening, pips}           a question line (<p class="ask">), pips: the member whose slots show
##   {type: "row", cls, items}                      a row of commands (cls "", "keys" or "targets")
##   {type: "menu", rows, options}                  a menu (options: {key, i, cap, label, sel, hint, tail})
## Row items: {type: "cmd", ...cmd()}, {type: "pad", items, lab}, {type: "lab", text}, {type: "how", parts}.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Status = preload("res://src/rules/status.gd")
const Tutorial = preload("res://src/rules/tutorial.gd")

const ARROWS := {"fwd": "up", "back": "down", "turnL": "left", "turnR": "right"}
const TITLE_HINT := "GENRE HALLS: ONE FLOOR, FIVE FIGHTS, EACH FACTION IN ITS OWN GENRE"


## The keycap for a key: an arrow icon for the movement keys, ESC, ENTER, or the key itself in capitals.
## Returns {cap, icon}: icon true means `cap` names an icon.
static func cap_of(k: String) -> Dictionary:
	if ARROWS.has(k):
		return {"cap": ARROWS[k], "icon": true}
	var named := {"escape": "ESC", "enter": "ENTER"}
	return {"cap": named.get(k, k.to_upper()), "icon": false}


## A keycap button. opts: hint, sub, cls (space-separated: main off locked guide go on ico-only), cap, title, color
static func cmd(k: String, label: String, opts := {}) -> Dictionary:
	var c := cap_of(k)
	if opts.has("cap"):
		c = {"cap": opts.cap, "icon": opts.get("cap_icon", false)}
	var cls := {}
	for word in str(opts.get("cls", "")).split(" ", false):
		cls[word] = true
	return {
		"type": "cmd",
		"key": k,
		"cap": c.cap,
		"cap_icon": c.icon,
		"label": label,
		"icon": opts.get("icon", ""), # a pixel icon in the label (the top bar's switches)
		"icon_color": opts.get("icon_color", ""),
		"sub": opts.get("sub", ""),
		"cls": cls,
		"hint": opts.get("hint", ""),
		"title": opts.get("title", ""),
		"color": opts.get("color", ""),
	}


static func _wait(text: String, opts := {}) -> Dictionary:
	return {"type": "wait", "text": text, "dots": opts.get("dots", false), "echo": opts.get("echo", false), "icon": opts.get("icon", "")}


static func _row(items: Array, cls := "") -> Dictionary:
	return {"type": "row", "cls": cls, "items": items}


## The dock before the game starts (the title screen)
static func title() -> Dictionary:
	return {
		"waiting": false,
		"hint": "",
		"blocks": [
			_wait("PRESS ANY KEY TO BEGIN"),
			_row([cmd("g", "GENRE HALLS", {"sub": "UNDERTALE-STYLE BATTLES", "hint": TITLE_HINT})]),
		],
	}


## menuHtml(m): the title (with the member's slot pips), the options in columns, then the keys to use them
static func menu(m: Dictionary) -> Array:
	var options: Array = m.get("options", [])
	var n := options.size()
	var rows := ceili(n / 2.0) if n > 4 else n
	var who = m.get("who")
	var opts := []
	for i in n:
		var o: Dictionary = options[i]
		var key := str(i + 1) if i < 9 else ("0" if i == 9 else "")
		var tail = null
		var cost = o.get("cost")
		if cost != null and int(cost) == 0:
			tail = {"kind": "free"}
		elif cost != null and int(cost) > 0 and who is Dictionary and who.get("slots") != null:
			var c := int(cost)
			var slots: Array = who.slots
			var left := int(slots[c - 1]) if c - 1 < slots.size() and slots[c - 1] != null else 0
			tail = {"kind": "pips", "color": Status.CIRCLE_COLORS[c - 1], "n": left, "tip": "USES ONE %s-CIRCLE SLOT. %d LEFT" % [Status.CIRCLE_WORDS[c - 1], left]}
		elif o.get("who") is Dictionary:
			var st := Status.hp_state(o.who)
			tail = {"kind": "hp", "color": st.color, "pct": st.pct}
		opts.append({"key": "pick:%d" % i, "i": i, "cap": key, "label": str(o.get("label", "")), "sel": i == int(m.get("sel", 0)), "hint": str(J.nz(o.get("hint"), "")), "tail": tail})
	var how := [{"kbd_icon": "up"}, {"kbd_icon": "down"}, {"text": "CHOOSE"}, {"kbd": "ENTER"}, {"text": "PICK"}]
	if n > 1:
		how.append_array([{"kbd": "1"}, {"text": "-"}, {"kbd": str(mini(n, 9))}])
	var has_pips: bool = who is Dictionary and who.get("maxSlots") != null
	return [
		{"type": "ask", "text": str(m.get("title", "")), "listening": false, "pips": who if has_pips else null},
		{"type": "menu", "rows": rows, "options": opts},
		_row([{"type": "how", "parts": how}, cmd("escape", "BACK")], "keys"),
	]


## renderDock(): what the dock shows for the state of the game
static func build(G: Dictionary, ctx := {}) -> Dictionary:
	var blocks := []
	var hint := ""
	var waiting := false
	var voice: bool = ctx.get("voice", false)
	var combat = G.get("combat")
	var inp = G.get("input")
	if J.truthy(G.get("waitKey")):
		waiting = true
		blocks.append(_row([cmd("enter", "CONTINUE", {"cap": "ANY KEY", "cls": "go"})]))
	elif J.truthy(G.get("roll")):
		blocks.append(_wait("THE ROLL OF FATE IS SPINNING", {"dots": true}))
	elif G.get("mode") == "over":
		waiting = true
		blocks.append({"type": "ask", "text": "YOUR PARTY HAS FALLEN.", "listening": false, "pips": null})
		blocks.append(_row([cmd("enter", "NEW RUN", {"cls": "go"})]))
	elif J.truthy(G.get("prompt")):
		blocks.append(_wait("ANSWER THE QUESTION ON THE VIEW", {"echo": true, "icon": "up"}))
	elif J.truthy(G.get("menu")):
		waiting = true
		var m: Dictionary = G.menu
		blocks.append_array(menu(m))
		var sel := int(m.get("sel", 0))
		var options: Array = m.get("options", [])
		if sel >= 0 and sel < options.size():
			hint = str(J.nz(options[sel].get("hint"), ""))
	elif inp is Dictionary and J.truthy(inp.get("listening")):
		waiting = true
		var how := "LET GO OF SPACE" if inp.listening == "space" else "LET GO OF THE MIC"
		blocks.append({"type": "ask", "text": "LISTENING. SPEAK, THEN %s TO SAY IT" % how, "listening": true, "pips": null})
		blocks.append(_row([cmd("escape", "CANCEL")]))
	elif inp is Dictionary:
		waiting = true
		var numeric: bool = J.truthy(inp.get("numeric"))
		var items := [cmd("enter", "GIVE" if numeric else "SAY IT", {"cls": "go"}), cmd("escape", "CANCEL")]
		if not numeric and voice:
			items.append({"type": "how", "parts": [{"text": "OR HOLD"}, {"kbd": "SPACE"}, {"text": "AND SPEAK"}]})
		blocks.append(_row(items, "keys"))
	elif J.truthy(G.get("busy")):
		blocks.append(_wait("THE FIGHT PLAYS OUT" if combat != null else "LISTENING", {"dots": true}))
	elif combat is Dictionary:
		var here: Array = ctx.get("present", [])
		var t = ctx.get("target")
		var tn := J.up(t.name) if t is Dictionary else "THE TARGET"
		var g = Tutorial.GUIDE.get(combat.get("guide")) if combat.get("guide") != null else null
		if g != null:
			hint = g.say
		var fc := func(k: String, opts: Dictionary) -> Dictionary:
			var o := opts.duplicate()
			var cls := str(o.get("cls", ""))
			if g != null:
				cls += " guide" if g.key == k else " locked"
				if g.key != k:
					o.hint = "%s. THIS WAITS FOR NOW" % g.say
			o.cls = cls
			return cmd(k, o.get("label", ""), o)
		var talk_hint := "SAY SOMETHING. EVERY MONSTER HERE HEARS IT" + (". OR HOLD SPACE AND SPEAK IT OUT LOUD" if voice else "")
		blocks.append(_row([
			fc.call("f", {"label": "QUICK ATTACK", "cls": "main", "sub": "EVERYONE'S USUAL MOVE", "hint": "EVERYONE DOES THEIR USUAL MOVE AT ONCE: WEAPONS, AND THE WIZARD'S FREE FIRE BOLT. USES NO SPELL SLOTS. ALLIES ACT ON THEIR OWN"}),
			fc.call("c", {"label": "CHOOSE MOVES", "cls": "main", "sub": "SPELLS AND SKILLS", "hint": "PICK A MOVE FOR EACH ADVENTURER, ONE BY ONE: ATTACK, A SKILL, OR A SPELL (SPELLS USE SLOTS)"}),
			fc.call("t", {"label": "TALK", "hint": talk_hint}),
			fc.call("r", {"label": "RECRUIT", "hint": "ASK %s TO JOIN YOUR PARTY" % tn}),
			fc.call("g", {"label": "GIVE GOLD", "hint": "OFFER %s SOME GOLD" % tn}),
			fc.call("v", {"label": "VOW", "hint": "SWEAR A PROMISE TO %s, ONCE PER FIGHT" % tn}),
			fc.call("e", {"label": "ESCAPE", "hint": "TRY TO RUN AWAY"}),
		]))
		if here.size() > 1:
			var items := [{"type": "lab", "text": "TARGET"}]
			var color_of: Callable = ctx.get("color_of", Callable())
			for i in here.size():
				var e: Dictionary = here[i]
				var color := str(color_of.call(e)) if color_of.is_valid() else "#e8e8e8"
				items.append(cmd(str(i + 1), J.up(e.name), {"cls": "on" if e.get("id") == combat.get("target") else "", "hint": "AIM YOUR ATTACKS AND WORDS AT %s" % J.up(e.name), "color": color}))
			blocks.append(_row(items, "targets"))
	else:
		var none: bool = int(ctx.get("allies", 0)) == 0
		var no_ally := {"cls": "off", "hint": "NO MONSTER ALLIES YET. WIN ONE OVER IN A FIGHT (RECRUIT)"}
		var talk := no_ally.duplicate() if none else {"hint": "TALK TO A MONSTER ALLY, ONCE PER ALLY PER FLOOR"}
		var vow := no_ally.duplicate() if none else {"hint": "SWEAR A PROMISE TO A MONSTER ALLY"}
		blocks.append(_row([
			{"type": "pad", "lab": "MOVE", "items": [
				cmd("turnL", "", {"hint": "TURN LEFT (A)"}),
				cmd("fwd", "", {"hint": "STEP FORWARD (W)"}),
				cmd("back", "", {"hint": "STEP BACK (S)"}),
				cmd("turnR", "", {"hint": "TURN RIGHT (D)"}),
			]},
			cmd("c", "CAMP", {"hint": "REST: HEAL HALF YOUR WOUNDS, GET SPELL SLOTS AND SKILLS BACK. SOMETHING MAY FIND YOU"}),
			cmd("e", "TALK TO ALLY", talk),
			cmd("v", "VOW", vow),
			cmd("b", "BOONS", {"hint": "LIST THE ROLL OF FATE BOONS YOU HAVE WON"}),
			cmd("m", "MAP", {"hint": "SHOW OR HIDE THE MAP"}),
		]))
	return {"waiting": waiting, "hint": hint, "blocks": blocks}
