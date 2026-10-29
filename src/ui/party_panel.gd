## The party (renderParty in game.js; .party / .prow in style.css): two compact lines per adventurer, one per
## monster ally. Health is a segmented bar whose length and colour say how hurt someone is (a word once it matters,
## death-save boxes when down), armor a shield, spell slots pips coloured by circle, conditions icon chips. The
## member choosing a move glows with a ▶; the one a menu is pointing at lights up. Hover anything for the numbers.
extends "res://src/ui/widget.gd"

const FONT := 9
const SMALL := 16 # VT323 under the names and bars
const CHIP_FONT := 7

var rows: Array = []
var accent := Css.ACCENT
## The height the rows need (main sizes the side column's log from it)
var natural_h := 0.0
var _t := 0.0


func set_rows(r: Array, accent_color: Color) -> void:
	rows = r
	accent = accent_color
	natural_h = measure()
	queue_redraw()


## Blinking rows (dying) repaint every frame
func animating() -> bool:
	return rows.any(func(r): return r.get("dying", false))


func _ac_w(r: Dictionary) -> float:
	return 14.0 + 4.0 + Css.width(Css.ps(), FONT, r.ac)


func _human_h(r: Dictionary, w: float) -> float:
	return 1.0 + 4.0 + 28.0 + 3.0 + _second_line_h(r, w) + 4.0 + 1.0


func _second_line_h(r: Dictionary, w: float) -> float:
	var cols := _cols(r, w)
	var pw_h: float = _pips_layout(r.pw, cols.c1).h if r.pw != null else 0.0
	var chips_h: float = _chips_layout(r.chips, cols.c2 + 8.0 + cols.ac, true).h
	return maxf(12.0, maxf(pw_h, chips_h))


func measure() -> float:
	var h := 0.0
	for r in rows:
		match r.kind:
			"div":
				h += 4.0 + 8.0 + 1.0
			"monster":
				h += 24.0
			_:
				h += _human_h(r, size.x)
	return h + 4.0 + 2.0 # padding-bottom 4, the 2px rule


func _cols(r: Dictionary, w: float) -> Dictionary:
	var ac := _ac_w(r)
	var cw := w - 10.0
	var c := (cw - 14.0 - 24.0 - ac) / 2.0
	return {"x0": 5.0, "c1": c, "c2": c, "ac": ac}


func paint() -> void:
	_t = now_ms()
	natural_h = measure()
	var y := 0.0
	for r in rows:
		match r.kind:
			"div":
				_divider(r, y)
				y += 13.0
			"monster":
				_ally_row(r, y)
				y += 24.0
			_:
				var h := _human_h(r, size.x)
				_human_row(r, y, h)
				y += h
	draw_rect(Rect2(0, y + 4.0, size.x, 2.0), Css.FAINT)
	add_hit(Rect2(0, 0, size.x, y + 6.0), {"id": "#party", "panel": "#party"})
	# the panel's region goes under the rows' own (a tooltip on a chip beats the row's)
	hits.push_front(hits.pop_back())


## "ALLIES 1/3", then a dashed line: how many monsters can still join, right where they'd go
func _divider(r: Dictionary, y: float) -> void:
	var font := Css.ps()
	var top := y + 4.0
	var x := Css.text(self, font, 7, 0, top, "ALLIES ", Css.DIM, 8)
	var n := "%d/%d" % [r.allies, r.max]
	x += Css.text(self, font, 7, x, top, n, accent if r.full else Css.INK, 8)
	Css.dashed(self, x + 6.0, size.x, top + 4.0, Css.FAINT)
	add_hit(Rect2(0, top, size.x, 8), {"id": "div", "tip": r.tip})


