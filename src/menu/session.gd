## What the menu hands to the gameplay scene: start a new run, or continue this saved state. Gameplay takes it once when
## it starts; opened with nothing pending (a tool, a test scene) it just starts a new run.
extends RefCounted

static var pending := {}


static func start_new() -> void:
	pending = {"kind": "new"}


static func start_load(state: Dictionary) -> void:
	pending = {"kind": "load", "state": state}


## The opening CG (menu/intro_cg.gd) ended: watched to its end ("whole", so the run need not bring her in again) or skipped.
static func cg_played(whole: bool) -> void:
	pending["cg"] = "whole" if whole else "skipped"


## The pending request ({} if none); it is gone after this.
static func take() -> Dictionary:
	var p := pending
	pending = {}
	return p
