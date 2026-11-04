## The colours of the picture: each run has a named palette (a wall colour and an accent), every monster its own colour, the
## champion red.
extends RefCounted

const Content = preload("res://src/rules/content.gd")

const BOSS := Color("#ff2a2a")
const YOU := Color("#8fd3ff") # the soul, your health
const MERCY := Color("#ffd27a") # gold, the chance of mercy, titles
const INK := Color("#e8e8e8") # text
const DIM := Color("#8a8a8a") # quiet text
const WARN := Color("#ff5a4a")
const FAINT := Color("#2e2e33") # borders of things that are not picked

const RUNS := [
	{"name": "BONE CRYPT", "wall": "#e8e2d0", "accent": "#ffb347"},
	{"name": "DROWNED HALLS", "wall": "#8fd3e8", "accent": "#7fffd4"},
	{"name": "BLOOD VAULT", "wall": "#e07a7a", "accent": "#ffcf5a"},
	{"name": "MOSS DEEP", "wall": "#9ed36b", "accent": "#ffe14a"},
	{"name": "ASH CHAMBERS", "wall": "#b9b0a4", "accent": "#ff6b3d"},
	{"name": "VIOLET CATACOMB", "wall": "#b79cf0", "accent": "#ff9de2"},
	{"name": "RUST TUNNELS", "wall": "#d39a6a", "accent": "#ffd27a"},
	{"name": "FROST WARRENS", "wall": "#cfe8ff", "accent": "#9ad0ff"},
]


## The colours of a run, from its `palette_id` (any whole number: it wraps round the list).
static func for_run(id: int) -> Dictionary:
	var p: Dictionary = RUNS[posmod(id, RUNS.size())]
	return {"name": p.name, "wall": Color(p.wall), "accent": Color(p.accent)}


static func monster(m) -> Color:
	return BOSS if m.boss else Color(Content.species(m.species).color)
