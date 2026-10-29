## A Canvas 2D context over a CanvasItem's draw_* calls, so the JS drawing code (render.js, art.js, dice.js,
## game.js, genre-halls.js) ports line for line: `ctx.fillStyle = "#000"` becomes `ctx.fill_style = "#000"`,
## `ctx.lineTo(x, y)` becomes `ctx.line_to(x, y)`. Make one inside `_draw()` (draw_* only works there):
##   var ctx = Canvas2D.new(self, Vector2(448, 288))
## Styles take CSS colors ("#e8e8e8", "#ffd27a80", "rgba(0,0,0,0.5)", "black"), Color values, or a gradient from
## create_linear_gradient / create_radial_gradient. The current transform applies when a path point is added, as in
## the browser. clip() supports any polygon for fills and strokes; text and images are not clipped.
## Approximations: a fill with holes fills each subpath on its own; radial gradients are drawn as a radial texture
## over the gradient's outer circle; shadow_blur draws a soft wider pass under strokes and fills (the postfx bloom does
## the rest); line_join/line_cap are accepted and ignored.
extends RefCounted

const FONT_FILES := {
	"press start 2p": "res://assets/fonts/PressStart2P-Regular.ttf",
	"vt323": "res://assets/fonts/VT323-Regular.ttf",
}
const DEFAULT_FONT := "res://assets/fonts/VT323-Regular.ttf"

static var _colors := {}
static var _fonts := {}
static var _font_specs := {}
static var _radial_textures := {}

var item: CanvasItem
var size: Vector2

var fill_style = "#000"
var stroke_style = "#000"
var line_width := 1.0
var global_alpha := 1.0
var font := "10px VT323"
var text_align := "start"
var text_baseline := "alphabetic"
var shadow_blur := 0.0
var shadow_color = "rgba(0,0,0,0)"
var line_join := "miter"
var line_cap := "butt"
var line_dash: Array = []
var image_smoothing_enabled := true
## Lines are antialiased like a browser canvas; set false for crisp pixel lines.
var antialiased := true

var _xf := Transform2D.IDENTITY
var _clip = null # PackedVector2Array in device space, or null
var _stack: Array = []
var _paths: Array = [] # [{pts: PackedVector2Array, closed: bool}]


func _init(target: CanvasItem, canvas_size := Vector2(448, 288)) -> void:
	item = target
	size = canvas_size


# ---------------------------------------------------------------- state

func save() -> void:
	_stack.append([fill_style, stroke_style, line_width, global_alpha, font, text_align, text_baseline, shadow_blur, shadow_color, line_join, line_cap, line_dash.duplicate(), _xf, _clip])


func restore() -> void:
	if _stack.is_empty():
		return
	var s: Array = _stack.pop_back()
	fill_style = s[0]; stroke_style = s[1]; line_width = s[2]; global_alpha = s[3]; font = s[4]
	text_align = s[5]; text_baseline = s[6]; shadow_blur = s[7]; shadow_color = s[8]; line_join = s[9]
	line_cap = s[10]; line_dash = s[11]; _xf = s[12]; _clip = s[13]


func translate(x: float, y: float) -> void:
	_xf = _xf * Transform2D(0.0, Vector2(x, y))


func scale(x: float, y: float) -> void:
	_xf = _xf * Transform2D(0.0, Vector2(x, y), 0.0, Vector2.ZERO)


func rotate(angle: float) -> void:
	_xf = _xf * Transform2D(angle, Vector2.ZERO)


func set_transform(a: float, b: float, c: float, d: float, e: float, f: float) -> void:
	_xf = Transform2D(Vector2(a, b), Vector2(c, d), Vector2(e, f))


func reset_transform() -> void:
	_xf = Transform2D.IDENTITY


func set_line_dash(segments: Array) -> void:
	line_dash = segments.duplicate()


# ---------------------------------------------------------------- paths

func begin_path() -> void:
	_paths = []


func move_to(x: float, y: float) -> void:
	_paths.append({"pts": PackedVector2Array([_xf * Vector2(x, y)]), "closed": false})


