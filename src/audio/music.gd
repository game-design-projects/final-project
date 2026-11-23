## The music: every place and every foe has its own (tools/music/build-themes.py). Where you are picks the exploring loop
## (`set_scene`): each biome, and the same biome again deeper; each clan's hall; the camp, the trader, the practice floor and the
## test room. It plays a stretch and then rests, except at the camp and the trader, which play while you are there. Who a fight
## is with picks its loop (`fight_with`): every kind of monster its own, and each champion. A clan's tunes share one melody
## and differ in key, tempo, band and the rest of the tune; the clans, the champions and the places each have melodies of their
## own. Short stings go over it all: the victory when a foe is spared, the fanfare at the stairs. A sting takes the loops out of
## its way, and the exploring music comes back after it has rung out and a few seconds more.
## Of the music before, the camp keeps one theme: Abdulla's hum theme. The tracks are in assets/audio/music/.
## A loop's fade belongs to the player it fades, and a new fade cancels the old one on the same player, so an old fade
## can never stop what a newer one has started. A fight's loop gets a player of its own for each fight; each place keeps its
## own player while you are on its floor, so the camp hands the floor's music back where it left off.
extends Node

const Mix = preload("res://src/audio/mix.gd")

const DIR := "res://assets/audio/music/"
## The one old theme still played: Abdulla's hum theme (tools/music/hum-theme/), a loop of 174.55 s, at the camp.
const CAMP := "res://assets/audio/hum-explore.ogg"
## Places that play for as long as you are in them, without the exploring music's rests.
const STAY := ["camp", "trade"]
## Where there is no biome (the classic floor), and the fight of a foe whose tune is missing.
const DEFAULT_SCENE := "explore-halls"
const DEFAULT_FIGHT := "fight-slime"
const STINGS := ["victory", "fanfare"]
## Level trims by track, dB: the hum theme is mastered 1 dB hotter than the rest (-18 against -19 dBFS RMS).
const TRIM_DB := {"camp": -1.0}
## The tracks are mastered to -19 dBFS RMS (exploring) and -17 dBFS RMS (fights and stings). These levels put a fight
## about as loud against the effects as the old music, and the exploring music about 2.6 dB under it.
const VOLUME := {"explore": 0.7, "battle": 0.75, "sting": 0.75}
## Seconds to fade a track in or out. A fight cuts in fast and the exploring music gets out of its way just as fast
## (under_fight), so the two never play together; between stretches of exploring it fades out slowly, and from one place to
## the next (the floor to the camp and back) it crosses over (`scene`).
const FADES := {"battle": {"in": 0.35, "out": 1.2}, "explore": {"in": 2.0, "out": 5.0, "under_fight": 0.4, "scene": 1.0}, "sting": 0.4}
## The exploring music's rhythm, in seconds: play a while, rest a while.
const PACE := {
	"play": [80.0, 110.0],
	"rest": [60.0, 120.0],
	"after_fight": 2.0, # a breath after a fight before the exploring music returns
	"after_sting": 4.0, # let the good news ring a moment
}
const FIRST_FADE_IN := 1.5
const SILENT_DB := -60.0
## Abdulla's motifs on trial (issue #49, the feature `motifs`): local files cut by tools/music/cut_motifs.sh, never shipped until
## their soundfont and license are known. Stretches take turns, a motif then the exploring music, with short rests so they can be
## compared. They are mastered at -17 dBFS RMS: this level puts them with the exploring music, not over it.
const MOTIF_DIR := "res://build/motifs/"
const TRIAL := {"play": [25.0, 35.0], "rest": [4.0, 8.0], "volume": 0.58}

## False with the `nomusic` flag: no player is made and nothing plays.
var enabled := true
## The motifs on trial, as streams in their order: none (as a shipped game has) leaves the music as it always was.
var motifs: Array = []
## () -> float in [0, 1), for the pacing (tests drive it).
var random: Callable = func(): return randf()

var _explore: AudioStreamPlayer # the player of the place you are in, or null before the first
var _scene := ""
var _scenes := {} # place -> its player, which keeps its place while another plays
var _battle: AudioStreamPlayer # this fight's loop, or null
var _battle_name := ""
var _fight := DEFAULT_FIGHT # the tune of the next fight
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
var _motif: AudioStreamPlayer # the motif playing, or null
var _motif_at := 0 # which comes next
var _motif_playing := 0 # 1.. while one plays
var _motif_turn := true # whose turn the next stretch is


func _ready() -> void:
	if not enabled:
		return
	print("music: a tune for every place and every foe (%s)" % DIR)
	_sting = _player(Mix.SFX)
	for n in STINGS:
		ResourceLoader.load_threaded_request(_sting_path(n))


