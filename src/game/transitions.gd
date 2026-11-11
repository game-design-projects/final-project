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
##   or, in the personality slice, on to the next intro.
extends RefCounted

const ALLOWED := {
	"": ["explore"], # a new run or a loaded one
	"explore": ["intro", "end", "explore", "trade", "request", "camp"],
	"camp": ["explore"],
	"intro": ["menu", "wait", "dodge"], # a monster that caught you strikes first
	"social": ["menu", "wait", "explore", "intro"],
	"menu": ["social", "act", "items", "skills", "fightbar", "wait", "explore", "intro", "menu", "ask"], # explore, intro: the fight is over; ask: it was spared
	"items": ["menu", "wait", "explore", "intro"],
	"skills": ["menu", "wait", "explore", "intro"], # skill-combat: back, its attack, or the fight is over
	"trade": ["explore"],
	"request": ["explore"],
	"ask": ["explore", "intro"],
	"act": ["menu", "talk", "wait", "explore", "intro"],
	"talk": ["act", "menu", "wait", "explore", "intro"],
	"fightbar": ["wait", "explore", "intro", "menu"],
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
const WALK := ["explore", "end", "trade", "request", "camp"]
## The fight is waiting for the player to pick something: the foe's card and the chat card may open, and a spareable foe shows
## its bubble.
const PICKING := ["intro", "menu", "act", "items", "skills", "talk"]


static func stages() -> Array:
	return ALLOWED.keys().filter(func(s): return s != "")


static func allowed(from: String, to: String) -> bool:
	return ALLOWED.get(from, []).has(to)
