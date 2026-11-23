## The flat 2D layer over the 3D picture, in the picture's own 448x288 coordinates (scaled to fit). While walking it
## draws only the popups: the automap and the ally chips sit over the picture (automap.gd, tips.gd). In a fight it covers the dungeon with
## the flat battle screen: the monster as line art, its name and health top left, the kind of fight top right, then the dodge box with
## its hazards, your soul, your charms and the time left, or the strike bar; a white flash as the fight begins. It only reads the game's state.
extends Control

const Art = preload("res://src/view/art.gd")
const BattleArt = preload("res://src/view/battle_art.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Dodge = preload("res://src/rules/dodge.gd")
const Keepsakes = preload("res://src/rules/keepsakes.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Flags = preload("res://src/utils/flags.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")
const Sprites = preload("res://src/view/sprites.gd")
const Transitions = preload("res://src/game/transitions.gd")
const Vignette = preload("res://src/view/vignette.gd")

const W := 448.0
const H := 288.0

# the dodge box, in picture pixels
const BOX_CELL := 28.0
const BOX_X := (W - Dodge.COLS * BOX_CELL) / 2.0
const BOX_Y := 82.0

const HEALTH_OK := Color("#9ed36b")
const LANTERN := Color("#fff3b0")
const GRID := Color("#1c1c20")
const PILLAR := Color("#3a3a3a")
const PILLAR_LINE := Color("#a7a39b")
const CHARM_USED := Color("#3a3a3a")
const INTRO_FLASH_MS := 700.0
const LANTERN_GLOW_R := 40.0 # how far the lantern's glow reaches, in picture pixels
const GOO_DROP := 70.0 # how far above its target a goo ball starts, in picture pixels
const STRIKE_BAR_H := 30.0
const HEAD_BAR := Rect2(W / 2.0 - 80.0, 21.0, 160.0, 7.0)
## The foe's bar while it is small over the dodge box: the same line and height as the one over its head, so the card ends
## above CARD_BOTTOM whichever size it is drawn at.
const SMALL_BAR := Rect2(12.0, HEAD_BAR.position.y, 120.0, HEAD_BAR.size.y)
## Where a fight's banner starts while a strike bar or the dodge box is up: every piece of the foe's card ends above this line,
## but for the feeling word when the card is drawn small -- it stands under the card, in the left margin the banner's box leaves
## free (BANNER_LEFT), so the news of the moment is read beside the card and never over it (the tip that says ACT first once
## covered the odds it was teaching, #164 read back).
const CARD_BOTTOM := HEAD_BAR.position.y + HEAD_BAR.size.y + 7.0
## The line the feeling word takes when the card is drawn small: under the card's bottom, in the left margin, clear of a banner.
const MOOD_IN_MARGIN := CARD_BOTTOM + 15.0
const GHOST_PER_S := 0.35 # how fast the trail behind the damage catches up (share of the bar per second)
const COMET_MS := 320.0
const SOUL_GLIDE := 28.0 # how fast your soul catches up with its square: the share left after a second is e to minus this
const LEAVE_FADE_MS := 280.0 # how long the battle screen takes to fade back to the halls
const SPEECH := Rect2(96.0, 228.0, 256.0, 54.0)
const SPEECH_SIZES := [14, 13, 12, 11, 10]
const SPEECH_SIZES_LARGE := [18, 17, 16, 15, 14, 13, 12, 11, 10]
static var large_text := false # the TEXT SIZE setting (the scene keeps this up to date)
const SPEECH_STAGES := ["intro", "menu", "ask", "act", "items", "skills", "talk", "fightbar", "wait"]
const FLY_MS := 550.0
const HEARD_MS := 950.0 # the listening dots stay this long after the words were sent, however fast the answer
const EMOTE_MS := 1100.0
const BANNER_FADE_MS := 220.0
const BANNER_W := 264.0
const BANNER_H := 44.0
## Where the banner's box starts: the picture's left margin is wider than the banner, and the card's feeling word stands there.
const BANNER_LEFT := (W - BANNER_W) / 2.0
const BANNER_PX := 13
const MERCY_AT := 0.5 # how likely mercy must be before the monster's name says so
const MOOD_WORDS := {"angry": ["ANGRY", Palette.WARN], "afraid": ["AFRAID", Palette.YOU], "friendly": ["FRIENDLY", Palette.MERCY], "wary": ["WARY", Palette.DIM]}
const NERVE_PIP := 11.0 # from one nerve pip to the next, in picture pixels
const NERVE_BESIDE_BOX := Vector2(BOX_X + Dodge.COLS * BOX_CELL + 14.0, BOX_Y + 8.0) # the nerve's label, right of the dodge box
const KEEPSAKES_BESIDE_BOX := Vector2(BOX_X + Dodge.COLS * BOX_CELL + 14.0, BOX_Y + 70.0) # the keepsakes' label, under the nerve and what it is worth
const NERVE_SPARK_MS := 320.0 # how long a close call rings round your soul
const NERVE_PULSE_MS := 420.0 # how long a pip just earned stays swollen
# the receding corridor behind the title: how big each frame is against the picture
const TITLE_BLINK_MS := 600.0

var state # State, set by the owner
var clock_ms := 0.0
## Until when the monster shakes (it was just hit), in clock ms.
var hurt_until := 0.0
## Until when the battle screen shakes, in clock ms.
var shake_until := 0.0
## True while the title card is up (before a run has started).
var title_card := false
## Whether the banner is held back: the full map (automap.gd) is up over the picture, and its own line sits where the banner goes.
var quiet := false
## When the fight began in clock ms, and how strong its white flash starts.
var intro_at := -1e9
var intro_strength := 0.5

var _title: Font = Fonts.title()
var _body: Font = Fonts.body()
var _art: BattleArt # what is drawn behind this layer: the monster, the title picture
## What the walk has stopped at, which the scene says each frame (view/choice_popup.gd lays it out over the picture, and this is
## its place in the picture's own pixels): {id, box, wall, accent, picked, backed, dim}, or {} for nothing. It is drawn here and
## not over the picture, so the glow, the scanlines and the picture's pixels are the drawing's own.
var event_art := {}
var _event_layer: Control # where it is drawn: over everything else in this layer, and smoothed as it is made smaller
var _popups: Array = [] # [{text, color, at, born}]
var extra_x := 0.0 # how much wider the picture is than this layer, on each side
var _words := "" # what you last typed, on its way to the monster
var _words_at := -1e9
var _emote := {} # {tone, born}: the last mood shown over the monster
var _ghost := 1.0 # where the trail behind the foe's health is
var _ghost_foe = null # whose
var _comets: Array = [] # [{from, born}]: what just hit you, on its way to your health bar
var _lantern_glow: GradientTexture2D
var _soul_shown = null # where your soul is drawn now, null to start at its square
var _was_fighting := false
var _left_fight_at := -1e9
var _nerve_seen := 0 # the nerve as last drawn, to see it move
var _nerve_moved_at := -1e9


func _ready() -> void:
	_art = BattleArt.new()
	_art.overlay = self
	add_child(_art)
	_event_layer = Control.new()
	_event_layer.name = "EventArt"
	_event_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_event_layer.draw.connect(_draw_event_art)
	add_child(_event_layer)


## Whether the monster in this fight is the drawing (battle_art.gd), with the halls dimmed behind it, rather than line art on black.
func drawn_foe() -> bool:
	return state != null and state.foe != null and BattleArt.can_draw(Sprites.look_of(state.foe))


## How a deed landed, for as long as that shows: "" otherwise.
func emote_tone() -> String:
	if _emote.is_empty() or clock_ms - _emote.born >= EMOTE_MS:
		return ""
	return str(_emote.tone)


## True while the flat battle screen is showing (the 3D set is hidden behind it).
func in_fight() -> bool:
	return state != null and state.foe != null and state.stage in Transitions.FIGHT


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


## How dark the picture still is from the fight that just ended (0 once it has faded).
func leave_fade() -> float:
	if state == null:
		return 0.0
	return clampf(1.0 - (clock_ms - _left_fight_at) / LEAVE_FADE_MS, 0.0, 1.0)


## The soul's square in picture pixels.
static func soul_square(run) -> Vector2:
	return Vector2(BOX_X + (run.soul.x + 0.5) * BOX_CELL, BOX_Y + (run.soul.y + 0.5) * BOX_CELL)


func _follow_soul(dt: float) -> void:
	if state == null or state.dodge == null or state.stage != "dodge":
		_soul_shown = null
		return
	var square := soul_square(state.dodge)
	if _soul_shown == null:
		_soul_shown = square
	else:
		_soul_shown = _soul_shown.lerp(square, 1.0 - exp(-SOUL_GLIDE * dt))


## The bar of the dodge's time left, whole (it is inside the picture, under the box).
func time_bar() -> Rect2:
	return Rect2(BOX_X - 3.0, BOX_Y + Dodge.ROWS * BOX_CELL + 5.0, Dodge.COLS * BOX_CELL + 6.0, 3.0)


## How strongly a hazard's warning fills its squares: it ramps up until it lands.
func warning_fill(h: Dictionary) -> float:
	return 0.12 + 0.28 * clampf((clock_ms - h.warn) / (h.hit - h.warn), 0.0, 1.0)


## Where a goo ball is now, falling onto the square it is aimed at (`at`; goo without one has no ball).
func goo_ball(h: Dictionary) -> Vector2:
	var to := _cell_rect(h.at).get_center()
	return to - Vector2(0.0, (1.0 - clampf((clock_ms - h.warn) / (h.hit - h.warn), 0.0, 1.0)) * GOO_DROP)


## Where a lantern is now, in picture pixels: it orbits all through a shadow dodge. `start` is where on its orbit it began.
func lantern_spot(start := Dodge.LANTERN_START_ANGLE) -> Vector2:
	var run = state.dodge
	return Vector2(BOX_X, BOX_Y) + Dodge.lantern_at(clock_ms - run.t0, run.intensity, start) * BOX_CELL


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
	if state.foe == null or state.foe.is_gone():
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


## What you typed flies up from the talk box to the monster.
func send_words(text: String) -> void:
	_words = text
	_words_at = clock_ms


## The line in the speech box now: the last thing the foe said, while the fight waits on it. {} when there is none.
func speech() -> Dictionary:
	if state == null or state.foe == null or not state.stage in SPEECH_STAGES:
		return {}
	for i in range(state.lines.size() - 1, -1, -1):
		var l: Dictionary = state.lines[i]
		if l.kind == "say" and l.who == state.foe.name:
			return l
	return {}


## The size the speech box writes `text` at: as large as fits, smaller for the longest lines.
static func speech_px(text: String) -> int:
	var body: Font = Fonts.body()
	for px in SPEECH_SIZES_LARGE if large_text else SPEECH_SIZES:
		if body.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, SPEECH.size.x - 12.0, px).y <= SPEECH.size.y - 16.0:
			return px
	return SPEECH_SIZES[-1]


## A bubble over the monster's head for a moment: how a deed landed ("good", "bad" or anything else).
func emote(tone: String) -> void:
	_emote = {"tone": tone, "born": clock_ms}


## What the bubble over the monster says now: a mood for a moment after a deed, or the question when it would likely join;
## {} when nothing. {tone} or {text}.
func bubble() -> Dictionary:
	if state.foe == null or state.foe.is_gone():
		return {}
	if state.listening or clock_ms - _words_at < HEARD_MS:
		return {"text": ".".repeat(1 + int(clock_ms / 300.0) % 3)}
	if not _emote.is_empty() and clock_ms - _emote.born < EMOTE_MS:
		return {"tone": _emote.tone}
	if can_spare() and state.stage in Transitions.PICKING:
		return {"text": "WANNA JOIN?"}
	return {}


## A number or word that floats up from `at` (picture pixels) and fades.
func popup(text: String, color: Color, at: Vector2) -> void:
	_popups.append({"text": text, "color": color, "at": at, "born": clock_ms})


## What hit you flies down to your health bar.
func comet(from: Vector2) -> void:
	_comets.append({"from": from, "born": clock_ms})


func _process(dt: float) -> void:
	_popups = _popups.filter(func(p): return clock_ms - p.born < 900.0)
	_comets = _comets.filter(func(c): return clock_ms - c.born < COMET_MS)
	if state != null and state.foe != null:
		if state.foe != _ghost_foe:
			_ghost_foe = state.foe
			_ghost = state.foe.hp_fraction()
		_ghost = ghost_after(_ghost, state.foe.hp_fraction(), dt)
	_follow_soul(dt)
	if state != null and state.nerve != _nerve_seen:
		if state.nerve > _nerve_seen:
			_nerve_moved_at = clock_ms
		_nerve_seen = state.nerve
	if _was_fighting and not in_fight():
		_left_fight_at = clock_ms
	_was_fighting = in_fight()
	queue_redraw()
	if _event_layer != null: # a layer driven before it is in the tree has none yet
		_event_layer.queue_redraw()


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
	var fade := leave_fade()
	if fade > 0.0:
		draw_rect(whole_picture(), Color(0, 0, 0, fade))
	for p in _popups:
		var age: float = (clock_ms - p.born) / 900.0
		var col: Color = p.color
		col.a = 1.0 - age
		_text(_body, p.text, p.at + Vector2(0.0, -26.0 * age), 22, col, HORIZONTAL_ALIGNMENT_CENTER)
	for c in _comets:
		var at: Vector2 = c.from.lerp(Vector2(W * 0.5, H), (clock_ms - c.born) / COMET_MS)
		draw_circle(at, 3.0, Palette.WARN)
		draw_line(at, at.lerp(c.from, 0.25), Color(Palette.WARN, 0.5), 2.0)
	if not quiet: # the whole floor's map is up over the picture, and the banner would land on the line the map says its keys in
		_banner()


## What the walk has stopped at (`event_art`): the picture goes dark behind a choice, and the moving picture of the thing is drawn
## over that, in a dark box of its own when it stands alone over the walk.
func _draw_event_art() -> void:
	if event_art.is_empty() or state == null:
		return
	var k := minf(size.x / W, size.y / H)
	_event_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var dim := float(event_art.get("dim", 0.0))
	if dim > 0.0:
		_event_layer.draw_rect(whole_picture(), Color(0, 0, 0, dim))
	var id := str(event_art.get("id", ""))
	if id == "":
		return
	var box: Rect2 = event_art.box
	if event_art.get("backed", false):
		_event_layer.draw_rect(box.grow(3.0), Color(0, 0, 0, 0.8))
		_event_layer.draw_rect(box.grow(3.0), Color(event_art.wall, 0.5), false, 1.0)
	Vignette.draw(_event_layer, id, box, clock_ms / 1000.0, event_art.wall, event_art.accent, int(event_art.get("picked", -1)))


## Where the soul is in the box, in picture pixels (the box's middle when there is no dodge).
func soul_at() -> Vector2:
	if state == null or state.dodge == null:
		return Vector2(W / 2.0, BOX_Y)
	return _cell_rect(Dodge.index(state.dodge.soul.x, state.dodge.soul.y)).get_center()


## The whole picture in this layer's coordinates: the layer keeps its 448 x 288 in the middle of a picture that may be wider.
func whole_picture() -> Rect2:
	return Rect2(-extra_x, 0.0, W + extra_x * 2.0, H)


## Where the banner goes: under the foe's card and above the dodge box or the strike bar when one is up, else low on the picture,
## clear of the health bars and the popups.
func banner_rect() -> Rect2:
	var y := H - BANNER_H - 8.0
	if not speech().is_empty():
		y = SPEECH.position.y - BANNER_H - 4.0
	if state != null and (state.dodge != null or state.bar != null):
		y = CARD_BOTTOM + 1.0
	return Rect2(BANNER_LEFT, y, BANNER_W, BANNER_H)


## Whether `text` fits the banner: two lines at most.
static func banner_fits(text: String) -> bool:
	var body: Font = Fonts.body()
	return body.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, BANNER_W - 12.0, BANNER_PX).y <= body.get_height(BANNER_PX) * 2.0


