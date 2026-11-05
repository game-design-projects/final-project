## Which stage can follow which. The flow refuses (and reports) any other move, so a stage can't wander into one it has
## no business in. This table is the whole shape of a run:
##
##   explore ─▶ intro ─▶ menu ─▶ act ─▶ talk
##      │                 │ ╲      │      │
##      │                 │  ▶ fightbar   │
##      ▼                 ▼        ▼      ▼
##     end            wait ─▶ dodge ─▶ dead
##   SPARE that lands goes from menu to ask (it asks to come along), and from there back to explore.
##   ITEM goes from menu to items and on like an ACT; walking into a trader goes from explore to trade and back.
##   A fight that ends (spared, slain, a cut paid, fled) goes from menu, act, talk or fightbar straight back to explore,
##   or, in the personality slice, on to the next intro.
extends RefCounted

const ALLOWED := {
	"": ["explore"], # a new run or a loaded one
	"explore": ["intro", "end", "explore", "trade"],
	"intro": ["menu"],
	"menu": ["act", "items", "fightbar", "wait", "explore", "intro", "menu", "ask"], # explore, intro: the fight is over; ask: it was spared
	"items": ["menu", "wait", "explore", "intro"],
	"trade": ["explore"],
	"ask": ["explore", "intro"],
	"act": ["menu", "talk", "wait", "explore", "intro"],
	"talk": ["act", "menu", "wait", "explore", "intro"],
	"fightbar": ["wait", "explore", "intro", "menu"],
	"wait": ["dodge"],
	"dodge": ["menu", "dead"],
	"dead": ["intro", "explore"],
	"end": ["explore"],
}


static func stages() -> Array:
	return ALLOWED.keys().filter(func(s): return s != "")


static func allowed(from: String, to: String) -> bool:
	return ALLOWED.get(from, []).has(to)
