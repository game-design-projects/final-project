## How long recruiting takes against killing, on the local rules: for each kind of monster, over many seeds, repeating the ACT
## that brings it round fastest (gold offers left out, as they end the fight with no recruit). It assumes the player already
## knows the best ACT, and measures turns, not how hard the dodging is.
## `standing=N` measures monsters whose clan already thinks that of you (-100..100).
##   godot --headless --path . -s res://tools/sim_recruit.gd -- nosave nosound
extends SceneTree

const Clans = preload("res://src/rules/clans.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Dice = preload("res://src/utils/dice.gd")
const Flags = preload("res://src/utils/flags.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Monster = preload("res://src/rules/monster.gd")
const Odds = preload("res://src/rules/odds.gd")
const Rng = preload("res://src/utils/rng.gd")

const SEEDS := 1000
const MAX_ACTS := 15
const TYPICAL_STRIKE := 0.2 # how far from the middle a typical strike stops, as a share of the bar's half


func _init() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray)
	var enc: Dictionary = Content.table("encounter")
	var boss: Dictionary = enc.boss
	var entries: Array = enc.roster + [{"species": boss.species, "genre": boss.genres[0], "hp": boss.hp, "name": boss.name, "boss": true}]
	print("monster | start | median ACTs to 50%% (reached in %d) | join odds there | strikes to kill" % MAX_ACTS)
	for entry in entries:
		_measure(entry)
	quit(0)


func _measure(entry: Dictionary) -> void:
	var starts := []
	var acts := []
	var joins := []
	var reached := 0
	for i in SEEDS:
		var rng := Rng.new(i + 1)
		var mind = LocalMind.new()
		var made = Monster.make(rng, entry, Vector2i.ONE)
		var shift: Dictionary = Clans.mood(_standing())
		for k in shift:
			made.meters[k] = clampf(made.meters[k] + shift[k], 0.0, 100.0)
		starts.append(mind.mercy(made))
		var best := MAX_ACTS + 1
		var best_join := 0.0
		var kinds: Array = Content.table("encounter").acts[entry.species]
		if Flags.enabled("recruit-step"):
			kinds = kinds + Content.table("encounter").kind_acts.get(entry.species, [])
		for act in kinds:
			if act.intent == "gold":
				continue
			var m = Monster.from_dict(made.to_dict())
			var dice := Dice.new(Rng.new(i + 7))
			var turns := MAX_ACTS + 1
			for n in MAX_ACTS:
				m.last_intent = act.intent
				var feeling := Feelings.apply(m, Odds.pick_by_odds(dice, mind.feeling_when_told(m, [{"intent": act.intent, "w": 1.0}])))
				if Flags.enabled("recruit-step"):
					Feelings.warm_up(m, feeling)
				if mind.mercy(m) >= 0.5:
					turns = n + 1
					break
			if turns < best:
				best = turns
				best_join = mind.join(m)
		if best <= MAX_ACTS:
			reached += 1
			acts.append(best)
			joins.append(best_join)
	acts.sort()
	var strike: int = Combat.strike(0.5 + TYPICAL_STRIKE / 2.0, entry.has("name"), false).damage
	print("%s | %.1f%% | %s (%.1f%%) | %.1f%% | %d" % [
		entry.species, _mean(starts) * 100.0, str(acts[acts.size() / 2]) if not acts.is_empty() else "-",
		reached * 100.0 / SEEDS, _mean(joins) * 100.0, ceili(float(entry.hp) / strike)])


func _standing() -> float:
	for word in OS.get_cmdline_user_args():
		if word.begins_with("standing="):
			return word.trim_prefix("standing=").to_float()
	return 0.0


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()
