## Everything you hear in a run. It listens to the game's events (`flow.happened`) and plays what they call for, and
## follows the player's health with the music's filter. The game never plays a sound itself; this is the only place
## that knows which event sounds like what. With the `nosound` flag it does nothing; `nosfx` and `nomusic` turn off
## the effects (and the monsters' voices) or the music alone.
extends Node

const Flags = preload("res://src/utils/flags.gd")
const Mix = preload("res://src/audio/mix.gd")
const Music = preload("res://src/audio/music.gd")
const Sfx = preload("res://src/audio/sfx.gd")
const Voices = preload("res://src/audio/voices.gd")

## Event name -> the effect it sounds like. Events that need more than that are handled in `_on_event`.
const SOUNDS := {
	"step": "step", "bump": "bump", "miss": "miss", "player_hurt": "hurt", "shield": "shield",
	"beat": "beat", "mercy_refused": "mercy_refused", "recruited": "recruited", "wants_join": "chime", "ally_left": "ally_left",
	"dead": "dead", "menu_move": "move", "menu_pick": "pick",
}

var _flow
var _sfx
var _music
var _voice: AudioStreamPlayer
var _quiet := false


func _ready() -> void:
	_quiet = Flags.on("nosound")
	if _quiet:
		return
	Mix.build_buses()
	_sfx = Sfx.new()
	_sfx.enabled = not Flags.on("nosfx")
	add_child(_sfx)
	_music = Music.new()
	_music.enabled = not Flags.on("nomusic")
	_music.hum = Flags.enabled("hum-theme")
	if Flags.enabled("motifs"):
		_music.motifs = Music.pick_motifs(Music.local_motifs(), Flags.value("motif"))
	add_child(_music)
	_voice = AudioStreamPlayer.new()
	_voice.bus = Mix.SFX
	_voice.finished.connect(_on_voice_done)
	add_child(_voice)


## Start listening to this game.
func bind(flow) -> void:
	_flow = flow
	flow.happened.connect(_on_event)
	if not _quiet:
		_music.set_mode("explore")


func _process(_dt: float) -> void:
	if _quiet or _flow == null:
		return
	var s = _flow.state
	Mix.set_danger((0.5 - float(s.hp) / s.max_hp) * 2.0)


func _on_event(name: String, data: Dictionary) -> void:
	if _quiet:
		return
	match name:
		"stage":
			if data.to == "explore" or data.to == "end":
				_music.set_mode("explore")
		"encounter":
			_sfx.play("boss" if data.boss else "encounter")
			_music.set_mode("battle")
		"strike":
			_sfx.play("crit" if data.crit else "strike")
		"spared", "slain":
			_sfx.play(name)
			_music.sting("victory")
		"stairs":
			_sfx.play("stairs")
			_music.sting("fanfare")
		"sound":
			_sfx.play(data.name)
		"shout":
			_speak(data)
		_:
			if SOUNDS.has(name):
				_sfx.play(SOUNDS[name])


## A monster says a line: its recording if it has one (the music ducks under it, and a newer line cuts an older one off,
## as the text on screen replaces the old line), otherwise the synthesised voice the line's wording asks for, which is
## silent for a line that is only a stage direction.
func _speak(data: Dictionary) -> void:
	var line = Voices.find(data.species, data.text)
	if line == null:
		print_verbose("audio: no recording for %s: %s" % [data.species, data.text])
		_sfx.shout(data.text, data.species, {"boss": data.boss})
		return
	if not _sfx.enabled:
		return
	_voice.stream = line
	_voice.volume_db = 0.0
	_voice.play()
	_music.duck(true)


func _on_voice_done() -> void:
	_music.duck(false)