func _banner() -> void:
	var strength := banner_strength()
	if strength <= 0.0:
		return
	var rect := banner_rect()
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.9 * strength))
	draw_rect(rect, Color(Palette.MERCY, strength), false, 1.0)
	_text(_title, state.banner.title, rect.position + Vector2(0, 11), 7, Color(Palette.MERCY, strength), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	draw_multiline_string(_body, rect.position + Vector2(6, 25), state.banner.text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 12.0, BANNER_PX, 2, Color(Palette.INK, strength))


func _text(font: Font, s: String, at: Vector2, px: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, at, s, align, width, px, color)


# ---------------------------------------------------------------- the title card

## The picture of the halls and of her is behind this (battle_art.gd): the name sits over the top of it, where the corridor is empty.
func _title_screen() -> void:
	_text(_title, "DONJON", Vector2(0, H * 0.2), 28, Palette.INK, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text(_title, "GENRE HALLS", Vector2(0, H * 0.28), 8, Palette.YOU, HORIZONTAL_ALIGNMENT_CENTER, W)
	draw_rect(Rect2(0.0, H * 0.88, W, H * 0.12), Color(0.0, 0.0, 0.0, 0.75))
	if title_prompt_on():
		_text(_title, "PRESS ANY KEY", Vector2(0, H * 0.93), 9, Palette.INK, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text(_title, "ESC: MENU", Vector2(0, H * 0.98), 6, Palette.DIM, HORIZONTAL_ALIGNMENT_CENTER, W)


## Whether the blinking prompt shows this moment.
func title_prompt_on() -> bool:
	return floori(clock_ms / TITLE_BLINK_MS) % 2 == 0


# ---------------------------------------------------------------- the battle screen

func _battle() -> void:
	var m = state.foe
	var color := Palette.monster(m)
	var small: bool = state.dodge != null
	if not drawn_foe():
		draw_rect(whole_picture(), Color.BLACK)
		var hurt := 1.0 if clock_ms < hurt_until else 0.0
		if small:
			Art.draw(self, m.species, clock_ms, color, W / 2.0, 76.0, 0.27, hurt)
		else:
			Art.draw(self, m.species, clock_ms, color, W / 2.0, 270.0, 0.85, hurt)
	_name_and_health(m)
	_nerve()
	_bubble(Vector2(W / 2.0 + 36.0, 28.0) if small else Vector2(W / 2.0 + 74.0, 72.0))
	_speech_box()
	_flying_words()
	if state.dodge != null:
		_dodge_box(color)
		_flashes()
	if state.bar != null:
		_strike_bar()
	var flash := intro_flash()
	if flash > 0.0:
		draw_rect(whole_picture(), Color(1, 1, 1, flash))


## Where the foe's health bar goes: over its head when it fills the picture, up in the corner while it is small over the dodge box.
func foe_bar() -> Rect2:
	if state.dodge == null:
		return HEAD_BAR
	return SMALL_BAR


## Where the foe's card draws, piece by piece: the bar and the gauge under it, the health numbers with the mercy odds after them
## on the same line, the name, the feeling word, and the attack's name. Every piece of it ends above CARD_BOTTOM, but for the
## feeling word when the card is drawn small, which stands left of BANNER_LEFT instead: no piece of the card falls in the band a
## fight's banner takes, so the news of the moment is read beside the card and never over it (#164 read back: the tip that says
## ACT first covered the MERCY line it was teaching). A text piece is {text, at (its baseline), px, align, width}; what a check
## reads the card by, and what `_name_and_health` draws it from.
func foe_card(m) -> Dictionary:
	var bar := foe_bar()
	var small: bool = bar != HEAD_BAR
	var mercy := mercy_gauge()
	var numbers := "%d/%d" % [maxi(0, m.hp), m.max_hp]
	var numbers_at := bar.position + Vector2(bar.size.x + 4.0, bar.size.y - 1.0)
	var odds_at := numbers_at + Vector2(_title.get_string_size(numbers, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 4.0, 0.0)
	var genre: String = state.dodge.genre if state.dodge != null else state.genre_of(m)
	var label: String = Content.table("encounter").genres[genre].name
	if m.boss:
		label = "TURN %d · %s" % [m.turn + 1, label]
	return {
		"bar": bar,
		"gauge": Rect2(bar.position + Vector2(0.0, bar.size.y + 4.0), Vector2(bar.size.x, 3.0)),
		"mercy": mercy,
		"name": {"text": m.name, "at": Vector2(12.0 if small else 0.0, bar.position.y - 4.0), "px": 8,
			"align": HORIZONTAL_ALIGNMENT_LEFT if small else HORIZONTAL_ALIGNMENT_CENTER, "width": W - 12.0 if small else W},
		"numbers": {"text": numbers, "at": numbers_at, "px": 6, "align": HORIZONTAL_ALIGNMENT_LEFT, "width": -1.0},
		"odds": {"text": "· MERCY %d%%" % roundi(mercy * 100.0) if mercy >= 0.0 else "", "at": odds_at, "px": 6,
			"align": HORIZONTAL_ALIGNMENT_LEFT, "width": -1.0},
		"mood": {"text": mood_word(m)[0], "at": Vector2(12.0, bar.position.y if not small else MOOD_IN_MARGIN), "px": 7,
			"align": HORIZONTAL_ALIGNMENT_LEFT, "width": -1.0},
		"label": {"text": label, "at": Vector2(0.0, bar.position.y), "px": 8,
			"align": HORIZONTAL_ALIGNMENT_RIGHT, "width": W - 12.0},
	}


## The box a text piece of the card draws in, from its baseline: as wide as the font makes its text at the size and alignment it
## is written in. What a check reads the pieces by, to see that none of them falls in the band a fight's banner takes.
static func card_box(piece: Dictionary) -> Rect2:
	var font: Font = Fonts.title()
	var span: Vector2 = font.get_string_size(str(piece.text), piece.align, piece.width, piece.px)
	var x: float = piece.at.x
	if piece.align == HORIZONTAL_ALIGNMENT_CENTER:
		x += (piece.width - span.x) / 2.0
	elif piece.align == HORIZONTAL_ALIGNMENT_RIGHT:
		x += piece.width - span.x
	return Rect2(Vector2(x, piece.at.y - font.get_ascent(piece.px)), span)


## A word for how the foe feels now, and its colour. Read off its meters, so it changes as they do.
static func mood_word(m) -> Array:
	return MOOD_WORDS[Feelings.mood(m)]


## How far the white trail behind a health bar has caught up with the real value after `dt` seconds.
static func ghost_after(ghost: float, frac: float, dt: float) -> float:
	return frac if frac >= ghost else move_toward(ghost, frac, dt * GHOST_PER_S)


func _name_and_health(m) -> void:
	var spare := can_spare()
	var card := foe_card(m)
	var bar: Rect2 = card.bar
	_card_text(card.name, Palette.MERCY if spare else Palette.INK)
	draw_rect(bar, Palette.FAINT)
	var frac: float = m.hp_fraction()
	if _ghost > frac:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _ghost, bar.size.y)), Palette.INK)
	var struck: bool = clock_ms < hurt_until
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color.WHITE if struck else (Palette.WARN if frac < 0.4 else HEALTH_OK))
	_card_text(card.numbers, Palette.INK)
	if not m.is_gone():
		_card_text(card.mood, mood_word(m)[1])
	var mercy: float = card.mercy
	if mercy >= 0.0:
		var gauge: Rect2 = card.gauge
		_card_text(card.odds, Palette.MERCY)
		draw_rect(gauge, Palette.FAINT)
		draw_rect(Rect2(gauge.position, Vector2(gauge.size.x * mercy, gauge.size.y)), Palette.MERCY)
		draw_line(gauge.position + Vector2(gauge.size.x * MERCY_AT, -1.0), gauge.position + Vector2(gauge.size.x * MERCY_AT, gauge.size.y + 1.0), Palette.INK)
	_card_text(card.label, Palette.DIM)