func _process(dt: float) -> void:
	advance(dt)


## The exploring music for a place (`scene_of`, "camp", "trade"): crosses over to it now if you are exploring, or when you next are.
func set_scene(name: String) -> void:
	if not enabled or name == _scene:
		return
	var path := track_path(name)
	if not ResourceLoader.exists(path):
		push_warning("music: no tune for %s (%s); %s instead" % [name, path, DEFAULT_SCENE])
		name = DEFAULT_SCENE
		if name == _scene:
			return
	var was := _scene
	var old := _explore
	_scene = name
	print("music: the place's tune %s -> %s" % [was if was != "" else "none", name])
	if old != null and not (was in STAY or name in STAY):
		_scenes.erase(was) # a floor left for another: its music goes with it
		_fade(old, SILENT_DB, FADES.explore.scene, _release.bind(old))
	elif old != null and old.playing and not old.stream_paused:
		_fade(old, SILENT_DB, FADES.explore.scene, func(): old.stream_paused = true)
	if not _scenes.has(name):
		var p := _player(Mix.MUSIC_IN)
		p.stream = _stream(track_path(name))
		p.volume_db = SILENT_DB
		_scenes[name] = p
	_explore = _scenes[name]
	if _mode == "explore" and not _resting:
		_explore_in(FADES.explore.scene)
	elif _mode == "explore" and name in STAY:
		_cancel_next()
		_explore_in(FADES.explore.scene)


## The tune of who the next fight is with (`fight_of`), said before `set_mode("battle")`.
func fight_with(name: String) -> void:
	if ResourceLoader.exists(track_path(name)):
		_fight = name
	else:
		push_warning("music: no tune for %s; %s instead" % [name, DEFAULT_FIGHT])
		_fight = DEFAULT_FIGHT


## Load these tunes in the background now (the fights a floor may bring), so a fight's music is ready when it starts.
func prepare(names: Array) -> void:
	if not enabled:
		return
	for n in names:
		var path := track_path(str(n))
		if not _streams.has(path) and ResourceLoader.exists(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)


## The exploring loop's place for a game state: the test room, the practice floor, a clan's hall, or the floor's biome, with
## its -deep tune once the biomes have all come round and it comes again.
static func scene_of(state) -> String:
	if state == null:
		return DEFAULT_SCENE
	if bool(state.testing):
		return "test-room"
	if bool(state.practice):
		return "practice"
	if str(state.visiting) != "":
		return "hall-" + str(state.visiting)
	var biome := str(state.floor_map.biome) if state.floor_map != null else ""
	if biome == "":
		return DEFAULT_SCENE
	var round_trip: int = (load("res://src/rules/content.gd").table("biomes").biomes as Array).size()
	return "explore-%s%s" % [biome, "-deep" if int(state.depth) > round_trip else ""]


## A fight's tune for its foe: a champion's own, or its kind's.
static func fight_of(foe) -> String:
	if foe == null:
		return DEFAULT_FIGHT
	if bool(foe.boss):
		return "champion-" + str(foe.name).to_lower()
	return "fight-" + str(foe.kind)


static func track_path(name: String) -> String:
	return CAMP if name == "camp" else "%s%s.ogg" % [DIR, name]


## "explore" (the place's loop), "battle" (the next fight's tune, `fight_with`) or "silence".
func set_mode(mode: String) -> void:
	if not enabled or (mode == _mode and (mode != "battle" or _battle != null)):
		return
	if mode == "explore" and _explore == null:
		set_scene(DEFAULT_SCENE) # before the mode changes, so it only chooses the tune and the mode brings it in
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
			_drop_motif(FADES.explore.under_fight)
			_fade_out_explore(FADES.explore.under_fight)
			_start_battle()
		_:
			_cancel_next()
			_drop_motif(FADES.explore.out)
			_drop_battle(FADES.battle.out)
			_fade_out_explore(FADES.explore.out)


## A short fanfare, over the music: "victory" (a foe spared) or "fanfare" (the stairs). The loops get out of its way, and
## the exploring music returns after it and a few seconds of quiet.
func sting(name: String) -> void:
	if not enabled:
		return
	var path := _sting_path(name)
	if not ResourceLoader.exists(path):
		push_error("music: no sting '%s'" % name)
		return
	var stream: AudioStream = _stream(path)
	if stream == null:
		return # _stream said why
	_drop_battle(FADES.sting)
	_drop_motif(FADES.sting)
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


## Which motif is playing, from 1, or 0 for none.
func playing_motif() -> int:
	return _motif_playing


