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
		"down", "right":
			s.selected = posmod(s.selected + 1, n)
		"confirm":
			await pick(flow, s.selected)
		"cancel":
			await cancel(flow)
		_:
			if key.length() == 1 and key >= "1" and key <= "9" and int(key) - 1 < n:
				s.selected = int(key) - 1
				await pick(flow, s.selected)


func pick(_flow, _index: int) -> void:
	pass


func cancel(_flow) -> void:
	pass
