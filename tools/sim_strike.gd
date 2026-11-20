## What the fight bar's two commands are worth: for a plain strike and a heavy one, the window you have to hit (in ms of the
## bar), and the damage at a perfect hit, in the middle, and at the far edge of the window. A table to read a tuning change
## against (#163: "not motivated to choose anything other than Attack"; "HEAVY may be too easy"). Its rows are the species in
## `data/species.json`, each on its own `heavy` number, so a species added there is in the table without this tool being touched.
##   godot --headless --path . -s res://tools/sim_strike.gd -- nosave [boss=1] [charms=none|rock|dragon]
extends SceneTree

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Flags = preload("res://src/utils/flags.gd")

const CHARMS := ["none", "rock", "dragon"]


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray)
	var boss := Flags.value("boss") == "1"
	var charm := Flags.value("charms", "none")
	if not CHARMS.has(charm):
		push_error("sim_strike: charms=%s is not one of %s" % [charm, ", ".join(PackedStringArray(CHARMS))])
		quit(1)
		return
	var steady := charm == "rock"
	var fire := charm == "dragon"
	var bar: float = Combat.bar_ms(steady)
	var heavy_bar: float = bar * Combat.HEAVY_BAR_SCALE
	# The table names the run it came from: a champion's scale or a charm changes the numbers under the same columns.
	var header := "strike table: bar %.0f ms" % bar
	if boss:
		header += ", a champion's damage (x%.1f)" % Combat.BOSS_DAMAGE_SCALE
	if steady:
		header += ", with the rock's charm"
	if fire:
		header += ", with the dragon's charm"
	print(header)
	print("  %-8s %5s %5s %5s | %5s %5s %5s | %s" % ["species", "win", "mid", "edge", "win", "mid", "edge", "heavy is"])
	for id in Content.table("species"):
		var species := str(id)
		var plain_win: int = _at(species, boss, fire, 0.0, false)
		var heavy_win: int = _at(species, boss, fire, 0.0, true)
		var plain_mid: int = _at(species, boss, fire, 0.2, false)
		var heavy_mid: int = _at(species, boss, fire, 0.2, true)
		var plain_edge: int = _at(species, boss, fire, Combat.MISS_EDGE, false)
		var heavy_edge: int = _at(species, boss, fire, Combat.HEAVY_MISS_EDGE, true)
		var verdict := "better everywhere"
		if heavy_mid < plain_mid or heavy_edge < plain_edge:
			verdict = "a trade" if heavy_win >= plain_win else "not worth it"
		print("  %-8s %5d %5d %5d | %5d %5d %5d | %s" % [species, plain_win, plain_mid, plain_edge, heavy_win, heavy_mid, heavy_edge, verdict])
	print("windows: a plain strike lands within %.0f ms either side of the middle (%.0f ms of the %.0f ms bar); a heavy one within %.0f ms (%.0f ms of its %.0f ms)" % [
		bar * Combat.MISS_EDGE / 2.0, bar * Combat.MISS_EDGE, bar,
		heavy_bar * Combat.HEAVY_MISS_EDGE / 2.0, heavy_bar * Combat.HEAVY_MISS_EDGE, heavy_bar])
	quit(0)


## What a strike of this kind does when the line is stopped `off` away from the middle (0 = perfect, 1 = an end), on the early
## side of it: the damage is the same either side.
func _at(species: String, boss: bool, fire: bool, off: float, heavy: bool) -> int:
	var x: float = 0.5 - off / 2.0
	var hit: Dictionary = Combat.heavy_strike(x, boss, species, fire) if heavy else Combat.strike(x, boss, fire)
	return int(hit.get("damage", 0))
