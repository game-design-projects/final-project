## The music: a quiet loop while exploring that plays a stretch and then rests (it does not play nonstop), one of four
## battle themes in a fight (a random one, never the last), and short stings: the victory when a fight is won, the
## fanfare at the stairs. A sting takes the loops out of its way, and the exploring music comes back after it has rung
## out and a few seconds more. The tracks are in assets/audio/.
## A loop's fade belongs to the player it fades, and a new fade cancels the old one on the same player, so an old fade
## can never stop what a newer one has started. A battle theme gets a player of its own for each fight.
extends Node

const Mix = preload("res://src/audio/mix.gd")

const EXPLORE := "res://assets/audio/ambient.ogg"
const BATTLES := ["battle-toccata", "battle-charge", "battle-crusade", "battle-gallop"]
const STINGS := ["victory", "fanfare"]
## The tracks are mastered to -19 dBFS RMS (exploring) and -17 dBFS RMS (fights and stings). These levels put a fight
## about as loud against the effects as the old music, and the exploring music about 2.6 dB under it.
const VOLUME := {"explore": 0.7, "battle": 0.75, "sting": 0.75}
## Seconds to fade a track in or out. A fight cuts in fast and the exploring music gets out of its way just as fast
## (under_fight), so the two never play together; between stretches of exploring it fades out slowly.
const FADES := {"battle": {"in": 0.35, "out": 1.2}, "explore": {"in": 2.0, "out": 5.0, "under_fight": 0.4}, "sting": 0.4}
## The exploring music's rhythm, in seconds: play a while, rest a while.
const PACE := {
	"play": [80.0, 110.0],
	"rest": [60.0, 120.0],
	"after_fight": 2.0, # a breath after a fight before the exploring music returns
	"after_sting": 4.0, # let the good news ring a moment
}
const FIRST_FADE_IN := 1.5
const SILENT_DB := -60.0

## False with the `nomusic` flag: no player is made and nothing plays.
var enabled := true
## () -> float in [0, 1), for the pacing and the choice of theme (tests drive it).
var random: Callable = func(): return randf()

var _explore: AudioStreamPlayer
var _battle: AudioStreamPlayer # this fight's theme, or null
var _battle_name := ""
var _last_battle := ""
var _sting: AudioStreamPlayer
var _mode := ""
var _resting := false # the exploring music is between stretches
var _now := 0.0 # seconds the music has been running, advanced by `advance`
var _next_at := -1.0
var _next: Callable
var _hold_until := 0.0 # a sting is ringing out, or just has: the exploring music waits until then
var _sting_length := 0.0
var _streams := {}
var _tweens := {} # player -> the fade it is in
var _duck_tween: Tween


func _ready() -> void:
	if not enabled:
		return
	_explore = _player(Mix.MUSIC_IN)
	_explore.stream = _stream(EXPLORE)
	_explore.volume_db = SILENT_DB
	_sting = _player(Mix.SFX)
	for n in BATTLES:
		ResourceLoader.load_threaded_request(_battle_path(n))
	for n in STINGS:
		ResourceLoader.load_threaded_request(_sting_path(n))


func _process(dt: float) -> void:
	advance(dt)


## "explore", "battle" (a random theme, not the last one's) or "silence".
func set_mode(mode: String) -> void:
	if not enabled or (mode == _mode and (mode != "battle" or _battle != null)):
		return
	var was := _mode
	_mode = mode
	print_verbose("music: %s -> %s" % [was, mode])
	match mode:
		"explore":
			_drop_battle(FADES.battle.out)
			if was == "":
				_explore_in(FIRST_FADE_IN)
			else:
				_rest_for(PACE.after_fight)
		"battle":
			_cancel_next()
			_resting = false
			_fade_out_explore(FADES.explore.under_fight)
			_start_battle()
		_:
			_cancel_next()
			_drop_battle(FADES.battle.out)
			_fade_out_explore(FADES.explore.out)


## A short fanfare, over the music: "victory" (a fight won) or "fanfare" (the stairs). The loops get out of its way, and
## the exploring music returns after it and a few seconds of quiet.
func sting(name: String) -> void:
	if not enabled:
		return
	var path := _sting_path(name)
	if not ResourceLoader.exists(path):
		push_error("music: no sting '%s'" % name)
		return
	var stream: AudioStream = _stream(path)
	_drop_battle(FADES.sting)
	_fade_out_explore(FADES.sting)
	_sting.stream = stream
	_sting.volume_db = linear_to_db(VOLUME.sting)
	_sting.play()
	_sting_length = stream.get_length()
	_hold_until = _now + _sting_length + PACE.after_sting
	print_verbose("music: sting %s (%.1f s), exploring music back in %.1f s" % [name, _sting_length, _hold_until - _now])
	if _mode == "explore":
		_rest_for(0.0)


