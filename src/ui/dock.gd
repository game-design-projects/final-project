## The command dock under the view (renderDock, menuHtml, cmd in game.js; .dock, .cmd, .opt, .menu, .say in
## style.css): every command as a keycap button you can press or click, the menus with their keyboard highlight,
## the talk box (label, caret, the text field, HOLD TO SPEAK) and the hint line. While the game waits on you it
## lights up in the floor's accent and glows; a key it doesn't take shakes it.
extends "res://src/ui/widget.gd"

const DockModel = preload("res://src/ui/dock_model.gd")
const Status = preload("res://src/rules/status.gd")

const BORDER := 2.0
const PAD := 8.0 # .dock padding: 8px 8px 4px
const PAD_BOTTOM := 4.0
const MIN_H := 80.0
const FONT := 9
const KBD := 8
const SUB := 15 # .cmd .lbl small: 15px VT323
const HINT := 18
const NUDGE_MS := 350.0

var model: Dictionary = DockModel.title()
var accent := Css.ACCENT
## The hint line: what the hovered (or highlighted) command does
var hint_text := ""
## The talk box (askText): its label, whether it takes a number, whether the mic shows
var input_open := false
var input_label := ""
var numeric := false
var mic_shown := false
var listening := false
var line_edit: LineEdit
var natural_h := MIN_H
var _items: Array = []
var _nudge_at := -1e9
var _t := 0.0


func _init() -> void:
	super()
	solid = true
	line_edit = LineEdit.new()
	line_edit.max_length = 240
	line_edit.visible = false
	line_edit.caret_blink = true
	line_edit.context_menu_enabled = false
	line_edit.select_all_on_focus = false
	line_edit.add_theme_font_override("font", Css.vt())
	line_edit.add_theme_font_size_override("font_size", 22)
	line_edit.add_theme_color_override("font_color", Css.YOU)
	line_edit.add_theme_color_override("caret_color", Css.YOU)
	line_edit.add_theme_color_override("selection_color", Css.alpha(Css.YOU, 0.3))
	line_edit.add_theme_color_override("font_selected_color", Css.INK)
	line_edit.add_theme_constant_override("caret_width", 2)
	add_child(line_edit)
	_style_input()


func _style_input() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Css.BG
	sb.border_width_bottom = 2
	sb.border_color = accent
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	line_edit.add_theme_stylebox_override("normal", sb)
	line_edit.add_theme_stylebox_override("focus", sb)
	line_edit.add_theme_stylebox_override("read_only", sb)


func set_model(m: Dictionary, accent_color: Color) -> void:
	model = m
	if accent_color != accent:
		accent = accent_color
		_style_input()
	if not model.waiting:
		_nudge_at = -1e9
	hint_text = model.hint
	_relayout()


func set_input(open: bool, label := "", is_numeric := false, mic := false) -> void:
	input_open = open
	input_label = label
	numeric = is_numeric
	mic_shown = mic and open and not is_numeric
	line_edit.visible = open
	if not open:
		line_edit.text = ""
	_relayout()


func nudge() -> void:
	_nudge_at = now_ms()


func animating() -> bool:
	return model.waiting or now_ms() - _nudge_at < NUDGE_MS or _has_dots() or _has_guide() or listening


func _has_dots() -> bool:
	for b in model.blocks:
		if b.type == "wait" and b.dots:
			return true
	return false


func _has_guide() -> bool:
	for it in _items:
		if it.kind == "cmd" and it.c.cls.has("guide"):
			return true
	return false


func _relayout() -> void:
	var L := _layout(size.x)
	_items = L.items
	natural_h = maxf(MIN_H, L.h)
	queue_redraw()
	retrack()


func _notification(what: int) -> void:
	super(what)
	if what == NOTIFICATION_RESIZED:
		_relayout()


# ---------------------------------------------------------------- layout: the model as boxes

## A keycap's size: font 8px, min-width 18, padding 4px 4px 3px (an icon is 7px)
static func kbd_size(cap: String, is_icon: bool, min_w := 18.0) -> Vector2:
	return Css.keycap_size(cap, KBD, is_icon, min_w)


