## The flat 2D layer over the 3D picture, in the picture's own 448x288 coordinates (scaled to fit). While walking it
## draws only the popups: the automap and the ally chips sit over the picture (automap.gd, tips.gd). In a fight it covers the dungeon with
## the flat battle screen: the monster as line art, its name and health top left, the kind of fight top right, then the dodge box with
## its hazards, your soul, your charms and the time left, or the strike bar; a white flash as the fight begins. It only reads the game's state.
extends Control

const Art = preload("res://src/view/art.gd")
const Content = preload("res://src/rules/content.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")

const W := 448.0
const H := 288.0

# the dodge box, in picture pixels
const BOX_CELL := 28.0
const BOX_X := (W - Dodge.COLS * BOX_CELL) / 2.0
const BOX_Y := 82.0

const FIGHT_STAGES := ["intro", "menu", "ask", "act", "talk", "fightbar", "wait", "dodge", "dead"]
const HEALTH_OK := Color("#9ed36b")
const LANTERN := Color("#fff3b0")
const GRID := Color("#1c1c20")
const PILLAR := Color("#3a3a3a")
const PILLAR_LINE := Color("#a7a39b")
const CHARM_USED := Color("#3a3a3a")
const INTRO_FLASH_MS := 700.0
const LANTERN_GLOW_R := 40.0 # how far the lantern's glow reaches, in picture pixels
const GOO_DROP := 70.0 # how far above its target a goo ball starts, in picture pixels
const EMOTE_MS := 1100.0
const BUBBLE_STAGES := ["intro", "menu", "act", "talk"]
const BANNER_FADE_MS := 220.0
const BANNER := Rect2(64, 40, 320, 46)
const MERCY_AT := 0.5 # how likely mercy must be before the monster's name says so
# the receding corridor behind the title: how big each frame is against the picture
const TITLE_FRAMES := [1.0, 0.556, 0.385, 0.294, 0.238]
const TITLE_BLINK_MS := 600.0

var state # State, set by the owner
var clock_ms := 0.0
## Until when the monster shakes (it was just hit), in clock ms.
var hurt_until := 0.0
## Until when the battle screen shakes, in clock ms.
var shake_until := 0.0
## True while the title card is up (before a run has started).
var title_card := false
## When the fight began in clock ms, and how strong its white flash starts.
var intro_at := -1e9
var intro_strength := 0.5

var _title: Font = Fonts.title()
var _body: Font = Fonts.body()
var _popups: Array = [] # [{text, color, at, born}]
var _emote := {} # {tone, born}: the last mood shown over the monster
var _lantern_glow: GradientTexture2D


## True while the flat battle screen is showing (the 3D set is hidden behind it).
func in_fight() -> bool:
	return state != null and state.foe != null and state.stage in FIGHT_STAGES


## How strong the white flash of a fight beginning is now (0 once it has faded).
func intro_flash() -> float:
	if state == null or state.stage != "intro":
		return 0.0
	return intro_strength * clampf(1.0 - (clock_ms - intro_at) / INTRO_FLASH_MS, 0.0, 1.0)


## Whether the monster would take mercy, as the mind last answered: its name says so, in gold.
func can_spare() -> bool:
	for row in state.mind_rows:
		if row.id == "mercy":
			return not state.foe.is_gone() and float(row.answer) >= MERCY_AT
	return false


## The bar of the dodge's time left, whole (it is inside the picture, under the box).
func time_bar() -> Rect2:
	return Rect2(BOX_X - 3.0, BOX_Y + Dodge.ROWS * BOX_CELL + 5.0, Dodge.COLS * BOX_CELL + 6.0, 3.0)


## How strongly a hazard's warning fills its squares: it ramps up until it lands.
func warning_fill(h: Dictionary) -> float:
	return 0.12 + 0.28 * clampf((clock_ms - h.warn) / (h.hit - h.warn), 0.0, 1.0)


