## Allies are passive charms that judge what you do. Each has loyalty (0..100); a deed it dislikes lowers it, one it likes
## raises it, and below a line it may walk out. What it thinks of each deed is in data/encounter.json (ally_approval).
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Dice = preload("res://src/utils/dice.gd")
const Odds = preload("res://src/rules/odds.gd")

const SCORES := 5 # a judgement is 0 (hates it) .. 4 (loves it)
const NEUTRAL := 2
const LOYALTY_PER_POINT := 10.0
const LEAVE_BELOW := 30.0
const START_LOYALTY_MIN := 60
const START_LOYALTY_MAX := 80
const EAGER_LOYALTY := 30.0 # the most wanting to come (or not) moves its starting loyalty, from one end to the other


static func start_loyalty(dice: Dice) -> float:
	return float(dice.int_between(START_LOYALTY_MIN, START_LOYALTY_MAX))


## How loyal one starts that chose to come: the usual start, and more or less by how much it wanted to (0..1).
static func eager_loyalty(dice: Dice, wants: float) -> float:
	return clampf(start_loyalty(dice) + (wants - 0.5) * EAGER_LOYALTY, LEAVE_BELOW + 1.0, 100.0)


## What a monster you made peace with leaves you, {gold, heal}. Gold only comes from one that goes its own way.
static func gift(species: String) -> Dictionary:
	return Content.table("encounter").gifts[species]


## Does an ally of this species have an opinion on this deed? ("slay", "spare", "flee", or a kind of words)
static func has_opinion(species: String, deed: String) -> bool:
	return Content.table("encounter").ally_approval.get(species, {}).has(deed)


## The odds of each score 0..4 for this deed, centred on how much the species cares (a bell curve around its mean).
static func score_odds(species: String, deed: String) -> Dictionary:
	var care: float = Content.table("encounter").ally_approval[species][deed]
	var mean := clampf(NEUTRAL + care, 0.0, SCORES - 1.0)
	var weights := {}
	var total := 0.0
	for i in SCORES:
		weights[str(i)] = exp(-pow(i - mean, 2) * 0.9)
		total += weights[str(i)]
	for k in weights:
		weights[k] /= total
	return weights


## The chance an unhappy ally (loyalty below the line) leaves after this deed.
static func leave_odds(loyalty: float) -> float:
	return Odds.sigmoid((LEAVE_BELOW - loyalty) / 6.0 - 0.5)


## One ally judging one deed. Changes its loyalty and returns what happened: its score, the kind of reaction line
## ("approve", "disapprove" or "" for a shrug), and whether it walked out.
static func judge(ally, deed: String, dice: Dice) -> Dictionary:
	var odds := score_odds(ally.species, deed)
	var score := int(Odds.pick_by_odds(dice, odds))
	ally.loyalty = clampf(ally.loyalty + (score - NEUTRAL) * LOYALTY_PER_POINT, 0.0, 100.0)
	var reaction := "disapprove" if score <= 1 else ("approve" if score >= 3 else "")
	var leaves := false
	if ally.loyalty < LEAVE_BELOW:
		leaves = Odds.succeeds(dice, leave_odds(ally.loyalty))
	print_verbose("allies: %s judges '%s': score %d, loyalty %.0f%s" % [ally.name, deed, score, ally.loyalty, ", leaves" if leaves else ""])
	return {"score": score, "reaction": reaction, "leaves": leaves, "odds": odds}


## "DEVOTED" .. "MAY LEAVE", for the ally's tooltip.
static func mood(loyalty: float) -> String:
	if loyalty >= 70.0:
		return "DEVOTED"
	if loyalty >= 45.0:
		return "CONTENT"
	return "UNEASY" if loyalty >= LEAVE_BELOW else "MAY LEAVE"
