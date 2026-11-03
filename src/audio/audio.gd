## Everything you hear in a run. It listens to the game's events (`flow.happened`) and plays what they call for, and
## follows the player's health with the music's filter. The game never plays a sound itself; this is the only place
## that knows which event sounds like what. With the `nosound` flag it does nothing.
extends Node

const Flags = preload("res://src/utils/flags.gd")
const Mix = preload("res://src/audio/mix.gd")
const Music = preload("res://src/audio/music.gd")
const Sfx = preload("res://src/audio/sfx.gd")
const Voices = preload("res://src/audio/voices.gd")

## Event name -> the effect it sounds like. Events that need more than that are handled in `_on_event`.
const SOUNDS := {
	"step": "step", "bump": "bump", "strike": "strike", "miss": "miss", "player_hurt": "hurt", "shield": "shield",
	"beat": "beat", "mercy_refused": "mercy_refused", "recruited": "recruited", "ally_left": "ally_left",
	"dead": "dead", "stairs": "stairs",
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
	add_child(_sfx)
	_music = Music.new()
	add_child(_music)
	_voice = AudioStreamPlayer.new()
	_voice.bus = Mix.SFX
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
			var foe = _flow.state.foe
			_sfx.play("boss" if data.boss else "encounter")
			_music.set_mode("battle", hash(foe.species) if foe != null else 0)
		"spared", "slain":
			_sfx.play(name)
			_music.sting("fanfare" if data.boss else "victory")
		"sound":
			_sfx.play(data.name)
		"shout":
			_speak(data)
		_:
			if SOUNDS.has(name):
				_sfx.play(SOUNDS[name])


func _speak(data: Dictionary) -> void:
	var line = Voices.find(data.species, data.text)
	if line == null:
		_sfx.play("shout", -6.0)
		return
	_voice.stream = line
	_voice.play()