## The size of a .cmd button (before the row stretches it)
func _cmd_size(c: Dictionary, pad_cmd := false) -> Vector2:
	var k := kbd_size(c.cap, c.cap_icon)
	if pad_cmd:
		return Vector2(2.0 + 3.0 + k.x + 3.0 + 2.0, 2.0 + 3.0 + k.y + 3.0 + 2.0)
	var label: String = ("> " if c.cls.has("on") else "") + c.label
	var lw := Css.width(Css.ps(), FONT, label) if c.label != "" else 0.0
	var lh := float(FONT)
	if c.sub != "":
		lw = maxf(lw, Css.width(Css.vt(), SUB, c.sub))
		lh = FONT + 3.0 + SUB
	var w := 2.0 + 4.0 + k.x + (7.0 + lw if c.label != "" else 0.0) + 7.0 + 2.0
	var h := maxf(30.0, 2.0 + 4.0 + maxf(k.y, lh) + 4.0 + 2.0)
	return Vector2(w, h)


## The parts of a .how hint ("↑ ↓ CHOOSE ENTER PICK"): [{kind, w, ...}]
func _how_size(parts: Array) -> float:
	var w := 0.0
	for p in parts:
		if p.has("text"):
			w += Css.width(Css.ps(), KBD, p.text)
		elif p.has("kbd_icon"):
			w += kbd_size(p.kbd_icon, true, 0.0).x
		else:
			w += kbd_size(p.kbd, false, 0.0).x
		w += 4.0
	return w - 4.0


func _layout(w: float) -> Dictionary:
	var items := []
	var x0 := BORDER + PAD
	var inner := w - 2.0 * (BORDER + PAD)
	var y := BORDER + PAD
	# The talk box comes first: its label on a line of its own, then the caret, the field and the mic
	if input_open:
		var lines := Css.wrap(Css.ps(), 10, input_label, inner)
		for l in lines:
			items.append({"kind": "text", "rect": Rect2(x0, y, inner, 15), "text": l, "size": 10, "color": "accent"})
			y += 15.0
		y += 8.0
		var row_h := 28.0
		items.append({"kind": "text", "rect": Rect2(x0, y, 9, row_h), "text": ">", "size": FONT, "color": "you"})
		var mic_w := 2.0 + 8.0 + 8.0 + 6.0 + Css.width(Css.ps(), FONT, "HOLD TO SPEAK") + 8.0 + 2.0
		var field_x := x0 + 9.0 + 8.0
		var field_w := inner - 9.0 - 8.0 - ((8.0 + mic_w) if mic_shown else 0.0)
		items.append({"kind": "field", "rect": Rect2(field_x, y, field_w, row_h)})
		if mic_shown:
			items.append({"kind": "mic", "rect": Rect2(field_x + field_w + 8.0, y + 1.0, mic_w, 26.0)})
		y += row_h + 8.0
	# The commands
	var first_row := true
	for b in model.blocks:
		match b.type:
			"wait":
				y += 4.0
				items.append({"kind": "wait", "rect": Rect2(x0, y, inner, 11), "b": b})
				y += 11.0 + 6.0
			"ask":
				var r := _ask(b, x0, y, inner)
				items.append_array(r.items)
				y = r.y + 8.0
			"menu":
				var r := _menu(b, x0, y, inner)
				items.append_array(r.items)
				y = r.y + 8.0
			"row":
				if not first_row:
					y += 6.0
				first_row = false
				var r := _row(b, x0, y, inner)
				items.append_array(r.items)
				y = r.y
	# The hint line under the commands
	items.append({"kind": "hint", "rect": Rect2(x0, y, inner, 25.0)})
	y += 25.0
	return {"items": items, "h": y + PAD_BOTTOM + BORDER}


