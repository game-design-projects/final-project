## Group encounters, ally talk and vows.
##   godot --headless --path . -s res://cli/social_scenarios.gd -- [filter] [--live] [--seed=N]
## By default Jev is mocked (mock_jev.gd): random but well-formed answers, no key, no credits, repeatable with --seed.
## That checks the plumbing and the game's rules, not Jev's judgement; pass --live for real calls (billed).
extends SceneTree

const J = preload("res://src/core/js.gd")
const JevConfig = preload("res://src/jev/config.gd")
const Enemy = preload("res://src/jev/enemy.gd")
const Bonds = preload("res://src/jev/bonds.gd")
const Species = preload("res://src/rules/species.gd")

const PARTY := [
	{"id": "h0", "name": "HORTENSE", "kind": "human", "cls": "G-FIG", "hp": 14, "maxHp": 14},
	{"id": "h1", "name": "ROLF", "kind": "human", "cls": "G-FIG", "hp": 13, "maxHp": 13},
	{"id": "h2", "name": "EUGENE", "kind": "human", "cls": "N-MAG", "hp": 8, "maxHp": 8},
]

var only := ""
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var live := false
	var seed := 1
	for a in OS.get_cmdline_user_args():
		if a == "--live":
			live = true
		elif a.begins_with("--seed="):
			seed = int(a.trim_prefix("--seed="))
		elif not a.begins_with("--"):
			only = a
	var setup := JevConfig.setup_tool(live, seed)
	print(setup["banner"])
	if not setup["ok"]:
		quit(1)
		return
	await _scenario("group", _group)
	await _scenario("talk", _talk)
	await _scenario("vow", _vow)
	quit(1 if failed else 0)


func _scenario(name: String, fn: Callable) -> void:
	if only == "" or name.contains(only):
		await fn.call()


func _fail(what: String, r: Dictionary) -> bool:
	if r.has("error"):
		printerr("  error in %s: %s" % [what, r["error"]])
		failed = true
		return true
	return false


func _mon(id: String, species: String, name: String, extra := {}) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[species]
	var m := {
		"id": id, "species": species, "name": name, "traits": sp["traits"].slice(0, 2), "hp": sp["hp"][1], "maxHp": sp["hp"][1], "meters": sp["start"].duplicate(),
		"specialReady": true, "paid": false, "demanded": false, "impressions": [], "formerAlly": false, "grudges": [], "thisRound": [],
	}
	m.merge(extra, true)
	return m


func _group() -> void:
	print("\n━━ goblin + slime: be kind to the slime, insult the goblin ━━")
	var monsters := [_mon("e0", "goblin", "Grok"), _mon("e1", "slime", "Glop")]
	var conversation := []
	var turns := [
		{"type": "start"},
		{"type": "talk", "message": "Glop, you sweet little slime, we'd never hurt you. Grok, you smelly brute, back off."},
		{"type": "talk", "message": "Glop, come with us, you'll be safe in our party. Grok is a bully."},
		{"type": "fight", "targetId": "e0"},
	]
	for i in turns.size():
		var t: Dictionary = turns[i]
		if monsters.is_empty():
			print("  (every monster has left)")
			break
		var events := []
		if t["type"] == "fight":
			events = ["The party attacked Grok."]
		elif t["type"] == "talk":
			events = ["The party spoke."]
		var out := await Enemy.group_turn({"monsters": monsters, "party": PARTY, "round": i + 1, "playerAction": t, "events": events, "conversation": conversation, "partyGold": 30, "vows": []})
		if _fail("group_turn", out):
			return
		print("> %s   (%s ms, %s q)" % ["“%s”" % t["message"] if t.has("message") else "[%s]" % t["type"], J.num(out["ms"]), J.num(out["questionCount"])])
		for r in out["results"]:
			var m: Dictionary = monsters.filter(func(x): return x["id"] == r["id"])[0]
			print("  %s [%s%s] f%s a%s (%s)%s — %s" % [
				m["name"], r["action"], " → " + r["monsterTargetId"] if r["monsterTargetId"] != null else "",
				J.num(r["meters"]["friendliness"]), J.num(r["meters"]["anger"]), r["side"],
				" BLOCKED %s: %s" % [r["picked"], r["blocked"]] if r["blocked"] != null else "", str(r["line"]),
			])
			conversation.append({"speaker": m["name"], "text": r["line"]})
			m["meters"] = r["meters"]
			m["impressions"] = r["impressions"]
			m["thisRound"] = []
		if t.has("message"):
			conversation.append({"speaker": "Party", "text": t["message"]})
		if t["type"] == "fight" and not monsters.is_empty():
			monsters[0]["thisRound"] = ["The party hit it for 6."]
		var gone := {}
		for r in out["results"]:
			if ["flee", "leave_peacefully", "join_party"].has(r["action"]):
				gone[r["id"]] = true
		monsters = monsters.filter(func(m): return not gone.has(m["id"]))


