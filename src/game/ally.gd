## An ally: a spared monster that follows the party as a passive charm and judges what you do.
extends RefCounted

const Content = preload("res://src/rules/content.gd")

var species := ""
var name := ""
var loyalty := 60.0 # 0..100, see rules/allies.gd


static func make(species_id: String, ally_name: String, start_loyalty: float):
	var a = new()
	a.species = species_id
	a.name = ally_name
	a.loyalty = start_loyalty
	return a


## {name, text} of what this ally's presence does.
func charm() -> Dictionary:
	return Content.table("encounter").charms[species]


func to_dict() -> Dictionary:
	return {"species": species, "name": name, "loyalty": loyalty}


static func from_dict(d: Dictionary):
	return make(str(d.get("species", "")), str(d.get("name", "")), float(d.get("loyalty", 60.0)))
