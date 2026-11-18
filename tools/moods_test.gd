## Seeded dynamic moods, pressure and old-save defaults. A suite built on `tools/test_base.gd` like every other one, so the
## watchdog, the script errors that fail a run and the verdict are that file's, not a copy of them here.
##   godot --headless --path . -s res://tools/moods_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Dice = preload("res://src/utils/dice.gd")
const Monster = preload("res://src/rules/monster.gd")
const Moods = preload("res://src/rules/moods.gd")
const Rng = preload("res://src/utils/rng.gd")


func _name() -> String:
	return "moods_test"


func _run() -> void:
	var dice = Dice.new(Rng.new(7042))
	dice.pin(0.5)
	var a = Monster.given({"species": "bandit", "genre": "chess", "hp": 24}, Vector2i.ZERO, "TIM", ["jumpy"], {"friendliness": 20.0, "anger": 10.0, "fear": 10.0})
	var b = Monster.from_dict(a.to_dict())
	b.traits = ["proud"]
	_check(Moods.advance(a, dice) == "", "no early spontaneous change")
	_check(Moods.advance(a, dice) == "", "second turn waits for third")
	_check(Moods.advance(a, dice) != "", "due change has cue")
	for i in 3:
		Moods.advance(b, dice)
	_check(a.mood.id != b.mood.id, "same species distinct intentions")
	_check(Moods.shift(a, "pressure") < Moods.shift(b, "pressure"), "mechanical pressure differs")
	var snap: Dictionary = a.to_dict()
	_check(Monster.from_dict(snap).to_dict() == snap, "save and retry snapshot round trip")
	_check(Moods.advance(a, dice) == "", "cooldown suppresses repetition")
	a.last_intent = "kindness"
	_check(Moods.advance(a, dice) != "" and a.mood.id == "calm", "comfort changes temporary mood")
	var restored = Monster.from_dict(snap)
	var twin = Monster.from_dict(snap)
	for i in 12:
		_check(Moods.advance(restored, dice) == Moods.advance(twin, dice), "identical draws reproduce cues")
	var old: Dictionary = snap.duplicate(true)
	old.erase("mood")
	_check(Monster.from_dict(old).mood.is_empty(), "old save default")
	_finish()
