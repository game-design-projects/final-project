## What a monster's face shows. A mood is read off its meters, so it changes as they do; the view has a drawing for each. As the halls
## go cold (rules/warmth.gd) faces go blank, one monster at a time, and the champions last.
extends RefCounted

const STRONG := 60.0 # a meter this high shows on the face
const HOLLOW_FROM := 0.1 # at or below this warmth every face but a champion's is blank
const HOLLOW_TO := 0.36 # above this warmth no face is
const BOSS_HOLLOW := 0.04


## "angry", "scared", "happy" or "calm".
static func of(m) -> String:
	if m.hunting or m.meters.anger >= STRONG:
		return "angry"
	if m.meters.fear >= STRONG:
		return "scared"
	if m.meters.friendliness >= m.threshold:
		return "happy"
	return "calm"


## Whether this monster's face has gone blank at this warmth. Each one goes at its own point, the same one every time.
static func hollow(m, warmth: float) -> bool:
	if m.boss:
		return warmth <= BOSS_HOLLOW
	var own := float(absi(str(m.name).hash()) % 1000) / 1000.0
	return warmth <= lerpf(HOLLOW_FROM, HOLLOW_TO, own)