## One text piece of the foe's card, drawn where `card_box` puts it (an empty piece draws nothing).
func _card_text(piece: Dictionary, color: Color) -> void:
	if str(piece.text).is_empty():
		return
	var box := card_box(piece)
	_text(_title, piece.text, Vector2(box.position.x, piece.at.y), piece.px, color, HORIZONTAL_ALIGNMENT_LEFT, -1.0)


func _speech_box() -> void:
	var l := speech()
	if l.is_empty():
		return
	draw_rect(SPEECH, Color(0.0, 0.0, 0.0, 0.92))
	draw_rect(SPEECH, Palette.MERCY, false, 1.0)
	_text(_title, l.who, SPEECH.position + Vector2(6, 10), 6, Palette.MERCY)
	var px := speech_px(l.text)
	draw_multiline_string(_body, SPEECH.position + Vector2(6, 12.0 + _body.get_ascent(px)), l.text, HORIZONTAL_ALIGNMENT_LEFT, SPEECH.size.x - 12.0, px, -1, Palette.INK)


func _flying_words() -> void:
	var age := (clock_ms - _words_at) / FLY_MS
	if age < 0.0 or age >= 1.0:
		return
	var at := Vector2(0.0, lerpf(H - 8.0, 110.0, age))
	_text(_body, _words.left(40), at, 13, Color(Palette.YOU, 1.0 - age * age), HORIZONTAL_ALIGNMENT_CENTER, W)