func _ask(b: Dictionary, x0: float, y: float, inner: float) -> Dictionary:
	var items := []
	var x := x0
	if b.listening:
		items.append({"kind": "rec", "rect": Rect2(x, y + 3.5, 8, 8)})
		x += 18.0
	var text_w := Css.width(Css.ps(), 10, b.text)
	var lines := Css.wrap(Css.ps(), 10, b.text, inner - (x - x0))
	var ty := y
	for l in lines:
		items.append({"kind": "text", "rect": Rect2(x, ty, inner, 15), "text": l, "size": 10, "color": "ink" if b.listening else "accent"})
		ty += 15.0
	if b.pips != null:
		var g := Status.slot_groups(b.pips.get("slots"), b.pips.get("maxSlots"))
		var pw := _pips_width(g)
		var px := x + minf(text_w, inner) + 10.0
		var py := ty - 15.0
		if px + pw > x0 + inner:
			px = x0
			py = ty + 10.0 - 15.0
			ty += 10.0
		items.append({"kind": "pips", "rect": Rect2(px, py + 2.5, pw, 10), "groups": g, "tip": _slot_tip(g)})
	return {"items": items, "y": ty}


static func _pips_width(groups: Array) -> float:
	var w := 0.0
	for g in groups:
		w += g.pips.size() * 8.0 - 2.0 + 7.0
	return maxf(0.0, w - 7.0)


static func _slot_tip(groups: Array) -> String:
	var parts := []
	for g in groups:
		parts.append("%s CIRCLE %d OF %d" % [Status.CIRCLE_WORDS[g.circle - 1], g.left, g.max])
	return "SPELL SLOTS LEFT: %s. A SPELL USES ONE SLOT OF ITS CIRCLE. CAMP TO REFILL" % ", ".join(parts)


func _menu(b: Dictionary, x0: float, y: float, inner: float) -> Dictionary:
	var items := []
	var rows: int = maxi(1, b.rows)
	var n: int = b.options.size()
	var cols := ceili(float(n) / rows)
	var col_w := (inner - 12.0 * (cols - 1)) / cols
	var opt_h := 27.0
	for o in b.options:
		var c: int = o.i / rows
		var r: int = o.i % rows
		items.append({"kind": "opt", "rect": Rect2(x0 + c * (col_w + 12.0), y + r * (opt_h + 4.0), col_w, opt_h), "o": o})
	return {"items": items, "y": y + rows * opt_h + (rows - 1) * 4.0}


func _row(b: Dictionary, x0: float, y: float, inner: float) -> Dictionary:
	# flex-wrap with a 5px gap; every box in a line stretches to the line's height; .how pushes what follows right
	var boxes := []
	for it in b.items:
		match it.type:
			"cmd":
				boxes.append({"kind": "cmd", "c": it, "size": _cmd_size(it), "target": b.cls == "targets"})
			"pad":
				var parts := []
				var w := 0.0
				for c in it.items:
					var s := _cmd_size(c, true)
					parts.append({"c": c, "size": s})
					w += s.x + 3.0
				var lab_w := Css.width(Css.ps(), KBD, it.lab) + 8.0
				boxes.append({"kind": "pad", "parts": parts, "lab": it.lab, "size": Vector2(w + lab_w, 24.0), "margin_right": 6.0})
			"lab":
				boxes.append({"kind": "lab", "text": it.text, "size": Vector2(Css.width(Css.ps(), KBD, it.text) + 8.0, 15.0)})
			"how":
				boxes.append({"kind": "how", "parts": it.parts, "size": Vector2(_how_size(it.parts), 15.0), "auto": true})
	var lines := [[]]
	var x := 0.0
	for bx in boxes:
		var bw: float = bx.size.x
		if x > 0.0 and x + bw > inner:
			lines.append([])
			x = 0.0
		lines[lines.size() - 1].append(bx)
		x += bw + 5.0 + bx.get("margin_right", 0.0)
	var items := []
	var ly := y
	for line in lines:
		var lh := 0.0
		var used := 0.0
		for bx in line:
			lh = maxf(lh, bx.size.y)
			used += bx.size.x + 5.0 + bx.get("margin_right", 0.0)
		used -= 5.0
		var lx := x0
		for bx in line:
			var h: float = lh if bx.kind == "cmd" else bx.size.y
			var r := Rect2(lx, ly + (lh - h) / 2.0, bx.size.x, h)
			var item: Dictionary = bx.duplicate()
			item.rect = r
			items.append(item)
			lx += bx.size.x + 5.0 + bx.get("margin_right", 0.0)
			if bx.get("auto", false):
				lx += maxf(0.0, inner - used)
		ly += lh + 5.0
	return {"items": items, "y": ly - 5.0}


# ---------------------------------------------------------------- painting

