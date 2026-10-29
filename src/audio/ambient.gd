## The game's music. Two kinds of pre-rendered loops crossfaded by mood, plus one-shot stings for good moments.
## All of it is baroque, played by one sampled band (harpsichord, organ, strings, choir, music box, bells,
## kettle drums) in one stone hall, and all of it is built on the game's own melody.
##   explore: ambient.ogg, a slow passacaglia in D minor (tools/music/build-ambient.py). It does not play
##            nonstop: a stretch of music, then a stretch of quiet, like a mood that comes and goes.
##   battle:  battle-*.ogg, four toccata-style fight loops in different keys, tempos, leads and grooves
##            (tools/music/build-battle.py). A fight picks one at random (never the last one) and keeps it for
##            the whole fight: changing tune mid-fight was jarring.
##   stings:  fanfare.ogg when you go down the stairs, victory.ogg when you win a fight (tools/music/build-stings.py)
## Each loop file is trimmed to exactly one loop, starting LOOP_START seconds into the render, so Godot's
## gapless Ogg loop wraps inside the music (tools/music/to_ogg.sh).
## Load it with `const Ambient = preload("res://src/audio/ambient.gd")` and use `Ambient.Ambient`.
extends RefCounted

const Self = preload("res://src/audio/ambient.gd")
const Synth = preload("res://src/audio/synth.gd")
const Mix = preload("res://src/audio/mix.gd")
const J = preload("res://src/core/js.gd")

## Beat 0 of every render sits this far before the start of its loop file (the loop is cut from 0.25 s into the render)
const LOOP_START := 0.25
const TRACKS := {
	# The renders are mastered to -19 dBFS RMS (explore) and -17 dBFS RMS (fights and stings). These
	# volumes put a fight at about -19.5 dB, as loud against the sound effects as the music it replaced,
	# and the exploring music about 2.6 dB under it.
	"explore": {"url": "res://assets/audio/ambient.ogg", "bpm": 64, "loopSeconds": 112.5, "volume": 0.7},  # 40 bars of 3/4 at 64 BPM
	"battle": {
		"volume": 0.75,
		# 16 bars of 4/4 at each tempo: 3840 / BPM seconds
		"variants": [
			{"name": "toccata", "url": "res://assets/audio/battle-toccata.ogg", "bpm": 132, "loopSeconds": 3840.0 / 132},
			{"name": "charge", "url": "res://assets/audio/battle-charge.ogg", "bpm": 126, "loopSeconds": 3840.0 / 126},
			{"name": "crusade", "url": "res://assets/audio/battle-crusade.ogg", "bpm": 112, "loopSeconds": 3840.0 / 112},
			{"name": "gallop", "url": "res://assets/audio/battle-gallop.ogg", "bpm": 120, "loopSeconds": 3840.0 / 120},
		],
	},
}
# Under a monster's spoken line the music drops to this share of its level, quickly, and comes back slowly
const DUCK := {"level": 0.25, "down": 0.15, "up": 0.6}
const STINGS := {
	"fanfare": {"url": "res://assets/audio/fanfare.ogg", "volume": 0.75},
	"victory": {"url": "res://assets/audio/victory.ogg", "volume": 0.75},
}
# Seconds to fade a track in or out. A fight cuts in fast and the ambient gets out of its way just as fast
# (underFight), so the two never play together; between stretches of exploring the ambient fades out slowly.
const FADES := {"battle": {"in": 0.35, "out": 1.2}, "explore": {"in": 2.0, "out": 5.0, "underFight": 0.4}}
# The ambient's rhythm while exploring, in seconds: play a while, rest a while
const PACE := {
	"play": [80, 110],
	"rest": [60, 120],
	"afterFight": 2,  # a breath after a fight before the ambient returns
	"afterSting": 4,  # let the good news ring a moment
}
const FIRST_FADE_IN := 1.5