## The speech bubble, its tail at the monster's head, down to the left of `at`.
func _bubble(at: Vector2) -> void:
	var b := bubble()
	if b.is_empty():
		return
	if drawn_foe() and (b.has("tone") or str(b.text).begins_with(".")):
		return # a drawing floats over its head instead (battle_art.gd)
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
		draw_rect(whole_picture(), Color(Palette.YOU, 0.22))
		_text(_title, "BOUNCY! THE SLIME TAKES THE HIT", Vector2(0, BOX_Y - 8.0), 8, Palette.YOU, HORIZONTAL_ALIGNMENT_CENTER, W)
	if clock_ms - run.hit_flash < 120.0:
		draw_rect(whole_picture(), Color(Palette.WARN, 0.25))


# ---------------------------------------------------------------- the dodge box

func _dodge_box(accent: Color) -> void:
	var run = state.dodge
	var box := Rect2(BOX_X, BOX_Y, Dodge.COLS * BOX_CELL, Dodge.ROWS * BOX_CELL)
	if drawn_foe():
		draw_rect(box, Color.BLACK) # the halls behind it must not read as squares
	for k in Dodge.COLS * Dodge.ROWS:
		if run.blocked.has(k):
			draw_rect(_cell_rect(k).grow(-2), PILLAR)
			draw_rect(_cell_rect(k).grow(-2.5), PILLAR_LINE, false, 1.0)
		else:
			draw_rect(_cell_rect(k), GRID, false, 1.0)
	for h in run.hazards:
		_hazard(h, LANTERN if h.kind == "light" else accent)
	for start in run.lanterns:
		_lantern(start)
	if run.mirror:
		_text(_title, "MIRRORED: LEFT IS RIGHT", Vector2(0, BOX_Y - 8.0), 7, Palette.YOU, HORIZONTAL_ALIGNMENT_CENTER, W)
	var pulse: float = maxf(0.0, 1.0 - (clock_ms - run.pulse) / 180.0) if run.pulse > 0.0 else 0.0
	draw_rect(box.grow(3), Palette.INK, false, 2.0 + pulse * 3.0)
	_soul(run)
	_charms()
	_keepsakes()
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
	if h.has("flash") and not live and clock_ms - h.warn > h.flash:
		return # a trap shows itself for a moment, then you have to remember it
	if h.kind == "star":
		_star(h)
		return
	if h.kind == "pad":
		_pad(h)
		return
	if h.kind == "heart":
		_heart(h)
		return
	if h.has("glyph") and not live:
		_rays(h, col)
	for k in h.cells:
		var cell := _cell_rect(k)
		if live:
			draw_rect(cell.grow(-1), Color(col, 0.85))
		else:
			draw_rect(cell.grow(-1), Color(col, warning_fill(h)))
			draw_rect(cell.grow(-3.5), Color(col, 0.5 + 0.5 * absf(sin(clock_ms / 90.0))), false, 1.0)
			if last_moment(h):
				draw_rect(cell.grow(-2.0), Palette.INK, false, 1.5) # stepping off it now is a close call
	if h.has("glyph"):
		var at := _cell_rect(h.at).get_center()
		draw_rect(Rect2(at - Vector2(11, 11), Vector2(22, 22)), Color.BLACK)
		_piece(h.glyph, at, Color.WHITE)
	if h.kind == "goo" and not live and h.has("at"): # a puddle's spread of goo has no one square to fall on
		draw_circle(goo_ball(h), 5.0, col)
	if h.has("mark") and h.has("at") and (live or h.get("mark_warn", false)) and clock_ms < h.end:
		_mark(h, live)


