## The achievements list, K (achievements.js screenHtml; .ach-screen in style.css): over the view and the side
## column, lit in the floor's accent while it waits on you. The total and a meter on top, every badge by group
## (earned ones lit in their group's colour with the date, locked ones dimmed with what to do, progress bars for
## the counters), faint scanlines like the old screen it pretends to be. K or Esc closes it, the arrows scroll it.
extends "res://src/ui/widget.gd"

const Achievements = preload("res://src/rules/achievements.gd")

const OPEN_MS := 200.0
const NUDGE_MS := 350.0
const HEAD_H := 46.0
const FOOT_H := 30.0
const GOLD := Color("#ffd27a")

var list: Array = []
var count := {"earned": 0, "total": 0}
var accent := Css.ACCENT
var body: Body
var _open_at := -1e9
var _nudge_at := -1e9
static var _scan: ImageTexture


## The scrolling list of badges
class Body:
	extends "res://src/ui/widget.gd"
	var screen
	var scroll := 0.0
	var target := 0.0
	var content_h := 0.0
	var _from := 0.0
	var _anim_at := -1e9

	func _init() -> void:
		super()
		solid = true
		clip_contents = true

	func max_scroll() -> float:
		return maxf(0.0, content_h - size.y)

	## scrollBy({top, behavior: "smooth"})
	func scroll_by(dy: float) -> void:
		_from = scroll
		target = clampf(target + dy, 0.0, max_scroll())
		_anim_at = now_ms()

	func animating() -> bool:
		var p := (now_ms() - _anim_at) / 250.0
		if p >= 1.0:
			scroll = target
			return false
		scroll = lerpf(_from, target, 1.0 - pow(1.0 - p, 3.0))
		return true

	func _wheel(dy: float) -> bool:
		scroll_by(dy * 60.0)
		return true

	func paint() -> void:
		content_h = screen.paint_body(self, -scroll)
		if content_h > size.y:
			# a thin square scrollbar: #444 on black
			var track := Rect2(size.x - 6.0, 0, 6.0, size.y)
			draw_rect(track, Color.BLACK)
			var h := maxf(20.0, size.y * size.y / content_h)
			var y := (size.y - h) * (scroll / max_scroll()) if max_scroll() > 0.0 else 0.0
			draw_rect(Rect2(track.position.x, y, 6.0, h), Color("#444444"))


func _init() -> void:
	super()
	solid = true
	body = Body.new()
	body.screen = self
	add_child(body)
	visible = false


func _ready() -> void:
	body.ui = ui


func open(entries: Array, totals: Dictionary, accent_color: Color) -> void:
	list = entries
	count = totals
	accent = accent_color
	_open_at = now_ms()
	_nudge_at = -1e9
	visible = true
	_place_body()
	queue_redraw()
	body.queue_redraw()


## A new unlock while it's open: repaint, keeping the scroll
func refresh(entries: Array, totals: Dictionary) -> void:
	list = entries
	count = totals
	queue_redraw()
	body.queue_redraw()


func close() -> void:
	visible = false


func nudge() -> void:
	_nudge_at = now_ms()


func scroll_by(dy: float) -> void:
	body.scroll_by(dy)


func animating() -> bool:
	if not visible:
		return false
	if body.animating():
		body.queue_redraw()
	return true


func _place_body() -> void:
	body.position = Vector2(2, 2 + HEAD_H)
	body.size = Vector2(size.x - 4.0, size.y - 4.0 - HEAD_H - FOOT_H)


func _notification(what: int) -> void:
	super(what)
	if what == NOTIFICATION_RESIZED and body != null:
		_place_body()


static func scanlines() -> ImageTexture:
	if _scan == null:
		var img := Image.create(1, 3, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color(1, 1, 1, 0.025))
		_scan = ImageTexture.create_from_image(img)
	return _scan


func paint() -> void:
	var t := now_ms()
	var box := Rect2(Vector2.ZERO, size)
	var age := t - _open_at
	var sy := 1.0
	var a := 1.0
	if age < OPEN_MS:
		var k := Css.steps(age / OPEN_MS, 4)
		sy = lerpf(0.08, 1.0, k)
		a = lerpf(0.5, 1.0, k)
	var n := Css.nudge(t - _nudge_at, NUDGE_MS, 6.0)
	var glow := 18.0 + 12.0 * Css.pulse(age - OPEN_MS, 1400.0)
	if t - _nudge_at < NUDGE_MS:
		glow = lerpf(18.0, 40.0, n[1])
	var c := box.get_center()
	draw_set_transform(Vector2(n[0], c.y - c.y * sy), 0.0, Vector2(1.0, sy))
	body.position.x = 2.0 + n[0]
	Css.glow(self, box, Css.alpha(accent, a), glow, 4.0)
	draw_rect(box.grow(4.0), Css.alpha(Color.BLACK, a))
	draw_rect(box, Css.alpha(Color.BLACK, a))
	draw_texture_rect(scanlines(), box.grow(-2.0), true)
	Css.frame(self, box, Css.alpha(accent, a), 2.0)
	_head(Rect2(2, 2, size.x - 4.0, HEAD_H), a)
	_foot(Rect2(2, size.y - 2.0 - FOOT_H, size.x - 4.0, FOOT_H), a)
	draw_set_transform(Vector2.ZERO)
	body.visible = age >= OPEN_MS * 0.75


