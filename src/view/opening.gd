## A run's first moment, for the feature wick: a very small witch hops down the corridor from as far as it runs, hands you a heart and
## goes to walk with you. It holds nothing up: the game is already yours, and the moment you move she is simply with you already.
extends Node3D

const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const Figure = preload("res://src/view/figure.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

const SHEET := "witch"
const MOST_CELLS := 4 # how far off she starts, in cells, if the corridor runs that far
const STOP_AHEAD := 1.5 # where she stops: this far past the middle of your cell, in world units, near enough to see and whole in the picture
const WALL_STOP_AHEAD := 0.75
const HOP_S := 0.46 # a hop, from one landing to the next
const GLIDE_S := 0.26 # the part of it she spends moving
const GIVE_S := 2.4 # how long she stands holding the heart out
const GOING_S := 0.5
const HEART_SIZE := 0.3
const HEART_RISE := 0.14
const FADE_IN_S := 0.35

var _figure: Node3D
var _heart: Node3D
var _path: Array = []
var _leg := 0
var _leg_t0 := 0.0
var _born := 0.0
var _gave_at := -1.0
var _going_at := -1.0
var _top := 1.0


## Where she comes from and where she stops, the near end last: the open cells straight ahead, farthest first, then the stop.
static func path(floor_map, cell: Vector2i, facing: int) -> Array:
	var way := Vector3(FloorMap.DIRS[facing].x, 0.0, FloorMap.DIRS[facing].y)
	var out := []
	var c := cell
	for i in MOST_CELLS:
		c += FloorMap.DIRS[facing]
		if not floor_map.is_open(c):
			break
		out.push_front(DungeonMesh.center(c))
	# a wall right ahead: she stands against it, nearer you
	var stop: Vector3 = DungeonMesh.center(cell) + way * (STOP_AHEAD if not out.is_empty() else WALL_STOP_AHEAD)
	if not out.is_empty() and out.back().distance_to(stop) < 0.6:
		out.pop_back()
	out.append(stop)
	return out


static func begin(floor_map, cell: Vector2i, facing: int, tint: Color, now: float) -> Node3D:
	var out = new()
	out._start(path(floor_map, cell, facing), tint, now)
	print("opening: Wick comes from %d steps off" % (out._path.size() - 1))
	return out


func _start(way: Array, tint: Color, now: float) -> void:
	_path = way
	_born = now
	_leg_t0 = now
	_figure = Figure.make(SHEET, tint, 7)
	_figure.position = _path[0]
	_top = _figure.top()
	add_child(_figure)
	_heart = Figure.prop("props", "say_heart", tint, HEART_SIZE)
	_heart.visible = false
	add_child(_heart)
	if _path.size() > 1:
		_figure.anim.hop(now)


## Whether she has reached you and has the heart out.
func given() -> bool:
	return _gave_at >= 0.0


## Bring her up to now. `moved`: you have moved, so she is done here. Returns false once she is gone.
func tick(now: float, camera: Vector3, moved: bool) -> bool:
	if moved and _going_at < 0.0:
		_going_at = now
	if _going_at < 0.0:
		_walk(now)
	_face(_figure, camera)
	_figure.pose(now)
	var fade := 1.0 - clampf((now - _born) / FADE_IN_S, 0.0, 1.0)
	if _going_at >= 0.0:
		fade = maxf(fade, clampf((now - _going_at) / GOING_S, 0.0, 1.0))
	_figure.set_fade(fade)
	_show_heart(now, camera, fade)
	return _going_at < 0.0 or now - _going_at < GOING_S


func _walk(now: float) -> void:
	if _gave_at >= 0.0:
		if now - _gave_at >= GIVE_S:
			_going_at = now
		return
	if _leg >= _path.size() - 1:
		_gave_at = now
		_figure.anim.set_mood("happy", now)
		return
	var p := (now - _leg_t0) / GLIDE_S
	_figure.position = _path[_leg].lerp(_path[_leg + 1], clampf(p, 0.0, 1.0))
	if now - _leg_t0 >= HOP_S:
		_leg += 1
		_leg_t0 = now
		if _leg < _path.size() - 1:
			_figure.anim.hop(now)


func _show_heart(now: float, camera: Vector3, fade: float) -> void:
	_heart.visible = _gave_at >= 0.0
	if not _heart.visible:
		return
	var p := clampf((now - _gave_at) / 0.5, 0.0, 1.0)
	_heart.position = _figure.position + Vector3.UP * (_top * 0.9 + HEART_RISE * p + sin(now * 3.0) * 0.015)
	_face(_heart, camera)
	_heart.set_fade(maxf(fade, 1.0 - p))


static func _face(what: Node3D, camera: Vector3) -> void:
	var to_you := camera - what.position
	what.rotation.y = atan2(to_you.x, to_you.z)