## What a hazard's thing looks like on its square: black inside a white line, so it reads on a lit square and a dark one.
func _mark(h: Dictionary, live: bool) -> void:
	var at := _cell_rect(h.at).get_center()
	var dir: Vector2 = Vector2(h.get("dir", Vector2i.RIGHT)).normalized()
	var side := Vector2(-dir.y, dir.x)
	var ink := Color.WHITE
	match str(h.mark):
		"ball":
			draw_circle(at, 7.5, Color.BLACK)
			draw_arc(at, 7.0, 0.0, TAU, 20, ink, 1.5)
		"rock":
			var pts := PackedVector2Array()
			for i in 7:
				var a := TAU * i / 7.0 + 0.3
				pts.append(at + Vector2(cos(a), sin(a)) * (9.0 if i % 2 == 0 else 7.0))
			draw_colored_polygon(pts, Color.BLACK)
			pts.append(pts[0])
			draw_polyline(pts, ink, 1.5)
		"head":
			var pts := PackedVector2Array([at + dir * 10.0, at + side * 7.0, at - dir * 6.0, at - side * 7.0, at + dir * 10.0])
			draw_colored_polygon(pts.slice(0, 4), Color.BLACK)
			draw_polyline(pts, ink, 1.5)
			draw_circle(at + dir * 2.0 + side * 3.0, 1.6, ink)
			draw_circle(at + dir * 2.0 - side * 3.0, 1.6, ink)
		"bomb":
			draw_circle(at + Vector2(0, 1), 8.0, Color.BLACK)
			draw_arc(at + Vector2(0, 1), 7.5, 0.0, TAU, 20, ink, 1.5)
			draw_line(at + Vector2(4, -6), at + Vector2(7, -10), ink, 1.5)
			if not live:
				var beat: float = float(h.get("beat", 1000.0))
				var left := ceili(maxf(0.0, h.hit - clock_ms) / beat)
				_text(_title, str(left), at + Vector2(-10, 5), 8, ink, HORIZONTAL_ALIGNMENT_CENTER, 20.0)
		"eye":
			var pts := PackedVector2Array([at + Vector2(-10, 0), at + Vector2(0, -6), at + Vector2(10, 0), at + Vector2(0, 6)])
			draw_colored_polygon(pts, Color.BLACK)
			pts.append(pts[0])
			draw_polyline(pts, ink, 1.5)
			draw_circle(at, 2.5, ink)
		"arrow":
			var pts := PackedVector2Array([at + dir * 10.0, at + side * 6.0 - dir * 2.0, at + side * 2.5 - dir * 2.0, at + side * 2.5 - dir * 10.0, at - side * 2.5 - dir * 10.0, at - side * 2.5 - dir * 2.0, at - side * 6.0 - dir * 2.0])
			draw_colored_polygon(pts, Color.BLACK)
			pts.append(pts[0])
			draw_polyline(pts, ink, 1.5)
		"fist":
			var r := Rect2(at - Vector2(9, 8), Vector2(18, 16))
			draw_rect(r, Color.BLACK)
			draw_rect(r, ink, false, 1.5)
			for i in 3:
				draw_line(r.position + Vector2(4.5 + i * 4.5, 0), r.position + Vector2(4.5 + i * 4.5, 5), ink, 1.0)
		_:
			push_error("overlay: no mark called '%s'" % h.mark)


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
		"Q": # a crown
			return [
				[Vector2(-8, 9), Vector2(8, 9), Vector2(8, 6), Vector2(-8, 6)],
				[Vector2(-6, 6), Vector2(6, 6), Vector2(8, -8), Vector2(4, -2), Vector2(0, -9), Vector2(-4, -2), Vector2(-8, -8)],
			]
		"P": # a little round head on a stem
			return [
				[Vector2(-7, 9), Vector2(7, 9), Vector2(7, 6), Vector2(-7, 6)],
				[Vector2(-3, 6), Vector2(3, 6), Vector2(2, -1), Vector2(-2, -1)],
				[Vector2(0, -9), Vector2(3.5, -7.5), Vector2(4.5, -4), Vector2(3, -1), Vector2(-3, -1), Vector2(-4.5, -4), Vector2(-3.5, -7.5)],
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


## The dance's light: an outline closing in on its square, so you can see the beat coming, and full on the beat.
func _pad(h: Dictionary) -> void:
	if h.get("taken", false):
		return
	var cell := _cell_rect(h.at)
	if clock_ms >= h.hit:
		draw_rect(cell.grow(-1), Palette.MERCY)
		return
	var coming: float = clampf((clock_ms - h.warn) / (h.hit - h.warn), 0.0, 1.0)
	draw_rect(cell.grow(-1), Color(Palette.MERCY, 0.2 * coming))
	draw_rect(cell.grow((1.0 - coming) * cell.size.x * 0.35), Color(Palette.MERCY, coming), false, 2.0)


## A lantern, all through a shadow dodge: a soft glow and the small flame in it. `start` is where on its orbit it began.
func _lantern(start := Dodge.LANTERN_START_ANGLE) -> void:
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
	var at := lantern_spot(start)
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
	if state.party_size() > 0: # a friend who isn't a monster lends no strength
		_text(_title, "+%d STRIKE" % state.party_size(), Vector2(12, BOX_Y + 22.0 + rows.size() * 12.0 + 4.0), 6, Palette.DIM)
		if state.dodge.guard > 0:
			_text(_title, "-%d HURT" % state.dodge.guard, Vector2(12, BOX_Y + 22.0 + rows.size() * 12.0 + 14.0), 6, Palette.DIM)


## The keepsakes you carry, right of the box under the nerve: what a champion left is at work in this fight.
func _keepsakes() -> void:
	var names: Array = Keepsakes.held_names(state)
	if names.is_empty():
		return
	_text(_title, "KEEPSAKES", KEEPSAKES_BESIDE_BOX, 7, Palette.DIM)
	for i in names.size():
		_text(_title, str(names[i]), KEEPSAKES_BESIDE_BOX + Vector2(0.0, 12.0 + i * 10.0), 6, Palette.MERCY)


func _cell_rect(k: int) -> Rect2:
	return Rect2(BOX_X + (k % Dodge.COLS) * BOX_CELL, BOX_Y + floori(float(k) / Dodge.COLS) * BOX_CELL, BOX_CELL, BOX_CELL)


func _soul(run) -> void:
	var at: Vector2 = _soul_shown if _soul_shown != null else soul_square(run)
	var alpha := 1.0 if clock_ms > run.iframes or int(clock_ms / 70.0) % 2 == 0 else 0.25
	var col := Color(Palette.YOU, alpha)
	var r := 8.0
	draw_colored_polygon([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)], col)
	if run.shield:
		draw_arc(at, r + 4.0, 0.0, TAU, 20, Color(Palette.MERCY, 0.9), 1.5)
	var spark := nerve_spark()
	if spark > 0.0: # a close call: a ring flies off you
		var grown := 1.0 - spark
		draw_arc(at, r + 3.0 + 20.0 * grown, 0.0, TAU, 24, Color(Palette.YOU, spark), 2.0)
		for i in 4:
			var way := Vector2.from_angle(PI / 4.0 + i * PI / 2.0)
			draw_line(at + way * (r + 4.0 + 14.0 * grown), at + way * (r + 10.0 + 20.0 * grown), Color(Palette.INK, spark), 1.5)


