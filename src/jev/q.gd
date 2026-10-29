## Question builders matching the TypeSafe SDK's output, with no dependencies.
## Load it with `const Q = preload("res://src/jev/q.gd")`. `criteria` is a Dictionary (choice, noul) or an Array (score).
extends RefCounted


static func noul(instructions, criteria = null) -> Dictionary:
	var q := {"type": "noul", "instructions": instructions}
	if criteria != null:
		q["criteria"] = criteria
	return q


static func choice(instructions, criteria) -> Dictionary:
	return {"type": "choice", "instructions": instructions, "criteria": criteria}


static func score(instructions, criteria) -> Dictionary:
	return {"type": "score", "instructions": instructions, "criteria": criteria}
