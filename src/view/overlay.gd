## The flat 2D layer over the 3D picture, in the picture's own 448x288 coordinates (scaled to fit). While walking it
## holds the automap and the allies. In a fight it covers the dungeon with the flat battle screen: the monster as line art,
## its name and health top left, the kind of fight top right, then the dodge box with its hazards and your soul, or the
## strike bar. It only reads the game's state.
extends Control

const Art = preload("res://src/view/art.gd")
const Content = preload("res://src/rules/content.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")

const W := 448.0
const H := 288.0

# the dodge box, in picture pixels
const BOX_CELL := 29.0
const BOX_X := (W - Dodge.COLS * BOX_CELL) / 2.0
const BOX_Y := 79.0

const FIGHT_STAGES := ["intro", "menu", "act", "talk", "fightbar", "wait", "dodge", "dead"]
const HEALTH_OK := Color("#9ed36b")
const LANTERN := Color("#fff2a0")

var state # State, set by the owner
var clock_ms := 0.0
var wall_color := Palette.INK
var accent_color := Color("#ffb347")
## Until when the monster shakes (it was just hit), in clock ms.
var hurt_until := 0.0
## Until when the battle screen shakes, in clock ms.
var shake_until := 0.0
## True while the title card is up (before a run has started).
var title_card := false

var _title: Font = Fonts.title()
var _body: Font = Fonts.body()
var _popups: Array = [] # [{text, color, at, born}]


## True while the flat battle screen is showing (the 3D set is hidden behind it).
func in_fight() -> bool:
	return state != null and state.foe != null and state.stage in FIGHT_STAGES


## How far the battle screen is knocked off its place this frame (picture pixels); zero when it isn't shaking.
func shake_offset() -> Vector2:
	if clock_ms >= shake_until:
		return Vector2.ZERO
	return Vector2(randf() - 0.5, randf() - 0.5) * 6.0


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
	elif state.stage in ["explore", "end"]:
		_automap()
	_allies()
	for p in _popups:
		var age: float = (clock_ms - p.born) / 900.0
		var col: Color = p.color
		col.a = 1.0 - age
		_text(_body, p.text, p.at + Vector2(0.0, -26.0 * age), 22, col, HORIZONTAL_ALIGNMENT_CENTER)


func _text(font: Font, s: String, at: Vector2, px: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, at, s, align, width, px, color)


# ---------------------------------------------------------------- the title card

