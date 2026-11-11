## The first-time tips: one short line at a time, on the picture, the first time something comes up, so the game teaches itself
## while it is being played. It listens to what happens and never changes the game. A tip that comes up while another banner is
## showing waits for the next time. What has been seen is remembered across runs by the scene (`seen`), and the TIPS setting
## switches them all off (`enabled`), and the slow first fights with them (stages/dodge.gd).
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Moods = preload("res://src/rules/moods.gd")
const Warmth = preload("res://src/rules/warmth.gd")

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
	var who := "TIP"
	var words: String = tips[id]
	if flow.state.practice and flow.feature("wick"): # on the practice floor she is the one who tells you
		var wick: Dictionary = Content.table("coach").get("wick", {})
		who = str(Content.table("floors").friend.title)
		words = str(wick.get(id, words))
	flow.announce(who, words, TIP_MS)
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
			if flow.state.practice:
				say("shy")
			if _blank(flow.state.foe):
				say("blank")


func _on_stage(to: String) -> void:
	match to:
		"explore":
			if not flow.state.deeds.is_empty(): # only the clans write deeds, and not on the slice
				say("clans")
		"menu":
			if not say("menu") and not (flow.feature("heavy-strike") and flow.state.skill_fight == null and say("heavy")) and seen.has("act") and (seen.has("strike") or seen.has("skills")):
				say("flee") # last: what to do comes before how to get out of it
		"act":
			say("act")
		"fightbar":
			say("strike")
		"skills":
			say("skills")
		"dodge":
			say("dodge")
		"ask":
			say("ask")
		"dead":
			say("dead")


## Whether this foe meets you with its face already gone (the warmth's blank faces, drawn only by hand-drawn): that reads like the drawing
## lost its eyes unless something says why.
func _blank(m) -> bool:
	return m != null and flow.feature("warmth") and flow.feature("hand-drawn") and Moods.hollow(m, Warmth.of(flow.state))