# ---------------------------------------------------------------- nerve and hearts

## Whether this hazard is in its last moments before it lands: stepping off it now is a close call (the feature nerve).
func last_moment(h: Dictionary) -> bool:
	return state.viewing("nerve") and clock_ms < h.hit and h.hit - clock_ms <= (state.dodge.nerve_window if state.dodge != null else Combat.NERVE_WINDOW_MS)


## How strong the ring of a close call still is round your soul (0 when there is none).
func nerve_spark() -> float:
	if state == null or state.dodge == null:
		return 0.0
	return clampf(1.0 - (clock_ms - state.dodge.nerve_flash) / NERVE_SPARK_MS, 0.0, 1.0)


## Where the nerve's pips go, the first one's middle: right of the box in a dodge, otherwise up on the right, under the kind of
## fight and clear of the mercy odds beside the health bar.
func nerve_at() -> Vector2:
	if state.dodge != null:
		return NERVE_BESIDE_BOX + Vector2(4.0, 12.0)
	return Vector2(W - 12.0 - NERVE_PIP * (Combat.NERVE_MAX - 1) - 4.0, 42.0)


## Your nerve: a pip for each point held, hollow for the rest. In a dodge it always shows (it is earned there), with what it is
## worth to a strike and to a SPARE; elsewhere only once you hold some, and the commands say what it adds.
func _nerve() -> void:
	if not state.viewing("nerve") or state.foe == null or state.foe.is_gone():
		return
	var held: int = state.nerve
	if held <= 0 and state.dodge == null:
		return
	var first := nerve_at()
	var pulse := clampf(1.0 - (clock_ms - _nerve_moved_at) / NERVE_PULSE_MS, 0.0, 1.0)
	if state.dodge != null:
		_text(_title, "NERVE", NERVE_BESIDE_BOX, 7, Palette.YOU if held > 0 else Palette.DIM)
	else: # over its pips, so neither runs into the mercy odds
		_text(_title, "NERVE", Vector2(0.0, first.y - 7.0), 7, Palette.YOU, HORIZONTAL_ALIGNMENT_RIGHT, W - 12.0)
	for i in Combat.NERVE_MAX:
		var at := first + Vector2(i * NERVE_PIP, 0.0)
		var r := 3.5 + (2.5 * pulse if i == held - 1 else 0.0)
		var pip := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
		if i < held:
			draw_colored_polygon(pip, Palette.YOU)
		else:
			pip.append(pip[0])
			draw_polyline(pip, Palette.FAINT, 1.0)
	if held > 0 and state.dodge != null:
		var worth := first + Vector2(-4.0, 16.0)
		_text(_title, "+%d STRIKE" % Combat.nerve_damage(held), worth, 6, Palette.DIM)
		_text(_title, "+%d%% MERCY" % roundi(Combat.nerve_mercy(held) * 100.0), worth + Vector2(0.0, 10.0), 6, Palette.DIM)


