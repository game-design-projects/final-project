## A stage that is a list of choices (the fight menu, ACT, game over). Up and down move the selection,
## confirm or a digit picks one, cancel goes back. A subclass fills `flow.state.menu` and answers `pick` and `cancel`.
extends "res://src/game/stages/stage.gd"


func handle(flow, key: String) -> void:
	var s = flow.state
	var n: int = s.menu.size()
	if n == 0:
		return
	match key:
		"up", "left":
			s.selected = posmod(s.selected - 1, n)
			_moved(flow, n)
		"down", "right":
			s.selected = posmod(s.selected + 1, n)
			_moved(flow, n)
		"confirm":
			flow.event("menu_pick")
			await pick(flow, s.selected)
		"cancel":
			await cancel(flow)
		_:
			if key.length() == 1 and key >= "1" and key <= "9" and int(key) - 1 < n:
				s.selected = int(key) - 1
				flow.event("menu_pick")
				await pick(flow, s.selected)


## The cursor moved (a list of one has nowhere to go).
func _moved(flow, n: int) -> void:
	if n > 1:
		flow.event("menu_move")


func pick(_flow, _index: int) -> void:
	pass


func cancel(_flow) -> void:
	pass
