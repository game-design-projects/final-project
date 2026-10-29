extends "res://tests/test_case.gd"

const Dock = preload("res://src/ui/dock_model.gd")
const Sample = preload("res://tests/ui/sample_g.gd")


func _keys(row: Dictionary) -> Array:
	var out := []
	for it in row.items:
		if it.type == "cmd":
			out.append(it.key)
		elif it.type == "pad":
			for c in it.items:
				out.append(c.key)
	return out


func test_cap_of_arrows_and_names():
	eq(Dock.cap_of("fwd"), {"cap": "up", "icon": true})
	eq(Dock.cap_of("escape"), {"cap": "ESC", "icon": false})
	eq(Dock.cap_of("enter"), {"cap": "ENTER", "icon": false})
	eq(Dock.cap_of("c"), {"cap": "C", "icon": false})


func test_title_offers_genre_halls():
	var d := Dock.title()
	eq(d.blocks.size(), 1, "one row: the dock keeps its height when the game starts")
	eq(d.blocks[0].items[0].text, "PRESS ANY KEY TO BEGIN")
	eq(_keys(d.blocks[0]), ["g"])
	ok(not d.waiting)


func test_exploring_has_the_pad_and_dims_ally_commands_without_allies():
	var G := Sample.explore()
	var d := Dock.build(G, {"allies": 0})
	ok(not d.waiting)
	eq(_keys(d.blocks[0]), ["turnL", "fwd", "back", "turnR", "c", "e", "v", "b", "m"])
	var talk: Dictionary = d.blocks[0].items[2]
	eq(talk.label, "TALK TO ALLY")
	ok(talk.cls.has("off"), "no allies: TALK TO ALLY is off")
	eq(talk.hint, "NO MONSTER ALLIES YET. WIN ONE OVER IN A FIGHT (RECRUIT)")
	var with_ally := Dock.build(G, {"allies": 1})
	ok(not with_ally.blocks[0].items[2].cls.has("off"))


func test_combat_rows_and_targets():
	var G := Sample.combat()
	var here: Array = G.combat.enemies
	var d := Dock.build(G, {"present": here, "target": here[0], "color_of": func(e): return "#9ed36b", "voice": true})
	eq(_keys(d.blocks[0]), ["f", "c", "t", "r", "g", "v", "e"])
	eq(d.blocks[0].items[0].sub, "EVERYONE'S USUAL MOVE")
	ok(d.blocks[0].items[0].cls.has("main"))
	eq(d.blocks[0].items[3].hint, "ASK KRUNK TO JOIN YOUR PARTY")
	ok(d.blocks[0].items[2].hint.ends_with("OR HOLD SPACE AND SPEAK IT OUT LOUD"))
	eq(d.blocks[1].cls, "targets")
	eq(_keys(d.blocks[1]), ["1", "2"])
	ok(d.blocks[1].items[1].cls.has("on"), "the target is lit")
	eq(d.blocks[1].items[1].label, "KRUNK")


func test_guided_fight_locks_all_but_one_key():
	var G := Sample.combat()
	G.combat.guide = "talk"
	var here: Array = [G.combat.enemies[1]]
	var d := Dock.build(G, {"present": here, "target": here[0]})
	eq(d.hint, "YOUR FIRST FIGHT: TALK TO IT FIRST. MONSTERS HERE LISTEN")
	for it in d.blocks[0].items:
		if it.key == "t":
			ok(it.cls.has("guide"), "T glows")
		else:
			ok(it.cls.has("locked"), "%s waits" % it.key)
			eq(it.hint, "YOUR FIRST FIGHT: TALK TO IT FIRST. MONSTERS HERE LISTEN. THIS WAITS FOR NOW")
	eq(d.blocks.size(), 1, "one monster: no target row")


