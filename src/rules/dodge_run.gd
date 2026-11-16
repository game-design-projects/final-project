## One dodge phase: the monster attacks for a few seconds and you move a soul around the box (rules/dodge.gd) to stay out
## of the lit squares. Each faction spawns its hazards its own way. Time is in milliseconds on the game's clock.
## `update` spawns and resolves hazards and returns what happened (hurt, shield blocked, sounds) for the game to act on.
##
## A close call: you stood on a square that was about to light and stepped off it in its last moments (Combat.NERVE_WINDOW_MS).
## The run only says so ({"type": "nerve"}); what it is worth is the game's business (stages/dodge.gd). Hazards that began in
## the same moment and are of one kind (the columns of a wall) are one thing: one close call for the lot.
##
## How the foe feels (`mood`, Feelings.mood) shows in any attack: a friendly one drops a heart to catch now and then, and a
## frightened one falters (one hazard in three never comes) and breaks off early.
extends RefCounted

const Combat = preload("res://src/rules/combat.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const Pace = preload("res://src/rules/pace.gd")
const Rng = preload("res://src/utils/rng.gd")

const DURATION_MS := 5400.0
const DURATION_BOSS_MS := 6200.0
const FIRST_SPAWN_MS := 300.0
const SAFE_MS := 700.0 # no second hit within this long of one
const SAFE_SNAKE_MS := 1100.0 # with the snake's charm
const WARN_BANDIT_SCALE := 1.3 # the bandit's charm keeps warnings lit longer (not stomps: those follow the beat)
const CATCHES := ["star", "pad", "heart"] # what is there to be caught, not dodged
const AFRAID_DURATION := 0.75 # a frightened monster breaks off early
const AFRAID_FALTERS := 3 # and one hazard in this many never comes
const GIFT_FIRST_MS := 900.0 # a friendly monster's first heart
const GIFT_EVERY_MS := 1300.0
const GIFT_WARN_MS := 700.0
const GIFT_STAYS_MS := 1100.0
const MINI_GAMES := {
	"bullet": preload("res://src/rules/minigames/goo.gd"),
	"chess": preload("res://src/rules/minigames/chess.gd"),
	"dance": preload("res://src/rules/minigames/dance.gd"),
	"gates": preload("res://src/rules/minigames/gates.gd"),
	"rhythm": preload("res://src/rules/minigames/rhythm.gd"),
	"shadow": preload("res://src/rules/minigames/shadow.gd"),
	"stars": preload("res://src/rules/minigames/stars.gd"),
}

var genre := ""
var intensity := 1.0
var t0 := 0.0
var end_t := 0.0
var soul := Vector2i(3, 3)
var hazards: Array = [] # {cells: {index: true}, warn, hit, end, kind, sounded, ...}
var next_t := 0.0
var beat := -1
var pad := Vector2i(3, 3) # where the dance's light last was
var blocked := {} # pillar cells in the shadow box
var iframes := 0.0
var shield := false # the slime's charm absorbs the first hit
var hit_flash := -1e9
var block_flash := -1e9
var pulse := 0.0
var boss := false
var guard := 0 # what the party takes off each hit
var foe_turn := 0
var bandit_charm := false
var snake_charm := false
var pace := 1.0 # below 1 the hazards come further apart and warn for longer (rules/pace.gd)
var elite_damage := 0 # what a clan's elite adds to each hit (rules/clans.gd)
var mood := "" # how the foe feels as it attacks (Feelings.mood), "" for a plain run
var close_calls := 0 # how many this dodge
var hits := 0 # how many hits landed this dodge (a hit the slime's charm took is not one)
var nerve_flash := -1e9 # when the last close call was
var _nerved := {} # group -> true: what has given its close call
var _pending: Array = [] # what a step taken between two updates has to say
var _added := 0 # hazards asked for, for the faltering
var _next_gift := 0.0


## `elite` is what a clan's elite adds ({intensity, damage}, Clans.elite()), or {} for anyone else. `foe_mood` is how it feels.
static func start(genre_id: String, pressure: float, boss_fight: bool, foe_turn_count: int, t: float, charms: Dictionary, dodge_pace := 1.0, elite := {}, foe_mood := ""):
	var run = new()
	run.pace = dodge_pace
	run.genre = genre_id
	run.mood = foe_mood
	run._next_gift = t + GIFT_FIRST_MS
	run.intensity = Combat.dodge_intensity(pressure, boss_fight) * float(elite.get("intensity", 1.0))
	run.elite_damage = int(elite.get("damage", 0))
	run.t0 = t
	run.end_t = t + (DURATION_BOSS_MS if boss_fight else DURATION_MS) * (Pace.DURATION_SCALE if dodge_pace < 1.0 else 1.0) * (AFRAID_DURATION if foe_mood == "afraid" else 1.0)
	run.next_t = t + FIRST_SPAWN_MS
	run.boss = boss_fight
	run.foe_turn = foe_turn_count
	run.shield = charms.get("slime", false)
	run.bandit_charm = charms.get("bandit", false)
	run.snake_charm = charms.get("snake", false)
	if genre_id == "shadow":
		run.blocked = Dodge.pillar_set()
	print_verbose("dodge: %s, intensity %.2f, boss %s" % [genre_id, run.intensity, boss_fight])
	return run


## A step. Given the time `t` it is also looked at as a close call (see the top of the file); without it, it only moves.
func move(dc: int, dr: int, t := -1.0) -> void:
	var c := soul + Vector2i(dc, dr)
	if Dodge.in_box(c.x, c.y) and not blocked.has(Dodge.index(c.x, c.y)):
		if t >= 0.0:
			_close_call(Dodge.index(soul.x, soul.y), Dodge.index(c.x, c.y), t)
		soul = c


## Stepping from square `from` to `to` at `t`: a close call for each thing about to land on `from` that `to` is clear of.
func _close_call(from: int, to: int, t: float) -> void:
	for h in hazards:
		if h.kind in CATCHES or t >= h.hit or h.hit - t > Combat.NERVE_WINDOW_MS:
			continue
		if not h.cells.has(from) or h.cells.has(to) or _nerved.has(h.group):
			continue
		_nerved[h.group] = true
		close_calls += 1
		nerve_flash = t
		_pending.append({"type": "nerve"})
		print_verbose("dodge: close call, %.0f ms before a %s landed" % [h.hit - t, h.kind])


func is_over(t: float) -> bool:
	return t >= end_t


## Advances to time `t`. Returns events: {"type": "sound", "name"}, {"type": "beat"}, {"type": "hurt", "damage"},
## {"type": "shield"}, {"type": "nerve"} (a close call), {"type": "star"} and {"type": "heart"} (caught). The caller applies
## damage and decides what each is worth.
func update(t: float, rng: Rng) -> Array:
	var events: Array = _pending
	_pending = []
	_spawn(t, rng, events)
	var here := Dodge.index(soul.x, soul.y)
	for h in hazards:
		if t >= h.hit and not h.sounded:
			h.sounded = true
			events.append({"type": "sound", "name": {"stomp": "hit", "chess": "slash", "light": "holy", "wall": "tick"}.get(h.kind, "")})
		if h.kind in CATCHES:
			if t >= h.hit and t < h.end and h.cells.has(here) and not h.get("taken", false):
				h.taken = true
				events.append({"type": "heart" if h.kind == "heart" else "star"})
				events.append({"type": "sound", "name": "good"})
			continue
		if t >= h.hit and t < h.end and h.cells.has(here) and t > iframes:
			iframes = t + (SAFE_SNAKE_MS if snake_charm else SAFE_MS)
			if shield:
				shield = false
				block_flash = t
				events.append({"type": "shield"})
				continue
			hit_flash = t
			hits += 1
			events.append({"type": "hurt", "damage": maxi(1, (Combat.DODGE_DAMAGE_BOSS if boss else Combat.DODGE_DAMAGE) + elite_damage - guard)})
	hazards = hazards.filter(func(h): return t < h.end)
	return events


func add_hazard(t: float, cells: Array, warn_ms: float, hit_ms: float, kind: String, extra := {}) -> void:
	if not kind in CATCHES:
		_added += 1
		if mood == "afraid" and _added % AFRAID_FALTERS == 0:
			return # it flinched: this one never comes
	if kind != "stomp" and bandit_charm:
		warn_ms *= WARN_BANDIT_SCALE
	warn_ms /= pace if kind != "stomp" else 1.0 # a stomp's warning is its beats, which are slowed already
	var live := {}
	for k in cells:
		if not blocked.has(k):
			live[k] = true
	var h := {"cells": live, "warn": t, "hit": t + warn_ms, "end": t + warn_ms + hit_ms, "kind": kind, "sounded": false, "group": "%s@%d" % [kind, roundi(t)]}
	h.merge(extra, true)
	hazards.append(h)


## Each kind of attack is a mini-game of its own (rules/minigames/): it adds this run's hazards as time passes.
func _spawn(t: float, rng: Rng, events: Array) -> void:
	if MINI_GAMES.has(genre):
		MINI_GAMES[genre].spawn(self, t, rng, events)
	else:
		push_error("dodge: no mini-game '%s'" % genre)
	if mood == "friendly" and t >= _next_gift:
		_drop_heart(t, rng)


## A friendly monster's attack, whichever it is, drops a heart now and then on a square nothing is coming for.
func _drop_heart(t: float, rng: Rng) -> void:
	_next_gift = t + GIFT_EVERY_MS
	var clear := []
	for k in Dodge.COLS * Dodge.ROWS:
		if not blocked.has(k) and not hazards.any(func(h): return not h.kind in CATCHES and h.cells.has(k)):
			clear.append(k)
	if clear.is_empty():
		return
	var at: int = rng.pick(clear)
	add_hazard(t, [at], GIFT_WARN_MS * pace, GIFT_STAYS_MS, "heart", {"at": at}) # (add_hazard undoes the pace: a heart falls as fast for anyone)