## Where a goo ball is now, falling onto the square it is aimed at.
func goo_ball(h: Dictionary) -> Vector2:
	var to := _cell_rect(h.at).get_center()
	return to - Vector2(0.0, (1.0 - clampf((clock_ms - h.warn) / (h.hit - h.warn), 0.0, 1.0)) * GOO_DROP)


## Where the lantern is now, in picture pixels: it orbits all through a shadow dodge.
func lantern_spot() -> Vector2:
	var run = state.dodge
	return Vector2(BOX_X, BOX_Y) + Dodge.lantern_at(clock_ms - run.t0, run.intensity) * BOX_CELL


## The charms beside the box, [{name, color, y}]; the slime's greys out once its shield is used.
func charm_rows() -> Array:
	var out := []
	for i in state.allies.size():
		var a = state.allies[i]
		var used: bool = a.species == "slime" and not state.dodge.shield
		out.append({"name": a.charm().name, "color": CHARM_USED if used else Color(Content.species(a.species).color), "y": BOX_Y + 22.0 + i * 12.0})
	return out


## The mercy odds as the mind last answered (0..1), for the gauge; below 0 when there is no gauge to draw.
func mercy_gauge() -> float:
	if not state.viewing("mercy-link") or state.foe == null or state.foe.is_gone():
		return -1.0
	for row in state.mind_rows:
		if row.id == "mercy":
			return float(row.answer)
	return -1.0


## The banner's strength now (0 when there is none): it fades in, holds and fades out.
func banner_strength() -> float:
	if state.banner == null:
		return 0.0
	var age: float = clock_ms - state.banner.t0
	if age < 0.0 or age >= state.banner.ms:
		return 0.0
	return minf(1.0, minf(age, state.banner.ms - age) / BANNER_FADE_MS)


## How far the battle screen is knocked off its place this frame (picture pixels); zero when it isn't shaking.
func shake_offset() -> Vector2:
	if clock_ms >= shake_until:
		return Vector2.ZERO
	return Vector2(randf() - 0.5, randf() - 0.5) * 6.0


## A bubble over the monster's head for a moment: how a deed landed ("good", "bad" or anything else).
func emote(tone: String) -> void:
	_emote = {"tone": tone, "born": clock_ms}


## What the bubble over the monster says now: a mood for a moment after a deed, or the question when it would likely join;
## {} when nothing. {tone} or {text}.
func bubble() -> Dictionary:
	if not state.viewing("mood-cues") or state.foe == null or state.foe.is_gone():
		return {}
	if not _emote.is_empty() and clock_ms - _emote.born < EMOTE_MS:
		return {"tone": _emote.tone}
	if can_spare() and state.stage in BUBBLE_STAGES:
		return {"text": "WANNA JOIN?"}
	return {}


## A number or word that floats up from `at` (picture pixels) and fades.
func popup(text: String, color: Color, at: Vector2) -> void:
	_popups.append({"text": text, "color": color, "at": at, "born": clock_ms})


func _process(_dt: float) -> void:
	_popups = _popups.filter(func(p): return clock_ms - p.born < 900.0)
	queue_redraw()


func _draw() -> void:
	if state == null:
		return
	var k := minf(size.x / W, size.y / H)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	if title_card:
		_title_screen()
		return
	if state.floor_map == null:
		return
	if in_fight():
		if clock_ms < shake_until:
			draw_set_transform(shake_offset() * k, 0.0, Vector2(k, k))
		_battle()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	for p in _popups:
		var age: float = (clock_ms - p.born) / 900.0
		var col: Color = p.color
		col.a = 1.0 - age
		_text(_body, p.text, p.at + Vector2(0.0, -26.0 * age), 22, col, HORIZONTAL_ALIGNMENT_CENTER)
	_banner()


