extends "res://tests/test_case.gd"

const Party = preload("res://src/ui/party_model.gd")
const Sample = preload("res://tests/ui/sample_g.gd")


func test_humans_show_health_armor_and_powers():
	var G := Sample.explore()
	var rows := Party.rows(G)
	eq(rows.size(), 3)
	var f: Dictionary = rows[0]
	eq(f.kind, "human")
	eq(f.num, "1")
	eq(f.name, "HORTENSE")
	eq(f.sub, "FIGHTER · LEVEL 1")
	eq(f.hp.text, "12/12")
	eq(f.hp.word, "", "healthy says nothing")
	eq(f.hp.tip, "HEALTH 12 OF 12: HEALTHY")
	eq(f.ac, "16")
	eq(f.pw.kind, "skills")
	eq(f.pw.pips, [true, true])
	eq(f.pw.tip, "SKILLS: SECOND WIND READY, ACTION SURGE READY. THEY COME BACK WHEN YOU CAMP")
	var c: Dictionary = rows[1]
	eq(c.pw.kind, "slots")
	eq(c.pw.groups[0].pips, [true, true])
	eq(c.pw.tip, "SPELL SLOTS LEFT: FIRST CIRCLE 2 OF 2. A SPELL USES ONE SLOT OF ITS CIRCLE. CAMP TO REFILL")


func test_hurt_dying_and_dead():
	var G := Sample.explore()
	G.party[0].hp = 3
	var r := Party.row(G, G.party[0], 0)
	eq(r.hp.word, "CRITICAL")
	eq(r.hp.text, "3/12")
	G.party[1].hp = 0
	G.party[1].down = true
	G.party[1].saves = {"s": 1, "f": 2}
	r = Party.row(G, G.party[1], 1)
	ok(r.dying)
	eq(r.hp.word, "DYING")
	eq(r.hp.text, "")
	eq(r.hp.saves.s, 1)
	eq(r.hp.saves.f, 2)
	eq(r.hp.saves.tip, "DEATH SAVES: 1 OF 3 SUCCESSES, 2 OF 3 FAILURES. THREE FAILURES AND ROLF DIES. ANY HEALING GETS THEM UP")
	G.party[1].stable = true
	ok(Party.row(G, G.party[1], 1).hp.saves == null, "stable: no boxes")
	G.party[2].dead = true
	r = Party.row(G, G.party[2], 2)
	ok(r.dead and r.skull)
	eq(r.hp.word, "DEAD")


func test_allies_get_a_divider_loyalty_and_one_line():
	var G := Sample.combat()
	var rows := Party.rows(G, {"color_of": func(m): return "#ffb347"})
	eq(rows.size(), 5)
	eq(rows[3].kind, "div")
	eq(rows[3].allies, 1)
	eq(rows[3].max, 3)
	eq(rows[3].tip, "YOUR PARTY HOLDS 6: ROOM FOR 3 MONSTER ALLIES BESIDE YOUR ADVENTURERS")
	var a: Dictionary = rows[4]
	eq(a.kind, "monster")
	eq(a.num, "4")
	eq(a.ink, "#ffb347")
	eq(a.chips[0].word, "CONTENT")
	eq(a.chips[0].tip, "LOYALTY 60 OF 100: CONTENT. AN UNHAPPY ALLY MAY LEAVE OR TURN ON YOU")
	eq(a.name_tip, "GLOP: SLIME ALLY · LEVEL 1")
	ok(a.pw == null)


func test_conditions_buffs_moods():
	var G := Sample.combat()
	var m: Dictionary = G.party[3]
	m.buff = {"id": "BOUNCY", "desc": "absorbs a hit"}
	m.mood = {"id": "SULKING", "desc": "sits out the next fight"}
	m.cond = {"poisoned": 2}
	var words := []
	for c in Party.status_chips(m):
		words.append([c.word, c.icon, c.color])
	eq(words, [["CONTENT", "heart", "#a8d38f"], ["POISONED", "drop", "#9ed36b"], ["BOUNCY", "star", "#ffe14a"], ["SULKING", "frown", "#8a8a8a"]])


func test_acting_and_picked_follow_the_menu():
	var G := Sample.combat()
	G.menu = {"title": "WHAT WILL ROLF DO?", "sel": 0, "who": G.party[1], "options": [{"label": "x", "value": null}]}
	var rows := Party.rows(G)
	ok(rows[1].acting)
	eq(rows[1].num, "▶")
	ok(not rows[0].acting)
	G.menu = {"title": "HEAL WHOM?", "sel": 1, "who": null, "options": [{"label": "A", "who": G.party[0]}, {"label": "B", "who": G.party[2]}]}
	rows = Party.rows(G)
	ok(rows[2].picked and not rows[0].picked)
