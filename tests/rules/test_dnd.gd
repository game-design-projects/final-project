extends "res://tests/test_case.gd"

const Dnd = preload("res://src/rules/dnd.gd")


func test_d_stays_in_range():
	seed(7)
	var seen := {}
	for i in 400:
		var v := Dnd.d(6)
		ok(v >= 1 and v <= 6)
		seen[v] = true
	eq(seen.size(), 6, "every face shows up")


func test_d20_plain_and_with_advantage():
	seed(1)
	var r := Dnd.d20()
	eq(r.rolls.size(), 1)
	eq(r.adv, 0)
	eq(r.roll, r.rolls[0])
	for i in 100:
		var up := Dnd.d20(1)
		eq(up.roll, maxi(up.rolls[0], up.rolls[1]))
		eq(up.adv, 1)
		var down := Dnd.d20(-3)
		eq(down.roll, mini(down.rolls[0], down.rolls[1]))
		eq(down.adv, -1, "adv is the sign")


func test_roll_dice_bounds_modifier_crit_and_count():
	seed(3)
	for i in 100:
		var v := Dnd.roll_dice("2d6+3")
		ok(v >= 5 and v <= 15, "2d6+3 = %d" % v)
		var crit := Dnd.roll_dice("2d6+3", {"crit": true})
		ok(crit >= 7 and crit <= 27, "crit rolls the dice twice, the modifier once: %d" % crit)
		var counted := Dnd.roll_dice("1d4+1", {"count": 3})
		ok(counted >= 4 and counted <= 13, "count overrides the dice number: %d" % counted)
		ok(Dnd.roll_dice("1d4-9") == 0, "never below zero")
	eq(Dnd.roll_dice("1d1+4"), 5)
	eq(Dnd.roll_dice("3d1-1"), 2)


func test_fmt_roll():
	eq(Dnd.fmt_roll({"roll": 14, "rolls": [14], "adv": 0}, 5), "ROLLED 14 +5 = 19")
	eq(Dnd.fmt_roll({"roll": 14, "rolls": [14], "adv": 0}, -2), "ROLLED 14 -2 = 12")
	eq(Dnd.fmt_roll({"roll": 16, "rolls": [16, 3], "adv": 1}, 5), "ROLLED 16 (ADVANTAGE) +5 = 21")
	eq(Dnd.fmt_roll({"roll": 3, "rolls": [16, 3], "adv": -1}, 0), "ROLLED 3 (DISADVANTAGE)")
	eq(Dnd.fmt_roll({"roll": 9, "rolls": [9], "adv": 0}, null), "ROLLED 9")
	eq(Dnd.fmt_roll({"roll": 9.0, "rolls": [9.0], "adv": 0}, 2.0), "ROLLED 9 +2 = 11", "floats from JSON print as ints")


func test_dice_range():
	eq(Dnd.dice_range("8d6"), "8-48")
	eq(Dnd.dice_range("1d4+1"), "2-5")
	eq(Dnd.dice_range("2D8"), "2-16")
	eq(Dnd.dice_range("1d4-9"), "0--5", "the low end clamps at 0, the high end does not")


func test_prof_and_slots():
	eq(Dnd.prof(1), 2)
	eq(Dnd.prof(4), 2)
	eq(Dnd.prof(5), 3)
	eq(Dnd.prof(0), 2)
	eq(Dnd.slots_for(1), [2])
	eq(Dnd.slots_for(3), [4, 2])
	eq(Dnd.slots_for(6), [4, 3, 3])
	eq(Dnd.slots_for(40), [4, 3, 3], "capped at the table")
	var s := Dnd.slots_for(2)
	s[0] = 99
	eq(Dnd.slots_for(2), [3], "callers get a copy")


func test_cantrip_dice_grow_with_level():
	eq(Dnd.cantrip_dice(1), 1)
	eq(Dnd.cantrip_dice(5), 2)
	eq(Dnd.cantrip_dice(11), 3)


func test_spell_text_fills_damage_range():
	eq(Dnd.spell_text("fireball"), "8-48 FIRE TO EVERY ENEMY. HALF IF THEY DODGE")
	eq(Dnd.spell_text("fire_bolt", 1), "1-10 FIRE DAMAGE IF IT HITS")
	eq(Dnd.spell_text("fire_bolt", 5), "2-20 FIRE DAMAGE IF IT HITS")
	eq(Dnd.spell_text("magic_missile"), "3 DARTS OF 2-5 DAMAGE THAT NEVER MISS")
	eq(Dnd.spell_text("sleep"), "PUTS THE WEAKEST ENEMIES TO SLEEP")
	eq(Dnd.spell_text("revivify"), "BRINGS A DEAD ALLY BACK WITH 1 HEALTH")
	for k in Dnd.SPELLS:
		ok(Dnd.SPELL_TEXT.has(k), "%s has text" % k)


func test_spells_known_follow_the_circles_you_have():
	eq(Dnd.spells_known("wizard", 1), ["fire_bolt", "magic_missile", "burning_hands", "sleep"])
	eq(Dnd.spells_known("wizard", 3), ["fire_bolt", "magic_missile", "burning_hands", "sleep", "scorching_ray", "hold_monster"])
	eq(Dnd.spells_known("cleric", 6).size(), 7)
	eq(Dnd.spells_known("fighter", 6), [])


func test_class_and_monster_tables():
	eq(Dnd.CLASSES.keys(), ["fighter", "cleric", "wizard"])
	eq(Dnd.CLASSES.wizard.caster, "int")
	eq(Dnd.CLASSES.fighter.caster, null)
	eq(Dnd.MONSTER_STATS.dragon.special.cond, null)
	eq(Dnd.MONSTER_STATS.slime.special.cond, "restrained")
	eq(Dnd.ABILITY_WORDS.cha, "CHARISMA")
	eq(Dnd.CONDITION_TEXT.prone, "KNOCKED DOWN: LOSES ITS NEXT ACTION")
