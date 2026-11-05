## The achievements of a run: it listens to what happens, and puts each new one on the picture, the first time. It never changes the
## game. A new one waits for a calm moment with no banner up, since what earned it usually has something to say first. What has been earned
## is remembered across runs by the scene (`earned`, kept by menu/progress.gd), which hears of each through the event "trophy".
extends RefCounted

const Achievements = preload("res://src/rules/achievements.gd")

const CALM := ["step", "stage", "run_closed"]

## Id -> true for those already earned.
var earned := {}

var flow
var _waiting: Array = []


func _init(owner) -> void:
	flow = owner
	flow.happened.connect(_on_event)


func _on_event(name: String, data: Dictionary) -> void:
	if name == "trophy" or not flow.feature("achievements"):
		return
	for id in Achievements.earned_by(name, data, flow.state):
		if not earned.has(id):
			earned[id] = true
			_waiting.append(id)
			print("trophies: earned %s" % id)
			flow.event("trophy", {"id": id})
	if name in CALM and not _waiting.is_empty() and not flow.banner_up():
		var id: String = _waiting.pop_front()
		var info: Dictionary = Achievements.info(id)
		flow.announce(str(Achievements.table().title), "%s: %s" % [info.label, info.text])
		flow.event("sound", {"name": "good"})
