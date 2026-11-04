## Walking the floor. Up and down step forward and back, left and right turn on the spot. Walking into a monster starts
## a fight; reaching the stairs ends the floor.
extends "res://src/game/stages/stage.gd"

const FloorMap = preload("res://src/rules/floor_map.gd")

const HINT := "UP / DOWN WALK · LEFT / RIGHT TURN · ESC MENU"


func enter(flow, args: Dictionary) -> void:
	var s = flow.state
	s.foe = null
	s.menu = []
	s.hint = HINT
	if args.has("lines"):
		s.say(args.lines)


func handle(flow, key: String) -> void:
	var s = flow.state
	match key:
		"up":
			await _step(flow, false)
		"down":
			await _step(flow, true)
		"left":
			s.turn(-1)
		"right":
			s.turn(1)
		"cancel":
			flow.event("pause_requested")


func _step(flow, backwards: bool) -> void:
	var s = flow.state
	var heading: int = (s.facing + 2) % 4 if backwards else s.facing
	var next: Vector2i = s.cell + FloorMap.DIRS[heading]
	if not s.floor_map.is_open(next):
		flow.event("bump")
		return
	var monster = s.floor_map.monster_at(next)
	if monster != null:
		await flow.go("intro", {"foe": monster})
		return
	s.cell = next
	s.visited[next] = true
	s.look()
	flow.event("step")
	if next == s.floor_map.stairs:
		await flow.go("end")
