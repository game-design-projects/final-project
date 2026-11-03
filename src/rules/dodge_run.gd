## One dodge phase: the monster attacks for a few seconds and you move a soul around the box (rules/dodge.gd) to stay out
## of the lit squares. Each faction spawns its hazards its own way. Time is in milliseconds on the game's clock.
## `update` spawns and resolves hazards and returns what happened (hurt, shield blocked, sounds) for the game to act on.
extends RefCounted

const Combat = preload("res://src/rules/combat.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")

const DURATION_MS := 5400.0
const DURATION_BOSS_MS := 6200.0
const FIRST_SPAWN_MS := 300.0
const SAFE_MS := 700.0 # no second hit within this long of one
const SAFE_SNAKE_MS := 1100.0 # with the snake's charm
const WARN_BANDIT_SCALE := 1.3 # the bandit's charm keeps warnings lit longer (not stomps: those follow the beat)

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


static func start(genre_id: String, pressure: float, boss_fight: bool, foe_turn_count: int, t: float, charms: Dictionary):
	var run = new()
	run.genre = genre_id
	run.intensity = Combat.dodge_intensity(pressure, boss_fight)
	run.t0 = t
	run.end_t = t + (DURATION_BOSS_MS if boss_fight else DURATION_MS)
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
			events.append({"type": "sound", "name": {"stomp": "hit", "chess": "slash", "light": "holy"}.get(h.kind, "")})
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


func _add_hazard(t: float, cells: Array, warn_ms: float, hit_ms: float, kind: String, extra := {}) -> void:
	if kind != "stomp" and bandit_charm:
		warn_ms *= WARN_BANDIT_SCALE
	var live := {}
	for k in cells:
		if not blocked.has(k):
			live[k] = true
	var h := {"cells": live, "warn": t, "hit": t + warn_ms, "end": t + warn_ms + hit_ms, "kind": kind, "sounded": false}
	h.merge(extra, true)
	hazards.append(h)


func _spawn(t: float, rng: Rng, events: Array) -> void:
	match genre:
		"chess":
			_spawn_chess(t, rng)
		"bullet":
			_spawn_bullet(t, rng)
		"rhythm":
			_spawn_rhythm(t, events)
		"shadow":
			_spawn_shadow(t)


func _spawn_chess(t: float, rng: Rng) -> void:
	if t < next_t:
		return
	next_t = t + 760.0 / intensity
	var kind: String = rng.pick(["rook", "rook", "bishop", "bishop", "knight"])
	if kind == "rook":
		# a rook enters from an edge, lined up with you on a row or a column
		var at: Vector2i
		if rng.chance(0.5):
			at = Vector2i(rng.pick([0, Dodge.COLS - 1]), soul.y)
		else:
			at = Vector2i(soul.x, rng.pick([0, Dodge.ROWS - 1]))
		_add_hazard(t, Dodge.rook_cells(at), 950.0, 320.0, "chess", {"glyph": "R", "at": Dodge.index(at.x, at.y)})
	elif kind == "bishop":
		var d: Vector2i = rng.pick(Dodge.BISHOP_DIRS)
		var k := rng.int_range(1, 3)
		while k > 0 and not Dodge.in_box(soul.x + d.x * k, soul.y + d.y * k):
			k -= 1
		var at := soul + d * k
		_add_hazard(t, Dodge.bishop_cells(at), 950.0, 320.0, "chess", {"glyph": "B", "at": Dodge.index(at.x, at.y)})
	else:
		var options := []
		for j in Dodge.KNIGHT_JUMPS:
			if Dodge.in_box(soul.x + j.x, soul.y + j.y):
				options.append(soul + j)
		var at: Vector2i = rng.pick(options)
		_add_hazard(t, Dodge.knight_cells(at), 900.0, 320.0, "chess", {"glyph": "N", "at": Dodge.index(at.x, at.y)})


func _spawn_bullet(t: float, rng: Rng) -> void:
	if t < next_t:
		return
	next_t = t + 330.0 / intensity
	var aimed := rng.chance(0.4)
	var c := soul.x if aimed else rng.int_range(0, Dodge.COLS - 1)
	var r := soul.y if aimed else rng.int_range(0, Dodge.ROWS - 1)
	var cells := []
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Dodge.in_box(c + d.x, r + d.y):
			cells.append(Dodge.index(c + d.x, r + d.y))
	_add_hazard(t, cells, 820.0, 260.0, "goo", {"at": Dodge.index(c, r)})


func _spawn_rhythm(t: float, events: Array) -> void:
	var beat_ms := 600.0 / sqrt(intensity)
	var b := floori((t - t0) / beat_ms)
	if b <= beat:
		return
	beat = b
	pulse = t
	events.append({"type": "beat"})
	events.append({"type": "sound", "name": "tick"})
	if b % 2 == 1:
		return # a new stomp every other beat, shown two beats ahead, landing on the beat
	var pattern := (b * 5 + foe_turn % 3) % Dodge.stomp_count()
	_add_hazard(t, Dodge.stomp_cells(pattern, soul), beat_ms * 2.0, 240.0, "stomp", {"beat_hit": true})


func _spawn_shadow(t: float) -> void:
	if t < next_t:
		return
	next_t = t + 1250.0 / intensity
	var warn := 900.0
	var lantern := Dodge.lantern_at(t + warn - t0, intensity)
	var cells := []
	for r in Dodge.ROWS:
		for c in Dodge.COLS:
			var k := Dodge.index(c, r)
			if not blocked.has(k) and not Dodge.in_shadow(lantern, c, r, blocked):
				cells.append(k)
	_add_hazard(t, cells, warn, 300.0, "light", {"lantern": lantern})
