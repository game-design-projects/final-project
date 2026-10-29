## Scripted encounters.
##   godot --headless --path . -s res://cli/scenarios.gd -- [filter] [--live] [--seed=N]
## By default Jev is mocked (mock_jev.gd): random but well-formed answers, no key, no credits, repeatable with --seed.
## That checks the plumbing and the game's rules, not Jev's judgement; pass --live for real calls (billed).
extends SceneTree

const J = preload("res://src/core/js.gd")
const JevConfig = preload("res://src/jev/config.gd")
const Enemy = preload("res://src/jev/enemy.gd")
const Allies = preload("res://src/jev/allies.gd")
const Species = preload("res://src/rules/species.gd")

const PARTY := [
	{"id": "p0", "name": "HORTENSE", "kind": "human", "cls": "G-FIG", "hp": 14, "maxHp": 14},
	{"id": "p1", "name": "ROLF", "kind": "human", "cls": "G-FIG", "hp": 13, "maxHp": 13},
	{"id": "p2", "name": "EUGENE", "kind": "human", "cls": "N-MAG", "hp": 8, "maxHp": 8},
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

	await _scenario("slime_friend", func(): await _encounter("befriend a slime", _enemy("slime", "Glop"), [
		{"type": "start"},
		_talk("Hey little buddy, we won't hurt you. What's your name?"),
		_talk("Why did the slime cross the road? To get to the other slide!"),
		_talk("You're great, Glop. Want to come adventure with us?"),
	]))
	await _scenario("slime_shy_retry", func(): await _encounter("shy slime: invite too early, then again", _enemy("slime", "Squish", {"traits": ["hungry", "shy"]}), [
		{"type": "start"},
		_talk("Hello friend! Why did the slime blush? It saw the dungeon's dressing! Hehe."),
		_talk("You're wonderful. Come adventure with us, we'll keep you safe and fed."),
		_talk("It's okay to be shy. We really like you, Squish. Please join us?"),
	]))
	await _scenario("goblin_rude", func(): await _encounter("insult a goblin", _enemy("goblin", "Grok"), [
		{"type": "start"},
		_talk("Out of the way, you stinking brainless lump."),
		{"type": "fight"},
	]))
	await _scenario("dragon_tribute", func(): await _encounter("flatter and pay a dragon", _enemy("dragon", "Vexalith"), [
		{"type": "start"},
		_talk("Mighty Vexalith, your scales outshine the sun. We mean no disrespect."),
		{"type": "give", "gold": 20},
		{"type": "give", "gold": 80},
		_talk("Might we pass, great one?"),
	], 120))
	await _scenario("allies_cruel", func(): await _reactions(
		"slime + goblin allies watch the party kill a begging slime",
		[
			{"id": "a1", "species": "slime", "name": "Glop", "traits": ["shy", "hungry"], "loyalty": 60},
			{"id": "a2", "species": "goblin", "name": "Grok", "traits": ["greedy", "boastful"], "loyalty": 60},
		],
		["The party attacked Drip, an orange slime.", "Drip begged: 'no hurt Drip. please.'", "The party killed Drip anyway and took 6 gold."],
	))
	await _scenario("allies_generous", func(): await _reactions(
		"allies watch the party pay a goblin to go away",
		[
			{"id": "a1", "species": "slime", "name": "Glop", "traits": ["shy", "hungry"], "loyalty": 40},
			{"id": "a2", "species": "goblin", "name": "Grok", "traits": ["greedy", "short-tempered"], "loyalty": 20},
		],
		["The party met Snaggle, a huge brown goblin.", "The party gave Snaggle 25 gold.", "Snaggle left peacefully."],
	))
	await _scenario("allies_betray", func(): await _reactions(
		"a resentful goblin watches the party flee and give away gold again",
		[{"id": "a2", "species": "goblin", "name": "Grok", "traits": ["greedy", "short-tempered"], "loyalty": 12}],
		["The party gave a slime 10 gold.", "The party ran away from a yellow dragon."],
	))
	quit(1 if failed else 0)


func _scenario(name: String, fn: Callable) -> void:
	if only == "" or name.contains(only):
		await fn.call()


func _talk(message: String) -> Dictionary:
	return {"type": "talk", "message": message}


func _enemy(species: String, name: String, extra := {}) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[species]
	var e := {
		"species": species, "name": name, "traits": [sp["traits"][0], sp["traits"][1]], "hp": sp["hp"][1], "maxHp": sp["hp"][1],
		"meters": sp["start"].duplicate(), "specialReady": true, "paid": false, "demanded": false, "impressions": [], "formerAlly": false,
	}
	e.merge(extra, true)
	return e


func _encounter(title: String, e: Dictionary, turns: Array, party_gold := 40) -> void:
	print("\n━━ %s ━━" % title)
	var conversation := []
	for i in turns.size():
		var t: Dictionary = turns[i]
		var events := []
		match t["type"]:
			"talk":
				events = ["The party spoke to you."]
			"give":
				events = ["The party offered you %s gold." % J.num(t["gold"])]
			"fight":
				events = ["The whole party attacked you."]
		var r := await Enemy.enemy_turn({"enemy": e, "party": PARTY, "round": i + 1, "playerAction": t, "events": events, "conversation": conversation, "partyGold": party_gold})
		if r.has("error"):
			printerr("  error: %s" % r["error"])
			failed = true
			return
		if t.has("message"):
			conversation.append({"speaker": "Party", "text": t["message"]})
		conversation.append({"speaker": e["name"], "text": r["line"]})
		e["meters"] = r["meters"]
		e["impressions"] = r["impressions"]
		if r["action"] == "accept_tribute":
			e["paid"] = true
		if r["action"] == "demand_tribute":
			e["demanded"] = true
		var top := []
		for x in r["probabilities"].slice(0, 3):
			top.append("%s %d%%" % [x["id"], J.round_js(x["p"] * 100)])
		var said: String = "“%s”" % t["message"] if t.has("message") else "[%s%s]" % [t["type"], " " + J.num(t["gold"]) if t.has("gold") else ""]
		print("> " + said)
		print("  jev: %s%s" % [", ".join(top), "  | BLOCKED %s: %s" % [r["picked"], r["blocked"]] if r["blocked"] != null else ""])
		print("  %s [%s%s]: %s" % [e["name"], r["action"], " → " + r["targetId"] if r["targetId"] != null else "", str(r["line"])])
		print("  mood f%s a%s fear%s | %sms %sq" % [J.num(r["meters"]["friendliness"]), J.num(r["meters"]["anger"]), J.num(r["meters"]["fear"]), J.num(r["ms"]), J.num(r["questionCount"])])
		if ["join_party", "flee", "leave_peacefully"].has(r["action"]):
			break


func _reactions(title: String, allies: Array, events: Array) -> void:
	print("\n━━ %s ━━" % title)
	for e in events:
		print("  event: %s" % e)
	var r := await Allies.ally_reactions({"allies": allies, "events": events})
	if r.has("error"):
		printerr("  error: %s" % r["error"])
		failed = true
		return
	for x in r["reactions"]:
		print("  %s: approval %.2f loyalty %s (%s%s) %s%s — %s" % [
			x["name"], x["approval"], J.num(x["loyalty"]), "+" if x["delta"] >= 0 else "", J.num(x["delta"]), x["decision"],
			" [%s]" % x["blocked"] if x["blocked"] != null else "", x["line"],
		])
	print("  %sms %sq" % [J.num(r["ms"]), J.num(r["questionCount"])])
