## D&D 5e-style rules: dice, classes, spells and monster stat blocks. Plain data and helpers, no UI.
## The tables are read-only constants: `.duplicate(true)` before changing a copy.
extends RefCounted

const J = preload("res://src/core/js.gd")

static var _dice_re := RegEx.create_from_string("^(\\d+)d(\\d+)([+-]\\d+)?$")
static var _dice_ci_re := RegEx.create_from_string("(?i)^(\\d+)d(\\d+)([+-]\\d+)?$")


## 1 + Math.floor(Math.random() * sides)
static func d(sides: int) -> int:
	return 1 + randi() % sides


## A d20 roll as {roll, rolls, adv}. adv > 0: roll two, keep the higher; adv < 0: keep the lower.
static func d20(adv = 0) -> Dictionary:
	var a := d(20)
	if not adv:
		return {"roll": a, "rolls": [a], "adv": 0}
	var b := d(20)
	return {"roll": maxi(a, b) if adv > 0 else mini(a, b), "rolls": [a, b], "adv": signi(int(adv))}


## "2d6+3" → total. A critical hit rolls the dice twice (the modifier once), as in 5e.
## opts: {crit = false, count = <dice count override>}. A malformed spec is a programmer error: logged, rolls 0.
static func roll_dice(spec: String, opts := {}) -> int:
	var m := _dice_re.search(spec)
	if m == null:
		push_error("bad dice %s" % spec)
		return 0
	var n: int = int(J.nz(opts.get("count"), int(m.get_string(1)))) * (2 if opts.get("crit", false) else 1)
	var total := int(m.get_string(3)) if m.get_string(3) != "" else 0
	for i in n:
		total += d(int(m.get_string(2)))
	return maxi(0, total)


## "ROLLED 14 +5 = 19", or "ROLLED 16 (ADVANTAGE) +5 = 21" when it rolled two dice and kept the better one
static func fmt_roll(r: Dictionary, bonus = 0) -> String:
	var how := ""
	if r.rolls.size() > 1:
		how = " (%s)" % ("ADVANTAGE" if r.adv > 0 else "DISADVANTAGE")
	var tail := ""
	if J.truthy(bonus):
		tail = " %s%s = %s" % ["+" if bonus > 0 else "-", J.num(absf(bonus)), J.num(r.roll + bonus)]
	return "ROLLED %s%s%s" % [J.num(r.roll), how, tail]


## "8d6" → "8-48": a range a newcomer can read, instead of dice notation.
static func dice_range(spec: String) -> String:
	var m := _dice_ci_re.search(spec)
	if m == null:
		push_error("bad dice %s" % spec)
		return ""
	var n := int(m.get_string(1))
	var k := int(m.get_string(3)) if m.get_string(3) != "" else 0
	return "%d-%d" % [maxi(0, n + k), n * int(m.get_string(2)) + k]


## Saving throws and abilities by name, for the log.
const ABILITY_WORDS = {
	"str": "STRENGTH",
	"dex": "DEXTERITY",
	"con": "CONSTITUTION",
	"int": "INTELLIGENCE",
	"wis": "WISDOM",
	"cha": "CHARISMA",
}


static func prof(level) -> int:
	return 2 + floori((maxf(1.0, float(level)) - 1.0) / 4.0)


const CLASSES = {
	"fighter": {
		"code": "FIGHTR",
		"hitDie": 10,
		"abil": {"str": 3, "dex": 1, "con": 2, "int": 0, "wis": 1, "cha": 0},
		"saves": ["str", "con"],
		"ac": 16,
		"weapon": {"name": "LONGSWORD", "dice": "1d8", "stat": "str"},
		"caster": null,
	},
	"cleric": {
		"code": "CLERIC",
		"hitDie": 8,
		"abil": {"str": 1, "dex": 0, "con": 2, "int": 0, "wis": 3, "cha": 2},
		"saves": ["wis", "cha"],
		"ac": 15,
		"weapon": {"name": "MACE", "dice": "1d6", "stat": "str"},
		"caster": "wis",
	},
	"wizard": {
		"code": "WIZARD",
		"hitDie": 6,
		"abil": {"str": -1, "dex": 2, "con": 1, "int": 3, "wis": 1, "cha": 1},
		"saves": ["int", "wis"],
		"ac": 12,
		"weapon": {"name": "DAGGER", "dice": "1d4", "stat": "dex"},
		"caster": "int",
	},
}

## Spell slots per character level for the 1st, 2nd and 3rd circles (the 5e full-caster table, capped at 3rd).
const SLOT_TABLE = [[2], [2], [3], [4, 2], [4, 3], [4, 3, 2], [4, 3, 3]]