func paint() -> void:
	_t = now_ms()
	var age := _t - _nudge_at
	var n := Css.nudge(age, NUDGE_MS, 6.0)
	var dx: float = n[0]
	var box := Rect2(dx, 0, size.x, size.y)
	var border := Css.FAINT
	if model.waiting:
		border = accent
		var g := 14.0 + 12.0 * Css.pulse(_t, 1400.0)
		if age < NUDGE_MS:
			g = lerpf(14.0, 36.0, n[1])
		Css.glow(self, box, accent, g)
	elif age < NUDGE_MS:
		Css.glow(self, box, accent, 36.0 * n[1])
		if n[1] > 0.3:
			border = accent
	draw_rect(box, Css.BG)
	Css.frame(self, box, border, BORDER)
	if dx != 0.0:
		draw_set_transform(Vector2(dx, 0))
	for it in _items:
		match it.kind:
			"text":
				var c: Color = {"accent": accent, "you": Css.YOU, "ink": Css.INK}.get(it.color, Css.INK)
				Css.text(self, Css.ps(), it.size, it.rect.position.x, it.rect.position.y, it.text, c, it.rect.size.y)
			"field":
				line_edit.position = it.rect.position
				line_edit.size = it.rect.size
			"mic":
				_mic(it)
			"rec":
				_rec(it.rect)
			"wait":
				_wait(it)
			"pips":
				_pips(it)
			"opt":
				_opt(it)
			"cmd":
				_cmd(it.c, it.rect, false, it.get("target", false))
			"pad":
				_pad(it)
			"lab":
				Css.text(self, Css.ps(), KBD, it.rect.position.x + 4.0, it.rect.position.y, it.text, Css.DIM, it.rect.size.y)
			"how":
				_how(it)
			"hint":
				var text := Css.ellipsize(Css.vt(), HINT, hint_text, it.rect.size.x - 4.0)
				Css.text(self, Css.vt(), HINT, it.rect.position.x + 2.0, it.rect.position.y + 5.0, text, Css.DIM, 20.0)
	if dx != 0.0:
		draw_set_transform(Vector2.ZERO)


func _wait(it: Dictionary) -> void:
	var b: Dictionary = it.b
	var x: float = it.rect.position.x
	var y: float = it.rect.position.y
	var color := accent if b.echo else Css.DIM
	if b.icon != "":
		Css.icon(self, b.icon, Vector2(x, y + 5.5 - 7.0).floor(), 14.0, color)
		x += 20.0
	var text: String = b.text
	if b.dots:
		text += ".".repeat(int(Css.steps(fposmod(_t, 1200.0) / 1200.0, 4) * 4.0))
	Css.text(self, Css.ps(), FONT, x, y + 1.0, text, color, FONT)


func _rec(r: Rect2) -> void:
	var a := 0.25 + 0.75 * (1.0 - Css.pulse(_t, 800.0))
	Css.glow(self, r, Css.alpha(Css.WARN, a), 8.0)
	draw_circle(r.get_center(), 4.0, Css.alpha(Css.WARN, a))


## The HOLD TO SPEAK button: a red dot and the words; the dot pulses while held
func _mic(it: Dictionary) -> void:
	var r: Rect2 = it.rect
	var hot := hover_id == "mic"
	var held := press_id == "mic" or listening
	draw_rect(r, Css.BG)
	Css.frame(self, r, accent if hot else Css.FAINT, 2.0)
	var dot := Rect2(r.position.x + 10.0, r.get_center().y - 4.0, 8, 8)
	if held:
		_rec(dot)
	else:
		draw_circle(dot.get_center(), 4.0, Css.WARN)
	Css.text(self, Css.ps(), FONT, dot.end.x + 6.0, r.position.y, "HOLD TO SPEAK", Css.INK, r.size.y)
	add_hit(r, {"id": "mic", "click": true, "tip": "HOLD TO SPEAK. LET GO TO SAY IT", "mic": true})


func _pips(it: Dictionary) -> void:
	var x: float = it.rect.position.x
	for g in it.groups:
		var c := Css.css(g.color)
		for on in g.pips:
			var b := Rect2(x, it.rect.position.y, 6, 10)
			if on:
				Css.glow(self, b, c, 4.0)
				draw_rect(b, c)
			else:
				Css.frame(self, b, Css.alpha(c, 0.55), 1.0)
			x += 8.0
		x += 5.0
	add_hit(it.rect, {"id": "pips", "tip": it.tip})