func _row_box(r: Dictionary, box: Rect2) -> void:
	if r.picked:
		draw_rect(box, Css.mix(accent, 0.16))
		Css.frame(self, box, Css.mix(accent, 0.6), 1.0)
	elif r.acting:
		Css.glow(self, box, Css.alpha(accent, 0.6), 10.0)
		draw_rect(box, Css.BG)
		Css.frame(self, box, accent, 1.0)
	else:
		draw_rect(Rect2(box.position.x, box.end.y - 1.0, box.size.x, 1.0), Color("#1a1a1a"))
	if r.title != "":
		add_hit(box, {"id": "row:" + r.num + r.name, "tip": r.title})
	if r.dying:
		add_hit(box, {"id": "dying:" + r.name, "panel": "#party .dying"})


func _human_row(r: Dictionary, y: float, h: float) -> void:
	var box := Rect2(0, y, size.x, h)
	var fade := 0.5 if r.dead else 1.0
	_row_box(r, box)
	var cols := _cols(r, size.x)
	var x0: float = cols.x0
	var top := y + 5.0
	var font := Css.ps()
	# number (▶ while this member chooses)
	Css.text(self, font, FONT, x0, top, r.num, Css.alpha(accent if r.acting else Css.DIM, fade), FONT)
	# who: name (struck through when dead, red while dying) and class · level
	var wx := x0 + 14.0 + 8.0
	var name_color := Css.WARN if r.dying else (Css.css(r.ink) if r.ink != "" else Css.INK)
	_name(r, Vector2(wx, top), cols.c1, Css.alpha(name_color, fade))
	_clip_text(Css.vt(), SMALL, wx, top + 11.0, r.sub, Css.alpha(Css.DIM, fade), cols.c1, SMALL)
	# health
	var hx: float = wx + cols.c1 + 8.0
	_health(r, Rect2(hx, top, cols.c2, 28.0), fade)
	# armor
	var ax: float = hx + cols.c2 + 8.0
	_armor(r, Vector2(ax, top + 14.0), fade)
	# second line: pips, then the chips
	var y2 := top + 28.0 + 3.0
	if r.pw != null:
		_pips(r.pw, Vector2(wx, y2), cols.c1, fade)
	_chips(r.chips, Vector2(hx, y2), cols.c2 + 8.0 + cols.ac, true, fade)


func _ally_row(r: Dictionary, y: float) -> void:
	var box := Rect2(0, y, size.x, 24.0)
	var fade := 0.5 if r.dead else 1.0
	_row_box(r, box)
	var font := Css.ps()
	var mid := y + 12.0
	var x0 := 5.0
	Css.text(self, font, FONT, x0, mid - FONT / 2.0, r.num, Css.alpha(Css.DIM, fade), FONT)
	# columns: 14 | 0.8fr | 1fr | auto | auto
	var ac := _ac_w(r)
	var chips_w: float = _chips_layout(r.chips, 1e6, false).w
	var free := size.x - 10.0 - 14.0 - 32.0 - ac - chips_w
	var who_w := free * 0.8 / 1.8
	var hp_w := free - who_w
	var wx := x0 + 22.0
	var name_color := Css.WARN if r.dying else (Css.css(r.ink) if r.ink != "" else Css.INK)
	_name(r, Vector2(wx, mid - FONT / 2.0), who_w, Css.alpha(name_color, fade))
	add_hit(Rect2(wx, y, who_w, 24.0), {"id": "name:" + r.name, "tip": r.name_tip})
	# health: the bar fills what's left of its cell beside the numbers
	var hx := wx + who_w + 8.0
	var hp: Dictionary = r.hp
	var words_w := _hp_words_w(hp)
	var label_w := maxf(40.0, words_w)
	var bar_w := maxf(24.0, hp_w - 6.0 - label_w)
	var blink := Css.blink(_t) if r.dying else 1.0
	Css.seg_bar(self, Rect2(hx, mid - 5.0, bar_w, 10.0), hp.pct, Css.css(hp.color), {"alpha": fade * blink, "border": Css.WARN if r.dying else Color("#555555")})
	var tx := hx + bar_w + 6.0 + label_w - words_w
	_hp_words(hp, Vector2(tx, mid - 8.0), fade, blink)
	add_hit(Rect2(hx, y, hp_w, 24.0), {"id": "hp:" + r.name, "tip": hp.tip})
	var cx := hx + hp_w + 8.0
	_chips(r.chips, Vector2(cx, mid - 7.0), chips_w + 1.0, false, fade)
	_armor(r, Vector2(cx + chips_w + 8.0, mid), fade)


