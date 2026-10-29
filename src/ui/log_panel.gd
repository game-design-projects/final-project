## The log (renderLog in game.js; .log in style.css): the last 50 lines in VT323, dim, warning red, your words in
## blue, big moments in Press Start 2P, a monster's lines in its colour. Rewritten only when the log changes, and
## then scrolled to the newest line. The scrollbar is the page's square pixel one.
extends Control

const Css = preload("res://src/ui/css.gd")

const SHOWN := 50
const BODY := 20 # body { font: 20px/1.1 VT323 }
const BIG := 11 # .log .big { font: 11px/1.5 "Press Start 2P" }

var ui
var rtl: RichTextLabel
var _sig := ""
var _body_font: FontVariation
var _big_font: FontVariation


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	rtl = RichTextLabel.new()
	rtl.bbcode_enabled = false
	rtl.scroll_active = true
	rtl.scroll_following = true
	rtl.selection_enabled = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.focus_mode = Control.FOCUS_NONE
	rtl.mouse_filter = Control.MOUSE_FILTER_PASS
	rtl.set_anchors_preset(Control.PRESET_FULL_RECT)
	# line-height 1.1 on 20px VT323 (its own height is 20): a pixel above and below each line
	_body_font = FontVariation.new()
	_body_font.base_font = Css.vt()
	_body_font.set_spacing(TextServer.SPACING_TOP, 1)
	_body_font.set_spacing(TextServer.SPACING_BOTTOM, 1)
	# line-height 1.5 on 11px Press Start 2P
	_big_font = FontVariation.new()
	_big_font.base_font = Css.ps()
	_big_font.set_spacing(TextServer.SPACING_TOP, 3)
	_big_font.set_spacing(TextServer.SPACING_BOTTOM, 2)
	rtl.add_theme_font_override("normal_font", _body_font)
	rtl.add_theme_font_size_override("normal_font_size", BODY)
	rtl.add_theme_color_override("default_color", Css.INK)
	rtl.add_theme_constant_override("line_separation", 0)
	rtl.add_theme_constant_override("paragraph_separation", 4)
	rtl.add_theme_stylebox_override("normal", _pad(0, 0, 4, 0))
	rtl.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	style_scrollbar(rtl.get_v_scroll_bar())
	add_child(rtl)


static func _pad(l: float, t: float, r: float, b: float) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = l
	sb.content_margin_top = t
	sb.content_margin_right = r
	sb.content_margin_bottom = b
	return sb


## The page's square pixel scrollbar: a hard-edged #5a5a5a thumb on a dark track, 10px wide
static func style_scrollbar(bar: ScrollBar, thumb := Color("#5a5a5a"), track := Color("#0b0b0b")) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = track
	bg.border_width_left = 2
	bg.border_color = Color("#1d1d1d")
	bg.content_margin_left = 10
	var grab := StyleBoxFlat.new()
	grab.bg_color = thumb
	grab.border_color = track
	grab.set_border_width_all(2)
	grab.content_margin_left = 10
	var grab_hot := grab.duplicate()
	grab_hot.bg_color = Css.INK
	bar.add_theme_stylebox_override("scroll", bg)
	bar.add_theme_stylebox_override("scroll_focus", bg)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hot)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hot)
	bar.custom_minimum_size.x = 10
	for icon in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
		bar.add_theme_icon_override(icon, ImageTexture.new())


## renderLog(): only when the lines changed (a re-render that changes nothing costs nothing)
func show_log(log: Array) -> void:
	var lines := log.slice(-SHOWN)
	var sig := "%d|%s" % [log.size(), JSON.stringify(lines[lines.size() - 1]) if not lines.is_empty() else ""]
	if lines.size() > 0:
		sig += "|" + JSON.stringify(lines[0])
	if sig == _sig:
		return
	_sig = sig
	rtl.clear()
	for i in lines.size():
		var l: Dictionary = lines[i]
		var cls := str(l.get("cls", "")).split(" ", false)
		var color := Css.INK
		if cls.has("dim"):
			color = Css.DIM
		if cls.has("warn"):
			color = Css.WARN
		if cls.has("you"):
			color = Css.YOU
		if l.get("color") != null and str(l.color) != "":
			color = Css.css(l.color)
		var big := cls.has("big")
		rtl.push_font(_big_font if big else _body_font, BIG if big else BODY)
		rtl.push_color(color)
		rtl.add_text(str(l.get("text", "")))
		rtl.pop()
		rtl.pop()
		if i < lines.size() - 1:
			rtl.newline()
	_to_bottom.call_deferred()


func _to_bottom() -> void:
	var bar := rtl.get_v_scroll_bar()
	bar.value = bar.max_value


func clear_log() -> void:
	_sig = ""
	rtl.clear()