static func slots_for(level) -> Array:
	return SLOT_TABLE[mini(int(level), SLOT_TABLE.size() - 1)].duplicate()


## kind: attack (spell attack roll), auto (always hits), save (target saves), sleep, heal, bless, revive.
## target: enemy (your current target), all (every enemy), ally, party, dead.
const SPELLS = {
	"fire_bolt": {
		"name": "FIRE BOLT",
		"cls": "wizard",
		"lvl": 0,
		"kind": "attack",
		"dice": "1d10",
		"target": "enemy",
		"sfx": "fire",
		"cantrip": true,
	},
	"magic_missile": {
		"name": "MAGIC MISSILE",
		"cls": "wizard",
		"lvl": 1,
		"kind": "auto",
		"dice": "1d4+1",
		"darts": 3,
		"target": "enemy",
		"sfx": "missile",
	},
	"burning_hands": {
		"name": "BURNING HANDS",
		"cls": "wizard",
		"lvl": 1,
		"kind": "save",
		"save": "dex",
		"dice": "3d6",
		"half": true,
		"target": "all",
		"sfx": "fire",
	},
	"sleep": {"name": "SLEEP", "cls": "wizard", "lvl": 1, "kind": "sleep", "dice": "5d8", "target": "all", "sfx": "sleep"},
	"scorching_ray": {
		"name": "SCORCHING RAY",
		"cls": "wizard",
		"lvl": 2,
		"kind": "attack",
		"dice": "2d6",
		"rays": 3,
		"target": "enemy",
		"sfx": "fire",
	},
	"hold_monster": {
		"name": "HOLD MONSTER",
		"cls": "wizard",
		"lvl": 2,
		"kind": "save",
		"save": "wis",
		"effect": "held",
		"target": "enemy",
		"sfx": "hold",
	},
	"fireball": {
		"name": "FIREBALL",
		"cls": "wizard",
		"lvl": 3,
		"kind": "save",
		"save": "dex",
		"dice": "8d6",
		"half": true,
		"target": "all",
		"sfx": "fireball",
	},
	"sacred_flame": {
		"name": "SACRED FLAME",
		"cls": "cleric",
		"lvl": 0,
		"kind": "save",
		"save": "dex",
		"dice": "1d8",
		"target": "enemy",
		"sfx": "holy",
		"cantrip": true,
	},
	"cure_wounds": {"name": "CURE WOUNDS", "cls": "cleric", "lvl": 1, "kind": "heal", "dice": "1d8", "target": "ally", "sfx": "heal"},
	"bless": {"name": "BLESS", "cls": "cleric", "lvl": 1, "kind": "bless", "target": "party", "sfx": "buff"},
	"guiding_bolt": {
		"name": "GUIDING BOLT",
		"cls": "cleric",
		"lvl": 1,
		"kind": "attack",
		"dice": "4d6",
		"effect": "lit",
		"target": "enemy",
		"sfx": "holy",
	},
	"prayer_of_healing": {
		"name": "PRAYER OF HEALING",
		"cls": "cleric",
		"lvl": 2,
		"kind": "heal",
		"dice": "2d8",
		"target": "party",
		"sfx": "heal",
	},
	"revivify": {"name": "REVIVIFY", "cls": "cleric", "lvl": 3, "kind": "revive", "target": "dead", "sfx": "revive"},
	"spirit_guardians": {
		"name": "SPIRIT GUARDIANS",
		"cls": "cleric",
		"lvl": 3,
		"kind": "save",
		"save": "wis",
		"dice": "3d8",
		"half": true,
		"target": "all",
		"sfx": "holy",
	},
}

## What each spell does, in words. {DMG} becomes the damage range at the caster's level (free spells grow).
const SPELL_TEXT = {
	"fire_bolt": "{DMG} FIRE DAMAGE IF IT HITS",
	"magic_missile": "3 DARTS OF {DMG} DAMAGE THAT NEVER MISS",
	"burning_hands": "{DMG} FIRE TO EVERY ENEMY. HALF IF THEY DODGE",
	"sleep": "PUTS THE WEAKEST ENEMIES TO SLEEP",
	"scorching_ray": "3 RAYS OF {DMG} FIRE, EACH ROLLS TO HIT",
	"hold_monster": "PARALYZES ONE ENEMY UNLESS IT RESISTS: IT LOSES TURNS AND YOUR HITS ARE CRITICAL",
	"fireball": "{DMG} FIRE TO EVERY ENEMY. HALF IF THEY DODGE",
	"sacred_flame": "{DMG} HOLY DAMAGE UNLESS IT DODGES",
	"cure_wounds": "HEALS ONE OF YOU FOR {DMG}, MORE WITH WISDOM",
	"bless": "+1 TO 4 ON THE PARTY'S ATTACKS AND SAVES THIS FIGHT",
	"guiding_bolt": "{DMG} HOLY DAMAGE, AND THE NEXT ATTACK ON IT IS BETTER",
	"prayer_of_healing": "HEALS THE WHOLE PARTY FOR {DMG}, MORE WITH WISDOM",
	"revivify": "BRINGS A DEAD ALLY BACK WITH 1 HEALTH",
	"spirit_guardians": "{DMG} HOLY DAMAGE TO EVERY ENEMY. HALF IF THEY RESIST",
}