func _head(r: Rect2, a: float) -> void:
	var font := Css.ps()
	var mid := r.position.y + 10.0 + 12.5
	var x := r.position.x + 12.0
	Css.glyph(self, Achievements.GLYPHS["trophy"], Vector2(x, mid - 7.0).floor(), 14.0, Css.alpha(GOLD, a))
	x += 22.0
	Css.glow(self, Rect2(x, mid - 4.0, Css.width(font, 11, "ACHIEVEMENTS"), 8.0), Color(1.0, 0.82, 0.48, 0.2 * a), 10.0)
	x += Css.text(self, font, 11, x, mid - 5.5, "ACHIEVEMENTS", Css.alpha(GOLD, a), 11) + 14.0
	x += Css.text(self, font, 14, x, mid - 9.0, str(count.earned), Css.alpha(GOLD, a), 14)
	x += Css.text(self, font, 10, x, mid - 3.0, "/%d" % count.total, Css.alpha(Css.DIM, a), 10) + 14.0
	# the buttons on the right, the meter fills what's between
	var close_w := 2.0 + 3.0 + 18.0 + 7.0 + Css.width(font, 8, "CLOSE") + 7.0 + 2.0
	var esc_w := 2.0 + 3.0 + Css.width(font, 8, "ESC") + 8.0 + 3.0 + 2.0
	var bx := r.end.x - 10.0 - esc_w - 4.0 - close_w
	var meter := Rect2(x, mid - 6.0, maxf(40.0, bx - 14.0 - x), 12.0)
	var pct := float(count.earned) / maxf(1.0, float(count.total))
	Css.seg_bar(self, meter, pct, GOLD, {"seg": 9.0, "alpha": a})
	add_hit(meter, {"id": "meter", "tip": "%d%% EARNED" % J_round(pct * 100.0)})
	_close_button(Rect2(bx, mid - 12.5, close_w, 25.0), "k", "K", "CLOSE", a)
	_close_button(Rect2(bx + close_w + 4.0, mid - 12.5, esc_w, 25.0), "escape", "ESC", "", a)
	draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2.0), Css.alpha(Css.FAINT, a))


static func J_round(x: float) -> int:
	return int(floor(x + 0.5))


func _close_button(r: Rect2, key: String, cap: String, label: String, a: float) -> void:
	var hot := hover_id == "close:" + key
	draw_rect(r, Css.alpha(Color.BLACK, a))
	Css.frame(self, r, Css.alpha(Css.INK if hot else Css.FAINT, a), 2.0)
	var k := Css.keycap(self, Vector2(r.position.x + 5.0, r.get_center().y - 7.5), cap, Css.alpha(accent, a), Css.alpha(Color.BLACK, a), {"size": 8})
	if label != "":
		Css.text(self, Css.ps(), 8, k.end.x + 7.0, r.get_center().y - 4.0, label, Css.alpha(Css.INK, a), 8)
	add_hit(r, {"id": "close:" + key, "key": key, "close": true})


func _foot(r: Rect2, a: float) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1.0)), Css.alpha(Css.FAINT, a))
	var y := r.position.y + 1.0 + 6.0
	Css.text(self, Css.vt(), 16, r.position.x + 12.0, y, "EARNED ONCE, KEPT FOR GOOD: ACROSS EVERY RUN, EVEN AFTER DEATH.", Css.alpha(Css.DIM, a), 16)
	var font := Css.ps()
	var x := r.end.x - 12.0 - Css.width(font, 7, " SCROLL") - 2.0 * 16.0 - 4.0
	for icon in ["up", "down"]:
		var k := Rect2(x, y + 1.0, 15, 14)
		draw_rect(k, Css.alpha(Css.FAINT, a))
		Css.icon(self, icon, (k.get_center() - Vector2(3.5, 3.5)).floor(), 7.0, Css.alpha(Css.INK, a))
		x += 19.0
	Css.text(self, font, 7, x - 2.0, y + 4.0, " SCROLL", Css.alpha(Css.DIM, a), 7)