## A .cmd button. pad: the movement pad's smaller caps; target: coloured in the monster's colour.
func _cmd(c: Dictionary, r: Rect2, pad: bool, target: bool) -> void:
	var id: String = "cmd:" + c.key
	var hot: bool = hover_id == id
	var cls: Dictionary = c.cls
	var a := 1.0
	if cls.has("off"):
		a = 0.4
	if cls.has("locked"):
		a = 0.3
	var col := Css.css(c.color) if target and c.color != "" else Css.INK
	var border := Css.FAINT
	var kbd_bg := Css.INK
	var kbd_fg := Color.BLACK
	var label_c := Css.INK
	if cls.has("main"):
		border = Css.INK
		kbd_bg = accent
	if cls.has("go"):
		border = accent
		label_c = accent
		kbd_bg = accent
	if target:
		label_c = col
		kbd_bg = col
		if cls.has("on"):
			border = col
			Css.glow(self, r, Css.alpha(col, a), 8.0)
	if cls.has("guide"):
		border = accent
		label_c = accent
		kbd_bg = accent
		var p := Css.pulse(_t, 1100.0)
		Css.glow(self, r.grow(2.0 * p), Css.alpha(accent, p), 18.0 * p)
		draw_rect(r.grow(2.0), Css.alpha(Color.BLACK, p))
		border = accent.lerp(Color.WHITE, p)
		if fposmod(_t, 1100.0) >= 550.0:
			kbd_bg = Color.BLACK
			kbd_fg = accent
	if hot and not cls.has("guide"):
		border = Css.INK
	var tint := func(x: Color) -> Color:
		var y := Css.gray(x) if cls.has("locked") else x
		return Css.alpha(y, a)
	draw_rect(r, tint.call(Css.BG))
	Css.frame(self, r, tint.call(border), 2.0)
	var k := kbd_size(c.cap, c.cap_icon)
	var pressed: bool = press_id == id
	var kx := r.position.x + (3.0 if pad else 2.0 + 4.0)
	var ky := r.get_center().y - k.y / 2.0 + (1.0 if pressed else 0.0)
	if c.cap_icon:
		draw_rect(Rect2(Vector2(kx, ky).floor(), k), tint.call(kbd_bg))
		Css.icon(self, c.cap, (Vector2(kx, ky) + k / 2.0 - Vector2(3.5, 3.5)).floor(), 7.0, tint.call(kbd_fg))
	else:
		Css.keycap(self, Vector2(kx, ky).floor(), c.cap, tint.call(kbd_bg), tint.call(kbd_fg), {"size": KBD, "box": k})
	if c.label != "" and not pad:
		var lx := kx + k.x + 7.0
		var label: String = ("> " if cls.has("on") else "") + c.label
		if c.sub != "":
			var top := r.get_center().y - (FONT + 3.0 + SUB) / 2.0
			Css.text(self, Css.ps(), FONT, lx, top, label, tint.call(label_c), FONT)
			Css.text(self, Css.vt(), SUB, lx, top + FONT + 3.0, c.sub, tint.call(Css.DIM), SUB)
		else:
			Css.text(self, Css.ps(), FONT, lx, r.get_center().y - FONT / 2.0, label, tint.call(label_c), FONT)
	add_hit(r, {"id": id, "key": c.key, "hint": c.hint, "tip": c.title, "focus_key": c.key})


func _pad(it: Dictionary) -> void:
	var x: float = it.rect.position.x
	var y: float = it.rect.position.y
	for p in it.parts:
		var r := Rect2(x, y, p.size.x, p.size.y)
		_cmd(p.c, r, true, false)
		x += p.size.x + 3.0
	Css.text(self, Css.ps(), KBD, x + 4.0, y, it.lab, Css.DIM, it.rect.size.y)


