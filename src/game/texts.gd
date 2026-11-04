## What the game says in its log: one place for the narration, so wording can be changed (or translated) without
## touching the rules. Monster lines come from data/species.json; this is the narrator and the menu hints.
extends RefCounted

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")

const SPARE_TIP := "Acceptance is a roll at any odds. Gold marks a 50%+ chance, not a guarantee. A spared monster may join as a passive charm."
const BOSS_RULE := "The champion shifts its rules every turn: chess, shadow, rhythm, goo."
const GOLD_ACT_TIP := "Costs 6 gold if accepted; ends the fight"


static func new_floor(depth: int) -> String:
	return "B%dF. Find the stairs." % depth


static func welcome_back(summary: String) -> String:
	return "Welcome back. %s." % summary


static func fight_rule(genre: Dictionary) -> String:
	return "It fights in %s. %s." % [genre.name, genre.rule]


static func you(what: String) -> String:
	return "You %s." % what.to_lower()


# ---- the foe's mood

## "friendliness rises; anger falls": what a feeling changes, in words.
static func feeling_effect(feeling: Dictionary) -> String:
	var changes := []
	for k in ["friendliness", "anger", "fear"]:
		var amount: float = feeling.get("meters", {}).get(k, 0.0)
		if amount != 0.0:
			changes.append("%s %s" % [k, "rises" if amount > 0.0 else "falls"])
	return "; ".join(changes) if not changes.is_empty() else "its mood shifts"


static func foe_feels(foe, feeling: Dictionary) -> String:
	return "%s is %s: %s." % [foe.name, feeling.label, feeling_effect(feeling)]


static func check(foe, individual_clues: Array) -> String:
	var sp := Content.species(foe.species)
	var likes: Array = sp.likes.slice(0, 2)
	var individual := "This one may differ." if individual_clues.is_empty() else "It %s." % ". It ".join(individual_clues)
	return "%s seems %s. Its kind likes %s and hates %s. %s" % [foe.name, " and ".join(foe.traits), ", ".join(likes), sp.dislikes[0], individual]


# ---- a fair cut of gold

static func cut_too_poor(gold: int, typed: bool) -> String:
	return "A fair cut is %d gold. You have %d.%s" % [Combat.CUT_COST, gold, " Your line is spent." if typed else ""]


static func cut_refused_reason(foe) -> String:
	if foe.meters.anger >= 60.0:
		return "It is too angry to trust an offer"
	if foe.has_trait("secretive"):
		return "It watches for a catch"
	if foe.has_trait("jumpy"):
		return "It keeps watching the exit"
	if foe.has_trait("proud"):
		return "Its pride outweighs the coins"
	return "It decides the risk is not worth the coins"


static func cut_refused(foe) -> String:
	return "You offer %d gold. %s. You keep your gold." % [Combat.CUT_COST, cut_refused_reason(foe)]


static func cut_accepted(foe) -> String:
	var reason := "The bargain suits it."
	if foe.has_trait("surprisingly honest about being dishonest"):
		reason = "It keeps its word."
	elif foe.has_trait("owes money to someone"):
		reason = "It needed the coins."
	return "SPARED. It takes %d gold and leaves. %s" % [Combat.CUT_COST, reason]


# ---- talking

static func said(text: String) -> String:
	return 'You say "%s".' % text


const ASKED := "You ask a question."
const NOT_UNDERSTOOD := "It didn't understand a word of that."


static func reveal_reason(foe) -> String:
	if foe.has_trait("curious"):
		return "Curious, it answers"
	if foe.has_trait("surprisingly honest about being dishonest"):
		return "It speaks plainly"
	return "It trusts you enough to answer"


static func no_answer(foe) -> String:
	var reason := "It does not trust you yet"
	if foe.has_trait("secretive"):
		reason = "It guards its secrets"
	elif foe.has_trait("jumpy"):
		reason = "It keeps watching the exit"
	return reason + " and gives no answer."


static func already_spoke() -> String:
	return "You've had your say this fight."


# ---- the fight

static func miss() -> String:
	return "You swing wide and miss."


static func hit(damage: int, crit: bool) -> String:
	return "%s%d damage." % ["A perfect strike! " if crit else "", damage]


static func mercy_refused(foe, odds: float) -> String:
	return "You offer mercy. %s refuses mercy. (%s chance to accept)" % [foe.name, Combat.chance_label(odds)]


static func flee(foe) -> String:
	return "You back away. %s stays where it is." % foe.name


const BOSS_BLOCKS := "The champion's tail blocks the way back."
const NOT_ATTACKING := "It doesn't attack this turn."


static func pauses(foe, spareable: bool) -> String:
	return "%s pauses. %s" % [foe.name, "Mercy odds are at least 50%." if spareable else "What now?"]


static func falls(foe) -> String:
	return "%s falls." % foe.name


static func verdict_spared(joined: bool, charm: Dictionary) -> String:
	return "SPARED. It joins you: %s, %s." % [charm.name, charm.text] if joined else "SPARED. It goes its own way."


const VERDICT_SLAIN := "SLAIN."


static func ally_gone(charm_name: String) -> String:
	return "(%s is gone)" % charm_name


static func you_fall(foe) -> String:
	return "You fall. %s watches." % foe.name


# ---- the end of a floor

static func floor_done(depth: int) -> String:
	return "B%dF behind you. The stairs go on down, and you catch your breath on the way." % depth


## {route, text, tail} for the summary at the stairs.
static func ending(tally: Dictionary, allies: Array) -> Dictionary:
	var met: int = tally.spared + tally.slain
	var route: String
	var text: String
	if met == 0:
		route = "THE GHOST ROUTE"
		text = "You slipped past everything. Nobody down here knows your name yet."
	elif tally.slain == 0:
		route = "THE QUIET ROUTE"
		text = "Every monster you met is still alive, and some of them are following you down."
	elif tally.spared == 0:
		route = "THE BLOOD ROUTE"
		text = "The halls go quiet behind you. On the next floor, the monsters will have heard."
	else:
		route = "THE TANGLED ROUTE"
		text = "Some you spared, some you didn't. The ones you spared saw what you did to the others."
	var tail := "Spared %d · slain %d · fled %d · recruited %d" % [tally.spared, tally.slain, tally.fled, tally.recruited]
	if tally.left > 0:
		tail += " · %d walked out on you" % tally.left
	if not allies.is_empty():
		tail += " · still with you: %s" % ", ".join(allies.map(func(a): return a.name))
	return {"route": route, "text": text, "tail": tail + "."}
