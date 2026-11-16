## Picks the mind a game uses. `mock` asks for the seeded random one (except for an offline game such as social-demo,
## which always gets the rule-based one). `jev=<url>` (or `saved_url`, the address the player saved, or else the one
## a build ships with, or else DEFAULT_URL for the game itself) asks Jev through the proxy, with the rule-based mind
## answering whenever the network can't. Otherwise the rule-based one.
extends RefCounted

const Flags = preload("res://src/utils/flags.gd")
const JevMind = preload("res://src/mind/jev_mind.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const SeededMind = preload("res://src/mind/seeded_mind.gd")


const SHIPPED_URL := "res://config/jev_url.txt" # written by tools/build.sh --proxy into a build
## The public Jev proxy (the Worker in proxy/, which holds the key and its credit limit). A game run from source asks
## Jev through it unless told not to, so a fresh checkout plays the way a build does.
const DEFAULT_URL := "https://donjon-api.lishuyustevenli.workers.dev"


## The Worker's address a build ships with, or "" (a build made without --proxy, or running from source).
static func shipped_url() -> String:
	return FileAccess.get_file_as_string(SHIPPED_URL).strip_edges() if FileAccess.file_exists(SHIPPED_URL) else ""


## The address a game from source asks when nothing else is given: DEFAULT_URL, except under `nojev`, headless, or a
## `-s` tool script (the test suites, autoplay and the screenshot tools stay on the local rules: they must repeat
## exactly and spend no credits).
static func default_url(tool_run := _is_tool_run()) -> String:
	return "" if tool_run or Flags.on("nojev") else DEFAULT_URL


static func _is_tool_run() -> bool:
	var args := OS.get_cmdline_args()
	return DisplayServer.get_name() == "headless" or args.has("-s") or args.has("--script")


## `offline` is a playtest that must repeat exactly (social-demo): it always thinks with the local rules, never asks Jev
## (whatever address is saved, given or shipped) and ignores `mock`.
static func create(rng: Rng, saved_url := "", offline := false, use_default := false):
	var mind
	if Flags.on("mock") and not offline:
		mind = SeededMind.new(rng)
	else:
		mind = LocalMind.new()
		var fallback := shipped_url()
		if fallback == "" and use_default:
			fallback = default_url()
		var url: String = "" if offline else Flags.value("jev", saved_url if saved_url != "" else fallback)
		if url != "":
			mind = JevMind.new(url, mind)
	print("mind: %s" % mind.label())
	return mind