func line_to(x: float, y: float) -> void:
	if _paths.is_empty():
		move_to(x, y)
		return
	_paths[-1].pts.append(_xf * Vector2(x, y))


func close_path() -> void:
	if _paths.is_empty():
		return
	_paths[-1].closed = true
	var first: Vector2 = _paths[-1].pts[0]
	_paths.append({"pts": PackedVector2Array([first]), "closed": false})


func rect(x: float, y: float, w: float, h: float) -> void:
	move_to(x, y)
	line_to(x + w, y)
	line_to(x + w, y + h)
	line_to(x, y + h)
	close_path()


func arc(x: float, y: float, r: float, a0: float, a1: float, ccw := false) -> void:
	ellipse(x, y, r, r, 0.0, a0, a1, ccw)


func ellipse(x: float, y: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw := false) -> void:
	var sweep := a1 - a0
	if not ccw and sweep < 0:
		sweep = fposmod(sweep, TAU)
	elif ccw and sweep > 0:
		sweep = -fposmod(-sweep, TAU)
	if absf(a1 - a0) >= TAU:
		sweep = TAU * (-1.0 if ccw else 1.0)
	var steps := clampi(int(ceil(absf(sweep) / TAU * 48.0 * clampf(maxf(rx, ry) / 12.0, 0.5, 2.0))), 6, 128)
	var rotation := Transform2D(rot, Vector2(x, y))
	for i in steps + 1:
		var a := a0 + sweep * i / steps
		var p := rotation * Vector2(cos(a) * rx, sin(a) * ry)
		# Like the browser: with no current point the arc starts a subpath, otherwise a line joins it on
		if i == 0 and _paths.is_empty():
			move_to(p.x, p.y)
		else:
			line_to(p.x, p.y)


func quadratic_curve_to(cx: float, cy: float, x: float, y: float) -> void:
	var p0 := _last_local()
	for i in range(1, 13):
		var t := i / 12.0
		var p := p0.lerp(Vector2(cx, cy), t).lerp(Vector2(cx, cy).lerp(Vector2(x, y), t), t)
		line_to(p.x, p.y)


func bezier_curve_to(c1x: float, c1y: float, c2x: float, c2y: float, x: float, y: float) -> void:
	var p0 := _last_local()
	var c1 := Vector2(c1x, c1y)
	var c2 := Vector2(c2x, c2y)
	var p3 := Vector2(x, y)
	for i in range(1, 17):
		var t := i / 16.0
		var u := 1.0 - t
		var p := p0 * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + p3 * (t * t * t)
		line_to(p.x, p.y)


func _last_local() -> Vector2:
	if _paths.is_empty() or _paths[-1].pts.is_empty():
		return Vector2.ZERO
	return _xf.affine_inverse() * _paths[-1].pts[-1]


# ---------------------------------------------------------------- painting

func stroke() -> void:
	var w := line_width * _scale_factor()
	var c = stroke_style
	for p in _paths:
		var pts: PackedVector2Array = p.pts
		if pts.size() < 2:
			continue
		if p.closed:
			pts = pts.duplicate()
			pts.append(pts[0])
		for line in _clipped_lines(pts):
			_stroke_line(line, c, w)


func fill() -> void:
	for p in _paths:
		var pts: PackedVector2Array = p.pts
		if pts.size() < 3:
			continue
		for poly in _clipped_polys(pts):
			_fill_poly(poly, fill_style)


func clip() -> void:
	var poly := PackedVector2Array()
	for p in _paths:
		poly.append_array(p.pts)
	if poly.size() < 3:
		_clip = PackedVector2Array()
		return
	if _clip == null:
		_clip = poly
	else:
		var parts := Geometry2D.intersect_polygons(_clip, poly)
		_clip = parts[0] if parts.size() > 0 else PackedVector2Array()


func fill_rect(x: float, y: float, w: float, h: float) -> void:
	var saved := _paths
	begin_path()
	rect(x, y, w, h)
	fill()
	_paths = saved


func stroke_rect(x: float, y: float, w: float, h: float) -> void:
	var saved := _paths
	begin_path()
	rect(x, y, w, h)
	stroke()
	_paths = saved


