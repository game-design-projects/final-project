## Pixel tooltips: how a title's text is laid out.
extends "res://tests/test_case.gd"

const Tooltip = preload("res://src/rules/tooltip.gd")


func test_each_dot_part_of_a_title_gets_its_own_line():
	eq(Tooltip.tip_model("LEVEL 2 · EXPERIENCE 57 OF 91 TO THE NEXT LEVEL · DAMAGE X1.00").lines, [
		"LEVEL 2",
		"EXPERIENCE 57 OF 91 TO THE NEXT LEVEL",
		"DAMAGE X1.00",
	])


func test_a_run_of_ability_scores_becomes_a_table_in_order_with_signs_as_numbers():
	var m := Tooltip.tip_model("LEVEL 2 · STRENGTH -1 DEXTERITY +2 CONSTITUTION +1 INTELLIGENCE +3 WISDOM +1 CHARISMA +1 · WILL CHEAT DEATH ONCE")
	eq(m.lines, ["LEVEL 2", "WILL CHEAT DEATH ONCE"])
	eq(m.stats, [["STRENGTH", -1], ["DEXTERITY", 2], ["CONSTITUTION", 1], ["INTELLIGENCE", 3], ["WISDOM", 1], ["CHARISMA", 1]])


func test_a_sentence_that_merely_mentions_an_ability_stays_a_line():
	var m := Tooltip.tip_model("ROLL 12+ ON STRENGTH +2 TO TAKE HALF")
	eq(m.stats, [])
	eq(m.lines.size(), 1)
	var two := Tooltip.tip_model("STRENGTH +2 DEXTERITY -1 MAKE A GOOD PAIR")
	eq(two.stats, [], "two scores plus words is still a sentence")
	eq(two.lines.size(), 1)


func test_plain_titles_and_empty_input():
	eq(Tooltip.tip_model("ARMOR 16"), {"lines": ["ARMOR 16"], "stats": []})
	eq(Tooltip.tip_model(""), {"lines": [], "stats": []})
	eq(Tooltip.tip_model(null), {"lines": [], "stats": []})
	eq(Tooltip.tip_model("  A  ·   · B "), {"lines": ["A", "B"], "stats": []}, "parts are trimmed and empty ones dropped")
