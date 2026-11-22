## Which stage can follow which. The flow refuses (and reports) any other move, so a stage can't wander into one it has
## no business in. This table is the whole shape of a run:
##
##   explore ─▶ intro ─▶ menu ─▶ act ─▶ talk
##      │                 │ ╲      │      │
##      │                 │  ▶ fightbar   │
##      ▼                 ▼        ▼      ▼
##     end            wait ─▶ dodge ─▶ dead
##   Enter on the walk sits you down: explore to camp and back.
##   SPARE that lands goes from menu to ask (it asks to come along), and from there back to explore.
##   HEAVY goes from menu to fightbar as FIGHT does. With skill-combat, SKILLS goes from menu to skills and on like an ACT. ITEM goes from menu to items and on like an ACT; walking into a trader goes from explore to trade and back, and into a monster with a request to request and back.
##   A fight that ends (spared, slain, a cut paid, fled) goes from menu, act, talk or fightbar straight back to explore,
##   or, with fights queued (social-demo), on to the next intro.
##   A champion out of the way leaves keepsakes (the feature keepsakes): the fight ends in keepsake, and goes on from there as above.
##   The Hoard's vault on one floor of a run opens out of the walk (explore to keepsake, #161), and the choice goes back to explore.
extends RefCounted

const ALLOWED := {
	"": ["explore"], # a new run or a loaded one
	"explore": ["intro", "end", "explore", "trade", "request", "camp", "keepsake"], # keepsake: the Hoard's vault, out of the walk (#161)
	"camp": ["explore"],
	"intro": ["menu", "wait", "dodge"], # a monster that caught you strikes first
	"social": ["menu", "wait", "explore", "intro", "keepsake"],
	"menu": ["social", "act", "items", "skills", "fightbar", "wait", "explore", "intro", "menu", "ask", "keepsake"], # explore, intro: the fight is over; ask: it was spared; keepsake: it was a champion
	"items": ["menu", "wait", "explore", "intro", "keepsake"],
	"skills": ["menu", "wait", "explore", "intro", "keepsake"], # skill-combat: back, its attack, or the fight is over
	"trade": ["explore"],
	"request": ["explore"],
	"ask": ["explore", "intro", "keepsake"],
	"act": ["menu", "talk", "wait", "explore", "intro", "keepsake"],
	"talk": ["act", "menu", "wait", "explore", "intro", "keepsake"],
	"fightbar": ["wait", "explore", "intro", "menu", "keepsake"],
	"keepsake": ["explore", "intro"], # one is taken, and the fight's end goes on
	"wait": ["dodge"],
	"dodge": ["menu", "dead"],
	"dead": ["intro", "explore"],
	"end": ["explore"],
}

## What kind of moment each stage is, for whoever has to tell them apart (the flow, the picture, the tooltips). Every stage is
## in exactly one of FIGHT and WALK, which meta_test checks, so a new stage must say which it is here and nowhere else.
## In a fight: a foe stands before you and the battle screen covers the halls.
const FIGHT := ["social", "intro", "menu", "ask", "act", "items", "skills", "talk", "fightbar", "wait", "dodge", "dead"]
## On the floor, out of a fight: the automap shows, and the map's card may open.
const WALK := ["explore", "end", "trade", "request", "camp", "keepsake"]
## The fight is waiting for the player to pick something: the foe's card and the chat card may open, and a spareable foe shows
## its bubble.
const PICKING := ["intro", "menu", "act", "items", "skills", "talk"]
## The stages whose choice is the whole moment (a keepsake to take, who holds the gate, the way down, how the run ends): the
## picture gives its middle to them, each choice a card with what it does written on it (view/choice_popup.gd), and the dock
## keeps the log and the keys.
const DECIDING := ["keepsake", "end"]


static func stages() -> Array:
	return ALLOWED.keys().filter(func(s): return s != "")


static func allowed(from: String, to: String) -> bool:
	return ALLOWED.get(from, []).has(to)