func _name(r: Dictionary, pos: Vector2, w: float, color: Color) -> void:
	var x := pos.x
	if r.skull:
		Css.icon(self, "skull", Vector2(x, pos.y + 1.0), 7.0, Css.DIM)
		x += 12.0
	var shown := _clip_text(Css.ps(), FONT, x, pos.y, r.name, color, w - (x - pos.x), FONT)
	if r.dead:
		draw_rect(Rect2(x, pos.y + 4.0, shown, 1.0), color)


## Text clipped at `w` pixels (overflow: hidden): drawn glyph by glyph while it fits. Returns the width drawn.
func _clip_text(font: Font, fsize: int, x: float, top: float, s: String, color: Color, w: float, h: float) -> float:
	var shown := s
	while shown != "" and Css.width(font, fsize, shown) > w:
		shown = shown.left(shown.length() - 1)
	return Css.text(self, font, fsize, x, top, shown, color, h)


## How wide "12/12 HURT" (and the death-save boxes) is
func _hp_words_w(hp: Dictionary) -> float:
	var w := Css.width(Css.vt(), SMALL, _hp_text(hp))
	if hp.word != "":
		w += (4.0 if hp.text != "" else 0.0) + Css.width(Css.ps(), 7, hp.word)
	if hp.saves != null:
		w += 6.0 + 6.0 * 9.0 + 4.0
	return w


func _hp_text(hp: Dictionary) -> String:
	return hp.text + (" " if hp.text != "" and hp.word != "" else "")


## "12/12", then the word (HURT, CRITICAL, DYING...) in small caps of its colour, then the death-save boxes
func _hp_words(hp: Dictionary, pos: Vector2, fade: float, blink: float) -> void:
	var x := pos.x
	var st := Css.css(hp.color)
	if hp.text != "":
		x += Css.text(self, Css.vt(), SMALL, x, pos.y, _hp_text(hp), Css.alpha(Css.DIM, fade), SMALL)
	if hp.word != "":
		if hp.text != "":
			x += 4.0
		x += Css.text(self, Css.ps(), 7, x, pos.y + 4.0, hp.word, Css.alpha(st, fade * blink), 7)
	if hp.saves != null:
		x += 6.0
		var sv: Dictionary = hp.saves
		var start := x
		for j in 6:
			var ok := j < 3
			var on: bool = (j < sv.s) if ok else (j - 3 < sv.f)
			var c := Color("#6bd36b") if ok else Css.WARN
			var b := Rect2(x, pos.y + 4.0, 7, 7)
			if on:
				draw_rect(b, Css.alpha(c, fade))
			Css.frame(self, b, Css.alpha(c, fade), 1.0)
			x += 9.0 + (4.0 if j == 2 else 0.0)
		add_hit(Rect2(start - 1.0, pos.y + 2.0, x - start, 11), {"id": "saves:%s" % hp.tip, "tip": sv.tip})


func _health(r: Dictionary, cell: Rect2, fade: float) -> void:
	var hp: Dictionary = r.hp
	var blink := Css.blink(_t) if r.dying else 1.0
	Css.seg_bar(self, Rect2(cell.position, Vector2(cell.size.x, 10.0)), hp.pct, Css.css(hp.color), {"alpha": fade * blink, "border": Css.WARN if r.dying else Color("#555555")})
	add_hit(cell, {"id": "hp:" + r.name, "tip": hp.tip})
	_hp_words(hp, cell.position + Vector2(0, 12.0), fade, blink)


