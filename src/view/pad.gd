## The touch pad: four arrows on the left, INFO, BACK and OK on the right, drawn the way the dock is. It is shown on a touch
## screen (or with the flag `pad`) and says what was pressed as the game's own keys ("up", "confirm", "cancel"...), plus "info"
## for the scene's info key. An arrow that is held says it again every moment, so walking and dodging keep going the way a held
## key does. It draws and says; the scene decides what a key does.
extends Control

const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")

signal pressed(key: String) ## a button went down
signal repeated(key: String) ## an arrow is still held

const HEIGHT := 52.0
const BUTTON := Vector2(60, 46)
const WIDE := Vector2(84, 46)
const GAP := 8.0
const HOLD_DELAY_MS := 280 # an arrow held this long starts repeating...
const REPEAT_MS := 110 # ...at this pace
const ARROWS := ["left", "up", "down", "right"]
const LABELS := {"info": "INFO", "cancel": "BACK", "confirm": "OK"}

var _title: Font = Fonts.title()
var _held := {} # key -> [when it went down, when it last said so], in engine msec


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(release_all)


func has_button(key: String) -> bool:
	return _rects().has(key)


## A button goes down (and stays down until `release`): says its key at once.
func press(key: String) -> void:
	if not has_button(key):
		return
	var now := Time.get_ticks_msec()
	_held[key] = [now, now]
	pressed.emit(key)
	queue_redraw()


func release(key: String) -> void:
	_held.erase(key)
	queue_redraw()


func release_all() -> void:
	_held.clear()
	queue_redraw()


## Down and up at once.
func tap(key: String) -> void:
	press(key)
	release(key)


func _process(_dt: float) -> void:
	if not visible or _held.is_empty():
		return
	var now := Time.get_ticks_msec()
	for key in _held.keys():
		if key in ARROWS and now - _held[key][0] >= HOLD_DELAY_MS and now - _held[key][1] >= REPEAT_MS:
			_held[key][1] = now
			repeated.emit(key)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var rects := _rects()
			for key in rects:
				if rects[key].has_point(event.position):
					press(key)
					accept_event()
					return
		else:
			release_all()


## Where each button is: the arrows from the left edge, INFO, BACK and OK against the right edge.
func _rects() -> Dictionary:
	var out := {}
	var y := (size.y - BUTTON.y) * 0.5
	for i in ARROWS.size():
		out[ARROWS[i]] = Rect2(Vector2(i * (BUTTON.x + GAP), y), BUTTON)
	var x := size.x
	for key in ["confirm", "cancel", "info"]:
		x -= WIDE.x
		out[key] = Rect2(Vector2(x, y), WIDE)
		x -= GAP
	return out


func _draw() -> void:
	var rects := _rects()
	for key in rects:
		var r: Rect2 = rects[key]
		var down: bool = _held.has(key)
		draw_rect(r, Color.BLACK)
		draw_rect(r.grow(-1.0), Palette.YOU if down else Palette.FAINT.lightened(0.25), false, 2.0)
		if key in ARROWS:
			_arrow(r.get_center(), ["up", "right", "down", "left"].find(key), Palette.YOU if down else Palette.INK)
		else:
			draw_string(_title, r.position + Vector2(0, r.size.y * 0.5 + 4.0), LABELS[key], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Palette.YOU if down else Palette.INK)


func _arrow(c: Vector2, dir: int, color: Color) -> void:
	var d := Vector2([Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][dir])
	draw_colored_polygon([c + d * 9.0, c - d * 7.0 + d.orthogonal() * 9.0, c - d * 7.0 - d.orthogonal() * 9.0], color)