func _talk() -> void:
	print("\n━━ ally talk ━━")
	for row in [
		["goblin", "Grok", "Grok, you're the strongest fighter we've got. Next chest we find, you get first pick of the loot."],
		["slime", "Glop", "Glop, you're slow and you slow us down."],
		["dragon", "Vexalith", "Mighty Vexalith, we fight beside a legend. Watch us be brave for you."],
	]:
		var species: String = row[0]
		var r := await Bonds.ally_talk({"ally": {"id": "a1", "species": species, "name": row[1], "traits": Species.SPECIES[species]["traits"].slice(0, 2), "loyalty": 55}, "message": row[2], "vows": []})
		if _fail("ally_talk", r):
			return
		var buff = r["buff"]["id"] if r["buff"] != null else "none"
		print("  %s: resonance %.2f loyalty %s%s buff %s — %s" % [row[1], r["resonance"], "+" if r["loyaltyDelta"] >= 0 else "", J.num(r["loyaltyDelta"]), buff, r["line"]])


func _vow() -> void:
	print("\n━━ vows made ━━")
	for row in [
		["slime", "Glop", "I won't kill slimes"],
		["goblin", "Grok", "I will give gold to goblins"],
		["goblin", "Grok", "I won't give gold to goblins"],
		["dragon", "Vexalith", "I won't run from dragons"],
	]:
		var species: String = row[0]
		var r := await Bonds.vow_made({"monster": {"species": species, "name": row[1], "traits": Species.SPECIES[species]["traits"].slice(0, 2)}, "vow": {"text": row[2]}})
		if _fail("vow_made", r):
			return
		print("  %s hears \"%s\": liking %.2f — %s" % [row[1], row[2], r["liking"], r["line"]])
	print("\n━━ vows broken ━━")
	for row in [
		["slime", "Glop", 60, "I won't kill slimes", "The party killed Drip, an orange slime, while it begged for mercy."],
		["goblin", "Grok", 40, "I won't give gold to goblins", "The party gave 25 gold to Snaggle, another goblin."],
		["dragon", "Vexalith", 70, "I won't run from dragons", "The party ran away from a yellow dragon."],
	]:
		var species: String = row[0]
		var r := await Bonds.vow_broken({
			"monster": {"species": species, "name": row[1], "traits": Species.SPECIES[species]["traits"].slice(0, 2), "loyalty": row[2]},
			"vow": {"text": row[3]}, "how": row[4], "gold": 60,
		})
		if _fail("vow_broken", r):
			return
		var ranked := []
		for k in r["probabilities"]:
			ranked.append([k, r["probabilities"][k]])
		ranked.sort_custom(func(a, b): return a[1] > b[1])
		var top := ", ".join(ranked.map(func(x): return "%s %d%%" % [x[0], J.round_js(x[1] * 100)]))
		print("  %s (loyalty %s): %s%s%s%s | %s — %s" % [
			row[1], J.num(row[2]), r["response"], " [%s]" % r["blocked"] if r["blocked"] != null else "",
			" stole %s" % J.num(r["stolen"]) if r["stolen"] > 0 else "", " CAUGHT" if r["caught"] else "", top, r["line"],
		])
