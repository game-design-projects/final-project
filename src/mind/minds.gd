## Picks the mind a game uses. `mock` asks for the seeded random one. `jev=<url>` (or `saved_url`, the address the player
## saved, or else the one a build ships with) asks Jev through the proxy, with the rule-based mind answering whenever the network can't. Otherwise the
## rule-based one.
extends RefCounted

const Flags = preload("res://src/utils/flags.gd")
const JevMind = preload("res://src/mind/jev_mind.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const SeededMind = preload("res://src/mind/seeded_mind.gd")


const SHIPPED_URL := "res://config/jev_url.txt" # written by tools/build.sh --proxy into a build


## The Worker's address a build ships with, or "" (a build made without --proxy, or running from source).
static func shipped_url() -> String:
	return FileAccess.get_file_as_string(SHIPPED_URL).strip_edges() if FileAccess.file_exists(SHIPPED_URL) else ""


static func create(rng: Rng, saved_url := ""):
	var mind
	if Flags.on("mock"):
		mind = SeededMind.new(rng)
	else:
		mind = LocalMind.new()
		var url: String = Flags.value("jev", saved_url if saved_url != "" else shipped_url())
		if url != "":
			mind = JevMind.new(url, mind)
	print("mind: %s" % mind.label())
	return mind