func _how(it: Dictionary) -> void:
	var x: float = it.rect.position.x
	var y: float = it.rect.position.y
	for p in it.parts:
		if p.has("text"):
			x += Css.text(self, Css.ps(), KBD, x, y, p.text, Css.DIM, 15.0) + 4.0
		else:
			var is_icon: bool = p.has("kbd_icon")
			var cap: String = p.kbd_icon if is_icon else p.kbd
			var k := kbd_size(cap, is_icon, 0.0)
			draw_rect(Rect2(x, y, k.x, k.y), Css.FAINT)
			if is_icon:
				Css.icon(self, cap, Vector2(x, y) + (k / 2.0 - Vector2(3.5, 3.5)).floor(), 7.0, Css.INK)
			else:
				Css.text(self, Css.ps(), KBD, x + 4.0, y, cap, Css.INK, k.y)
			x += k.x + 4.0


## A menu option: the number, the words (cut with an ellipsis), and what it costs or whose health it is
func _opt(it: Dictionary) -> void:
	var o: Dictionary = it.o
	var r: Rect2 = it.rect
	var id: String = "opt:%d" % o.i
	var hot: bool = hover_id == id
	if o.sel:
		draw_rect(r, Css.mix(accent, 0.14))
		Css.frame(self, r, accent, 2.0)
	elif hot:
		Css.frame(self, r, Css.INK, 2.0)
	var k := kbd_size(o.cap if o.cap != "" else " ", false)
	var kx := r.position.x + 6.0
	var ky := r.get_center().y - k.y / 2.0 + (1.0 if press_id == id else 0.0)
	Css.keycap(self, Vector2(kx, ky).floor(), o.cap, accent if o.sel else Css.FAINT, Color.BLACK if o.sel else Css.INK, {"size": KBD, "box": k})
	var lx := kx + k.x + 7.0
	var right := r.end.x - 10.0
	var tail = o.tail
	var tail_w := 0.0
	if tail != null:
		match tail.kind:
			"free":
				tail_w = Css.width(Css.ps(), 7, "FREE") + 8.0
			"pips":
				tail_w = maxf(0.0, tail.n * 8.0 - 2.0)
			"hp":
				tail_w = 64.0
	var label_w := right - lx - (tail_w + 7.0 if tail_w > 0.0 else 0.0)
	Css.text(self, Css.ps(), FONT, lx, r.get_center().y - FONT / 2.0, Css.ellipsize(Css.ps(), FONT, o.label, label_w), Css.INK, FONT)
	if tail != null:
		var tx := right - tail_w
		match tail.kind:
			"free":
				var b := Rect2(tx, r.get_center().y - 6.5, tail_w, 13)
				Css.frame(self, b, Css.FAINT, 1.0)
				Css.text(self, Css.ps(), 7, tx + 4.0, b.position.y, "FREE", Css.DIM, 13)
			"pips":
				var c := Css.css(tail.color)
				for j in tail.n:
					var b := Rect2(tx + j * 8.0, r.get_center().y - 5.0, 6, 10)
					Css.glow(self, b, c, 4.0)
					draw_rect(b, c)
				add_hit(Rect2(tx, r.position.y, tail_w, r.size.y), {"id": id + ":tail", "key": o.key, "i": o.i, "hint": o.hint, "tip": tail.tip})
			"hp":
				Css.seg_bar(self, Rect2(tx, r.get_center().y - 4.0, 64, 8), tail.pct, Css.css(tail.color))
	add_hit(r, {"id": id, "key": o.key, "i": o.i, "hint": o.hint})
	if tail != null and tail.kind == "pips":
		hits.push_back(hits.pop_at(hits.size() - 2)) # the pips' tooltip sits over the option


# ---------------------------------------------------------------- input

func _hover_changed(h) -> void:
	if h != null and h.has("i") and ui != null:
		ui.hover_option(int(h.i))
	var hint := str(h.get("hint", "")) if h != null else ""
	var shown: String = hint if hint != "" else model.hint
	if h != null and h.has("i"):
		shown = hint
	if shown != hint_text:
		hint_text = shown
		queue_redraw()


func _pressed(h: Dictionary) -> void:
	if h.has("key") and ui != null:
		ui.press_key(h.key)


func _down(h: Dictionary) -> void:
	queue_redraw()
	if h.get("mic", false) and ui != null:
		ui.mic_down()


func _up(_h) -> void:
	queue_redraw()
	if ui != null:
		ui.mic_up()
