## A hand-made game state for developing and testing the ui without game.gd: G built the way game.js's newRun(),
## human(), encounter() and the halls.ally() debug hook build it. Not a test file (no test_ prefix).
extends RefCounted

const J = preload("res://src/core/js.gd")
const DnD = preload("res://src/rules/dnd.gd")
const Species = preload("res://src/rules/species.gd")
const Render = preload("res://src/view/render.gd")
const Floors = preload("res://src/game/floors.gd")

static var uid := 0


static func human(name: String, cls_id: String) -> Dictionary:
	var c: Dictionary = DnD.CLASSES[cls_id]
	var hp: int = c.hitDie + c.abil.con
	var m := {"id": "h%d" % uid, "name": name, "kind": "human", "clsId": cls_id, "cls": c.code, "hp": hp, "maxHp": hp, "ac": c.ac, "abil": c.abil.duplicate(), "dead": false, "down": false, "level": 1, "xp": 0, "mods": {"dmg": 1.0, "critMin": 20, "hits": 1, "lifesteal": 0, "spell": 1.0, "hitBonus": 0}, "cond": {}, "uses": {}}
	uid += 1
	if c.caster != null:
		m.bonusSlots = [0, 0, 0]
		m.maxSlots = DnD.slots_for(1)
		m.slots = m.maxSlots.duplicate()
	if cls_id == "fighter":
		m.uses = {"second_wind": 1, "action_surge": 1}
	return m


static func ally(species: String, name: String) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[species]
	var m := {"id": "m%d" % uid, "name": name.to_upper(), "kind": "monster", "species": species, "cls": sp.cls, "hp": sp.hp[1], "maxHp": sp.hp[1], "ac": DnD.MONSTER_STATS[species].ac, "dmg": sp.dmg.duplicate(), "traits": sp.traits.slice(0, 2), "loyalty": 60, "dead": false, "down": false, "level": 1, "xp": 0, "mods": {"dmg": 1.0, "critMin": 20, "hits": 1, "lifesteal": 0, "spell": 1.0, "hitBonus": 0}, "cond": {}, "cooldown": 1}
	uid += 1
	return m


static func enemy(species: String, name: String, id: String) -> Dictionary:
	var sp: Dictionary = Species.SPECIES[species]
	return {"id": id, "species": species, "name": name, "shiny": false, "elite": false, "hp": sp.hp[1], "maxHp": sp.hp[1], "ac": DnD.MONSTER_STATS[species].ac, "status": "here", "cond": {}, "meters": sp.start.duplicate(), "traits": sp.traits.slice(0, 2), "thisRound": [], "impressions": []}


## newRun(): floor 1, the three adventurers, the opening lines in the log
static func explore(seed_n := 7) -> Dictionary:
	seed(seed_n)
	var G := {
		"mode": "explore", "floor": 1, "gold": 30, "boons": [], "goldMult": 1, "combat": null, "busy": false, "prompt": null,
		"menu": null, "input": null, "vows": [], "pendingBreaks": [], "graceSteps": 4, "log": [], "roll": null, "waitKey": null,
		"party": [human("HORTENSE", "fighter"), human("ROLF", "cleric"), human("EUGENE", "wizard")],
	}
	G.map = Floors.gen_floor(1)
	G.map.palette = Render.PALETTES[5]
	G.map.seed = 12345
	G.x = 1
	G.y = 1
	G.dir = 0
	for d in 4:
		var dx: int = Render.DIRS[d][0]
		var dy: int = Render.DIRS[d][1]
		if Floors.cell(G.map.grid, 1 + dx, 1 + dy) == 1:
			G.dir = d
			break
	G.seen = {}
	G.visited = {G.map.n + 1: true}
	for text in [
		["You descend into the Donjon. The monsters here listen, if you talk to them.", "dim"],
		["HORTENSE IS A FIGHTER, ROLF A CLERIC WHO HEALS, EUGENE A WIZARD. EVERY SWING, SPELL AND PLEA IS A DICE ROLL.", "dim"],
		["FIND THE STAIRS ON EACH FLOOR. EVERY FLOOR YOU CLEAR EARNS A ROLL OF FATE.", "dim"],
		["FLOOR 1 IS QUIET: SMALL HALLS, LONE SLIMES AND GOBLINS. A GOOD PLACE TO LEARN THE DICE.", "dim"],
	]:
		G.log.append({"text": text[0], "cls": text[1], "color": null})
	return G


## encounter([goblin, slime]) with a slime ally along, after a round
static func combat(seed_n := 7) -> Dictionary:
	var G := explore(seed_n)
	G.party.append(ally("slime", "Glop"))
	G.mode = "combat"
	var a := enemy("goblin", "Krunk", "e0")
	var b := enemy("slime", "Mellow", "e1")
	a.hp = 5
	a.cond = {"enraged": true}
	b.cond = {"asleep": true}
	G.combat = {"enemies": [a, b], "nextId": 2, "target": "e0", "round": 1, "conversation": [], "history": [], "rounds": {}, "spoken": {}, "vowed": false, "kills": 0, "recruits": [], "boss": false, "guide": null}
	G.party[0].hp = 7
	G.party[2].hp = 2
	G.party[2].cond = {"poisoned": 2}
	G.party[1].slots = [1]
	G.log.append({"text": "A GOBLIN APPEARS!", "cls": "big", "color": "#9ed36b"})
	G.log.append({"text": "WHO MOVES FIRST: PARTY ROLLED 14, MONSTERS 9. YOU ACT FIRST!", "cls": "", "color": null})
	G.log.append({"text": "YOU: \"hello there\"", "cls": "you", "color": null})
	G.log.append({"text": "KRUNK: Grr. *bares its teeth*", "cls": "npc", "color": "#9ed36b"})
	G.log.append({"text": "EUGENE IS POISONED.", "cls": "warn", "color": null})
	return G
