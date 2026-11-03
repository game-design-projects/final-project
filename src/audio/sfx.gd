## The game's sound effects: a name for each thing that happens, a recipe (synth.gd) for each name. They are made the
## first time they are asked for and kept. A small pool of players lets several overlap.
extends Node

const Synth = preload("res://src/audio/synth.gd")

const BUS := "SFX"
const VOICES := 8

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


## name -> parts. One line per sound, so the whole sound of the game reads in one place.
static func recipes() -> Dictionary:
	var t := Synth.tone
	var n := Synth.noise
	return {
		"step": [n.call(0.06, 0.18, 700.0)],
		"bump": [t.call("sine", 110.0, 60.0, 0.12, 0.5), n.call(0.05, 0.2, 500.0)],
		"encounter": [t.call("saw", 140.0, 70.0, 0.5, 0.35), t.call("square", 220.0, 110.0, 0.4, 0.2, 0.08)],
		"boss": [t.call("saw", 90.0, 45.0, 0.9, 0.45), t.call("square", 180.0, 60.0, 0.8, 0.25, 0.1)],
		"strike": [n.call(0.12, 0.45, 3000.0), t.call("square", 320.0, 90.0, 0.14, 0.3)],
		"crit": [n.call(0.18, 0.5, 5000.0), t.call("square", 520.0, 120.0, 0.2, 0.35), t.call("sine", 880.0, 880.0, 0.25, 0.25, 0.04)],
		"miss": [n.call(0.15, 0.2, 1800.0)],
		"hurt": [t.call("saw", 200.0, 50.0, 0.28, 0.5), n.call(0.1, 0.3, 1500.0)],
		"hit": [t.call("sine", 160.0, 50.0, 0.18, 0.5), n.call(0.06, 0.3, 1200.0)],
		"slash": [n.call(0.14, 0.4, 6000.0), t.call("saw", 1200.0, 300.0, 0.12, 0.15)],
		"holy": [t.call("sine", 660.0, 990.0, 0.35, 0.3), t.call("sine", 990.0, 1320.0, 0.35, 0.2, 0.05)],
		"shield": [t.call("tri", 600.0, 900.0, 0.18, 0.35), t.call("sine", 1200.0, 1200.0, 0.2, 0.15, 0.05)],
		"beat": [t.call("sine", 90.0, 55.0, 0.09, 0.45)],
		"spared": [t.call("sine", 523.0, 523.0, 0.2, 0.3), t.call("sine", 659.0, 659.0, 0.2, 0.3, 0.12), t.call("sine", 784.0, 784.0, 0.4, 0.3, 0.24)],
		"slain": [t.call("saw", 300.0, 40.0, 0.7, 0.4), n.call(0.4, 0.3, 800.0)],
		"recruited": [t.call("tri", 392.0, 392.0, 0.15, 0.3), t.call("tri", 523.0, 523.0, 0.15, 0.3, 0.12), t.call("tri", 784.0, 784.0, 0.4, 0.3, 0.24)],
		"ally_left": [t.call("tri", 440.0, 330.0, 0.3, 0.3), t.call("tri", 330.0, 220.0, 0.4, 0.3, 0.2)],
		"mercy_refused": [t.call("square", 180.0, 150.0, 0.15, 0.25), t.call("square", 150.0, 120.0, 0.2, 0.25, 0.14)],
		"shout": [t.call("square", 300.0, 340.0, 0.05, 0.12), t.call("square", 360.0, 300.0, 0.06, 0.12, 0.07)],
		"dead": [t.call("saw", 260.0, 35.0, 1.2, 0.45), n.call(0.6, 0.25, 600.0, 0.1)],
		"stairs": [t.call("tri", 330.0, 330.0, 0.2, 0.3), t.call("tri", 440.0, 440.0, 0.2, 0.3, 0.15), t.call("tri", 660.0, 660.0, 0.5, 0.3, 0.3)],
		"tick": [t.call("square", 900.0, 900.0, 0.02, 0.1)],
		"move": [t.call("square", 440.0, 440.0, 0.03, 0.12)],
		"pick": [t.call("square", 660.0, 880.0, 0.07, 0.15)],
	}


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)


## Play a named effect. `db` adjusts the loudness. An unknown name is reported, so a typo can't silently be silent.
func play(sound: String, db := 0.0) -> void:
	var stream := stream_for(sound)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = randf_range(0.97, 1.03)
	p.play()


func stream_for(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		var all := recipes()
		if not all.has(sound):
			push_error("sfx: no sound called '%s'" % sound)
			return null
		_cache[sound] = Synth.render(all[sound])
		print_verbose("sfx: made '%s'" % sound)
	return _cache[sound]
