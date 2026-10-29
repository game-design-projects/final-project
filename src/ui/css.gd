## The web page's stylesheet (crawler/public/style.css) as Godot values and drawing helpers: the :root colours, the
## two pixel fonts, and boxes the way the CSS draws them (borders, glows from box-shadow, keycaps, pixel icons,
## segmented bars), for widgets that paint themselves in `_draw()`.
## Load it with `const Css = preload("res://src/ui/css.gd")`.
extends RefCounted

const Canvas2D = preload("res://src/view/canvas2d.gd")
const Status = preload("res://src/rules/status.gd")

# ---------------------------------------------------------------- :root
const BG := Color("#000000")
const PAGE := Color("#111111")
const INK := Color("#e8e8e8")
const DIM := Color("#8a8a8a")
const FAINT := Color("#3a3a3a")
const WARN := Color("#ff5a4a")
const YOU := Color("#8fd3ff")
const GOLD := Color("#ffd27a")
const ACCENT := Color("#ffb347") # --accent when the floor has none yet
const OFF_ICON := Color("#5a5a5a")

const PS := "press start 2p"
const VT := "vt323"

const PS_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
const VT_PATH := "res://assets/fonts/VT323-Regular.ttf"
const ELLIPSIS := "…"

static var _glows := {}
static var _fonts := {}
## The window is scaled by a fraction (canvas_items stretch): pixel fonts drawn without antialiasing would lose
## strokes there, so they get grayscale antialiasing, as the browser draws them
static var _fractional := false


## Press Start 2P for bars, the dock, the party, headings: crisp at whole-number scales
static func ps() -> Font:
	return _font(PS_PATH)


## VT323 for the body text and the log
static func vt() -> Font:
	return _font(VT_PATH)


static func _font(path: String) -> FontFile:
	if not _fonts.has(path):
		var f: FontFile = (load(path) as FontFile).duplicate()
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.generate_mipmaps = false
		_fonts[path] = f
		_apply_aa(f, path)
	return _fonts[path]


## Press Start 2P below its 8px design size loses whole strokes without antialiasing ("Y" turns into "V"):
## smaller text is drawn with a grayscale-antialiased copy, as the browser draws it
static func _small_ps() -> FontFile:
	if not _fonts.has("ps-small"):
		var f: FontFile = (load(PS_PATH) as FontFile).duplicate()
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.generate_mipmaps = false
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_fonts["ps-small"] = f
	return _fonts["ps-small"]


## The font to draw `font` with at `size`
static func face(font: Font, size: int) -> Font:
	if size < 8 and font == _fonts.get(PS_PATH):
		return _small_ps()
	return font


static func _apply_aa(f: FontFile, path: String) -> void:
	# VT323 reads like the page with soft edges at any size; Press Start 2P stays crisp unless the scale is fractional
	var aa := _fractional or path == VT_PATH
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY if aa else TextServer.FONT_ANTIALIASING_NONE


## The canvas scale the window shows the 1180x820 layout at (main calls it on every resize)
static func set_scale(s: float) -> void:
	var frac := absf(s - roundf(s)) > 0.01
	if frac == _fractional:
		return
	_fractional = frac
	print_verbose("ui fonts: %s at scale %.3f" % ["antialiased" if frac else "crisp", s])
	for path in [PS_PATH, VT_PATH]:
		if _fonts.has(path):
			_apply_aa(_fonts[path], path)


## A CSS colour string (or Color) as a Color
static func css(c) -> Color:
	return Canvas2D.css(c)


## color-mix(in srgb, c pct, base): `pct` of `c` over `base`
static func mix(c: Color, pct: float, base := BG) -> Color:
	var out := base.lerp(c, pct)
	out.a = lerpf(base.a, c.a, pct)
	return out


static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


## filter: grayscale(1), keeping the alpha
static func gray(c: Color) -> Color:
	var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	return Color(l, l, l, c.a)


# ---------------------------------------------------------------- text

