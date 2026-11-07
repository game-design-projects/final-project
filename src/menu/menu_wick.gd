## Wick beside the main menu, in the room the page leaves: she stands about, blinks, and now and then hops or is glad to see you. She keeps out
## of the way of a narrow window. She reads nothing of the game: there is no run yet.
extends Control

const Content = preload("res://src/rules/content.gd")
const FigureAnim = preload("res://src/view/figure_anim.gd")
const Sprites = preload("res://src/view/sprites.gd")

const SHEET := "witch"
const PAGE_W := 600.0 # the width of the menu's page (menu_panel.gd)
const LEAST_ROOM := 170.0 # less room than this beside the page and she stays away
const FEET_AT := 0.8 # how far down the window she stands: on the drawn floor
const BODY_SHARE := 0.27 # how tall she is, as a share of the window
const WAIT_S := [3.5, 8.0] # between one thing she does and the next
const GLAD_S := 2.2

var _anim: FigureAnim
var _t := 0.0
var _next := 2.5
var _glad_until := -1.0
var _tint := Color.WHITE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_anim = FigureAnim.new(SHEET, 3)
	_tint = Color(Content.species(SHEET).color)


func _process(dt: float) -> void:
	_t += dt
	if _glad_until >= 0.0 and _t >= _glad_until:
		_glad_until = -1.0
		_anim.set_mood("calm", _t)
	if _t >= _next:
		_next = _t + randf_range(WAIT_S[0], WAIT_S[1])
		if randf() < 0.3:
			_glad_until = _t + GLAD_S
			_anim.set_mood("happy", _t)
		else:
			_anim.hop(_t)
	queue_redraw()


## Where she stands: the middle of the room right of the page. x below 0 when there is no room.
func stands_at() -> Vector2:
	var room := (size.x - PAGE_W) / 2.0
	if room < LEAST_ROOM:
		return Vector2(-1.0, 0.0)
	return Vector2(size.x - room / 2.0, size.y * FEET_AT)


func _draw() -> void:
	var feet := stands_at()
	if feet.x < 0.0:
		return
	var sheet := Sprites.sheet(SHEET)
	var at: Dictionary = _anim.tick(_t)
	var k: float = minf(size.y * BODY_SHARE, (size.x - PAGE_W) * 0.34) / float(sheet.body_h)
	feet.y -= float(at.lift) * float(sheet.body_h) * k
	draw_set_transform(feet, -float(at.lean), Vector2(float(at.sx), float(at.sy)) * k)
	var cell := Vector2(sheet.cell[0], sheet.cell[1])
	draw_texture_rect_region(Sprites.texture(SHEET), Rect2(-Sprites.feet(SHEET), cell), Sprites.frame_rect(SHEET, at.act, at.frame), _tint)
