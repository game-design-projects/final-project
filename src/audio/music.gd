## The music: a quiet loop while exploring, one of four battle themes in a fight, short stings when a fight ends well.
## Changing the mode crossfades. The tracks are in assets/audio/.
extends Node

const Mix = preload("res://src/audio/mix.gd")

const EXPLORE := "res://assets/audio/ambient.ogg"
const BATTLES := ["battle-charge", "battle-crusade", "battle-gallop", "battle-toccata"]
const FADE_S := 0.8
const SILENT_DB := -60.0

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _front: AudioStreamPlayer # the one that is audible
var _sting: AudioStreamPlayer
var _mode := ""


func _ready() -> void:
	_a = _player(Mix.MUSIC)
	_b = _player(Mix.MUSIC)
	_sting = _player(Mix.SFX)
	_front = _a


## "explore", "battle" (a theme picked from `seed`, so a monster keeps its theme), or "silence".
func set_mode(mode: String, seed := 0) -> void:
	var key := mode if mode != "battle" else "battle%d" % posmod(seed, BATTLES.size())
	if key == _mode:
		return
	_mode = key
	var path := ""
	if mode == "explore":
		path = EXPLORE
	elif mode == "battle":
		path = "res://assets/audio/%s.ogg" % BATTLES[posmod(seed, BATTLES.size())]
	print_verbose("music: %s" % key)
	_crossfade(path)


## A short fanfare, over the music: "victory" or "fanfare" (the champion).
func sting(name: String) -> void:
	var path := "res://assets/audio/%s.ogg" % name
	if not ResourceLoader.exists(path):
		push_error("music: no sting '%s'" % name)
		return
	_sting.stream = load(path)
	_sting.play()


func _crossfade(path: String) -> void:
	var old := _front
	var fresh := _b if old == _a else _a
	if path != "" and ResourceLoader.exists(path):
		var stream = load(path)
		stream.loop = true
		fresh.stream = stream
		fresh.volume_db = SILENT_DB
		fresh.play()
		_fade(fresh, 0.0)
		_front = fresh
	_fade(old, SILENT_DB, true)


func _fade(p: AudioStreamPlayer, to_db: float, stop_after := false) -> void:
	var tween := create_tween()
	tween.tween_property(p, "volume_db", to_db, FADE_S)
	if stop_after:
		tween.tween_callback(p.stop)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p