static func width(font: Font, size: int, s: String) -> float:
	if s.ends_with(ELLIPSIS) and not font.has_char(0x2026):
		return font.get_string_size(s.left(-1), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + _ellipsis_w(size)
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## The pixel ellipsis drawn where a font has no "…": three square dots on the baseline
static func _dot(size: int) -> float:
	return maxf(1.0, roundf(size * 0.2))


static func _ellipsis_w(size: int) -> float:
	return 3.0 * _dot(size) + 2.0 * maxf(1.0, roundf(size * 0.12)) + 1.0


## The baseline that centres a line of `font` at `size` in a line box `h` tall starting at `top` (how CSS places
## text inside its line-height).
static func baseline(font: Font, size: int, top: float, h: float) -> float:
	return top + (h + font.get_ascent(size) - font.get_descent(size)) / 2.0


## Draws `s` with its line box's top-left at (x, top), the line box `h` tall (0: the font's own height). Returns the
## width drawn.
static func text(ci: CanvasItem, font: Font, size: int, x: float, top: float, s: String, color: Color, h := 0.0) -> float:
	if s == "":
		return 0.0
	font = face(font, size)
	var lh := h if h > 0.0 else font.get_height(size)
	var base := Vector2(roundf(x), roundf(baseline(font, size, top, lh)))
	if s.ends_with(ELLIPSIS) and not font.has_char(0x2026):
		var head := s.left(-1)
		ci.draw_string(font, base, head, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		var d := _dot(size)
		var gap := maxf(1.0, roundf(size * 0.12))
		var dx := base.x + font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 1.0
		for i in 3:
			ci.draw_rect(Rect2(dx + i * (d + gap), base.y - d, d, d), color)
		return width(font, size, s)
	ci.draw_string(font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return width(font, size, s)


## `s` cut to fit `w` pixels with an ellipsis (text-overflow: ellipsis)
static func ellipsize(font: Font, size: int, s: String, w: float) -> String:
	if w <= 0.0:
		return ""
	if width(font, size, s) <= w:
		return s
	var dots := ELLIPSIS
	var n := s.length()
	while n > 0 and width(font, size, s.left(n).strip_edges(false, true) + dots) > w:
		n -= 1
	return s.left(n).strip_edges(false, true) + dots if n > 0 else ""


## Words wrapped to `w` pixels (white-space: normal). Long words are kept whole on their own line.
static func wrap(font: Font, size: int, s: String, w: float) -> PackedStringArray:
	var lines := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var next := word if line == "" else line + " " + word
			if line != "" and width(font, size, next) > w:
				lines.append(line)
				line = word
			else:
				line = next
		lines.append(line)
	return lines


# ---------------------------------------------------------------- boxes

## A CSS border-box: `bw` px of border inside `r`, the rest filled with `bg` (either may be transparent).
static func frame(ci: CanvasItem, r: Rect2, border: Color, bw := 2.0, bg := Color(0, 0, 0, 0)) -> void:
	if bg.a > 0.0:
		ci.draw_rect(r, bg)
	if border.a <= 0.0 or bw <= 0.0:
		return
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, bw)), border)
	ci.draw_rect(Rect2(r.position.x, r.end.y - bw, r.size.x, bw), border)
	ci.draw_rect(Rect2(r.position.x, r.position.y + bw, bw, r.size.y - 2 * bw), border)
	ci.draw_rect(Rect2(r.end.x - bw, r.position.y + bw, bw, r.size.y - 2 * bw), border)


## box-shadow: 0 0 <blur>px <color>, drawn around `r` (call it before painting the box itself)
static func glow(ci: CanvasItem, r: Rect2, color: Color, blur: float, spread := 0.0) -> void:
	if color.a <= 0.0 or blur <= 0.0:
		return
	var key := "%s|%d" % [color.to_html(), int(blur)]
	var sb: StyleBoxFlat = _glows.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.draw_center = false
		sb.bg_color = Color(0, 0, 0, 0)
		# A CSS blur of B px reads as a soft fringe about B px wide that starts at about half strength
		sb.shadow_color = Color(color.r, color.g, color.b, color.a * 0.62)
		sb.shadow_size = int(blur)
		sb.anti_aliasing = false
		_glows[key] = sb
		if _glows.size() > 400:
			_glows.clear()
	ci.draw_style_box(sb, r.grow(spread))


## A horizontal dashed rule (border-top: 1px dashed)
static func dashed(ci: CanvasItem, x0: float, x1: float, y: float, color: Color, dash := 3.0) -> void:
	var x := x0
	while x < x1:
		ci.draw_rect(Rect2(x, y, minf(dash, x1 - x), 1), color)
		x += dash * 2.0


## A dashed outline (border: 1px dashed)
static func dashed_frame(ci: CanvasItem, r: Rect2, color: Color, dash := 3.0) -> void:
	dashed(ci, r.position.x, r.end.x, r.position.y, color, dash)
	dashed(ci, r.position.x, r.end.x, r.end.y - 1, color, dash)
	var y := r.position.y
	while y < r.end.y:
		ci.draw_rect(Rect2(r.position.x, y, 1, minf(dash, r.end.y - y)), color)
		ci.draw_rect(Rect2(r.end.x - 1, y, 1, minf(dash, r.end.y - y)), color)
		y += dash * 2.0


## One of status.js's 7x7 pixel icons, scaled to `size` px (whole pixels per dot where it can)
static func icon(ci: CanvasItem, name: String, pos: Vector2, size: float, color: Color) -> void:
	if color.a <= 0.0:
		return
	glyph(ci, Status.ICONS.get(name, Status.ICONS["dot"]), pos, size, color)