## Drop the music under a monster's recorded voice, then bring it back.
func duck(on: bool) -> void:
	if not enabled:
		return
	var idx := AudioServer.get_bus_index(Mix.MUSIC_IN)
	if idx < 0:
		return
	if _duck_tween != null:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(func(db): AudioServer.set_bus_volume_db(idx, db), AudioServer.get_bus_volume_db(idx), Mix.DUCK_DB if on else 0.0, Mix.DUCK_DOWN_S if on else Mix.DUCK_UP_S)


## Move the music's clock on (the game's frames do this; a test can jump).
func advance(dt: float) -> void:
	_now += dt
	if _next_at >= 0.0 and _now >= _next_at:
		var fn := _next
		_cancel_next()
		fn.call()


# ---- what the tests and the log can ask

func mode() -> String:
	return _mode


## The player of a loop ("explore" or "battle"), or null.
func loop_player(track: String) -> AudioStreamPlayer:
	return _explore if track == "explore" else _battle


## The theme of the fight on, or of the last one.
func battle_name() -> String:
	return _battle_name


## Seconds until the exploring music next starts or rests, or -1 when nothing is waiting.
func pending_in() -> float:
	return _next_at - _now if _next_at >= 0.0 else -1.0


func is_resting() -> bool:
	return _resting


func sting_length() -> float:
	return _sting_length


# ---- a fight's theme

## A theme that is not the last one's.
func pick_battle() -> String:
	var fresh := BATTLES.filter(func(n): return n != _last_battle)
	return fresh[mini(floori(float(random.call()) * fresh.size()), fresh.size() - 1)]


func _start_battle() -> void:
	_drop_battle(FADES.battle.out) # a theme still fading from the last fight is let go; this fight gets its own player
	_battle_name = pick_battle()
	_last_battle = _battle_name
	var stream: AudioStream = _stream(_battle_path(_battle_name))
	_battle = _player(Mix.MUSIC_IN)
	_battle.stream = stream
	_battle.volume_db = SILENT_DB
	_battle.play()
	_fade(_battle, linear_to_db(VOLUME.battle), FADES.battle["in"])
	print_verbose("music: battle theme %s" % _battle_name)


## Let the fight's theme fade out and go; the next fight makes a new player.
func _drop_battle(seconds: float) -> void:
	if _battle == null:
		return
	_fade(_battle, SILENT_DB, seconds, _release.bind(_battle))
	_battle = null


# ---- the exploring music's rhythm: play a stretch, rest a stretch

func _explore_in(fade: float) -> void:
	if _mode != "explore":
		return
	_resting = false
	_explore.stream_paused = false # it keeps its place while resting and comes back from there
	if not _explore.playing:
		_explore.play()
	_fade(_explore, linear_to_db(VOLUME.explore), fade)
	_schedule(_between(PACE.play), _rest_after_playing)
	print_verbose("music: exploring music in, resting in %.0f s" % pending_in())


func _resume_explore() -> void:
	_explore_in(FADES.explore["in"])


func _rest_after_playing() -> void:
	_fade_out_explore(FADES.explore.out)
	_rest_for(_between(PACE.rest))


## The exploring music is out; it comes back in `seconds`, or when the last sting has rung out, whichever is later.
func _rest_for(seconds: float) -> void:
	_resting = true
	_schedule(maxf(seconds, _hold_until - _now), _resume_explore)
	print_verbose("music: resting for %.1f s" % pending_in())


func _fade_out_explore(seconds: float) -> void:
	if _explore != null and _explore.playing and not _explore.stream_paused:
		_fade(_explore, SILENT_DB, seconds, func(): _explore.stream_paused = true)


func _schedule(seconds: float, fn: Callable) -> void:
	_next_at = _now + seconds
	_next = fn


func _cancel_next() -> void:
	_next_at = -1.0
	_next = Callable()


func _between(range_: Array) -> float:
	return range_[0] + (range_[1] - range_[0]) * float(random.call())


# ---- players and fades

## Fade a player's volume. A fade already running on that player is cancelled first, with whatever it was going to do at
## its end, so an old fade-out cannot stop or pause what a newer fade-in brought back.
func _fade(p: AudioStreamPlayer, to_db: float, seconds: float, then := Callable()) -> void:
	if _tweens.has(p):
		_tweens[p].kill()
	var tween := create_tween()
	_tweens[p] = tween
	tween.tween_property(p, "volume_db", to_db, seconds)
	if then.is_valid():
		tween.tween_callback(then)


func _release(p: AudioStreamPlayer) -> void:
	_tweens.erase(p)
	p.stop()
	p.queue_free()


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _battle_path(name: String) -> String:
	return "res://assets/audio/%s.ogg" % name


func _sting_path(name: String) -> String:
	return "res://assets/audio/%s.ogg" % name


## A track, loaded the first time (the fights' themes and the stings were requested in the background at the start).
func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		var stream: AudioStream
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			stream = ResourceLoader.load_threaded_get(path)
		else:
			stream = load(path)
		if stream is AudioStreamOggVorbis and (path == EXPLORE or path.contains("/battle-")):
			stream.loop = true # the loops are cut to whole bars, so they wrap inside the music
		_streams[path] = stream
	return _streams[path]
