extends SceneTree
const Monster = preload("res://src/rules/monster.gd")
const Moods = preload("res://src/rules/moods.gd")
const Dice = preload("res://src/utils/dice.gd")
const Rng = preload("res://src/utils/rng.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
func _initialize() -> void:
	var dice = Dice.new(Rng.new(7042))
	dice.pin(0.5)
	var a = Monster.given({"species": "bandit", "genre": "chess", "hp": 24}, Vector2i.ZERO, "TIM", ["jumpy"], {"friendliness": 20.0, "anger": 10.0, "fear": 10.0})
	var b = Monster.from_dict(a.to_dict())
	b.traits = ["proud"]
	check(Moods.advance(a, dice) == "", "no early spontaneous change")
	check(Moods.advance(a, dice) == "", "second turn waits for third")
	check(Moods.advance(a, dice) != "", "due change has cue")
	for i in 3:
		Moods.advance(b, dice)
	check(a.mood.id != b.mood.id, "same species distinct intentions")
	check(Moods.shift(a, "pressure") < Moods.shift(b, "pressure"), "mechanical pressure differs")
	var snap: Dictionary = a.to_dict()
	check(Monster.from_dict(snap).to_dict() == snap, "save and retry snapshot round trip")
	check(Moods.advance(a, dice) == "", "cooldown suppresses repetition")
	a.last_intent = "kindness"
	check(Moods.advance(a, dice) != "" and a.mood.id == "calm", "comfort changes temporary mood")
	var restored = Monster.from_dict(snap)
	var twin = Monster.from_dict(snap)
	for i in 12:
		check(Moods.advance(restored, dice) == Moods.advance(twin, dice), "identical draws reproduce cues")
	var old: Dictionary = snap.duplicate(true)
	old.erase("mood")
	check(Monster.from_dict(old).mood.is_empty(), "old save default")
	print("moods_test: all checks passed" if failures == 0 else "moods_test: %d checks failed" % failures)
	quit(failures)