## A 7-row pattern of "#" dots (status.js ICONS, achievements.js GLYPHS) drawn into a `size`-px square
static func glyph(ci: CanvasItem, rows: Array, pos: Vector2, size: float, color: Color) -> void:
	var px := size / 7.0
	for y in rows.size():
		var row: String = rows[y]
		var x := 0
		while x < row.length():
			if row[x] != "#":
				x += 1
				continue
			var run := 1
			while x + run < row.length() and row[x + run] == "#":
				run += 1
			var a := Vector2(floorf(pos.x + x * px), floorf(pos.y + y * px))
			var b := Vector2(floorf(pos.x + (x + run) * px), floorf(pos.y + (y + 1) * px))
			ci.draw_rect(Rect2(a, b - a), color)
			x += run


## A segmented health/progress bar (.hpbar): a 1px #555 frame, 1px padding, the fill split every `seg` px
static func seg_bar(ci: CanvasItem, r: Rect2, pct: float, color: Color, opts := {}) -> void:
	var a: float = opts.get("alpha", 1.0)
	var border: Color = opts.get("border", Color("#555555"))
	ci.draw_rect(r, alpha(opts.get("bg", Color("#111111")), a))
	frame(ci, r, alpha(border, a), 1.0)
	var inner := r.grow(-2.0)
	var w := roundf(inner.size.x * clampf(pct, 0.0, 1.0))
	if w <= 0.0:
		return
	var fill := Rect2(inner.position, Vector2(w, inner.size.y))
	if opts.get("glow", true):
		glow(ci, fill, alpha(color, 0.5 * a), 6.0)
	ci.draw_rect(fill, alpha(color, a))
	var seg: float = opts.get("seg", 7.0)
	if seg > 0.0:
		var gap := Color(0, 0, 0, 0.6 * a)
		var x := inner.position.x + seg - 1.0
		while x < fill.end.x:
			ci.draw_rect(Rect2(x, inner.position.y, 1, inner.size.y), gap)
			x += seg


## A <kbd> keycap: `cap` text (or an icon name with icon = true), `font_size` px, bg and fg colours.
## min_w: CSS min-width; pad: [left/right, top, bottom]. Returns the cap's rect.
static func keycap_size(cap: String, font_size := 8, is_icon := false, min_w := 18.0, pad := [4.0, 4.0, 3.0]) -> Vector2:
	var w: float = 7.0 if is_icon else width(ps(), font_size, cap)
	var h: float = 7.0 if is_icon else float(font_size)
	return Vector2(maxf(min_w, w + pad[0] * 2.0), h + pad[1] + pad[2])


static func keycap(ci: CanvasItem, pos: Vector2, cap: String, bg: Color, fg: Color, opts := {}) -> Rect2:
	var font_size: int = opts.get("size", 8)
	var is_icon: bool = opts.get("icon", false)
	var sz: Vector2 = opts.get("box", keycap_size(cap, font_size, is_icon, opts.get("min_w", 18.0), opts.get("pad", [4.0, 4.0, 3.0])))
	var r := Rect2(pos, sz)
	if bg.a > 0.0:
		ci.draw_rect(r, bg)
	if is_icon:
		icon(ci, cap, (r.get_center() - Vector2(3.5, 3.5)).floor(), 7.0, fg)
	else:
		var tw := width(ps(), font_size, cap)
		text(ci, ps(), font_size, r.position.x + (sz.x - tw) / 2.0, r.position.y, cap, fg, sz.y)
	return r


# ---------------------------------------------------------------- CSS animations

## ease-in-out between keyframes 0% and 50% (and back): 0 at the ends of the cycle, 1 at its middle
static func pulse(t_ms: float, period_ms: float) -> float:
	var p := fposmod(t_ms, period_ms) / period_ms
	var k := p * 2.0 if p < 0.5 else (1.0 - p) * 2.0
	return k * k * (3.0 - 2.0 * k)


## A nudge (keyframes 20%/60% -amp, 40%/80% +amp) at `age_ms` into a `dur_ms` animation: [dx, strength 0..1]
static func nudge(age_ms: float, dur_ms := 350.0, amp := 6.0) -> Array:
	if age_ms < 0.0 or age_ms >= dur_ms:
		return [0.0, 0.0]
	var p := age_ms / dur_ms
	var keys := [[0.0, 0.0], [0.2, -amp], [0.4, amp], [0.6, -amp], [0.8, amp], [1.0, 0.0]]
	for i in range(1, keys.size()):
		if p <= keys[i][0]:
			var k: float = (p - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0])
			var dx: float = lerpf(keys[i - 1][1], keys[i][1], k)
			return [roundf(dx), absf(dx) / amp]
	return [0.0, 0.0]


## steps(2) blink to `low` opacity for the second half of each period
static func blink(t_ms: float, period_ms := 800.0, low := 0.35) -> float:
	return 1.0 if fposmod(t_ms, period_ms) < period_ms / 2.0 else low


## animation timing steps(n): progress p (0..1) rounded down to n steps
static func steps(p: float, n: int) -> float:
	return clampf(floorf(clampf(p, 0.0, 1.0) * n) / n, 0.0, 1.0)
