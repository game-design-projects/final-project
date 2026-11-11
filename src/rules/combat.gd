## The numbers of a fight: what a strike does, what it costs the monster's mood, and the party's starting purse.
## The values are tuning; change them here, nowhere else.
extends RefCounted

const START_HP := 20
const START_GOLD := 8
const CUT_COST := 6 # what a fair cut of gold costs, if the monster takes it
const PARTY_MAX := 3

# The strike bar: a line sweeps across and you stop it near the middle.
const BAR_MS := 1100.0
const BAR_MS_STEADY := 1500.0 # with the rock's charm
const MISS_EDGE := 0.92 # farther than this from the middle is a miss
const CRIT_EDGE := 0.08 # closer than this is a perfect strike
const CRIT_DAMAGE := 14.0
const BOSS_DAMAGE_SCALE := 0.8
const HOARD_FIRE_BONUS := 4 # the dragon's charm

# The heavy strike: the line runs faster and the mark is smaller, for a harder hit that some monsters take worse than others.
# tools/features_test.gd keeps the trade honest: at steady timing it pays against a rock and never against a slime.
const HEAVY_BAR_SCALE := 0.6
const HEAVY_MISS_EDGE := 0.35
const HEAVY_DAMAGE := 1.25
const HEAVY_WEAK := {"rock": 1.5, "dragon": 1.2, "bandit": 1.0, "snake": 0.8, "slime": 0.55}
const HEAVY_MISS_PRESSURE := 0.5 # a miss leaves you off balance: the next attack presses this much harder

# What being hit does to a monster's mood
const HIT_FRIENDLINESS := -8.0
const HIT_ANGER := 10.0
const HIT_FEAR := 8.0
const REFUSED_MERCY_ANGER := 4.0

# What friends do for a fight
const AID_PER_ALLY := 1 # added to every strike
const GUARD_FROM_ALLIES := 2 # this many allies take a point off every hit

# Damage the player takes from one hit in the dodge box
const DODGE_DAMAGE := 3
const DODGE_DAMAGE_BOSS := 4

# Real-time beats between the player's move and the next thing
const INTRO_MS := 700.0
const WINDUP_MS := 650.0


## How a strike landed. `x` is how far along the bar the line was when stopped (0..1). `hoard_fire` is whether the
## party has the dragon's charm, which adds to every strike.
static func strike(x: float, boss: bool, hoard_fire: bool, aid := 0) -> Dictionary:
	var off := absf(x - 0.5) * 2.0
	if off > MISS_EDGE:
		return {"miss": true, "crit": false, "damage": 0}
	var crit := off < CRIT_EDGE
	var base := CRIT_DAMAGE if crit else 4.0 + 8.0 * pow(1.0 - off, 1.2)
	var damage := roundi(base * (BOSS_DAMAGE_SCALE if boss else 1.0)) + (HOARD_FIRE_BONUS if hoard_fire else 0) + aid
	return {"miss": false, "crit": crit, "damage": damage}


## How a heavy strike landed: as `strike`, but it misses sooner and hits harder, by how `species` takes such a blow.
static func heavy_strike(x: float, boss: bool, species: String, hoard_fire: bool, aid := 0) -> Dictionary:
	var off := absf(x - 0.5) * 2.0
	if off > HEAVY_MISS_EDGE:
		return {"miss": true, "crit": false, "damage": 0}
	var crit := off < CRIT_EDGE
	var base := CRIT_DAMAGE if crit else 4.0 + 8.0 * pow(1.0 - off, 1.2)
	var scaled: float = base * HEAVY_DAMAGE * heavy_weakness(species) * (BOSS_DAMAGE_SCALE if boss else 1.0)
	return {"miss": false, "crit": crit, "damage": roundi(scaled) + (HOARD_FIRE_BONUS if hoard_fire else 0) + aid}


## How much a heavy blow does to this species, against 1.0 for one that takes it plainly.
static func heavy_weakness(species: String) -> float:
	return float(HEAVY_WEAK.get(species, 1.0))


## What this many allies add to a strike.
static func party_aid(allies: int) -> int:
	return allies * AID_PER_ALLY


## What this many allies take off each hit in the dodge box.
static func party_guard(allies: int) -> int:
	return 1 if allies >= GUARD_FROM_ALLIES else 0


static func bar_ms(steady: bool) -> float:
	return BAR_MS_STEADY if steady else BAR_MS


## The monster's mood after being hit.
static func apply_hit_to_mood(m) -> void:
	m.meters.friendliness = clampf(m.meters.friendliness + HIT_FRIENDLINESS, 0.0, 100.0)
	m.meters.anger = clampf(m.meters.anger + HIT_ANGER, 0.0, 100.0)
	m.meters.fear = clampf(m.meters.fear + HIT_FEAR, 0.0, 100.0)


## How strongly the next dodge presses, from a mind's pressure (0..3): faster hazards when it is angrier.
static func dodge_intensity(pressure: float, boss: bool) -> float:
	return (0.8 + 0.25 * pressure) * (1.2 if boss else 1.0)


## "37%", or "<1%" / ">99%" at the extremes so a tiny or near-certain chance never reads as 0 or 100.
static func chance_label(p: float) -> String:
	if p > 0.0 and p < 0.01:
		return "<1%"
	if p < 1.0 and p > 0.99:
		return ">99%"
	return "%d%%" % roundi(p * 100.0)
