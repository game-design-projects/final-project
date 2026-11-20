## What the walk has stopped at, over the middle of the picture. In the stages Transitions.DECIDING names (a keepsake to
## take, who holds the gate, the way down, how the run ends) the choice is the whole moment, so it is not left in the dock
## under a picture of a wall: a small moving picture of the thing (view/vignette.gd), what is being asked, and each choice a
## card with what it does written on it, where the eye already is. A choice with nothing to say about itself (MAIN MENU) is a
## small button under the cards. A stage that is not deciding but has stopped at something (the camp) gets the picture alone.
## Reads the state and says what was pressed, like the dock.
extends Control

const Badges = preload("res://src/view/badges.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")
const Transitions = preload("res://src/game/transitions.gd")
const Vignette = preload("res://src/view/vignette.gd")

signal picked(index: int) ## a choice was clicked
signal hovered(index: int) ## the pointer is over this choice

const DIM := 0.68 # how far the picture goes dark behind a choice
const GAP := 10.0
const COLS := 3 # as the arrows move in a list stage (stages/list_stage.gd), so right is right and down is down
const CARD_W := 300.0
const CARD_H := 128.0
const CARD_H_MIN := 84.0
const PLAIN_H := 34.0
const NAME_PX := 14
const SUB_PX := 18
const ASK_PX := 20
const ART_H := 96.0 # the moving picture's height when there is room
const ART_H_BIG := 150.0 # and when there is room to spare: it takes most of what the cards leave
const ART_H_ALONE := 84.0
const ART_SHARE := 0.6 # what the question and the cards leave, of which the moving picture takes this much
const ART_MIN_H := 48.0 # under this the moving picture goes rather than be squashed to nothing
const BADGES_H := 38.0 # the row of what the run earned, on the card that ends it
const BADGE_PX := 32.0

## What this run has earned (Achievements.card() each), which the scene keeps up to date: shown on the card that ends the run.
var badges: Array = []

var state # State, set by the owner

var _title: Font = Fonts.title()
var _body: Font = Fonts.body()
var _hover := -1
var _art: Control # the moving picture, on a layer of its own: a drawing is smoothed when it is made smaller, the letters never are
var _art_box := Rect2() # where it goes, as the last draw laid it out


func _ready() -> void:
	mouse_exited.connect(func(): _set_hover(-1))
	_art = Control.new()
	_art.name = "Art"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.draw.connect(_draw_art)
	add_child(_art)


func _draw_art() -> void:
	if state == null or not _art_box.has_area():
		return
	var colours: Dictionary = Palette.for_run(state.palette_id)
	Vignette.draw(_art, state.vignette, _art_box, Time.get_ticks_msec() / 1000.0, colours.wall, colours.accent)


## Whether the choices are up (the commands are here and not in the dock). The dock asks this of the state too, so the one
## rule is here and not in each view: a stage taken out of Transitions.DECIDING has its commands in the dock again.
static func deciding(s) -> bool:
	return s != null and s.stage in Transitions.DECIDING and not s.menu.is_empty()


## The lines of the log that are said here instead: the last one (what is being asked), and with it the one before when
## that is someone's words (the route's name and what it came to, at a run's end).
static func asked(s) -> Array:
	if s == null or not s.stage in Transitions.DECIDING or s.lines.is_empty():
		return []
	var from: int = s.lines.size() - 1
	if from > 0 and s.lines[from - 1].kind == "say":
		from -= 1
	return s.lines.slice(from)