## Clears to transparent black. Inside a SubViewport that clears every frame this only matters for partial clears;
## the area is painted with the viewport's clear color.
func clear_rect(x: float, y: float, w: float, h: float) -> void:
	if x <= 0 and y <= 0 and w >= size.x and h >= size.y and _xf == Transform2D.IDENTITY:
		item.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1))
		return
	var a := global_alpha
	global_alpha = 1.0
	var saved = fill_style
	fill_style = Color(0, 0, 0, 1)
	fill_rect(x, y, w, h)
	fill_style = saved
	global_alpha = a


# ---------------------------------------------------------------- text

func fill_text(text, x: float, y: float, _max_width = null) -> void:
	var s := str(text)
	var spec := _font_spec()
	var f: Font = spec[0]
	var px: int = spec[1]
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var ox := 0.0
	match text_align:
		"center":
			ox = -w / 2.0
		"right", "end":
			ox = -w
	var oy := 0.0
	match text_baseline:
		"top", "hanging":
			oy = f.get_ascent(px)
		"middle":
			oy = (f.get_ascent(px) - f.get_descent(px)) / 2.0
		"bottom", "ideographic":
			oy = -f.get_descent(px)
	var col := _color(fill_style)
	item.draw_set_transform_matrix(_xf)
	if shadow_blur > 0.0:
		var sc := _color(shadow_color)
		if sc.a > 0.0:
			sc.a *= 0.5
			item.draw_string_outline(f, Vector2(x + ox, y + oy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, int(clampf(shadow_blur / 3.0, 1.0, 6.0)), sc)
	item.draw_string(f, Vector2(x + ox, y + oy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	item.draw_set_transform_matrix(Transform2D.IDENTITY)


func stroke_text(text, x: float, y: float, _max_width = null) -> void:
	var s := str(text)
	var spec := _font_spec()
	item.draw_set_transform_matrix(_xf)
	item.draw_string_outline(spec[0], Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, spec[1], int(maxf(1.0, line_width)), _color(stroke_style))
	item.draw_set_transform_matrix(Transform2D.IDENTITY)


## { width } like the browser's TextMetrics
func measure_text(text) -> Dictionary:
	var spec := _font_spec()
	return {"width": (spec[0] as Font).get_string_size(str(text), HORIZONTAL_ALIGNMENT_LEFT, -1, spec[1]).x}


# ---------------------------------------------------------------- images

## draw_image(tex, dx, dy) / (tex, dx, dy, dw, dh) / (tex, sx, sy, sw, sh, dx, dy, dw, dh)
func draw_image(tex: Texture2D, a: float, b: float, c = null, d = null, e = null, f = null, g = null, h = null) -> void:
	if tex == null:
		return
	var src := Rect2(Vector2.ZERO, tex.get_size())
	var dst: Rect2
	if e != null:
		src = Rect2(a, b, c, d)
		dst = Rect2(e, f, g, h)
	elif c != null:
		dst = Rect2(a, b, c, d)
	else:
		dst = Rect2(a, b, tex.get_width(), tex.get_height())
	item.draw_set_transform_matrix(_xf)
	item.draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, global_alpha))
	item.draw_set_transform_matrix(Transform2D.IDENTITY)


# ---------------------------------------------------------------- gradients

class Gradient2D:
	extends RefCounted
	var kind := "linear"
	var p0 := Vector2.ZERO
	var p1 := Vector2.ZERO
	var r0 := 0.0
	var r1 := 0.0
	var stops: Array = [] # [[offset, Color]]

	func add_color_stop(offset: float, color) -> void:
		stops.append([clampf(offset, 0.0, 1.0), color if color is Color else _parse(color)])
		stops.sort_custom(func(x, y): return x[0] < y[0])

	func at(t: float) -> Color:
		if stops.is_empty():
			return Color(0, 0, 0, 0)
		t = clampf(t, 0.0, 1.0)
		if t <= stops[0][0]:
			return stops[0][1]
		for i in range(1, stops.size()):
			if t <= stops[i][0]:
				var span: float = stops[i][0] - stops[i - 1][0]
				var k: float = 0.0 if span <= 0.0 else (t - stops[i - 1][0]) / span
				return (stops[i - 1][1] as Color).lerp(stops[i][1], k)
		return stops[-1][1]

	static func _parse(c) -> Color:
		return load("res://src/view/canvas2d.gd").css(c)


func create_linear_gradient(x0: float, y0: float, x1: float, y1: float) -> Gradient2D:
	var g := Gradient2D.new()
	g.kind = "linear"
	g.p0 = _xf * Vector2(x0, y0)
	g.p1 = _xf * Vector2(x1, y1)
	return g


func create_radial_gradient(x0: float, y0: float, r0: float, x1: float, y1: float, r1: float) -> Gradient2D:
	var g := Gradient2D.new()
	g.kind = "radial"
	g.p0 = _xf * Vector2(x0, y0)
	g.p1 = _xf * Vector2(x1, y1)
	g.r0 = r0 * _scale_factor()
	g.r1 = r1 * _scale_factor()
	return g


# ---------------------------------------------------------------- colors

## A CSS color string (or Color) as a Color: #rgb, #rgba, #rrggbb, #rrggbbaa, rgb(), rgba(), hsl(), hsla(), names.
static func css(c) -> Color:
	if c is Color:
		return c
	var s := str(c).strip_edges().to_lower()
	if _colors.has(s):
		return _colors[s]
	var out := Color(0, 0, 0, 1)
	if s.begins_with("#"):
		out = Color.html(s)
	elif s.begins_with("rgb"):
		var v := _args(s)
		out = Color(v[0] / 255.0, v[1] / 255.0, v[2] / 255.0, v[3] if v.size() > 3 else 1.0)
	elif s.begins_with("hsl"):
		var v := _args(s)
		out = _hsl(v[0], v[1] / 100.0, v[2] / 100.0, v[3] if v.size() > 3 else 1.0)
	elif s == "transparent":
		out = Color(0, 0, 0, 0)
	elif Color.html_is_valid(s):
		out = Color.html(s)
	else:
		out = Color.from_string(s, Color(0, 0, 0, 1))
	_colors[s] = out
	return out


static func _args(s: String) -> Array:
	var inner := s.substr(s.find("(") + 1).trim_suffix(")")
	var out := []
	for part: String in inner.replace("/", ",").split(",", false):
		var p := part.strip_edges()
		out.append(p.trim_suffix("%").to_float() if p.ends_with("%") and out.size() == 3 else p.trim_suffix("%").trim_suffix("deg").to_float())
		if p.ends_with("%") and out.size() == 4:
			out[3] = out[3] / 100.0
	return out


static func _hsl(h: float, s: float, l: float, a: float) -> Color:
	h = fposmod(h, 360.0) / 360.0
	var q := l * (1.0 + s) if l < 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return Color(_hue(p, q, h + 1.0 / 3.0), _hue(p, q, h), _hue(p, q, h - 1.0 / 3.0), a)


static func _hue(p: float, q: float, t: float) -> float:
	t = fposmod(t, 1.0)
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0
	return p


func _color(style) -> Color:
	var c := css(style) if not (style is Gradient2D) else (style as Gradient2D).at(0.5)
	c.a *= global_alpha
	return c


# ---------------------------------------------------------------- internals

func _scale_factor() -> float:
	return sqrt(absf(_xf.determinant()))


func _font_spec() -> Array:
	if _font_specs.has(font):
		return _font_specs[font]
	# "28px \"Press Start 2P\", monospace" -> family + pixel size
	var px := 10
	var re := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)px\\s*(.*)")
	var m := re.search(font)
	var family := ""
	if m:
		px = int(round(m.get_string(1).to_float()))
		family = m.get_string(2)
	var path := DEFAULT_FONT
	for name in FONT_FILES:
		if family.to_lower().contains(name):
			path = FONT_FILES[name]
			break
	var spec := [_load_font(path), px]
	_font_specs[font] = spec
	return spec