## A heart a friendly monster dropped: it falls to its square and waits there a moment to be caught.
func _heart(h: Dictionary) -> void:
	if h.get("taken", false):
		return
	var live: bool = clock_ms >= h.hit
	var to := _cell_rect(h.at).get_center()
	var at := to if live else to - Vector2(0.0, (1.0 - clampf((clock_ms - h.warn) / (h.hit - h.warn), 0.0, 1.0)) * GOO_DROP)
	if live:
		draw_rect(_cell_rect(h.at).grow(-1), Color(Palette.MERCY, 0.3))
	var beat := 1.0 + 0.12 * sin(clock_ms / 110.0)
	for shape in heart_shape(7.0 * beat):
		var pts := PackedVector2Array()
		for p in shape:
			pts.append(at + p)
		draw_colored_polygon(pts, Palette.MERCY)


## A heart `size` pixels from its middle to its side, as polygons round (0, 0): two lobes and the point below them.
static func heart_shape(size: float) -> Array:
	var lobes := []
	for side in [-1.0, 1.0]:
		var lobe := []
		for i in 9:
			var a := PI + i * PI / 8.0
			lobe.append(Vector2(side * size * 0.5 + cos(a) * size * 0.5, -size * 0.2 + sin(a) * size * 0.5))
		lobes.append(lobe)
	return lobes + [[Vector2(-size, -size * 0.2), Vector2(size, -size * 0.2), Vector2(0.0, size * 0.95)]]


