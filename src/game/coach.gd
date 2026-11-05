## The first-time tips: one short line at a time, on the picture, the first time something comes up, so the game teaches itself
## while it is being played. It listens to what happens and never changes the game. A tip that comes up while another banner is
## showing waits for the next time. What has been seen is remembered across runs by the scene (`seen`), and the TIPS setting
## switches them all off (`enabled`), and the slow first fights with them (stages/dodge.gd).
extends RefCounted

const Content = preload("res://src/rules/content.gd")

const TIP_MS := 4200.0
const SPARE_AT := 0.5

## Off with the TIPS setting (the scene keeps this up to date).
var enabled := true
## Tip id -> true for those already shown.
var seen := {}

var flow


func _init(owner) -> void:
	flow = owner
	flow.happened.connect(_on_event)


## Show this tip, if it is due. True when it went up.
func say(id: String) -> bool:
	if not enabled or seen.has(id) or not flow.feature("tutorial") or flow.banner_up():
		return false
	var tips: Dictionary = Content.table("coach").tips
	if not tips.has(id):
		push_error("coach: no tip '%s'" % id)
		return false
	seen[id] = true
	flow.announce("TIP", tips[id], TIP_MS)
	print("coach: %s" % id)
	flow.event("coach", {"id": id})
	return true


func _on_event(name: String, data: Dictionary) -> void:
	match name:
		"stage":
			_on_stage(data.to)
		"mercy_changed":
			if data.to >= SPARE_AT:
				say("spare")
			else:
				say("mercy")
		"encounter":
			if data.boss:
				say("boss")


func _on_stage(to: String) -> void:
	match to:
		"explore":
			if flow.feature("clans") and not flow.state.deeds.is_empty():
				say("clans")
		"menu":
			if not say("menu") and not (flow.feature("heavy-strike") and say("heavy")) and seen.has("act") and seen.has("strike"):
				say("flee") # last: what to do comes before how to get out of it
		"act":
			say("act")
		"fightbar":
			say("strike")
		"dodge":
			say("dodge")
		"ask":
			say("ask")
		"dead":
			say("dead")