static func _load_font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	var f: FontFile = load(path)
	f = f.duplicate()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.generate_mipmaps = false
	_fonts[path] = f
	return f


## The game's fonts with the crisp pixel settings, for UI code too
static func pixel_font(family := "press start 2p") -> Font:
	return _load_font(FONT_FILES.get(family.to_lower(), DEFAULT_FONT))


func _clipped_lines(pts: PackedVector2Array) -> Array:
	if _clip == null:
		return [pts]
	if (_clip as PackedVector2Array).size() < 3:
		return []
	return Geometry2D.intersect_polyline_with_polygon(pts, _clip)


func _clipped_polys(pts: PackedVector2Array) -> Array:
	if _clip == null:
		return [pts]
	if (_clip as PackedVector2Array).size() < 3:
		return []
	return Geometry2D.intersect_polygons(pts, _clip)


func _stroke_line(pts: PackedVector2Array, style, w: float) -> void:
	var col := _color(style)
	if col.a <= 0.0:
		return
	if not line_dash.is_empty():
		for seg in _dashed(pts):
			_raw_polyline(seg, col, w)
		return
	_raw_polyline(pts, col, w)


func _raw_polyline(pts: PackedVector2Array, col: Color, w: float) -> void:
	if shadow_blur > 0.0:
		var sc := _color(shadow_color)
		if sc.a > 0.0:
			sc.a *= 0.35
			item.draw_polyline(pts, sc, w + shadow_blur * 0.6 * _scale_factor(), true)
	item.draw_polyline(pts, col, w, antialiased)


