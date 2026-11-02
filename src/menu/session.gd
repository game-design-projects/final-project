## What the main menu hands to the Genre Halls scene: start a new run, or load this state. The scene takes it once
## in `_ready`; a scene opened with nothing pending (tests, tools, `-- meet=rock`) shows its own title card.
extends RefCounted

static var pending := {}


static func start_new() -> void:
	pending = {"kind": "new"}


static func start_load(state: Dictionary) -> void:
	pending = {"kind": "load", "state": state}


## The pending request ({} if none); it is gone after this
static func take() -> Dictionary:
	var p := pending
	pending = {}
	return p
