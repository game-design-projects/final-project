## The drawn half of the battle screen, for the feature hand-drawn: the halls dimmed behind it, and the monster itself, as big as it is
## walking is small. It is a child of the overlay, drawn behind what the overlay draws, because drawings want smooth filtering and the
## overlay's text wants none. It shrinks up out of the way for a dodge. Everything it shows it reads off the overlay and the game: moods off
## the meters (rules/moods.gd), a blink of mood after a deed, a hit, a lunge as an attack comes, a face gone blank (rules/warmth.gd).
extends Control

const FigureAnim = preload("res://src/view/figure_anim.gd")
const Moods = preload("res://src/rules/moods.gd")
const Palette = preload("res://src/view/palette.gd")
const Sprites = preload("res://src/view/sprites.gd")
const Warmth = preload("res://src/rules/warmth.gd")

const FEET_Y := 224.0 # where it stands
const PX_PER_WORLD := 150.0 # how big, in picture pixels per world unit of its height: a slime is still smaller than a dragon
const SMALL_FEET_Y := 78.0 # where it stands over the dodge box
const SMALL_SCALE := 0.36
const SHRINK_PER_S := 5.0
const DIM := 0.8 # how much of the halls the dark hides behind a fight
const DIM_DODGE := 0.93
const SHAKE_PX := 5.0
const SAY_SIZE := 34.0 # how big a mark over its head is
const SAY_S := 0.14 # how fast it pops up
const TITLE_DIM := 0.25

var overlay # the Overlay it belongs to, set by it

var _anim: FigureAnim
var _foe = null
var _small := 0.0
var _hurt_seen := 0.0
var _dodging := false
var _say := ""
var _say_at := 0.0


func _init() -> void:
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Whether this monster is drawn here (the overlay draws the old line art for any that isn't).
static func can_draw(species: String) -> bool:
	return Sprites.has(species) and Sprites.has_action(species, "idle")


## What its face is showing now, for a test.
func face() -> String:
	return "" if _anim == null else _anim.mood_act()


func _process(dt: float) -> void:
	queue_redraw()
	if overlay == null or overlay.state == null or not overlay.in_fight() or not overlay.drawn_foe():
		_foe = null
		_anim = null
		_small = 0.0
		return
	var s = overlay.state
	var now: float = overlay.clock_ms / 1000.0
	if s.foe != _foe:
		_foe = s.foe
		_anim = FigureAnim.new(_foe.species, str(_foe.name).hash())
		_hurt_seen = overlay.hurt_until
		_dodging = false
		_small = 0.0
		_say = ""
		print("battle art: %s the %s" % [_foe.name, _foe.species])
	_small = move_toward(_small, 1.0 if s.dodge != null else 0.0, dt * SHRINK_PER_S)
	_anim.set_mood(_mood(s), now)
	if overlay.hurt_until != _hurt_seen:
		_hurt_seen = overlay.hurt_until
		if overlay.clock_ms < overlay.hurt_until:
			_anim.hurt(now)
	var dodging: bool = s.dodge != null
	if dodging and not _dodging:
		_anim.lunge(now)
	_dodging = dodging
	var say := _say_now()
	if say != _say:
		_say = say
		_say_at = now


func _mood(s) -> String:
	var m = s.foe
	if m.gone == "slain":
		return "hollow"
	if m.gone == "spared":
		return "happy"
	if s.viewing("warmth") and Moods.hollow(m, Warmth.of(s)):
		return "hollow"
	var tone: String = overlay.emote_tone()
	if tone == "good":
		return "happy"
	if tone == "bad":
		return "angry"
	return Moods.of(m)


## Which drawing floats over its head now: "" for none. Gladness and anger are in the frames already, with their own heart and alarm; what is
## left is puzzlement and the quiet of listening. (A question for you stays the overlay's: it is words.)
func _say_now() -> String:
	var b: Dictionary = overlay.bubble()
	if b.is_empty():
		return ""
	if b.has("tone"):
		return "" if b.tone in ["good", "bad"] else "say_what"
	return "say_quiet" if str(b.text).begins_with(".") else ""


func _draw() -> void:
	if overlay == null or overlay.state == null:
		return
	if overlay.title_card:
		_title()
		return
	if _anim == null or _foe == null or not overlay.in_fight():
		return
	draw_rect(overlay.whole_picture(), Color(0.0, 0.0, 0.0, lerpf(DIM, DIM_DODGE, _small)))
	_figure()


func _figure() -> void:
	var sheet: Dictionary = Sprites.sheet(_foe.species)
	var now: float = overlay.clock_ms / 1000.0
	var at: Dictionary = _anim.tick(now)
	var k: float = float(sheet.world_h) * PX_PER_WORLD / float(sheet.body_h) * lerpf(1.0, SMALL_SCALE, _small)
	var body_px: float = float(sheet.body_h) * k
	var feet := Vector2(overlay.W / 2.0, lerpf(FEET_Y, SMALL_FEET_Y, _small))
	var jolt: Vector2 = overlay.shake_offset()
	feet += jolt + Vector2(float(at.shake) * SHAKE_PX, -float(at.lift) * body_px)
	var cell := Vector2(sheet.cell[0], sheet.cell[1])
	var anchor := Sprites.feet(_foe.species)
	var tint: Color = Palette.monster(_foe)
	if overlay.clock_ms < overlay.hurt_until:
		tint = tint.lerp(Color.WHITE, 0.7)
	draw_set_transform(feet, -float(at.lean), Vector2(float(at.sx), float(at.sy)) * k)
	draw_texture_rect_region(Sprites.texture(_foe.species), Rect2(-anchor, cell), Sprites.frame_rect(_foe.species, at.act, at.frame), tint)
	draw_set_transform(Vector2.ZERO)
	_mark(feet, body_px, tint, now)


## The small drawing over its head: a question, or the quiet that means it is listening.
func _mark(feet: Vector2, body_px: float, tint: Color, now: float) -> void:
	if _say == "":
		return
	var pop := clampf((now - _say_at) / SAY_S, 0.0, 1.0)
	var size := SAY_SIZE * lerpf(1.0, 0.6, _small) * (0.6 + 0.4 * pop)
	var c := feet + Vector2(body_px * 0.62, -body_px * 1.02 + sin(now * 4.0) * 1.5)
	var rect := Sprites.drawing_rect("props", _say)
	var shape := Vector2(rect.size.x / rect.size.y, 1.0) * size
	draw_texture_rect_region(Sprites.texture("props"), Rect2(c - shape / 2.0, shape), rect, Color(tint, pop))


## The title card's picture, as the whole picture.
func _title() -> void:
	var whole: Rect2 = overlay.whole_picture()
	var tex: Texture2D = Sprites.texture("keyart")
	var cover := maxf(whole.size.x / tex.get_width(), whole.size.y / tex.get_height())
	var shape := tex.get_size() * cover
	draw_rect(whole, Color.BLACK)
	draw_texture_rect(tex, Rect2(whole.get_center() - shape / 2.0, shape), false, Color(1.0, 1.0, 1.0, 1.0 - TITLE_DIM))
