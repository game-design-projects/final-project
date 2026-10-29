## The status line on top (renderBar, sysToggles, achCap in game.js; .bar.top in style.css): where you are, which
## way you face (or that you're in a fight), gold, boons, and the rarely touched switches as keycaps with pixel
## icons, slashed red when off. Every slot has a fixed width, so nothing shifts as the numbers change.
extends "res://src/ui/widget.gd"

const Achievements = preload("res://src/rules/achievements.gd")

const FONT := 9
const H := 38.0
const PAD_X := 2.0
const GAP := 12.0
const CH := 9.0 # 1ch of Press Start 2P at 9px
const SYS_FONT := 8

## Set by main (render_bar): null before the game starts (an empty bar)
var model = null


func _init() -> void:
	super()


func paint() -> void:
	# the 2px rule under the bar
	draw_rect(Rect2(0, H, size.x, 2), Css.INK)
	if model == null:
		return
	var font := Css.ps()
	var mid := (4.0 + H - 8.0) / 2.0 + 0.5
	var sys_w := _sys_width()
	var dir_w := 5.0 * CH + 24.0
	var gold_w := 9.0 * CH + 24.0
	var boons_w := 8.0 * CH + 24.0
	var right := size.x - PAD_X
	var x_sys := right - sys_w
	var x_boons := x_sys - GAP - boons_w
	var x_gold := x_boons - GAP - gold_w
	var x_dir := x_gold - GAP - dir_w
	var loc_w := maxf(8.0 * CH, x_dir - GAP - PAD_X)

	# where: the floor in its accent, then the floor's name (it gives way first)
	var loc: Dictionary = model.loc
	var x := PAD_X
	var top := mid - FONT / 2.0
	var fw := Css.text(self, font, FONT, x, top, loc.floor, Css.css(loc.accent), FONT)
	var name_w := loc_w - fw - 6.0
	Css.text(self, font, FONT, x + fw + 6.0, top, Css.ellipsize(font, FONT, loc.name, name_w), Css.DIM, FONT)
	add_hit(Rect2(x, 4, loc_w, H - 12.0), {"id": "loc", "tip": loc.tip})

	_slot(x_dir, dir_w, model.dir, mid, "dir")
	_slot(x_gold, gold_w, model.gold, mid, "gold")
	_slot(x_boons, boons_w, model.boons, mid, "boons")

	# the switches, in keyboard order
	x = x_sys
	for s in model.sys:
		var w := _switch_width(s)
		_switch(Rect2(x, mid - 11.5, w, 23.0), s)
		x += w + 2.0


## One fixed-width slot: a 14px pixel icon, 6px gap, the words
func _slot(x: float, w: float, s: Dictionary, mid: float, id: String) -> void:
	Css.icon(self, s.icon, Vector2(x, mid - 7.0).floor(), 14.0, Css.css(s.icon_color))
	Css.text(self, Css.ps(), FONT, x + 20.0, mid - FONT / 2.0, s.text, Css.css(s.color), FONT)
	add_hit(Rect2(x, 4, w, H - 12.0), {"id": id, "tip": s.tip})


func _switch_width(s: Dictionary) -> float:
	if s.get("trophy", false):
		# border 2, padding-left 2, kbd 18, gap 5, label (min 5ch: trophy 14 + 5 + count), padding-right 4, border 2
		var label := maxf(5.0 * SYS_FONT, 14.0 + 5.0 + Css.width(Css.ps(), SYS_FONT, s.text))
		return 2.0 + 2.0 + 18.0 + 5.0 + label + 4.0 + 2.0
	return 2.0 + 2.0 + 18.0 + 4.0 + 14.0 + 3.0 + 2.0


func _sys_width() -> float:
	var w := 0.0
	for s in model.sys:
		w += _switch_width(s) + 2.0
	return w - 2.0


## .sys .cmd: a keycap and a pixel icon (or the trophy and the count), slashed red when off
func _switch(r: Rect2, s: Dictionary) -> void:
	var hot: bool = hover_id == "sys:" + s.key
	var lit: bool = s.get("open", false)
	var kbd_bg := Css.GOLD if lit else Css.FAINT
	var kbd_fg := Color.BLACK if lit else Css.INK
	var cap := Css.keycap(self, Vector2(r.position.x + 4.0, r.get_center().y - 7.5).floor(), s.key.to_upper(), kbd_bg, kbd_fg, {"size": SYS_FONT})
	var ix := cap.end.x + (5.0 if s.get("trophy", false) else 4.0)
	var icon_pos := Vector2(ix, r.get_center().y - 7.0).floor()
	if s.get("trophy", false):
		Css.glyph(self, Achievements.GLYPHS["trophy"], icon_pos, 14.0, Css.css(s.icon_color))
		var fg := Css.INK if hot or lit else Css.DIM
		Css.text(self, Css.ps(), SYS_FONT, ix + 19.0, r.get_center().y - SYS_FONT / 2.0, s.text, fg, SYS_FONT)
	else:
		Css.icon(self, s.icon, icon_pos, 14.0, Css.css(s.icon_color))
		if not s.on:
			# the red slash: 18px long, 2px thick, turned -40deg about its middle
			var c := icon_pos + Vector2(7.0, 7.0)
			var d := Vector2(cos(deg_to_rad(-40.0)), sin(deg_to_rad(-40.0))) * 9.0
			draw_line(c - d, c + d, Css.WARN, 2.0)
	add_hit(r, {"id": "sys:" + s.key, "key": s.key, "tip": s.title, "focus_key": s.key})