## Nested frames, the name, what the game is, and how to leave.
func _title_screen() -> void:
	var pulse := 0.5 + 0.5 * sin(clock_ms / 500.0)
	draw_rect(Rect2(3, 3, W - 6, H - 6), Palette.INK, false, 1.0)
	draw_rect(Rect2(101, 66, 246, 158), Color(Palette.INK, 0.7), false, 1.0)
	draw_rect(Rect2(52, 87, 344, 122), Palette.INK, false, 2.0)
	draw_rect(Rect2(53, 88, 342, 120), Color.BLACK)
	_text(_title, "DONJON", Vector2(0, 134), 32, Palette.INK, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text(_title, "GENRE HALLS", Vector2(0, 160), 8, Palette.YOU, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text(_title, "ESC: MENU", Vector2(0, 236), 8, Color(Palette.DIM, 0.6 + 0.4 * pulse), HORIZONTAL_ALIGNMENT_CENTER, W)


# ---------------------------------------------------------------- the automap

func _automap() -> void:
	var f = state.floor_map
	var cell := 4.0
	var span: float = f.size * cell
	var origin := Vector2(W - span - 8.0, 8.0)
	draw_rect(Rect2(origin - Vector2(3, 3), Vector2(span, span) + Vector2(6, 6)), Color.BLACK)
	draw_rect(Rect2(origin - Vector2(3, 3), Vector2(span, span) + Vector2(6, 6)), Palette.FAINT, false, 1.0)
	for c in state.seen:
		var col := Color(wall_color, 0.55 if state.visited.has(c) else 0.28)
		draw_rect(Rect2(origin + Vector2(c) * cell, Vector2(cell, cell)).grow(-0.5), col)
	if state.seen.has(f.stairs):
		draw_rect(Rect2(origin + Vector2(f.stairs) * cell, Vector2(cell, cell)).grow(-0.5), accent_color)
	for m in f.monsters:
		if not m.is_gone() and not m.boss and state.seen.has(m.cell):
			draw_rect(Rect2(origin + Vector2(m.cell) * cell + Vector2(2, 2), Vector2(cell - 4, cell - 4)), Palette.monster(m))
	var me := origin + (Vector2(state.cell) + Vector2(0.5, 0.5)) * cell
	var d := Vector2(f.DIRS[state.facing])
	draw_colored_polygon([me + d * cell * 0.55, me - d * cell * 0.3 + d.orthogonal() * cell * 0.35, me - d * cell * 0.3 - d.orthogonal() * cell * 0.35], Palette.INK)


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
	if state.dodge != null:
		_dodge_box(color)
		_flashes()
	if state.bar != null:
		_strike_bar()


func _name_and_health(m) -> void:
	_text(_title, m.name, Vector2(12, 21), 8, Palette.INK)
	var bar := Rect2(12, 26, 120, 6)
	draw_rect(bar, Palette.FAINT)
	var frac: float = m.hp_fraction()
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Palette.WARN if frac < 0.4 else HEALTH_OK)
	var genre: String = state.dodge.genre if state.dodge != null else _genre_of(m)
	var label: String = Content.table("encounter").genres[genre].name
	if m.boss:
		label = "TURN %d · %s" % [m.turn + 1, label]
	_text(_title, label, Vector2(0, 21), 8, Palette.DIM, HORIZONTAL_ALIGNMENT_RIGHT, W - 12.0)


## The kind of fight it is in this turn (a champion changes every turn).
func _genre_of(m) -> String:
	if not m.boss:
		return m.genre
	var genres: Array = Content.table("encounter").boss.genres
	return genres[m.turn % genres.size()]


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
	for i in range(Dodge.COLS + 1):
		draw_line(Vector2(BOX_X + i * BOX_CELL, BOX_Y), Vector2(BOX_X + i * BOX_CELL, BOX_Y + box.size.y), Palette.FAINT)
		draw_line(Vector2(BOX_X, BOX_Y + i * BOX_CELL), Vector2(BOX_X + box.size.x, BOX_Y + i * BOX_CELL), Palette.FAINT)
	for k in run.blocked:
		draw_rect(_cell_rect(k).grow(-3), Color(Palette.INK, 0.5))
	for h in run.hazards:
		var col: Color = LANTERN if h.kind == "light" else accent
		var lit: bool = clock_ms >= h.hit
		for k in h.cells:
			var r := _cell_rect(k).grow(-2)
			if lit:
				draw_rect(r, Color(col, 0.85))
			else:
				draw_rect(r, Color(col, 0.16 + 0.1 * sin(clock_ms * 0.02)))
				draw_rect(r, Color(col, 0.8), false, 1.0)
		if h.has("glyph"):
			var at := _cell_rect(h.at).get_center()
			draw_rect(_cell_rect(h.at).grow(-3), Color.BLACK)
			draw_rect(_cell_rect(h.at).grow(-3), Palette.INK, false, 1.0)
			_text(_title, h.glyph, at + Vector2(-4, 4), 10, Palette.INK)
		if h.has("lantern"):
			var l: Vector2 = h.lantern
			draw_circle(Vector2(BOX_X, BOX_Y) + l * BOX_CELL, 6.0, Color(LANTERN, 0.9))
	var pulse: float = maxf(0.0, 1.0 - (clock_ms - run.pulse) / 180.0) if run.pulse > 0.0 else 0.0
	draw_rect(box.grow(3), Palette.INK, false, 2.0 + pulse * 3.0)
	var left := clampf((run.end_t - clock_ms) / maxf(1.0, run.end_t - run.t0), 0.0, 1.0)
	draw_rect(Rect2(BOX_X, BOX_Y + box.size.y + 8.0, box.size.x * left, 2.0), Color(Palette.MERCY, 0.6))
	_soul(run)


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


# ---------------------------------------------------------------- the allies

func _allies() -> void:
	var y := H - 10.0
	for a in state.allies:
		var name: String = a.charm().name
		var width := _title.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		draw_rect(Rect2(9.0, y - 9.0, width + 18.0, 12.0), Color(0.0, 0.0, 0.0, 0.85)) # a wall line crossing the name would hide it
		draw_circle(Vector2(14.0, y - 3.0), 3.5, Color(Content.species(a.species).color))
		_text(_title, name, Vector2(22.0, y), 7, Palette.WARN if a.loyalty < 30.0 else Palette.DIM)
		y -= 12.0