func _process(_dt: float) -> void:
	var up := deciding(state)
	var shown: bool = state != null and (up or state.vignette != "")
	visible = shown
	mouse_filter = Control.MOUSE_FILTER_STOP if shown and up else Control.MOUSE_FILTER_IGNORE
	if shown:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not deciding(state):
		return
	if event is InputEventMouseMotion:
		_set_hover(choice_at(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := choice_at(event.position)
		if i >= 0:
			picked.emit(i)
		accept_event() # a click beside the cards is not a click on the picture


func _set_hover(at: int) -> void:
	if at == _hover:
		return
	_hover = at
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if at >= 0 else Control.CURSOR_ARROW
	if at >= 0:
		hovered.emit(at)


func choice_at(at: Vector2) -> int:
	var rects := choice_rects()
	for i in rects.size():
		if rects[i].has_point(at) and not state.menu[i].get("disabled", false):
			return i
	return -1


## Where each choice of the menu is, in this control's pixels: one rect per item, in the menu's order.
func choice_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	out.assign(_layout().rects)
	return out


func _is_card(item: Dictionary) -> bool:
	return str(item.get("sub", "")) != ""


func _ask_height(lines: Array, width: float) -> float:
	var h := 0.0
	for l in lines:
		if l.kind == "say" and str(l.who) != "":
			h += 20.0
		h += _body.get_multiline_string_size(str(l.text), HORIZONTAL_ALIGNMENT_CENTER, width, ASK_PX).y + 2.0
	return h


## Everything's place: {art: Rect2 (no area when there is no room or nothing to show), ask: Rect2, badges: Rect2 (the row of
## what the run earned, where a run's card is), rects: [Rect2]}. The cards are in rows of COLS, the plain choices in one row
## under them, the whole block in the middle of the picture. When the picture is short the cards give up height first, then the
## moving picture does.
func _layout() -> Dictionary:
	var out := {"art": Rect2(), "ask": Rect2(), "badges": Rect2(), "rects": []}
	if not deciding(state):
		return out
	var items: Array = state.menu
	var cards: Array = []
	var plain: Array = []
	for i in items.size():
		if _is_card(items[i]):
			cards.append(i)
		else:
			plain.append(i)
	var width := minf(size.x - 32.0, COLS * CARD_W + (COLS - 1) * GAP)
	var cols := mini(COLS, maxi(1, cards.size()))
	var rows := ceili(float(cards.size()) / COLS)
	var card_w := minf(CARD_W, (width - GAP * (cols - 1)) / cols)
	var ask_h := _ask_height(asked(state), width)
	var plain_h := PLAIN_H if not plain.is_empty() else 0.0
	var room := size.y - 16.0
	var badge_h := BADGES_H if state.run_over and not badges.is_empty() else 0.0
	var fixed := ask_h + (GAP * 2.0 + badge_h if badge_h > 0.0 else 0.0) + (GAP if rows > 0 else 0.0) + (GAP + plain_h if plain_h > 0.0 else 0.0) + GAP * maxi(0, rows - 1)
	var card_h := CARD_H
	var art_h := 0.0
	if state.vignette in Vignette.KNOWN:
		art_h = clampf((room - fixed - GAP - rows * card_h) * ART_SHARE, ART_H, ART_H_BIG)
	if rows > 0 and fixed + art_h + GAP + rows * card_h > room:
		card_h = clampf((room - fixed - art_h - GAP) / rows, CARD_H_MIN, CARD_H)
	if fixed + art_h + GAP + rows * card_h > room:
		art_h = maxf(0.0, room - fixed - GAP - rows * card_h)
		if art_h < ART_MIN_H:
			art_h = 0.0
	var total := fixed + rows * card_h + (art_h + GAP if art_h > 0.0 else 0.0)
	var y := maxf(8.0, (size.y - total) / 2.0)
	if art_h > 0.0:
		out.art = Rect2((size.x - art_h * Vignette.RATIO) / 2.0, y, art_h * Vignette.RATIO, art_h)
		y += art_h + GAP
	out.ask = Rect2((size.x - width) / 2.0, y, width, ask_h)
	y += ask_h
	if badge_h > 0.0:
		out.badges = Rect2((size.x - width) / 2.0, y + GAP, width, badge_h)
		y += GAP * 2.0 + badge_h
	y += GAP if rows > 0 else 0.0
	var rects := []
	rects.resize(items.size())
	for n in cards.size():
		var row := n / COLS
		var in_row := mini(COLS, cards.size() - row * COLS)
		var row_w := in_row * card_w + (in_row - 1) * GAP
		rects[cards[n]] = Rect2((size.x - row_w) / 2.0 + (n % COLS) * (card_w + GAP), y + row * (card_h + GAP), card_w, card_h)
	y += rows * card_h + GAP * maxi(0, rows - 1)
	if not plain.is_empty():
		y += GAP # the gap the layout counted between these and what is above them, cards or question
		var widths: Array = plain.map(func(i): return maxf(150.0, _title.get_string_size(str(items[i].label), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 64.0))
		var row_w := GAP * (plain.size() - 1)
		for pw in widths:
			row_w += pw
		var x := (size.x - row_w) / 2.0
		for n in plain.size():
			rects[plain[n]] = Rect2(x, y, widths[n], PLAIN_H)
			x += widths[n] + GAP
	out.rects = rects
	return out


func _draw() -> void:
	_art_box = Rect2()
	_art.queue_redraw()
	if state == null:
		return
	var colours: Dictionary = Palette.for_run(state.palette_id)
	if not deciding(state):
		if state.vignette in Vignette.KNOWN: # stopped at something, with its commands in the dock: the picture of it, alone
			var box := Rect2((size.x - ART_H_ALONE * Vignette.RATIO) / 2.0, 10.0, ART_H_ALONE * Vignette.RATIO, ART_H_ALONE)
			draw_rect(box.grow(8.0), Color(0, 0, 0, 0.8))
			draw_rect(box.grow(8.0), Color(colours.wall, 0.5), false, 1.0)
			_art_box = box
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, DIM))
	var plan := _layout()
	_art_box = plan.art
	var y: float = plan.ask.position.y
	for l in asked(state):
		if l.kind == "say" and str(l.who) != "":
			draw_string(_title, Vector2(plan.ask.position.x, y + 14.0), str(l.who), HORIZONTAL_ALIGNMENT_CENTER, plan.ask.size.x, 11, Palette.MERCY)
			y += 20.0
		draw_multiline_string(_body, Vector2(plan.ask.position.x, y + ASK_PX - 3.0), str(l.text), HORIZONTAL_ALIGNMENT_CENTER, plan.ask.size.x, ASK_PX, -1, Palette.INK)
		y += _body.get_multiline_string_size(str(l.text), HORIZONTAL_ALIGNMENT_CENTER, plan.ask.size.x, ASK_PX).y + 2.0
	if plan.badges.has_area():
		_badges_row(plan.badges)
	for i in plan.rects.size():
		_choice(i, plan.rects[i])


## What the run earned, in a row: as many badges as fit beside the words.
func _badges_row(r: Rect2) -> void:
	var label := "EARNED THIS RUN"
	var label_w := _title.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var n := clampi(int((r.size.x - label_w - 14.0 + 6.0) / (BADGE_PX + 6.0)), 0, badges.size())
	var w := label_w + 14.0 + n * BADGE_PX + maxi(0, n - 1) * 6.0
	var x := r.position.x + (r.size.x - w) / 2.0
	draw_string(_title, Vector2(x, r.position.y + r.size.y / 2.0 + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.DIM)
	x += label_w + 14.0
	for i in n:
		var card: Dictionary = badges[i]
		Badges.badge(self, str(card.icon), Rect2(x, r.position.y + (r.size.y - BADGE_PX) / 2.0, BADGE_PX, BADGE_PX), Color(str(card.color)), true)
		x += BADGE_PX + 6.0


func _choice(i: int, r: Rect2) -> void:
	var item: Dictionary = state.menu[i]
	var picked_one: bool = i == state.selected
	var disabled: bool = item.get("disabled", false)
	var name_ink: Color = Palette.FAINT if disabled else (Palette.MERCY if item.get("gold", false) else Palette.INK)
	draw_rect(r, Color.BLACK)
	if picked_one:
		draw_rect(r.grow(-1.5), Palette.INK, false, 3.0)
	else:
		draw_rect(r.grow(-1.0), Palette.DIM if i == _hover else Color(Palette.DIM, 0.45), false, 2.0)
	var card := _is_card(item)
	var base := r.position + Vector2(14.0, 30.0 if card else r.size.y * 0.5 + 5.0)
	if picked_one:
		draw_colored_polygon([base + Vector2(0, -9), base + Vector2(8, -4.5), base + Vector2(0, 0)], Palette.YOU)
	var px := NAME_PX if card else 10
	var label := str(item.label)
	while px > 8 and _title.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > r.size.x - 62.0:
		px -= 1
	draw_string(_title, base + Vector2(14, 0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, px, Palette.DIM)
	draw_string(_title, base + Vector2(38, 0), label, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - base.x - 44.0, px, name_ink)
	if card:
		var lines := maxi(1, int((r.size.y - 50.0) / (SUB_PX + 3.0)))
		draw_multiline_string(_body, r.position + Vector2(16.0, 58.0), str(item.sub), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 30.0, SUB_PX, lines, Palette.INK if picked_one else Palette.DIM)
