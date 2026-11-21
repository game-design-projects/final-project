## Experience and levels inside one run (#162): a finished fight teaches something however it ended, and enough of it makes a
## level, which is more max HP, health back, and (every second level) a harder strike. The numbers are in data/experience.json:
## this reads them and rolls nothing, and the scene keeps what a run has learned.
##
## What a fight teaches does not depend on how you ended it — slain, spared, or won over after a spare — so the mercy the game is
## built around is never the slower path. Fleeing is the one way out that teaches nothing, so a monster can't be farmed by backing
## off and walking back into it.
extends RefCounted

const Content = preload("res://src/rules/content.gd")


static func table() -> Dictionary:
	return Content.table("experience")


## What finishing a fight as `how` ("slain" or "spared") is worth, and a champion's bonus on top. Anything else, a fight fled
## among them, is worth none.
static func xp_for(how: String, boss: bool) -> int:
	var xp: Dictionary = table().xp
	var out := int(xp.get(how, 0))
	if boss:
		out += int(xp.get("champion", 0))
	return maxi(0, out)


## How much experience each level takes, level 1 first.
static func levels() -> Array:
	return table().levels


## The level this much experience makes. Level 1 is where every run starts, so anything under the second level's price is
## still 1.
static func level_at(xp: int) -> int:
	var at := 1
	for i in levels().size():
		if xp < int(levels()[i]):
			break
		at = i + 1
	return at


## What the next level takes, or -1 at the top.
static func next_at(level: int) -> int:
	return int(levels()[level]) if level >= 1 and level < levels().size() else -1


## How far the run is between this level and the next, 0..1: what the status row fills. The same numbers `within` gives, so the
## thin line under the health bar and the camp's sentence cannot disagree. Full at the top level.
static func frac(xp: int) -> float:
	var at := within(xp)
	if int(at.need) <= 0:
		return 1.0
	return clampf(float(at.into) / float(at.need), 0.0, 1.0)


## How much of the level's price is paid: the experience into it, and what the level costs (0 and 0 at the top), for wherever
## the run says where it stands.
static func within(xp: int) -> Dictionary:
	var level := level_at(xp)
	var next := next_at(level)
	if next < 0:
		return {"into": 0, "need": 0}
	var from: int = int(levels()[level - 1])
	return {"into": xp - from, "need": next - from}


## What reaching this level adds: max HP, the health it gives back, and the strike every hit gains (0 on an ordinary level).
static func gain(level: int) -> Dictionary:
	var g: Dictionary = table().gain
	if level <= 1: # the level every run starts at gives nothing: it is only what a level above it adds
		return {"max_hp": 0, "heal": 0, "edge": 0}
	return {
		"max_hp": maxi(0, int(g.get("max_hp", 0))),
		"heal": maxi(0, int(g.get("heal", 0))),
		"edge": int(g.get("edge", 0)) if edge_level(level) else 0,
	}


## Whether a level brings the harder strike: the second, and every `edge_every` levels after it, so 2, 4, 6 ... with the data's
## 2. Counted from the second because level 1 is where every run starts and is nobody's news.
static func edge_level(level: int) -> bool:
	var every := maxi(1, int(table().gain.get("edge_every", 1)))
	return level >= 2 and (level - 2) % every == 0


## What every strike that lands has earned from the levels reached so far.
static func edge(level: int) -> int:
	var each := int(table().gain.get("edge", 0))
	var out := 0
	for l in range(2, level + 1):
		if edge_level(l):
			out += each
	return out
