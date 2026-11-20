## What the fight bar's two commands are worth: for a plain strike and a heavy one, the window you have to hit (in ms of the
## bar), and the damage at a perfect hit, in the middle, and at the far edge of the window. A table to read a tuning change
## against (#163: "not motivated to choose anything other than Attack"; "HEAVY may be too easy").
##   godot --headless --path . -s res://tools/sim_strike.gd -- nosave [boss=1] [charms=none|rock|dragon]
extends SceneTree

const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")


func _initialize() -> void:
	var boss := false
	var steady := false
	var fire := false
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text == "boss=1":
			boss = true
		elif text == "charms=rock":
			steady = true
		elif text == "charms=dragon":
			fire = true
	var bar: float = Combat.bar_ms(steady)
	var heavy_bar: float = bar * Combat.HEAVY_BAR_SCALE
	print("strike table: bar %.0f ms%s%s" % [bar, ", with the rock's charm" if steady else "", ", with the dragon's charm" if fire else ""])
	print("  %-8s %5s %5s %5s | %5s %5s %5s | %s" % ["species", "win", "mid", "edge", "win", "mid", "edge", "heavy is"])
	for species in ["slime", "bandit", "snake", "rock", "dragon"]:
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
	print("windows: a plain strike lands within %.0f ms of the middle; a heavy one within %.0f ms (%.0f%% of its bar)" % [
		bar * Combat.MISS_EDGE, heavy_bar * Combat.HEAVY_MISS_EDGE, Combat.HEAVY_MISS_EDGE * 100.0])
	quit()


## What a strike of this kind does when the line is stopped `off` away from the middle (0 = perfect, 1 = an end).
func _at(species: String, boss: bool, fire: bool, off: float, heavy: bool) -> int:
	var x: float = 0.5 - off / 2.0 # the line stopped `off` from the middle: 0 is a perfect hit, 0.92 an end
	var hit: Dictionary = Combat.heavy_strike(x, boss, species, fire) if heavy else Combat.strike(x, boss, fire)
	return int(hit.get("damage", 0))