func test_menu_columns_tails_and_hint():
	var G := Sample.combat()
	var who: Dictionary = G.party[2]
	G.menu = {"title": "WHAT WILL EUGENE DO? (1 OF 3)", "sel": 1, "who": who, "options": [
		{"label": "ATTACK WITH DAGGER", "value": {}, "hint": "HIT"},
		{"label": "FIRE BOLT", "value": {}, "cost": 0, "hint": "FREE ONE"},
		{"label": "MAGIC MISSILE", "value": {}, "cost": 1, "hint": "M"},
		{"label": "SLEEP", "value": {}, "cost": 1, "hint": "S"},
		{"label": "BURNING HANDS", "value": {}, "cost": 1, "hint": "B"},
	]}
	var d := Dock.build(G)
	ok(d.waiting)
	eq(d.hint, "FREE ONE")
	eq(d.blocks[0].type, "ask")
	ok(d.blocks[0].pips == who, "the title shows Eugene's slots")
	var menu: Dictionary = d.blocks[1]
	eq(menu.rows, 3, "5 options: 3 rows in 2 columns")
	eq(menu.options[0].cap, "1")
	ok(menu.options[1].sel)
	eq(menu.options[1].tail, {"kind": "free"})
	eq(menu.options[2].tail.kind, "pips")
	eq(menu.options[2].tail.n, 2)
	eq(menu.options[2].tail.tip, "USES ONE FIRST-CIRCLE SLOT. 2 LEFT")
	var keys: Dictionary = d.blocks[2]
	eq(keys.cls, "keys")
	eq(keys.items[1].key, "escape")


func test_menu_heal_targets_show_health():
	var G := Sample.combat()
	G.menu = {"title": "CURE WOUNDS: HEAL WHOM?", "sel": 0, "who": null, "options": [{"label": "HORTENSE", "value": G.party[0], "who": G.party[0]}]}
	var d := Dock.build(G)
	eq(d.blocks[1].options[0].tail.kind, "hp")
	eq(d.blocks[1].options[0].tail.color, "#ffd23f", "7 of 12 is hurt")
	ok(d.blocks[0].pips == null)


func test_talk_box_waiting_states():
	var G := Sample.combat()
	G.input = {"label": "WHAT DO YOU SAY?", "numeric": false, "listening": null}
	var d := Dock.build(G, {"voice": true})
	ok(d.waiting)
	eq(_keys(d.blocks[0]), ["enter", "escape"])
	eq(d.blocks[0].items[0].label, "SAY IT")
	eq(d.blocks[0].items[2].type, "how")
	G.input.numeric = true
	eq(Dock.build(G, {"voice": true}).blocks[0].items[0].label, "GIVE")
	eq(Dock.build(G, {"voice": true}).blocks[0].items.size(), 2, "no speaking into a number")
	G.input = {"label": "X", "numeric": false, "listening": "space"}
	d = Dock.build(G, {"voice": true})
	eq(d.blocks[0].text, "LISTENING. SPEAK, THEN LET GO OF SPACE TO SAY IT")
	ok(d.blocks[0].listening)


func test_other_waits():
	var G := Sample.explore()
	G.prompt = {"text": "DESCEND?", "yes": "YES", "no": "NO", "walkAway": true}
	var d := Dock.build(G)
	eq(d.blocks[0].text, "ANSWER THE QUESTION ON THE VIEW")
	ok(d.blocks[0].echo)
	G.prompt = null
	G.busy = true
	eq(Dock.build(G).blocks[0].text, "LISTENING")
	ok(Dock.build(G).blocks[0].dots)
	G.busy = false
	G.mode = "over"
	d = Dock.build(G)
	ok(d.waiting)
	eq(d.blocks[0].text, "YOUR PARTY HAS FALLEN.")
	eq(d.blocks[1].items[0].label, "NEW RUN")
	G.waitKey = true
	d = Dock.build(G)
	eq(d.blocks[0].items[0].cap, "ANY KEY")
	G.waitKey = null
	G.mode = "explore"
	G.roll = {"start": 0}
	eq(Dock.build(G).blocks[0].text, "THE ROLL OF FATE IS SPINNING")
