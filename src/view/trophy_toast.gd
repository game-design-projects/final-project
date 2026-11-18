## An achievement earned, said the moment it is: its badge, its name and line, and how many that makes, sliding in at the
## picture's top left, over everything on the picture (a choice's dimmed halls too). It stays a few seconds and leaves; more
## than MAX_UP at once wait their turn. It takes no clicks and holds nothing up. `card` is Achievements.card().
extends Control

const Badges = preload("res://src/view/badges.gd")
const Content = preload("res://src/rules/content.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")

const STAY_S := 4.5 # how long one stays, once in
const SLIDE_S := 0.22 # sliding in, and out
const GLOW_S := 0.9 # its badge is brighter at first
const MAX_UP := 2
const WIDTH := 344.0
const HEIGHT := 78.0
const MARGIN := 10.0
const GAP := 6.0
const BADGE := 50.0
const TEXT_PX := 16

var hint := "" # the key that shows them all, said under the count ("K")

var _up: Array = [] # {card, n, of, age}
var _waiting: Array = []
var _title: Font = Fonts.title()
var _body: Font = Fonts.body()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Say this one: `n` of `of` are earned now.
func add(card: Dictionary, n: int, of: int) -> void:
	var one := {"card": card, "n": n, "of": of, "age": 0.0}
	if _up.size() < MAX_UP:
		_up.append(one)
	else:
		_waiting.append(one)
	visible = true
	queue_redraw()
	print("trophy toast: %s (%d of %d), %d up, %d waiting" % [card.id, n, of, _up.size(), _waiting.size()])


## How many are on the picture, and how many wait.
func counts() -> Array:
	return [_up.size(), _waiting.size()]


func _process(dt: float) -> void:
	if _up.is_empty():
		return
	advance(dt)
	queue_redraw()


## Time passes: each one up grows older, one that has had its time leaves, and one that waited takes the place.
func advance(dt: float) -> void:
	for one in _up:
		one.age += dt
	_up = _up.filter(func(one): return one.age < SLIDE_S * 2.0 + STAY_S)
	while _up.size() < MAX_UP and not _waiting.is_empty():
		_up.append(_waiting.pop_front())
	visible = not _up.is_empty()


## Where the i-th one up is now (it slides in from the left edge and back out to it).
func toast_rect(i: int) -> Rect2:
	var one: Dictionary = _up[i]
	var w := minf(WIDTH, size.x - MARGIN * 2.0)
	var whole := SLIDE_S * 2.0 + STAY_S
	var shown := clampf(one.age / SLIDE_S, 0.0, 1.0) if one.age < whole - SLIDE_S else clampf((whole - one.age) / SLIDE_S, 0.0, 1.0)
	shown = 1.0 - (1.0 - shown) * (1.0 - shown)
	return Rect2(lerpf(-w - 4.0, MARGIN, shown), MARGIN + i * (HEIGHT + GAP), w, HEIGHT)


## Whether the card's line fits in the lines the toast has for it, at the toast's full width.
static func line_fits(text: String) -> bool:
	var room := WIDTH - BADGE - 34.0
	return Fonts.body().get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, room, TEXT_PX).y <= (TEXT_PX + 3.0) * 2.0 + 1.0


func _draw() -> void:
	for i in _up.size():
		var one: Dictionary = _up[i]
		var card: Dictionary = one.card
		var r := toast_rect(i)
		var colour := Color(str(card.color))
		var glow := clampf(1.0 - (one.age - SLIDE_S) / GLOW_S, 0.0, 1.0) if one.age > SLIDE_S else 1.0
		draw_rect(r, Color(0, 0, 0, 0.94))
		draw_rect(r.grow(-1.0), colour, false, 2.0)
		Badges.badge(self, str(card.icon), Rect2(r.position + Vector2(12.0, (HEIGHT - BADGE) / 2.0), Vector2(BADGE, BADGE)), colour, true, glow)
		var x := r.position.x + BADGE + 24.0
		var room := r.end.x - 10.0 - x
		draw_string(_title, Vector2(x, r.position.y + 17.0), str(Content.table("achievements").unlocked), HORIZONTAL_ALIGNMENT_LEFT, room - 44.0, 7, colour)
		draw_string(_title, Vector2(x, r.position.y + 17.0), "%d/%d" % [one.n, one.of], HORIZONTAL_ALIGNMENT_RIGHT, room, 7, Palette.DIM)
		draw_string(_title, Vector2(x, r.position.y + 35.0), str(card.label), HORIZONTAL_ALIGNMENT_LEFT, room, 11, Palette.INK)
		draw_multiline_string(_body, Vector2(x, r.position.y + 52.0), str(card.text), HORIZONTAL_ALIGNMENT_LEFT, room, TEXT_PX, 2, Palette.DIM)
		if hint != "" and i == _up.size() - 1:
			var keys := "%s  SEE THEM ALL" % hint
			var w := _title.get_string_size(keys, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 12.0
			var tab := Rect2(r.position.x, r.end.y, w, 15.0)
			draw_rect(tab, Color(0, 0, 0, 0.94))
			draw_string(_title, tab.position + Vector2(6.0, 11.0), keys, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Palette.DIM)

