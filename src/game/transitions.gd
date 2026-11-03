## Which stage can follow which. The flow refuses (and reports) any other move, so a stage can't wander into one it has
## no business in. This table is the whole shape of a run:
##
##   explore ─▶ intro ─▶ menu ─▶ act ─▶ talk
##      │                 │ ╲      │      │
##      │                 │  ▶ fightbar   │
##      ▼                 ▼        ▼      ▼
##     end            wait ─▶ dodge ─▶ dead
##                      result ─▶ explore
extends RefCounted

const ALLOWED := {
	"": ["explore"], # a new run or a loaded one
	"explore": ["intro", "end", "explore"],
	"intro": ["menu"],
	"menu": ["act", "fightbar", "wait", "result", "explore", "menu"],
	"act": ["menu", "talk", "wait", "result"],
	"talk": ["act", "menu", "wait", "result"],
	"fightbar": ["wait", "result", "menu"],
	"wait": ["dodge"],
	"dodge": ["menu", "dead"],
	"result": ["explore"],
	"dead": ["intro", "explore"],
	"end": ["explore"],
}


static func stages() -> Array:
	return ALLOWED.keys().filter(func(s): return s != "")


static func allowed(from: String, to: String) -> bool:
	return ALLOWED.get(from, []).has(to)