func _banner() -> void:
	var strength := banner_strength()
	if strength <= 0.0:
		return
	draw_rect(BANNER, Color(0.0, 0.0, 0.0, 0.88 * strength))
	draw_rect(BANNER, Color(Palette.MERCY, strength), false, 1.0)
	_text(_title, state.banner.title, BANNER.position + Vector2(0, 17), 9, Color(Palette.MERCY, strength), HORIZONTAL_ALIGNMENT_CENTER, BANNER.size.x)
	_text(_body, state.banner.text, BANNER.position + Vector2(0, 35), 14, Color(Palette.INK, strength), HORIZONTAL_ALIGNMENT_CENTER, BANNER.size.x)


func _text(font: Font, s: String, at: Vector2, px: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, at, s, align, width, px, color)


# ---------------------------------------------------------------- the title card

## A receding corridor, the name in its box, what the game is, a blinking prompt, and how to leave.
func _title_screen() -> void:
	draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	for f in TITLE_FRAMES:
		var size_at := (Vector2(W, H) - Vector2(8, 8)) * float(f)
		draw_rect(Rect2((Vector2(W, H) - size_at) / 2.0, size_at).abs(), Palette.INK, false, 2.0)
	var box := Rect2(W * 0.12, H * 0.3, W * 0.76, H * 0.42)
	draw_rect(box, Color.BLACK)
	draw_rect(box, Palette.INK, false, 2.0)
	_text(_title, "DONJON", Vector2(0, H * 0.45), 28, Palette.INK, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text(_title, "GENRE HALLS", Vector2(0, H * 0.55), 8, Palette.YOU, HORIZONTAL_ALIGNMENT_CENTER, W)
	if title_prompt_on():
		_text(_title, "PRESS ANY KEY", Vector2(0, H * 0.65), 9, Palette.INK, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text(_title, "ESC: MENU", Vector2(0, H * 0.82), 8, Palette.DIM, HORIZONTAL_ALIGNMENT_CENTER, W)


## Whether the blinking prompt shows this moment.
func title_prompt_on() -> bool:
	return floori(clock_ms / TITLE_BLINK_MS) % 2 == 0


# ---------------------------------------------------------------- the battle screen

func _battle() -> void:
	var m = state.foe
	var color := Palette.monster(m)
	draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	var small: bool = state.dodge != null
	var hurt := 1.0 if clock_ms < hurt_until else 0.0
	if small:
		Art.draw(self, m.species, clock_ms, color, W / 2.0, 76.0, 0.27, hurt)
	else:
		Art.draw(self, m.species, clock_ms, color, W / 2.0, 270.0, 0.85, hurt)
	_name_and_health(m)
	_bubble(Vector2(W / 2.0 + 36.0, 28.0) if small else Vector2(W / 2.0 + 74.0, 72.0))
	if state.dodge != null:
		_dodge_box(color)
		_flashes()
	if state.bar != null:
		_strike_bar()
	var flash := intro_flash()
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, flash))


func _name_and_health(m) -> void:
	var spare := can_spare()
	_text(_title, m.name + ("  (MERCY 50%+)" if spare else ""), Vector2(12, 21), 8, Palette.MERCY if spare else Palette.INK)
	var bar := Rect2(12, 26, 120, 6)
	draw_rect(bar, Palette.FAINT)
	var frac: float = m.hp_fraction()
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Palette.WARN if frac < 0.4 else HEALTH_OK)
	var mercy := mercy_gauge()
	if mercy >= 0.0:
		var gauge := Rect2(12, 34, 120, 3)
		draw_rect(gauge, Palette.FAINT)
		draw_rect(Rect2(gauge.position, Vector2(gauge.size.x * mercy, gauge.size.y)), Palette.MERCY)
		draw_line(gauge.position + Vector2(gauge.size.x * MERCY_AT, -1.0), gauge.position + Vector2(gauge.size.x * MERCY_AT, gauge.size.y + 1.0), Palette.INK)
		_text(_title, "MERCY %d%%" % roundi(mercy * 100.0), Vector2(136, 38), 6, Palette.MERCY)
	var genre: String = state.dodge.genre if state.dodge != null else state.genre_of(m)
	var label: String = Content.table("encounter").genres[genre].name
	if m.boss:
		label = "TURN %d · %s" % [m.turn + 1, label]
	_text(_title, label, Vector2(0, 21), 8, Palette.DIM, HORIZONTAL_ALIGNMENT_RIGHT, W - 12.0)