## A spell's description for a caster of this level.
static func spell_text(key: String, level = 1) -> String:
	var s: Dictionary = SPELLS[key]
	var dice := ""
	if s.get("dice") != null:
		dice = ("%d%s" % [cantrip_dice(level), s.dice.substr(s.dice.find("d"))]) if s.get("cantrip", false) else s.dice
	var text: String = SPELL_TEXT[key]
	var range_text := dice_range(dice) if dice != "" else ""
	var at := text.find("{DMG}")
	return text if at < 0 else text.substr(0, at) + range_text + text.substr(at + 5)


## Spells a caster of this class can cast at this level (the highest circle they have slots for).
static func spells_known(cls: String, level) -> Array:
	var circles := slots_for(level).size()
	var out := []
	for k in SPELLS:
		var s: Dictionary = SPELLS[k]
		if s.cls == cls and s.lvl <= circles:
			out.append(k)
	return out


## Cantrips grow with character level, as in 5e: one die, then two at 5th, three at 11th.
static func cantrip_dice(level) -> int:
	return 3 if level >= 11 else (2 if level >= 5 else 1)


## 5e-style stat blocks for each species at floor 1 (code scales them with depth).
## special: what the species' special move forces: a saving throw, its damage, and on deeper floors a condition.
const MONSTER_STATS = {
	"slime": {
		"ac": 8,
		"hit": 2,
		"dmg": "1d4+1",
		"dex": -2,
		"saves": {"str": 1, "dex": -2, "con": 2, "int": -4, "wis": -1, "cha": -3},
		"special": {"save": "str", "dc": 10, "dice": "1d6+1", "cond": "restrained", "rounds": 2},
	},
	"goblin": {
		"ac": 12,
		"hit": 4,
		"dmg": "1d6+2",
		"dex": 0,
		"saves": {"str": 3, "dex": 0, "con": 2, "int": -1, "wis": -1, "cha": -1},
		"special": {"save": "str", "dc": 12, "dice": "2d6+2", "cond": "prone", "rounds": 1},
	},
	"dragon": {
		"ac": 17,
		"hit": 6,
		"dmg": "2d6+3",
		"dex": 2,
		"saves": {"str": 4, "dex": 2, "con": 5, "int": 2, "wis": 3, "cha": 3},
		"special": {"save": "dex", "dc": 14, "dice": "4d6", "cond": null},
	},
	"snake": {
		"ac": 13,
		"hit": 4,
		"dmg": "1d6+2",
		"dex": 3,
		"saves": {"str": 1, "dex": 3, "con": 1, "int": 1, "wis": 1, "cha": 2},
		"special": {"save": "con", "dc": 12, "dice": "2d6", "cond": "poisoned", "rounds": 3},
	},
	"rock": {
		"ac": 17,
		"hit": 5,
		"dmg": "1d10+2",
		"dex": -1,
		"saves": {"str": 4, "dex": -1, "con": 4, "int": -2, "wis": 0, "cha": -2},
		"special": {"save": "dex", "dc": 13, "dice": "2d8", "cond": "prone", "rounds": 1},
	},
	"bandit": {
		"ac": 13,
		"hit": 4,
		"dmg": "1d6+2",
		"dex": 3,
		"saves": {"str": 1, "dex": 3, "con": 1, "int": 0, "wis": 0, "cha": 1},
		"special": {"save": "dex", "dc": 12, "dice": "2d4+1", "cond": null},
	},
}

## Conditions on party members and monsters, and what they do.
const CONDITION_TEXT = {
	"poisoned": "POISONED: DISADVANTAGE ON ATTACKS",
	"restrained": "RESTRAINED: DISADVANTAGE ON ATTACKS, EASIER TO HIT",
	"prone": "KNOCKED DOWN: LOSES ITS NEXT ACTION",
	"asleep": "ASLEEP: SKIPS TURNS UNTIL HURT, YOUR HITS CRIT",
	"held": "PARALYZED: SKIPS TURNS, YOUR HITS CRIT",
}
