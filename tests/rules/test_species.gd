extends "res://tests/test_case.gd"

const Species = preload("res://src/rules/species.gd")


func test_fill_replaces_known_keys_and_keeps_unknown():
	eq(Species.fill("hi {name}, {name}! {target}", {"name": "Drip"}), "hi Drip, Drip! {target}")
	eq(Species.fill("*slaps {target}*", {"target": "KIRA"}), "*slaps KIRA*")
	eq(Species.fill("no keys", {"name": "x"}), "no keys")
	eq(Species.fill("{n}", {"n": 3.0}), "3", "numbers print like JS")
	eq(Species.fill("{a}{b}", {"a": ""}), "{b}", "an empty string is a value, not missing")


func test_every_species_has_lines_for_every_enemy_action():
	for id in Species.SPECIES:
		var sp: Dictionary = Species.SPECIES[id]
		for action in Species.ENEMY_ACTIONS:
			ok(sp.lines.has(action) and not sp.lines[action].is_empty(), "%s has lines.%s" % [id, action])
		for k in ["approve", "neutral", "disapprove", "leave", "betray"]:
			ok(not sp.reactions[k].is_empty(), "%s has reactions.%s" % [id, k])
		for k in ["forgive", "leave_party", "attack_party", "steal_gold"]:
			ok(not sp.broken[k].is_empty(), "%s has broken.%s" % [id, k])


func test_species_stats_are_sane():
	eq(Species.SPECIES.keys(), ["slime", "goblin", "dragon", "snake", "rock", "bandit"])
	for id in Species.SPECIES:
		var sp: Dictionary = Species.SPECIES[id]
		ok(sp.hp[0] <= sp.hp[1] and sp.dmg[0] <= sp.dmg[1] and sp.gold[0] <= sp.gold[1], "%s ranges ordered" % id)
		ok(sp.color.begins_with("#") and sp.color.length() == 7, "%s color" % id)
		ok(sp.joinThreshold > sp.start.friendliness, "%s must be befriended to join" % id)
	eq(Species.SPECIES.dragon.special.all, true)
	eq(Species.SPECIES.slime.special.all, false)
