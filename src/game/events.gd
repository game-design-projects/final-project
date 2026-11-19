## The events the game announces for the picture and the sound to react to (the game never draws or plays anything).
## `Flow.event(name, data)` carries one of these; a name that isn't listed is reported, so a typo can't silently
## drop an effect. The fields listed are what `data` carries.
extends RefCounted

const FIELDS := {
	"social_offer": ["who", "species", "turn", "goal"],
	"social_reply": ["who", "choice", "cost", "outcome"],
	"stage": ["from", "to"], # the game moved to another stage
	"step": [], # the party walked one cell
	"pad": [], # a pad carried the party to its partner somewhere else on the floor
	"bump": [], # walked into a wall
	"encounter": ["boss", "final"], # a fight begins: with a champion (`boss`), and with the last of them, who waits at the Last Door (`final`)
	"strike": ["damage", "crit"], # your hit landed
	"miss": [], # your swing missed
	"sweep": ["step"], # the strike bar's line crossed another part of the bar: 1 at the ends, up to 4 in the middle
	"follow": ["who", "species", "damage"], # a friend's strike landed after yours (the feature follow-through)
	"player_hurt": ["damage"], # a hazard hit you
	"shield": [], # the slime's charm absorbed a hit
	"second_wind": [], # the keepsake second wind kept you standing through the hit that would have felled you
	"keepsake": ["id"], # you took a keepsake a champion left (the feature keepsakes)
	"star": [], # you caught a star in the mini-game
	"heart": [], # you caught a heart a friendly monster dropped in its attack
	"nerve": ["total", "how"], # your nerve moved to `total`: "close" (a close call), "clean" (a dodge with no hit in it), "lost" (a hit shook one out) or "spent" (a strike or a SPARE used it)
	"sound": ["name"], # a hazard landed (hit, slash, holy)
	"beat": [], # the rhythm beat
	"menu_move": [], # the cursor moved in a list of choices
	"menu_pick": [], # a choice was confirmed
	"mercy_refused": [],
	"mercy_changed": ["from", "to"], # a deed moved the mercy odds (0..1)
	"said": ["text"], # you sent a typed line
	"mood": ["tone"], # how the last deed landed: good, bad or odd
	"wants_join": [], # mercy just became likely
	"word_spread": ["clan", "tone"], # a monster met you having heard what you did to its clan
	"spared": ["boss"],
	"slain": ["boss"],
	"recruited": ["species"],
	"lord_joined": ["species"], # a clan's lord, sworn by its second favour, came along (rules/lords.gd)
	"ally_left": ["species"],
	"request_done": ["clan", "id"], # one of a clan's requests is done (rules/envoys.gd)
	"gate_opened": ["clan"], # the second: its teleporter is open at the next stairs
	"lord_met": ["clan"], # its lord was heard out in its hall
	"teleport": ["to"], # carried off the floor through a clan's teleporter, `to` its "hall" (a pad across the floor is "pad")
	"shout": ["text", "species", "boss"], # a monster says a line
	"warmth": ["from", "to"], # the halls moved to another level of how they feel about you (rules/warmth.gd)
	"dead": [],
	"coach": ["id"], # a first-time tip went up
	"stairs": [], # reached the stairs
	"reached_last": [], # came down to the run's last floor
	"run_ended": ["how"], # the run ended at the stairs: "cleared" or "lonely"
	"run_closed": ["embers"], # the run is over for good, having earned this many embers in all (the feature legacy)
	"trophy": ["id"], # an achievement was earned; the scene keeps it
	"found": ["what"], # you found something on the floor: "chest", or "lore" with {id, read, total}: the writing on a wall, and how many pieces of it have been read over all runs
	"charted": ["how", "cells"], # the rest of the floor's layout went onto the map: "instinct" (enough of it seen) or "map" (a monster was carrying one), and how many cells that was
	"butchered": ["species"], # a friend went into the bag
	"found_out": ["species"], # a friend worked out what happened to another
	"state_replaced": ["how"], # a new run ("new"), the next floor ("floor"), a loaded save ("load") or the test room ("test") replaced the game state; whoever holds the old one must let go
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