## One sound being played: the JS AudioBufferSourceNode plus its gain. `player` is the AudioStreamPlayer that
## makes it audible (made when the source is).
class Src:
	extends RefCounted
	var buffer: AudioStream
	var track := ""
	var loop := false
	var loop_start := 0.0  # where the loop starts, in render seconds (LOOP_START)
	var loop_end := 0.0
	var offset := 0.0  # where in the file playback began
	var gain: Synth.Param  # the loop's fader, linear; null for a sting
	var start_at := 0.0  # audio-clock time the player starts
	var started_at = null
	var stopped_at = null
	var player: AudioStreamPlayer
	var _started := false


class Ambient:
	extends Node
	var tracks: Dictionary
	var stings: Dictionary
	var clock: Callable  # () -> seconds on the audio clock; tests drive it
	var random: Callable  # () -> float in [0, 1)
	var on := false
	var mood := "explore"
	var buffers := {}
	var voices := {}  # track -> { src, gain, bpm, origin } while playing
	var sources: Array = []  # the latest sources made (a sting's is the last one)
	var next = null  # the pending explore play/rest switch: { at, fn }
	var battle = null  # the battle variant playing (or about to)
	var last_battle = null
	var attached := false
	var master := Synth.Param.new(1.0)  # speech ducking (duck)
	var mute := Synth.Param.new(1.0)  # the P switch
	var _loading: J.Waiter = null
	var _active: Array = []
	var _bus_db := 1.0e9

	func _init(opts := {}) -> void:
		tracks = opts.get("tracks", Self.TRACKS)
		stings = opts.get("stings", Self.STINGS)
		clock = opts.get("clock", Mix.clock)
		random = opts.get("random", func(): return randf())

	## Play through the shared buses (mix.gd). Call before start(). The music then switches off by muting itself.
	func attach(_mixer = null) -> void:
		if attached:
			return
		Mix.build_buses()
		attached = true
		mute.set_value_at_time(0.0, clock.call())
		_apply_bus(clock.call())

	func set_muted(muted: bool) -> void:
		mute.fade_to(0.0 if muted else 1.0, clock.call(), 0.12)

	## Call at the start of the game (on the web, from the first key press or click: browsers keep audio locked until then).
	## Resolves once the ambient is loaded and playing; the rest of the music loads behind it. Returns null, or
	## {"error": message} when the ambient can't be loaded (the music then stays off; calling start() again retries).
	func start():
		if not attached:
			attach()
		on = true
		set_muted(false)
		if _loading == null:
			_loading = J.Waiter.new()
			# Load the ambient first so it starts quickly; the rest load behind it
			if load_stream("explore") == null:
				var failed := _loading
				_loading = null
				failed.resolve()
				return {"error": "music: can't load %s" % tracks.explore.url}
			if mood == "explore":
				explore_in(Self.FIRST_FADE_IN)
			else:
				battle_in(Self.FADES.battle["in"])
			_loading.resolve()
			var rest: Array = []
			for v in tracks.battle.variants:
				rest.append("battle:" + v.name)
			rest.append_array(stings.keys())
			for name in rest:
				await get_tree().process_frame
				if load_stream(name) == null:
					push_warning("music: %s did not load" % name)
		else:
			await _loading.wait()
		if not on:
			silence()

	## The stream of a track: "explore", "battle:<variant>" or a sting
	func load_stream(name: String) -> AudioStream:
		if not buffers.has(name):
			var spec = _spec(name)
			if spec == null:
				return null
			var res = load(spec.url)
			if res == null:
				push_warning("music: can't load %s" % spec.url)
				return null
			if res is AudioStreamOggVorbis and not stings.has(name):
				res.loop = true
				res.loop_offset = 0.0
			buffers[name] = res
		return buffers[name]

	func _spec(name: String):
		if name.begins_with("battle:"):
			for v in tracks.battle.variants:
				if "battle:" + v.name == name:
					return v
			return null
		return tracks.get(name, stings.get(name))

	## Switch between "explore" and "battle". Safe to call any time, with music on or off, loaded or not.
	func set_mood(m: String) -> void:
		if m == mood or not tracks.has(m):
			return
		var was := mood
		mood = m
		print_verbose("music: %s -> %s" % [was, m])
		if not attached:
			return  # not started yet: start() plays the current mood
		fade_out(was, Self.FADES.explore.underFight if m == "battle" else Self.FADES[was]["out"])
		if m == "explore":
			rest_for(Self.PACE.afterFight)
			return
		cancel_next()
		battle_in(Self.FADES.battle["in"])

	## A one-shot cue for good news. Whatever is playing gets out of its way, then quiet for a while.
	func sting(name: String) -> void:
		if not attached or not buffers.has(name):
			print_verbose("music: sting %s skipped (not loaded)" % name)
			return
		print_verbose("music: sting %s" % name)
		var now: float = clock.call()
		for track in voices.keys():
			fade_out(track, 0.4)
		var src := Src.new()
		src.buffer = buffers[name]
		src.track = name
		src.start_at = now + 0.15
		src.started_at = src.start_at
		_play(src, linear_to_db(stings[name].volume))
		if mood == "explore":
			rest_for(src.buffer.get_length() + Self.PACE.afterSting)

	# ---- battle: a random loop per fight, kept for the whole fight

	func pick_battle():
		var all: Array = tracks.battle.variants
		var last_name = null if last_battle == null else last_battle.name
		var fresh := all.filter(func(v): return v.name != last_name)
		# Prefer one that's already loaded, so the fight's music starts at once
		var ready := fresh.filter(func(v): return buffers.has("battle:" + v.name))
		var pool: Array = ready if not ready.is_empty() else (fresh if not fresh.is_empty() else all)
		return pool[floori(float(random.call()) * pool.size())]

	func battle_in(fade: float, v = null) -> void:
		if v == null:
			v = pick_battle()
		battle = v
		last_battle = v
		var key: String = "battle:" + v.name
		if not buffers.has(key):
			_battle_when_loaded(key, v, fade)
			return
		print_verbose("music: battle loop %s" % v.name)
		fade_out("battle", fade)  # a loop still fading from the last fight, if any
		start_loop("battle", buffers[key], v.loopSeconds, tracks.battle.volume, fade, v.bpm)

	## The chosen loop is not loaded yet: load it, and play it if the fight is still on
	func _battle_when_loaded(key: String, v: Dictionary, fade: float) -> void:
		await get_tree().process_frame
		if load_stream(key) == null:
			push_warning("music: %s did not load" % key)
			return
		if mood == "battle" and battle == v:
			battle_in(fade, v)

	# ---- the explore rhythm: play a stretch, rest a stretch

	func explore_in(fade: float = Self.FADES.explore["in"]) -> void:
		if mood != "explore":
			return
		play("explore", fade)
		schedule(between(Self.PACE.play), _rest_after_playing)

	func _rest_after_playing() -> void:
		fade_out("explore", Self.FADES.explore["out"])
		rest_for(between(Self.PACE.rest))

	func rest_for(seconds: float) -> void:
		schedule(seconds, explore_in)

	func schedule(seconds: float, fn: Callable) -> void:
		cancel_next()
		next = {"at": float(clock.call()) + seconds, "fn": fn}

	func cancel_next() -> void:
		next = null

	## Seconds until the pending switch, as a list (empty when nothing is scheduled)
	func pending() -> Array:
		return [] if next == null else [next.at - float(clock.call())]

	func between(range_: Array) -> float:
		return range_[0] + (range_[1] - range_[0]) * float(random.call())

	# ---- voices

	## The ambient keeps its place while silent and comes back from there
	func play(track: String, fade: float) -> void:
		if not buffers.has(track):
			return
		var t: Dictionary = tracks[track]
		start_loop(track, buffers[track], t.loopSeconds, t.volume, fade, t.bpm)

	func start_loop(track: String, buffer: AudioStream, loop_seconds: float, volume: float, fade: float, bpm: float) -> void:
		var now: float = clock.call()
		var v = voices.get(track)
		if v == null:
			var src := Src.new()
			src.buffer = buffer
			src.track = track
			src.loop = true
			src.loop_start = Self.LOOP_START
			src.loop_end = Self.LOOP_START + loop_seconds
			src.offset = 0.0
			src.start_at = now
			src.started_at = now
			src.gain = Synth.Param.new(0.0)
			src.gain.set_value_at_time(0.0, now)
			_play(src, -80.0)
			# Beat k of the loop sounds at origin + k * 60 / bpm (the loop is whole bars, so the grid survives the wrap)
			v = {"src": src, "gain": src.gain, "bpm": bpm, "origin": now - Self.LOOP_START}
			voices[track] = v
		v.gain.fade_to(volume, now, fade)

	func fade_out(track: String, fade: float) -> void:
		var v = voices.get(track)
		if v == null:
			return
		var now: float = clock.call()
		v.gain.fade_to(0.0, now, fade)
		# A battle loop stops once silent (each fight starts a loop from bar one); the ambient idles at zero
		if track == "battle":
			v.src.stopped_at = now + fade + 0.05
			voices.erase(track)

	## Make room for speech (text to speech can't be turned up, so everything else turns down)
	func duck(is_on: bool) -> void:
		master.fade_to(Self.DUCK.level if is_on else 1.0, clock.call(), Self.DUCK.down if is_on else Self.DUCK.up)

	## The beat grid of what is playing, for anything that should land on the music's beat (the heartbeat):
	## { bpm, origin } with a beat on `origin` (audio-clock seconds), or null when no loop is running.
	func beat_clock():
		var v = voices.get("battle" if mood == "battle" else "explore")
		return {"bpm": v.bpm, "origin": v.origin} if v != null and v.bpm else null

	func stop() -> void:
		on = false
		silence()

	func silence() -> void:
		if attached:
			set_muted(true)

	func toggle() -> bool:
		if on:
			stop()
			return false
		await start()
		return true

	# ---- players

	## Makes the AudioStreamPlayer for a source and starts it (at src.start_at)
	func _play(src: Src, db: float) -> void:
		var p := AudioStreamPlayer.new()
		p.stream = src.buffer
		p.bus = Mix.BUS_MUSIC_IN
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		p.volume_db = db
		add_child(p)
		src.player = p
		sources.append(src)
		if sources.size() > 32:
			sources.pop_front()
		_active.append(src)
		if src.start_at <= float(clock.call()):
			_begin(src)

	func _begin(src: Src) -> void:
		src._started = true
		src.player.play(src.offset)

	func _process(_delta: float) -> void:
		tick()

	## Per-frame work: the pending explore switch, sting starts, fades into player volumes, finished sources
	func tick() -> void:
		var now: float = clock.call()
		if next != null and now >= next.at:
			var fn: Callable = next.fn
			next = null
			fn.call()
		for src in _active.duplicate():
			if src.stopped_at != null and now >= src.stopped_at:
				_release(src)
			elif not src._started:
				if now >= src.start_at:
					_begin(src)
			elif src.gain != null:
				src.player.volume_db = maxf(linear_to_db(maxf(src.gain.value_at(now), 1e-5)), -80.0)
				if src.gain.events.size() > 24:
					src.gain.rebase(now)
			elif not src.player.playing:
				_release(src)  # a sting that has played out
		_apply_bus(now)

	func _release(src: Src) -> void:
		_active.erase(src)
		if src.player != null:
			src.player.stop()
			src.player.queue_free()
			src.player = null

	## MusicIn carries the speech ducking and the P switch
	func _apply_bus(now: float) -> void:
		for p in [master, mute]:
			if p.events.size() > 24:
				p.rebase(now)
		var db := linear_to_db(maxf(master.value_at(now) * mute.value_at(now), 1e-5))
		if absf(db - _bus_db) > 0.01:
			_bus_db = db
			var idx := AudioServer.get_bus_index(Mix.BUS_MUSIC_IN)
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, db)
