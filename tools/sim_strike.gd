## What the fight bar's two commands are worth to the same hand (#163: "not motivated to choose anything other than Attack";
## "HEAVY may be too easy"). Two tables, both read off `Combat`:
##   per hit   — both commands stopped the same number of ms from the middle, so the faster line is not flattered by being read
##               against its own narrower edge;
##   per swing — what a whole fight is worth to a hand that misses the middle by that much on average, misses counted, which is
##               the other half of the trade: the heavy mark is 231 ms wide against the plain one's 1012.
## The rows are the species in `data/species.json`, each on its own `heavy` number, so a species added there is in the tables
## without this tool being touched.
##   godot --headless --path . -s res://tools/sim_strike.gd -- nosave [boss=1] [charms=none|rock|dragon] [swings=4000]
extends SceneTree

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Flags = preload("res://src/utils/flags.gd")

const CHARMS := ["none", "rock", "dragon"]
const SAME_HAND_MS := [0.0, 50.0, 115.0, 230.0, 506.0] # 0 is the middle; 115 the heavy mark's edge, 506 the plain one's
const NOISE_MS := [50.0, 80.0, 200.0] # how far a steady, an ordinary and a shaky hand miss by, on average
const SWING_SEED := 35 # the seed tools/features_test.gd reads the same trade with


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray)
	var boss := Flags.value("boss") == "1"
	var charm := Flags.value("charms", "none")
	if not CHARMS.has(charm):
		push_error("sim_strike: charms=%s is not one of %s" % [charm, ", ".join(PackedStringArray(CHARMS))])
		quit(1)
		return
	var swings := maxi(1, int(Flags.value("swings", "4000")))
	var steady := charm == "rock"
	var fire := charm == "dragon"
	var species: Array = []
	for id in Content.table("species"):
		species.append(str(id))
	var bar: float = Combat.bar_ms(steady)
	var heavy_bar: float = bar * Combat.HEAVY_BAR_SCALE
	var header := "strike table: a bar of %.0f ms, a heavy one of %.0f ms" % [bar, heavy_bar]
	if boss:
		header += ", a champion's damage (x%.1f)" % Combat.BOSS_DAMAGE_SCALE
	if steady:
		header += ", with the rock's charm"
	if fire:
		header += ", with the dragon's charm"
	print(header)
	print("  how each species takes a heavy blow: %s" % ", ".join(species.map(func(id): return "%s x%.2f" % [id, Combat.heavy_weakness(id)])))
	print("per hit, both stopped the same ms from the middle (0 = the middle; a miss is 0):")
	print("  %6s %6s | %s" % ["off", "FIGHT", _names(species)])
	for error in SAME_HAND_MS:
		var cells := species.map(func(id): return "%6d" % _heavy_hit(id, boss, fire, error, heavy_bar))
		print("  %4.0f ms %6d | %s" % [error, _plain_hit(boss, fire, error, bar), " ".join(cells)])
	print("per swing, a hand that misses the middle by this much on average (%d swings a row, seed %d):" % [swings, SWING_SEED])
	print("  %6s %6s | %s | %s" % ["off", "FIGHT", _names(species), "HEAVY pays against"])
	# One stream across the three hands, in this order, so these are the very numbers tools/features_test.gd prints and checks.
	var rng := RandomNumberGenerator.new()
	rng.seed = SWING_SEED
	for noise in NOISE_MS:
		var mean: Dictionary = _per_swing(species, boss, fire, noise, swings, rng, bar, heavy_bar)
		var pays: Array = species.filter(func(id): return float(mean[id]) > float(mean.quick))
		print("  %4.0f ms %6.1f | %s | %s" % [noise, mean.quick,
			" ".join(species.map(func(id): return "%6.1f" % float(mean[id]))),
			"nothing: FIGHT everywhere" if pays.is_empty() else ", ".join(pays)])
	print("windows: a plain strike lands within %.0f ms either side of the middle (%.0f ms of the %.0f ms bar); a heavy one within %.0f ms (%.0f ms of its %.0f ms)" % [
		bar * Combat.MISS_EDGE / 2.0, bar * Combat.MISS_EDGE, bar,
		heavy_bar * Combat.HEAVY_MISS_EDGE / 2.0, heavy_bar * Combat.HEAVY_MISS_EDGE, heavy_bar])
	quit(0)


## The column headings one table puts over its species columns.
func _names(species: Array) -> String:
	return " ".join(species.map(func(id): return "%6s" % id))


## What a plain strike does when the line is stopped `error_ms` away from the middle. The hand is the same for both commands: the
## error is in ms, and each command's own bar turns it into its own `off` (off = 2 * error / bar), which is why the heavy line
## reads worse and worse as the error grows.
func _plain_hit(boss: bool, fire: bool, error_ms: float, bar: float) -> int:
	return int(Combat.strike(clampf(0.5 + error_ms / bar, 0.0, 1.0), boss, fire).get("damage", 0))


## The same, for a heavy blow taken by `id`, on the heavy bar's own width.
func _heavy_hit(id: String, boss: bool, fire: bool, error_ms: float, heavy_bar: float) -> int:
	return int(Combat.heavy_strike(clampf(0.5 + error_ms / heavy_bar, 0.0, 1.0), boss, id, fire).get("damage", 0))


## What a swing of each command is worth to a hand with this much error in it, misses counted: the mean over `swings` draws of the
## seeded bell tools/features_test.gd reads the trade with, from the same stream it reads it from.
func _per_swing(species: Array, boss: bool, fire: bool, noise_ms: float, swings: int, rng: RandomNumberGenerator, bar: float, heavy_bar: float) -> Dictionary:
	var out := {"quick": 0.0}
	for id in species:
		out[id] = 0.0
	for _i in swings:
		var e: float = rng.randfn(0.0, noise_ms)
		out.quick += Combat.strike(clampf(0.5 + e / bar, 0.0, 1.0), boss, fire).damage / float(swings)
		for id in species:
			out[id] += Combat.heavy_strike(clampf(0.5 + e / heavy_bar, 0.0, 1.0), boss, id, fire).damage / float(swings)
	return out