func _dashed(pts: PackedVector2Array) -> Array:
	var out := []
	var pattern: Array = line_dash if line_dash.size() % 2 == 0 else line_dash + line_dash
	var k := _scale_factor()
	var idx := 0
	var left: float = float(pattern[0]) * k
	var on := true
	var cur := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var pos := 0.0
		while seg - pos > left:
			pos += left
			var p := a.lerp(b, pos / seg)
			if on:
				cur.append(p)
				out.append(cur)
			cur = PackedVector2Array([p])
			on = not on
			idx = (idx + 1) % pattern.size()
			left = float(pattern[idx]) * k
		left -= seg - pos
		if on:
			cur.append(b)
		else:
			cur = PackedVector2Array([b])
	if on and cur.size() > 1:
		out.append(cur)
	return out


func _fill_poly(poly: PackedVector2Array, style) -> void:
	if style is Gradient2D:
		_fill_gradient(poly, style)
		return
	var col := _color(style)
	if col.a <= 0.0:
		return
	if shadow_blur > 0.0:
		var sc := _color(shadow_color)
		if sc.a > 0.0:
			sc.a *= 0.3
			item.draw_polyline(_closed(poly), sc, shadow_blur * 0.8 * _scale_factor(), true)
	if Geometry2D.triangulate_polygon(poly).is_empty():
		return # degenerate (zero area or self-intersecting)
	item.draw_colored_polygon(poly, col)


func _fill_gradient(poly: PackedVector2Array, g: Gradient2D) -> void:
	if g.kind == "radial":
		var tex := _radial_texture(g)
		var r := g.r1
		item.draw_texture_rect(tex, Rect2(g.p1 - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, global_alpha))
		return
	if Geometry2D.triangulate_polygon(poly).is_empty():
		return
	var axis := g.p1 - g.p0
	var len2 := axis.length_squared()
	var colors := PackedColorArray()
	for p: Vector2 in poly:
		var t: float = 0.0 if len2 == 0.0 else (p - g.p0).dot(axis) / len2
		var c := g.at(t)
		c.a *= global_alpha
		colors.append(c)
	item.draw_polygon(poly, colors)


func _radial_texture(g: Gradient2D) -> Texture2D:
	var key := "%s|%s" % [g.r0 / maxf(g.r1, 0.001), str(g.stops)]
	if _radial_textures.has(key):
		return _radial_textures[key]
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array()
	grad.colors = PackedColorArray()
	var inner := g.r0 / maxf(g.r1, 0.001)
	for s in g.stops:
		grad.add_point(inner + (1.0 - inner) * float(s[0]), s[1])
	if grad.get_point_count() == 0:
		grad.add_point(0.0, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_radial_textures[key] = tex
	return tex


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out