## The speech bubble, its tail at the monster's head, down to the left of `at`.
func _bubble(at: Vector2) -> void:
	var b := bubble()
	if b.is_empty():
		return
	var w: float = 70.0 if b.has("text") else 26.0
	var rect := Rect2(at - Vector2(0.0, 22.0), Vector2(w, 22.0))
	var ink: Color = Palette.MERCY if b.has("text") else _tone_color(b.tone)
	draw_rect(rect, Color.BLACK)
	draw_rect(rect, ink, false, 1.0)
	draw_colored_polygon(PackedVector2Array([at + Vector2(3, 0), at + Vector2(11, 0), at + Vector2(-3, 8)]), ink)
	if b.has("text"):
		_text(_title, b.text, rect.position + Vector2(0, 14), 6, ink, HORIZONTAL_ALIGNMENT_CENTER, w)
	else:
		_mood_glyph(b.tone, rect.get_center(), ink)


static func _tone_color(tone: String) -> Color:
	return Palette.MERCY if tone == "good" else (Palette.WARN if tone == "bad" else Palette.INK)


## A heart, an angry mark or a question mark.
func _mood_glyph(tone: String, c: Vector2, ink: Color) -> void:
	match tone:
		"good":
			draw_circle(c + Vector2(-3, -2), 3.2, ink)
			draw_circle(c + Vector2(3, -2), 3.2, ink)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -1), c + Vector2(6, -1), c + Vector2(0, 7)]), ink)
		"bad":
			for pair in [[Vector2(-5, -5), Vector2(-1, -1)], [Vector2(5, -5), Vector2(1, -1)], [Vector2(-5, 5), Vector2(-1, 1)], [Vector2(5, 5), Vector2(1, 1)]]:
				draw_line(c + pair[0], c + pair[1], ink, 2.0)
		_:
			_text(_title, "?", c + Vector2(-13, 4), 9, ink, HORIZONTAL_ALIGNMENT_CENTER, 26.0)


func _flashes() -> void:
	var run = state.dodge
	if clock_ms - run.block_flash < 160.0:
		draw_rect(Rect2(0, 0, W, H), Color(Palette.YOU, 0.22))
		_text(_title, "BOUNCY! THE SLIME TAKES THE HIT", Vector2(0, BOX_Y - 8.0), 8, Palette.YOU, HORIZONTAL_ALIGNMENT_CENTER, W)
	if clock_ms - run.hit_flash < 120.0:
		draw_rect(Rect2(0, 0, W, H), Color(Palette.WARN, 0.25))


# ---------------------------------------------------------------- the dodge box

func _dodge_box(accent: Color) -> void:
	var run = state.dodge
	var box := Rect2(BOX_X, BOX_Y, Dodge.COLS * BOX_CELL, Dodge.ROWS * BOX_CELL)
	for k in Dodge.COLS * Dodge.ROWS:
		if run.blocked.has(k):
			draw_rect(_cell_rect(k).grow(-2), PILLAR)
			draw_rect(_cell_rect(k).grow(-2.5), PILLAR_LINE, false, 1.0)
		else:
			draw_rect(_cell_rect(k), GRID, false, 1.0)
	for h in run.hazards:
		_hazard(h, LANTERN if h.kind == "light" else accent)
	if run.genre == "shadow":
		_lantern()
	var pulse: float = maxf(0.0, 1.0 - (clock_ms - run.pulse) / 180.0) if run.pulse > 0.0 else 0.0
	draw_rect(box.grow(3), Palette.INK, false, 2.0 + pulse * 3.0)
	_soul(run)
	_charms()
	var bar := time_bar()
	var left := clampf((run.end_t - clock_ms) / maxf(1.0, run.end_t - run.t0), 0.0, 1.0)
	draw_rect(bar, Palette.FAINT)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * left, bar.size.y)), Palette.DIM)


