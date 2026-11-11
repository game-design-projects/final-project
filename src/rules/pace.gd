## How fast a dodge runs: slower than the original dodge to begin with, then faster down the floors and
## slower when the foe is friendly, when the player has been getting hit, with allies at their side, or with the EASY DODGE
## setting. 1.0 is the classic pace. Hazards come further apart and warn for longer as the number falls.
extends RefCounted

const BASE := 0.72
const PER_FLOOR := 0.06
const FRIENDLY := 0.22 # taken off at full friendliness
const BOSS := 0.06
const PER_STRUGGLE := 0.05 # for each hit lately
const STRUGGLE_MAX := 4.0
const PER_ALLY := 0.04
const EASY_SCALE := 0.75
const OPENING := [0.85, 0.92] # the first fights of a run, in order (the feature tutorial)
const LOWEST := 0.4
const HIGHEST := 1.05
const DURATION_SCALE := 0.85 # a shorter dodge, so a fight isn't mostly waiting


## The pace of the next dodge from `foe` at this depth. `struggle` is how many hits lately (see `after_dodge`).
static func of(foe, depth: int, struggle: float, allies: int, easy: bool) -> float:
	var p := BASE + PER_FLOOR * (depth - 1)
	p -= FRIENDLY * float(foe.meters.friendliness) / 100.0
	p += BOSS if foe.boss else 0.0
	p -= PER_STRUGGLE * minf(struggle, STRUGGLE_MAX)
	p -= PER_ALLY * allies
	p *= EASY_SCALE if easy else 1.0
	return clampf(p, LOWEST, HIGHEST)


## What the first fights of a run ease the pace by, from how many came before.
static func opening(fights_before: int) -> float:
	return OPENING[fights_before] if fights_before < OPENING.size() else 1.0


## How the struggle stands after a dodge in which you took `hits`: each hit adds one, a clean dodge eases it.
static func after_dodge(struggle: float, hits: int) -> float:
	return clampf(struggle + hits if hits > 0 else struggle - 1.0, 0.0, STRUGGLE_MAX)
