## The events the game announces for the picture and the sound to react to (the game never draws or plays anything).
## `Flow.event(name, data)` carries one of these; a name that isn't listed is reported, so a typo can't silently
## drop an effect. The fields listed are what `data` carries.
extends RefCounted

const FIELDS := {
	"stage": ["from", "to"], # the game moved to another stage
	"step": [], # the party walked one cell
	"bump": [], # walked into a wall
	"encounter": ["boss"], # a fight begins
	"strike": ["damage", "crit"], # your hit landed
	"miss": [], # your swing missed
	"player_hurt": ["damage"], # a hazard hit you
	"shield": [], # the slime's charm absorbed a hit
	"sound": ["name"], # a hazard landed (hit, slash, holy)
	"beat": [], # the rhythm beat
	"mercy_refused": [],
	"spared": ["boss"],
	"slain": ["boss"],
	"recruited": ["species"],
	"ally_left": ["species"],
	"shout": ["text", "species", "boss"], # a monster says a line
	"dead": [],
	"stairs": [], # reached the stairs
	"new_floor": [],
	"pause_requested": [],
	"leave": ["to"], # the player chose to go back to the main menu
}


## True when `name` is a known event and `data` has its fields. Reports a problem otherwise.
static func valid(name: String, data: Dictionary) -> bool:
	if not FIELDS.has(name):
		push_error("events: unknown event '%s'" % name)
		return false
	for field in FIELDS[name]:
		if not data.has(field):
			push_error("events: '%s' is missing '%s'" % [name, field])
			return false
	return true
