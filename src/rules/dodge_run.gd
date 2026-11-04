## One dodge phase: the monster attacks for a few seconds and you move a soul around the box (rules/dodge.gd) to stay out
## of the lit squares. Each faction spawns its hazards its own way. Time is in milliseconds on the game's clock.
## `update` spawns and resolves hazards and returns what happened (hurt, shield blocked, sounds) for the game to act on.
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
const MINI_GAMES := {
	"bullet": preload("res://src/rules/minigames/goo.gd"),
	"chess": preload("res://src/rules/minigames/chess.gd"),
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
var blocked := {} # pillar cells in the shadow box
var iframes := 0.0
var shield := false # the slime's charm absorbs the first hit
var hit_flash := -1e9
var block_flash := -1e9
var pulse := 0.0
var boss := false
var foe_turn := 0
var bandit_charm := false
var snake_charm := false
var pace := 1.0 # below 1 the hazards come further apart and warn for longer (rules/pace.gd)


static func start(genre_id: String, pressure: float, boss_fight: bool, foe_turn_count: int, t: float, charms: Dictionary, dodge_pace := 1.0):
	var run = new()
	run.pace = dodge_pace
	run.genre = genre_id
	run.intensity = Combat.dodge_intensity(pressure, boss_fight)
	run.t0 = t
	run.end_t = t + (DURATION_BOSS_MS if boss_fight else DURATION_MS) * (Pace.DURATION_SCALE if dodge_pace < 1.0 else 1.0)
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


func move(dc: int, dr: int) -> void:
	var c := soul + Vector2i(dc, dr)
	if Dodge.in_box(c.x, c.y) and not blocked.has(Dodge.index(c.x, c.y)):
		soul = c


func is_over(t: float) -> bool:
	return t >= end_t


## Advances to time `t`. Returns events: {"type": "sound", "name"}, {"type": "beat"}, {"type": "hurt", "damage"},
## {"type": "shield"}. The caller applies damage and decides what a hit does to the player.
func update(t: float, rng: Rng) -> Array:
	var events: Array = []
	_spawn(t, rng, events)
	var here := Dodge.index(soul.x, soul.y)
	for h in hazards:
		if t >= h.hit and not h.sounded:
			h.sounded = true
			events.append({"type": "sound", "name": {"stomp": "hit", "chess": "slash", "light": "holy", "wall": "tick"}.get(h.kind, "")})
		if h.kind == "star":
			if t >= h.hit and t < h.end and h.cells.has(here) and not h.get("taken", false):
				h.taken = true
				events.append({"type": "star"})
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
			events.append({"type": "hurt", "damage": Combat.DODGE_DAMAGE_BOSS if boss else Combat.DODGE_DAMAGE})
	hazards = hazards.filter(func(h): return t < h.end)
	return events


func add_hazard(t: float, cells: Array, warn_ms: float, hit_ms: float, kind: String, extra := {}) -> void:
	if kind != "stomp" and bandit_charm:
		warn_ms *= WARN_BANDIT_SCALE
	warn_ms /= pace if kind != "stomp" else 1.0 # a stomp's warning is its beats, which are slowed already
	var live := {}
	for k in cells:
		if not blocked.has(k):
			live[k] = true
	var h := {"cells": live, "warn": t, "hit": t + warn_ms, "end": t + warn_ms + hit_ms, "kind": kind, "sounded": false}
	h.merge(extra, true)
	hazards.append(h)


## Each kind of attack is a mini-game of its own (rules/minigames/): it adds this run's hazards as time passes.
func _spawn(t: float, rng: Rng, events: Array) -> void:
	if MINI_GAMES.has(genre):
		MINI_GAMES[genre].spawn(self, t, rng, events)
	else:
		push_error("dodge: no mini-game '%s'" % genre)
