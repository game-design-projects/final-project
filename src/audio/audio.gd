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
	"dead": "dead", "menu_move": "move", "menu_pick": "pick", "follow": "strike", "second_wind": "shield", "keepsake": "chime",
}

const SWEEP_NOTES := 4 # the strike bar's ticks, a note higher towards the middle (sfx.gd has sweep_1 to sweep_4)
const NERVE_NOTES := 5 # one rising note for each point of nerve (sfx.gd has nerve_1 to nerve_5)

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
	if Flags.enabled("motifs"):
		_music.motifs = Music.pick_motifs(Music.local_motifs(), Flags.value("motif"))
	add_child(_music)
	_voice = AudioStreamPlayer.new()
	_voice.bus = Mix.SFX
	_voice.finished.connect(_on_voice_done)
	add_child(_voice)


## The exploring tune of where the party is, and the fights its floor may bring loaded in the background.
func _place_music() -> void:
	if _flow == null or _flow.state == null:
		return
	var s = _flow.state
	_music.set_scene(Music.scene_of(s))
	if s.floor_map != null:
		_music.prepare(s.floor_map.monsters.map(func(m): return Music.fight_of(m)))


## Start listening to this game.
func bind(flow) -> void:
	_flow = flow
	flow.happened.connect(_on_event)
	if not _quiet:
		_place_music()
		_music.set_mode("explore")


func _process(_dt: float) -> void:
	if _quiet or _flow == null:
		return
	if _voice.playing: # the setting moved while a line is being said
		_voice.volume_db = linear_to_db(maxf(Mix.voice_gain(), 0.0001))
	var s = _flow.state
	Mix.set_danger((0.5 - float(s.hp) / s.max_hp) * 2.0)


func _on_event(name: String, data: Dictionary) -> void:
	if _quiet:
		return
	match name:
		"stage":
			if data.to in ["camp", "trade"]: # the camp and the trader have tunes of their own while you are there
				_music.set_scene(data.to)
				_music.set_mode("explore")
			elif data.to in ["explore", "end", "keepsake"]:
				_place_music()
				_music.set_mode("explore")
		"state_replaced": # a new floor, a hall, the test room: its own tune, and its foes' made ready
			_place_music()
		"encounter":
			_sfx.play("boss" if data.boss else "encounter")
			_music.fight_with(Music.fight_of(_flow.state.foe if _flow != null and _flow.state != null else null)) # its kind's tune, or the champion's
			_music.set_mode("battle")
		"strike":
			_sfx.play("crit" if data.crit else "strike")
		"spared": # the fanfare is for a mercy: a kill has its own sound and no triumph over it (#168)
			_sfx.play(name)
			_music.sting("victory")
		"slain":
			_sfx.play(name)
		"stairs":
			_sfx.play("stairs")
			_music.sting("fanfare")
		"sound":
			_sfx.play(data.name)
		"sweep":
			_sfx.play("sweep_%d" % clampi(int(data.step), 1, SWEEP_NOTES))
		"nerve":
			if data.how in ["close", "clean"]: # each point sounds a step higher than the last
				_sfx.play("nerve_%d" % clampi(int(data.total), 1, NERVE_NOTES))
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
	if not _sfx.enabled or Mix.voice_gain() <= 0.0:
		return # no sound, or the player turned monsters' voices off: nothing plays and the music stays up
	_voice.stream = line
	_voice.volume_db = linear_to_db(Mix.voice_gain())
	_voice.play()
	_music.duck(true)


func _on_voice_done() -> void:
	_music.duck(false)