## Seconds until the exploring music next starts or rests, or -1 when nothing is waiting.
func pending_in() -> float:
	return _next_at - _now if _next_at >= 0.0 else -1.0


func is_resting() -> bool:
	return _resting


func sting_length() -> float:
	return _sting_length


# ---- a fight's tune

func _start_battle() -> void:
	_drop_battle(FADES.battle.out) # a theme still fading from the last fight is let go; this fight gets its own player
	_battle_name = _fight
	var stream: AudioStream = _stream(_battle_path(_battle_name))
	_battle = _player(Mix.MUSIC_IN)
	_battle.stream = stream
	_battle.volume_db = SILENT_DB
	_battle.play()
	_fade(_battle, _level("battle", _battle_name), FADES.battle["in"])
	print_verbose("music: fight tune %s" % _battle_name)


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
	if not motifs.is_empty() and _motif_turn:
		_play_motif()
		return
	_motif_turn = true
	_explore.stream_paused = false # it keeps its place while resting and comes back from there
	if not _explore.playing:
		_explore.play()
	_fade(_explore, _level("explore", _scene), fade)
	if _scene in STAY:
		_cancel_next() # the floor's rest is not this place's
		print_verbose("music: %s in, for as long as you are there" % _scene)
		return
	_schedule(_between(TRIAL.play if not motifs.is_empty() else PACE.play), _rest_after_playing)
	print_verbose("music: %s in, resting in %.0f s" % [_scene, pending_in()])


func _resume_explore() -> void:
	_explore_in(FADES.explore["in"])


func _rest_after_playing() -> void:
	_fade_out_explore(FADES.explore.out)
	_rest_for(_between(TRIAL.rest if not motifs.is_empty() else PACE.rest))


## The next motif, once, to its end. The exploring music keeps its place.
func _play_motif() -> void:
	var stream: AudioStream = motifs[_motif_at % motifs.size()]
	_motif_playing = _motif_at % motifs.size() + 1
	_motif_at += 1
	_motif_turn = false
	_motif = _player(Mix.MUSIC_IN)
	_motif.stream = stream
	_motif.volume_db = linear_to_db(TRIAL.volume)
	_motif.play()
	print("music: motif %d of %d (%.1f s)" % [_motif_playing, motifs.size(), stream.get_length()])
	_schedule(stream.get_length(), _motif_done)


func _motif_done() -> void:
	_drop_motif(FADES.sting)
	_rest_for(_between(TRIAL.rest))


func _drop_motif(seconds: float) -> void:
	if _motif == null:
		return
	if not motifs.is_empty() and _motif_playing > 0:
		_motif_turn = false # it was cut short or it ended: either way the exploring music is next
	_fade(_motif, SILENT_DB, seconds, _release.bind(_motif))
	_motif = null
	_motif_playing = 0


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


# ---- the motifs on trial

## The sections cut into `dir`, as streams in their order. None when they aren't there, as in anything exported.
static func local_motifs(dir := MOTIF_DIR) -> Array:
	var out := []
	var n := 1
	while FileAccess.file_exists("%smotif-%d.ogg" % [dir, n]):
		var stream := AudioStreamOggVorbis.load_from_file("%smotif-%d.ogg" % [dir, n])
		if stream != null:
			out.append(stream)
		n += 1
	if not out.is_empty():
		print("music: %d motifs on trial from %s" % [out.size(), dir])
	return out


## All of them, or the one `motif=N` asks for (from 1).
static func pick_motifs(all: Array, wanted: String) -> Array:
	if wanted.is_valid_int() and int(wanted) >= 1 and int(wanted) <= all.size():
		return [all[int(wanted) - 1]]
	return all


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


## A loop's playing level in dB: "explore" or "battle", and the tune's own trim.
func _level(track: String, tune: String) -> float:
	return linear_to_db(VOLUME[track]) + float(TRIM_DB.get(tune, 0.0))


func _battle_path(name: String) -> String:
	return track_path(name)


func _sting_path(name: String) -> String:
	return "%ssting-%s.ogg" % [DIR, name]


## A track, loaded the first time (the stings, and the fights `prepare` was told of, were requested in the background).
func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		var stream: AudioStream
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			stream = ResourceLoader.load_threaded_get(path)
		else:
			stream = load(path)
		if stream == null:
			push_error("music: can't load '%s'; if it was just pulled, run `godot --headless --path . --import`" % path)
		if stream is AudioStreamOggVorbis and not path.get_file().begins_with("sting-"):
			stream.loop = true # the loops are cut to whole bars, so they wrap inside the music
		_streams[path] = stream
	return _streams[path]