# ---------------------------------------------------------------- the strike bar

## Where the strike bar goes: above the speech box when the foe has said something.
func strike_bar_rect() -> Rect2:
	var y := SPEECH.position.y - STRIKE_BAR_H - 6.0 if not speech().is_empty() else 209.0
	return Rect2(62.0, y, 324.0, STRIKE_BAR_H)


func _strike_bar() -> void:
	var bar = state.bar
	var rect := strike_bar_rect()
	draw_rect(rect, Color(0, 0, 0, 0.7))
	if bar.get("heavy", false):
		var mark := rect.size.x * Combat.HEAVY_MISS_EDGE
		draw_rect(Rect2(rect.get_center().x - mark / 2.0, rect.position.y, mark, rect.size.y), Color(Palette.WARN, 0.4))
	var perfect: float = Combat.CRIT_EDGE * (Keepsakes.STEADY_SCALE if Keepsakes.has(state, "steady_hand") else 1.0) # the perfect mark, as a share of the bar
	draw_rect(Rect2(rect.position.x + rect.size.x * (0.5 - perfect / 2.0), rect.position.y, rect.size.x * perfect, rect.size.y), Color(Palette.MERCY, 0.35))
	draw_line(Vector2(rect.get_center().x, rect.position.y), Vector2(rect.get_center().x, rect.end.y), Palette.MERCY, 2.0)
	for mark in bar.get("marks", []): # each friend's mark, in its colour: lit once it lands, greyed once it is lost
		var ink := Color(Content.species(mark.species).color)
		var zone := Rect2(rect.position.x + rect.size.x * (float(mark.at) - Combat.FOLLOW_EDGE), rect.position.y, rect.size.x * Combat.FOLLOW_EDGE * 2.0, rect.size.y)
		match str(mark.state):
			"hit":
				draw_rect(zone, Color(ink, 0.9))
			"lost":
				draw_rect(zone.grow(-1.0), Palette.FAINT, false, 1.0) # an empty frame: nothing to press for any more
			_:
				draw_rect(zone, Color(ink, 0.28 + 0.12 * absf(sin(clock_ms / 140.0))))
				draw_line(Vector2(zone.get_center().x, zone.position.y), Vector2(zone.get_center().x, zone.end.y), ink, 2.0)
	if float(bar.get("struck", -1.0)) >= 0.0: # where your own strike fell, while the line runs on
		var sx: float = rect.position.x + rect.size.x * float(bar.struck)
		draw_line(Vector2(sx, rect.position.y), Vector2(sx, rect.end.y), Color(Palette.MERCY, 0.9), 2.0)
	var p := clampf((clock_ms - bar.t0) / bar.dur, 0.0, 1.0)
	var x := rect.position.x + rect.size.x * p
	draw_line(Vector2(x, rect.position.y - 3), Vector2(x, rect.end.y + 3), Palette.INK, 3.0)
	draw_rect(rect, Palette.INK, false, 2.0)