func _armor(r: Dictionary, left_mid: Vector2, fade: float) -> void:
	Css.icon(self, "shield", Vector2(left_mid.x, left_mid.y - 7.0).floor(), 14.0, Css.alpha(Color("#9fb0c0"), fade))
	var w := Css.text(self, Css.ps(), FONT, left_mid.x + 18.0, left_mid.y - FONT / 2.0, r.ac, Css.alpha(Color("#c8d2dc"), fade), FONT)
	add_hit(Rect2(left_mid.x, left_mid.y - 8.0, 18.0 + w, 16.0), {"id": "ac:" + r.name, "tip": r.ac_tip})


## Pips: one per slot, coloured by circle; lit ones are left. Groups wrap within the cell.
func _pips_layout(pw: Dictionary, w: float) -> Dictionary:
	var groups := []
	if pw.kind == "skills":
		groups = [{"color": pw.color, "pips": pw.pips, "sq": true}]
	else:
		for g in pw.groups:
			groups.append({"color": g.color, "pips": g.pips, "sq": false})
	var x := 0.0
	var y := 0.0
	var line_h := 10.0
	var placed := []
	for g in groups:
		var pw_one := 9.0 if g.sq else 6.0
		var gw: float = g.pips.size() * (pw_one + 2.0) - 2.0
		if x > 0.0 and x + gw > w:
			x = 0.0
			y += line_h + 3.0
		placed.append({"g": g, "x": x, "y": y})
		x += gw + 7.0
	return {"placed": placed, "h": y + line_h, "w": w}


func _pips(pw: Dictionary, pos: Vector2, w: float, fade: float) -> void:
	var L := _pips_layout(pw, w)
	for p in L.placed:
		var g: Dictionary = p.g
		var c := Css.css(g.color)
		var x: float = pos.x + p.x
		var sz := Vector2(9, 9) if g.sq else Vector2(6, 10)
		for on in g.pips:
			var b := Rect2(Vector2(x, pos.y + p.y + (10.0 - sz.y) / 2.0), sz)
			if on:
				Css.glow(self, b, Css.alpha(c, fade), 4.0)
				draw_rect(b, Css.alpha(c, fade))
			else:
				Css.frame(self, b, Css.alpha(c, 0.55 * fade), 1.0)
			x += sz.x + 2.0
	add_hit(Rect2(pos, Vector2(w, L.h)), {"id": "pips:%s" % pw.tip, "tip": pw.tip})


## Chips: a pixel icon and a word in a thin frame of the chip's colour
func _chip_w(c: Dictionary) -> float:
	return 1.0 + 4.0 + 7.0 + 4.0 + Css.width(Css.ps(), CHIP_FONT, c.word) + 4.0 + 1.0


func _chips_layout(chips: Array, w: float, wrap: bool) -> Dictionary:
	var x := 0.0
	var y := 0.0
	var placed := []
	var widest := 0.0
	for c in chips:
		var cw := _chip_w(c)
		if wrap and x > 0.0 and x + cw > w:
			x = 0.0
			y += 14.0 + 4.0
		placed.append({"c": c, "x": x, "y": y})
		x += cw + 4.0
		widest = maxf(widest, x - 4.0)
	return {"placed": placed, "h": (y + 14.0) if not chips.is_empty() else 0.0, "w": widest}


func _chips(chips: Array, pos: Vector2, w: float, wrap: bool, fade: float) -> void:
	var L := _chips_layout(chips, w, wrap)
	for p in L.placed:
		var c: Dictionary = p.c
		var col := Css.css(c.color)
		var b := Rect2(pos + Vector2(p.x, p.y), Vector2(_chip_w(c), 14.0))
		if b.end.x > pos.x + w + 0.5 and not wrap:
			break
		draw_rect(b, Css.alpha(Css.mix(col, 0.12), fade))
		Css.frame(self, b, Css.alpha(col, fade), 1.0)
		Css.icon(self, c.icon, b.position + Vector2(5, 4), 7.0, Css.alpha(col, fade))
		Css.text(self, Css.ps(), CHIP_FONT, b.position.x + 16.0, b.position.y + 4.0, c.word, Css.alpha(col, fade), 7)
		add_hit(b, {"id": "chip:%s:%s" % [c.word, c.tip], "tip": c.tip})
