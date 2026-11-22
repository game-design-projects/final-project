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

## The flow this belongs to, held weakly: the flow holds this, and a strong hold back would be a cycle neither is freed from.
var _flow_ref: WeakRef
var flow:
	get:
		return _flow_ref.get_ref() if _flow_ref else null


func _init(owner) -> void:
	_flow_ref = weakref(owner)
	flow.happened.connect(_on_event)


func _on_event(name: String, data: Dictionary) -> void:
	if name == "trophy" or not flow.feature("achievements"):
		return
	if name == "state_replaced" and str(data.get("how", "")) != "floor":
		this_run = [] # a new run, a save loaded, or the test room
	if flow.state.testing: # nothing is earned in the test room: every champion is one step away there
		return
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