## A hazard: its squares fill slowly with a flickering outline until it lands, then light up. A chess piece shows on its
## square; goo falls toward where it will land.
func _hazard(h: Dictionary, col: Color) -> void:
	var live: bool = clock_ms >= h.hit
	if h.has("shows") and not live and h.hit - clock_ms > h.shows:
		return # a wall flying in shows only its next column, so it reads as moving
	if h.kind == "star":
		_star(h)
		return
	if h.has("glyph") and icons() and not live:
		_rays(h, col)
	for k in h.cells:
		var cell := _cell_rect(k)
		if live:
			draw_rect(cell.grow(-1), Color(col, 0.85))
		else:
			draw_rect(cell.grow(-1), Color(col, warning_fill(h)))
			draw_rect(cell.grow(-3.5), Color(col, 0.5 + 0.5 * absf(sin(clock_ms / 90.0))), false, 1.0)
	if h.has("glyph"):
		var at := _cell_rect(h.at).get_center()
		draw_rect(Rect2(at - Vector2(11, 11), Vector2(22, 22)), Color.BLACK)
		if icons():
			_piece(h.glyph, at, Color.WHITE)
		else:
			_text(_title, h.glyph, at + Vector2(-6, 6), 12, Color.WHITE)
	if h.kind == "goo" and not live:
		draw_circle(goo_ball(h), 5.0, col)


## Whether chess attacks show a piece's shape (the feature piece-icons).
func icons() -> bool:
	return state != null and state.viewing("piece-icons")


## A chess piece as a shape, so it can't be taken for a key to press: a tower, a pointed hat, a horse's head.
func _piece(glyph: String, at: Vector2, col: Color) -> void:
	for shape in piece_shape(glyph):
		var pts := PackedVector2Array()
		for p in shape:
			pts.append(at + p)
		draw_colored_polygon(pts, col)


## The polygons of a piece around its middle, in picture pixels (a piece fits the 22 x 22 square it stands on).
static func piece_shape(glyph: String) -> Array:
	match glyph:
		"R":
			return [
				[Vector2(-8, 9), Vector2(8, 9), Vector2(8, 6), Vector2(-8, 6)], # base
				[Vector2(-5, 6), Vector2(5, 6), Vector2(5, -4), Vector2(-5, -4)], # tower
				[Vector2(-7, -4), Vector2(-7, -9), Vector2(-4, -9), Vector2(-4, -6), Vector2(-1, -6), Vector2(-1, -9), Vector2(1, -9), Vector2(1, -6), Vector2(4, -6), Vector2(4, -9), Vector2(7, -9), Vector2(7, -4)], # teeth
			]
		"B":
			return [
				[Vector2(-8, 9), Vector2(8, 9), Vector2(8, 6), Vector2(-8, 6)],
				[Vector2(-3, 6), Vector2(3, 6), Vector2(5, -2), Vector2(0, -9), Vector2(-5, -2)],
			]
		_:
			return [
				[Vector2(-8, 9), Vector2(8, 9), Vector2(8, 6), Vector2(-8, 6)],
				[Vector2(-5, 6), Vector2(6, 6), Vector2(5, -5), Vector2(0, -9), Vector2(-2, -6), Vector2(-8, -1), Vector2(-7, 2), Vector2(-2, 0)],
			]


## Thin lines from the piece to each square it will hit, while they are still only a warning.
func _rays(h: Dictionary, col: Color) -> void:
	var from := _cell_rect(h.at).get_center()
	var line := Color(col, 0.55)
	for k in h.cells:
		if k != h.at:
			draw_line(from, _cell_rect(k).get_center(), line, 1.0)


