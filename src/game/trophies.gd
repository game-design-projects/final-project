## The achievements of a run: it listens to what happens, and says each new one the moment it is earned, with the event
## "trophy" (and one sound for however many came at once). It never changes the game and puts nothing on the picture itself:
## the scene shows a toast in the picture's corner (view/trophy_toast.gd), which is out of the way of whatever earned it. What
## has been earned is remembered across runs by the scene (`earned`, kept by menu/progress.gd).
extends RefCounted

const Achievements = preload("res://src/rules/achievements.gd")

## Id -> true for those already earned.
var earned := {}
## The ones earned since this run began, in order.
var this_run: Array = []

var flow


func _init(owner) -> void:
	flow = owner
	flow.happened.connect(_on_event)


func _on_event(name: String, data: Dictionary) -> void:
	if name == "trophy" or not flow.feature("achievements"):
		return
	if name == "state_replaced" and str(data.get("how", "")) != "floor":
		this_run = [] # a new run, or a save loaded
	var new := false
	for id in Achievements.earned_by(name, data, flow.state):
		if not earned.has(id):
			earned[id] = true
			this_run.append(id)
			new = true
			print("trophies: earned %s (%d of %d)" % [id, earned.size(), Achievements.ids().size()])
			flow.event("trophy", {"id": id})
	if new:
		flow.event("sound", {"name": "trophy"})
