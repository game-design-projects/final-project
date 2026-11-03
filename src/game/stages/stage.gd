## One stage of a run (explore, a fight's menu, the dodge...). The flow calls these; a stage changes the game by
## changing `flow.state` and asking `flow.go(next)`. All of them may `await` (a mind can take time to answer).
extends RefCounted

## The stage begins. `args` is whatever the previous stage passed to `flow.go`.
func enter(_flow, _args: Dictionary) -> void:
	pass


## A key press: "up", "down", "left", "right", "confirm", "cancel", or a digit "1".."9".
func handle(_flow, _key: String) -> void:
	pass


## Time passes; `t` is the game clock in milliseconds.
func tick(_flow, _t: float) -> void:
	pass


## The stage ends (the next one has not started yet).
func leave(_flow) -> void:
	pass