## A star falling to where it can be caught; it shines while it is there, and goes once caught.
func _star(h: Dictionary) -> void:
	if h.get("taken", false):
		return
	var live: bool = clock_ms >= h.hit
	var to := _cell_rect(h.at).get_center()
	var at := to if live else to - Vector2(0.0, (1.0 - clampf((clock_ms - h.warn) / (h.hit - h.warn), 0.0, 1.0)) * GOO_DROP)
	if live:
		draw_rect(_cell_rect(h.at).grow(-1), Color(Palette.MERCY, 0.45))
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0 - PI / 2.0
		pts.append(at + Vector2(cos(a), sin(a)) * (8.0 if i % 2 == 0 else 3.5))
	draw_colored_polygon(pts, Palette.MERCY)


## The lantern, all through a shadow dodge: a soft glow and the small flame in it.
func _lantern() -> void:
	if _lantern_glow == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(LANTERN, 0.9))
		gradient.set_color(1, Color(LANTERN, 0.0))
		_lantern_glow = GradientTexture2D.new()
		_lantern_glow.gradient = gradient
		_lantern_glow.fill = GradientTexture2D.FILL_RADIAL
		_lantern_glow.fill_from = Vector2(0.5, 0.5)
		_lantern_glow.fill_to = Vector2(1.0, 0.5)
		_lantern_glow.width = 64
		_lantern_glow.height = 64
	var at := lantern_spot()
	draw_texture_rect(_lantern_glow, Rect2(at - Vector2.ONE * LANTERN_GLOW_R, Vector2.ONE * LANTERN_GLOW_R * 2.0), false)
	draw_rect(Rect2(at - Vector2(3, 5), Vector2(6, 10)), LANTERN)


## Your charms beside the box.
func _charms() -> void:
	var rows := charm_rows()
	if rows.is_empty():
		return
	_text(_title, "CHARMS", Vector2(12, BOX_Y + 8.0), 7, Palette.DIM)
	for row in rows:
		_text(_title, row.name, Vector2(12, row.y), 7, row.color)
	if state.viewing("party-aid"):
		_text(_title, "+%d STRIKE" % rows.size(), Vector2(12, BOX_Y + 22.0 + rows.size() * 12.0 + 4.0), 6, Palette.DIM)
		if state.dodge.guard > 0:
			_text(_title, "-%d HURT" % state.dodge.guard, Vector2(12, BOX_Y + 22.0 + rows.size() * 12.0 + 14.0), 6, Palette.DIM)


func _cell_rect(k: int) -> Rect2:
	return Rect2(BOX_X + (k % Dodge.COLS) * BOX_CELL, BOX_Y + floori(float(k) / Dodge.COLS) * BOX_CELL, BOX_CELL, BOX_CELL)


func _soul(run) -> void:
	var at := Vector2(BOX_X + (run.soul.x + 0.5) * BOX_CELL, BOX_Y + (run.soul.y + 0.5) * BOX_CELL)
	var alpha := 1.0 if clock_ms > run.iframes or int(clock_ms / 70.0) % 2 == 0 else 0.25
	var col := Color(Palette.YOU, alpha)
	var r := 8.0
	draw_colored_polygon([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)], col)
	if run.shield:
		draw_arc(at, r + 4.0, 0.0, TAU, 20, Color(Palette.MERCY, 0.9), 1.5)


# ---------------------------------------------------------------- the strike bar

func _strike_bar() -> void:
	var bar = state.bar
	var rect := Rect2(62.0, 209.0, 324.0, 30.0)
	draw_rect(rect, Color(0, 0, 0, 0.7))
	draw_rect(Rect2(rect.position.x + rect.size.x * 0.46, rect.position.y, rect.size.x * 0.08, rect.size.y), Color(Palette.MERCY, 0.35))
	draw_line(Vector2(rect.get_center().x, rect.position.y), Vector2(rect.get_center().x, rect.end.y), Palette.MERCY, 2.0)
	var p := clampf((clock_ms - bar.t0) / bar.dur, 0.0, 1.0)
	var x := rect.position.x + rect.size.x * p
	draw_line(Vector2(x, rect.position.y - 3), Vector2(x, rect.end.y + 3), Palette.INK, 3.0)
	draw_rect(rect, Palette.INK, false, 2.0)