## Paints every group of badges into `b` (the body), shifted by `dy`; returns the content's height
func paint_body(b: Control, dy: float) -> float:
	var w := b.size.x - 24.0
	var cols := maxi(1, floori((w + 6.0) / (240.0 + 6.0)))
	var col_w := (w - 6.0 * (cols - 1)) / cols
	var y := 2.0 + dy
	for gid in Achievements.GROUPS:
		var info: Dictionary = Achievements.GROUPS[gid]
		var items := list.filter(func(x): return x.group == gid)
		if items.is_empty():
			continue
		var g := Css.css(info.color)
		var got := items.filter(func(x): return x.earned).size()
		y += 12.0
		var x := 12.0
		x += Css.text(b, Css.ps(), 8, x, y, info.label, g, 8) + 8.0
		var tally := "%d/%d" % [got, items.size()]
		x += Css.text(b, Css.ps(), 7, x, y + 1.0, tally, Css.DIM, 7) + 8.0
		b.draw_rect(Rect2(x, y + 4.0, 12.0 + w - x, 1.0), Css.alpha(g, 0.3))
		y += 8.0 + 6.0
		for i in range(0, items.size(), cols):
			var row := items.slice(i, i + cols)
			var row_h := 0.0
			for a in row:
				row_h = maxf(row_h, _badge_h(a, col_w))
			for j in row.size():
				_badge(b, Rect2(12.0 + j * (col_w + 6.0), y, col_w, row_h), row[j])
			y += row_h + 6.0
		y -= 6.0
	return y + 10.0 - dy


func _text_w(w: float) -> float:
	return w - 6.0 - 30.0 - 9.0 - 8.0


func _badge_h(a: Dictionary, w: float) -> float:
	var tw := _text_w(w)
	var h := Css.wrap(Css.ps(), 8, a.name, tw).size() * 10.8 + 3.0 + Css.wrap(Css.vt(), 16, a.desc, tw).size() * 15.2
	if a.earned or a.progress != null or a.get("secret", false):
		h += 5.0 + 6.0
	return 6.0 + maxf(30.0, h) + 6.0


func _badge(b: Control, r: Rect2, a: Dictionary) -> void:
	var g := Css.css(Achievements.color_of(a))
	var earned: bool = a.earned
	if earned:
		b.draw_rect(r, Css.mix(g, 0.08))
		Css.glow(b, r.grow(-6.0), Css.alpha(g, 0.12), 8.0)
		Css.frame(b, r, g, 1.0)
	else:
		b.draw_rect(r, Color("#050505"))
		Css.dashed_frame(b, r, Color("#2c2c2c"))
	var ico := Rect2(r.position.x + 6.0, r.position.y + 6.0, 30, 30)
	if earned:
		Css.glow(b, ico, Css.alpha(g, 0.6), 8.0)
		b.draw_rect(ico, Css.mix(g, 0.2))
		Css.frame(b, ico, g, 1.0)
	else:
		b.draw_rect(ico, Color("#0c0c0c"))
		Css.frame(b, ico, Color("#2c2c2c"), 1.0)
	Css.glyph(b, Achievements.GLYPHS.get(Achievements.glyph_of(a), Achievements.GLYPHS["secret"]), ico.get_center() - Vector2(10.5, 10.5), 21.0, g if earned else Color("#5a5a5a"))
	var x := ico.end.x + 9.0
	var tw := _text_w(r.size.x)
	var y := r.position.y + 6.0
	var secret: bool = a.get("secret", false) and not earned
	for l in Css.wrap(Css.ps(), 8, a.name, tw):
		if secret:
			var cx := x
			for ch in l:
				cx += Css.text(b, Css.ps(), 8, cx, y, ch, Color("#8a8a8a"), 10.8) + 2.4
		else:
			Css.text(b, Css.ps(), 8, x, y, l, g if earned else Color("#8a8a8a"), 10.8)
		y += 10.8
	y += 3.0
	for l in Css.wrap(Css.vt(), 16, a.desc, tw):
		Css.text(b, Css.vt(), 16, x, y, l, Css.INK if earned else Color("#6a6a6a"), 15.2)
		y += 15.2
	y += 5.0
	var meta_c := Css.mix(g, 0.75) if earned else Color("#4a4a4a")
	if earned:
		Css.text(b, Css.ps(), 6, x, y, "EARNED %s" % Achievements.fmt_date(a.at), meta_c, 6)
	elif a.progress != null:
		var bar := Rect2(x, y, 64, 6)
		Css.frame(b, bar, Color("#555555"), 1.0)
		var fill := roundf(60.0 * float(a.progress.n) / maxf(1.0, float(a.progress.goal)))
		if fill > 0.0:
			b.draw_rect(Rect2(x + 2.0, y + 2.0, fill, 2.0), Css.alpha(g, 0.8))
		Css.text(b, Css.ps(), 6, x + 70.0, y, "%d/%d" % [a.progress.n, a.progress.goal], meta_c, 6)
	elif a.get("secret", false):
		Css.text(b, Css.ps(), 6, x, y, "SECRET", meta_c, 6)
	var tip := ""
	if earned:
		tip = "%s · %s · EARNED %s" % [a.name, a.desc, Achievements.fmt_date(a.at)]
	elif a.get("secret", false):
		tip = "A SECRET · KEEP PLAYING."
	else:
		tip = "%s · %s%s" % [a.name, a.desc, " · %d OF %d SO FAR" % [a.progress.n, a.progress.goal] if a.progress != null else ""]
	if r.end.y > 0.0 and r.position.y < b.size.y:
		b.add_hit(r, {"id": "badge:" + a.id, "tip": tip})


func _pressed(h: Dictionary) -> void:
	if h.get("close", false) and ui != null:
		ui.press_key(h.key)
