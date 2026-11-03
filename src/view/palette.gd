## The colours of the picture: each floor has a wall colour and an accent, every monster its own colour, the champion red.
extends RefCounted

const Content = preload("res://src/rules/content.gd")

const BOSS := Color("#ff2a2a")
const YOU := Color("#8fd3ff") # the soul, your health
const MERCY := Color("#ffd27a") # gold, the chance of mercy, titles
const INK := Color("#e8e8e8") # text
const DIM := Color("#8a8a8a") # quiet text
const WARN := Color("#ff5a4a")
const FAINT := Color("#2e2e33") # borders of things that are not picked

const FLOORS := [
	{"wall": "#e8e3d1", "accent": "#ffb347"},
	{"wall": "#9fd8ff", "accent": "#ff7aa8"},
	{"wall": "#a8f0a0", "accent": "#ffd966"},
	{"wall": "#f5a3d0", "accent": "#7fe0ff"},
	{"wall": "#ffd27f", "accent": "#a78bff"},
]


## The wall and accent colours of a floor (0 is B1F); they cycle after the last.
static func for_floor(index: int) -> Dictionary:
	var p: Dictionary = FLOORS[posmod(index, FLOORS.size())]
	return {"wall": Color(p.wall), "accent": Color(p.accent)}


static func monster(m) -> Color:
	return BOSS if m.boss else Color(Content.species(m.species).color)
