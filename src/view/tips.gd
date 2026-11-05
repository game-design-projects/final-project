## The explanations that sit over the picture. Hover (or tap, or press the info key) the foe for its mind: how friendly,
## angry and afraid it is, what its traits are, and the last answers of the mind as bars. Hover an ally chip for its charm, mood,
## loyalty and what it cares about. Hover the automap for what its colours mean, and a command for what it does. The chips of the
## allies are Controls of this node (they stay at the picture's bottom left, in the dark box they always had), so the pointer can
## be over them. It only reads the game's state; the scene tells it where the pointer is (`hover`, `hover_chip`,
## `hover_command`) and which keys were pressed (`cycle`, `unpin`). With the flag `debug` the foe's panel stays open, all its rows.
extends Control

const Automap = preload("res://src/view/automap.gd")
const Allies = preload("res://src/rules/allies.gd")
const Clans = preload("res://src/rules/clans.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Flags = preload("res://src/utils/flags.gd")
const Feelings = preload("res://src/rules/feelings.gd")
const Fonts = preload("res://src/view/fonts.gd")
const Palette = preload("res://src/view/palette.gd")
const Reveal = preload("res://src/rules/reveal.gd")

const W := 448.0
const H := 288.0
## Where the foe stands in the picture (picture pixels); the pointer there asks for its card.
const FOE_RECT := Rect2(110, 20, 228, 258)
const AUTOMAP_MARGIN := 10.0 # screen pixels from the picture's corner, as gameplay.gd places it
## The stages in which the foe's card is worth reading: the fight waits on you.
const CARD_STAGES := ["intro", "menu", "act", "items", "talk"]
const CHAT_SHOWN := 8
const MIND_ROWS_SHOWN := 2 # the card shows the last answers; the debug panel all of them

var state # State, set by the owner
## Keep the foe's panel open with every row (the flag `debug`).
var debug := false
## What the mind is (`Mind.label()`), for the card's last line.
var mind_label := ""
## What the keys or a tap keep open: "", "foe", "ally<i>" or "map".
var pinned := ""

var _hover := "" # what the pointer is over: "", "foe", "map" or "ally<i>"
var _command := -1 # the command the pointer is over, with where it is (screen pixels)
var _command_rect := Rect2()
var _chips: Array = []
var _chip_signature := ""
var _card: Card
var _panel: Card
var _last_shown := ""
var _last_rows := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = Card.new()
	add_child(_card)
	_panel = Card.new()
	add_child(_panel)


# ---------------------------------------------------------------- what the pointer and the keys say

## The pointer is at `p` in the picture (448 x 288 pixels); (-1, -1) is "off the picture".
func hover(p: Vector2) -> void:
	var over := ""
	if state != null and _allowed("foe") and FOE_RECT.has_point(p):
		over = "foe"
	elif state != null and _allowed("map") and automap_rect().has_point(p):
		over = "map"
	if over != _hover:
		_hover = over
		print_verbose("tips: pointer over '%s'" % over)


## The pointer entered (`on`) or left the chip of ally `i`.
func hover_chip(i: int, on: bool) -> void:
	var key := "ally%d" % i
	if on:
		_hover = key
	elif _hover == key:
		_hover = ""


## The pointer is over command `i` of the dock, drawn at `rect` (screen pixels); -1 when it left.
func hover_command(i: int, rect := Rect2()) -> void:
	_command = i
	_command_rect = rect


## A click or tap at `p` in the picture: on the foe or the automap it keeps that card open (or closes it).
func tap(p: Vector2) -> void:
	if state != null and _allowed("foe") and FOE_RECT.has_point(p):
		toggle("foe")
	elif state != null and _allowed("map") and automap_rect().has_point(p):
		toggle("map")


## A tap or click on `key`'s thing: keep its card open, or close it when it is the one open.
func toggle(key: String) -> void:
	pinned = "" if pinned == key else key
	print("tips: %s" % ("'%s' kept open" % pinned if pinned != "" else "closed"))


## The info key: the foe, then each ally, then the map's legend (those there are now), then closed.
func cycle() -> void:
	var order := targets()
	if order.is_empty():
		pinned = ""
		return
	var at := order.find(pinned)
	pinned = "" if at == order.size() - 1 else order[at + 1]
	print("tips: info key, %s" % ("'%s'" % pinned if pinned != "" else "closed"))


## What a press of the info key can show now, in order.
func targets() -> Array:
	var out := []
	if state == null:
		return out
	if _allowed("foe"):
		out.append("foe")
	for i in state.allies.size():
		out.append("ally%d" % i)
	if _allowed("map"):
		out.append("map")
	if _allowed("chat"):
		out.append("chat")
	return out


## Any other key: whatever was kept open closes (the pointer's own card stays while it is there).
func unpin() -> void:
	if pinned != "":
		print("tips: closed by a key")
	pinned = ""


# ---------------------------------------------------------------- what is shown

## The tooltip showing now: "foe", "map", "ally<i>", "command<i>", or "" for none. The pointer's choice comes first.
func shown() -> String:
	var candidates := [_hover, "command%d" % _command if _command >= 0 else "", pinned]
	for key in candidates:
		if key != "" and _allowed(key):
			return key
	return ""


## Is the foe's panel open all the time (the flag `debug`, and a fight to look at)?
func panel_open() -> bool:
	return debug and state != null and _allowed("foe")


## The cards' lines, as data: {kind, ...} (see `_blocks_for`); what is drawn is only these.
func blocks() -> Array:
	return _blocks_for(shown())


func chip_count() -> int:
	return _chips.size()


func _allowed(key: String) -> bool:
	if state == null or state.floor_map == null:
		return false
	if key == "foe":
		return state.foe != null and state.stage in CARD_STAGES
	if key == "map":
		return state.stage in ["explore", "end", "trade"]
	if key == "chat":
		return state.viewing("chat") and not state.chat.is_empty() and state.stage in CARD_STAGES
	if key.begins_with("ally"):
		return int(key.substr(4)) < state.allies.size()
	if key.begins_with("command"):
		var i := int(key.substr(7))
		return state.stage in ["menu", "act", "items", "trade"] and i < state.menu.size() and str(state.menu[i].get("sub", "")) != ""
	return false


## The mind's answers the card may show: none with no-show-mind, unless the debug panel asks for them.
func _rows() -> Array:
	return state.mind_rows if debug or not Flags.switched_off("show-mind") else []


func _blocks_for(key: String) -> Array:
	if key == "":
		return []
	if key == "chat":
		return chat_blocks(state.chat)
	if key == "foe":
		return foe_blocks(state.foe, _rows(), MIND_ROWS_SHOWN if not debug else 0, mind_label, state.viewing("reveal") and not debug)
	if key == "map":
		return map_blocks(state.viewing("secrets"), state.viewing("items"))
	if key.begins_with("ally"):
		return ally_blocks(state.allies[int(key.substr(4))])
	return [{"kind": "text", "text": str(state.menu[int(key.substr(7))].sub)}]


# ---------------------------------------------------------------- the content

## The foe: who it is, what it seems like, how it feels, and the last `shown` answers of the mind (0 for all of them).
## `gradual` says only what the player has found out (the feature reveal), with ??? for the rest.
static func foe_blocks(m, rows: Array, shown := MIND_ROWS_SHOWN, label := "", gradual := false) -> Array:
	var out := [{"kind": "head", "left": m.name, "right": str(Content.species(m.species).label).to_upper()}]
	if gradual:
		out.append({"kind": "text", "text": found_text(m)})
	elif not m.traits.is_empty():
		var text := "Seems %s." % " and ".join(m.traits)
		var clues: Array = m.clues()
		if not clues.is_empty():
			text += "\nIt %s." % ". It ".join(clues)
		out.append({"kind": "text", "text": text})
	if not m.heard.is_empty():
		out.append({"kind": "text", "text": "%s heard you %s %s." % [Clans.title(m.heard.clan), "killed" if m.heard.deed == "slain" else "spared", m.heard.who]})
	out.append({"kind": "meters", "cells": [["FRIENDLY", roundi(m.meters.friendliness)], ["ANGER", roundi(m.meters.anger)], ["FEAR", roundi(m.meters.fear)]]})
	for row in (rows if shown <= 0 else rows.slice(-shown)):
		out.append(question(row))
	out.append({"kind": "note", "text": mind_note(label)})
	return out


## What has been found out about `m`, with ??? for each trait still hidden.
static func found_text(m) -> String:
	var seems: Array = m.known_traits.duplicate()
	for i in maxi(0, m.traits.size() - seems.size()):
		seems.append("???")
	var text := "Seems %s." % " and ".join(seems)
	var clues: Array = m.clues().slice(0, m.checks)
	if not clues.is_empty():
		text += "\nIt %s." % ". It ".join(clues)
	var likes: Array = Reveal.found(m, Reveal.LIKES)
	var hates: Array = Reveal.found(m, Reveal.HATES)
	if not likes.is_empty():
		text += "\nLikes %s." % ", ".join(likes)
	if not hates.is_empty():
		text += "\nHates %s." % ", ".join(hates)
	if likes.is_empty() and hates.is_empty():
		text += "\nTry things on it and see."
	return text


## The talk so far this run, the latest lines.
static func chat_blocks(chat: Array) -> Array:
	var out := [{"kind": "head", "left": "THE TALK SO FAR", "right": ""}]
	var text := PackedStringArray()
	for c in chat.slice(-CHAT_SHOWN):
		text.append("%s: %s" % [c.who, c.text])
	out.append({"kind": "text", "text": "\n".join(text)})
	return out


static func mind_note(label: String) -> String:
	if label.begins_with("jev"):
		return "Jev answers these; the local rules cover when it can't."
	if label == "seeded":
		return "Random stand-in for Jev (flag mock)."
	return "Offline stand-in for Jev."


## An ally: its name and mood, its loyalty as a bar, what its charm does and what it cares about.
static func ally_blocks(a) -> Array:
	var charm: Dictionary = a.charm()
	return [
		{"kind": "head", "left": a.name, "right": Allies.mood(a.loyalty), "warn": a.loyalty < Allies.LEAVE_BELOW},
		{"kind": "bar", "label": charm.name, "p": a.loyalty / 100.0, "pct": str(roundi(a.loyalty)), "pick": true},
		{"kind": "text", "text": "%s. Cares about: %s\nA refused gold offer may still affect loyalty; only an accepted offer spends gold." % [charm.text, Content.species(a.species).values]},
	]


## The automap's legend: each monster's colour and the kind of fight it brings.
static func map_blocks(secrets := false, items := false) -> Array:
	var out := [{"kind": "head", "left": "MONSTERS SHOW WHEN SEEN", "right": ""}]
	var genres: Dictionary = Content.table("encounter").genres
	var fights := {}
	for entry in Content.table("encounter").roster:
		fights[entry.species] = str(genres[entry.genre].name).to_lower()
	fights[Content.table("encounter").boss.species] = "all four"
	for id in Content.table("species"):
		out.append({"kind": "swatch", "color": Palette.BOSS if id == Content.table("encounter").boss.species else Color(Content.species(id).color), "left": id.to_upper(), "right": fights.get(id, "")})
	if secrets:
		out.append({"kind": "swatch", "color": Palette.YOU, "left": "PAD", "right": "carries you away"})
		out.append({"kind": "swatch", "color": Palette.MERCY, "left": "CHEST", "right": "behind a cracked wall"})
	if items:
		out.append({"kind": "swatch", "color": Palette.MERCY, "left": "ITEM", "right": "walk over it"})
		out.append({"kind": "swatch", "color": Palette.INK, "left": "TRADER", "right": "walk up to buy"})
	return out


## One answer of the mind as a question with bars: {kind: "question", label, code, bars: [[name, p, pct, picked]], note}.
static func question(row: Dictionary) -> Dictionary:
	var answer = row.get("answer")
	var q := {"kind": "question", "label": str(row.get("label", row.get("id", "?"))), "code": "", "bars": [], "note": ""}
	if answer is Dictionary and row.get("id") == "words":
		q.code = "choice"
		q.bars = _top_bars(answer, func(k): return str(Content.table("words").intent_words.get(k, k)).to_upper(), "")
	elif answer is Dictionary:
		q.code = "choice"
		q.bars = _top_bars(answer, func(k): return str(Feelings.all()[k].label) if Feelings.all().has(k) else str(k).to_upper(), str(row.get("picked", "")))
	elif str(row.get("id", "")) == "pressure":
		q.code = "score"
		q.note = "Pressure %.2f / 3 sets the next dodge's pace." % float(answer)
	elif str(row.get("id", "")).begins_with("judge-"):
		q.code = "level"
		var odds: Dictionary = row.get("odds", {})
		for k in odds:
			q.bars.append(["LEVEL %s" % k, float(odds[k]), Combat.chance_label(float(odds[k])), int(k) == int(answer)])
	else:
		q.code = "noul"
		var name := "YES"
		if row.has("picked"):
			name += " → YES" if row.picked else " → NO"
		q.bars.append([name, float(answer), Combat.chance_label(float(answer)), true])
	return q


## The three likeliest of a spread, likeliest first (ties in the order they came); `picked` is the one that happened.
static func _top_bars(odds: Dictionary, name_of: Callable, picked: String) -> Array:
	var rows := []
	var i := 0
	for k in odds:
		rows.append([k, float(odds[k]), i])
		i += 1
	rows.sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and a[2] < b[2]))
	var top: String = rows[0][0] if not rows.is_empty() else ""
	var bars := []
	for r in rows.slice(0, 3):
		bars.append([name_of.call(r[0]), r[1], Combat.chance_label(r[1]), r[0] == (picked if picked != "" else top)])
	return bars


## Where the automap's panel is in the picture, for hovering it. It sits over the picture at a fixed size in screen pixels (automap.gd).
func automap_rect() -> Rect2:
	var k := size.x / W if size.x > 0.0 else 1.0
	var span := Automap.PANEL / k
	return Rect2(Vector2(W - span - AUTOMAP_MARGIN / k, AUTOMAP_MARGIN / k), Vector2(span, span))


# ---------------------------------------------------------------- the frame each frame

func _process(_dt: float) -> void:
	if state == null:
		return
	_update_chips()
	if pinned != "" and not _allowed(pinned):
		pinned = ""
	var key := shown()
	if key != _last_shown:
		_last_shown = key
		print_verbose("tips: showing '%s'" % key)
	var k := size.x / W
	if key == "":
		_card.visible = false
	else:
		_card.set_blocks(_blocks_for(key))
		_card.visible = true
		_card.place(_anchor_for(key, k), Card.POINTER if _hover == key and not key.begins_with("command") else (Card.ABOVE if key.begins_with("command") or key.begins_with("ally") else Card.AT))
	if panel_open():
		var rows: Array = state.mind_rows
		if str(rows) != _last_rows:
			_last_rows = str(rows)
			print("tips: %s mind rows: %s" % [state.foe.name, rows.map(func(r): return "%s=%s" % [r.get("id", "?"), r.get("answer", "?")])])
		_panel.set_blocks(foe_blocks(state.foe, state.mind_rows, 0, mind_label))
		_panel.visible = true
		_panel.place(global_position + Vector2(size.x - _panel.size.x - 8.0, 36.0 * k), Card.AT)
	else:
		_panel.visible = false


## Where the card of `key` goes (screen pixels): by the pointer, above the command, or at its fixed place when kept open.
func _anchor_for(key: String, k: float) -> Vector2:
	if key.begins_with("command"):
		return _command_rect.position
	if key == _hover:
		return get_global_mouse_position()
	if key == "foe" or key == "chat":
		return global_position + Vector2(12.0, 40.0) * k
	if key == "map":
		var map := automap_rect()
		return global_position + Vector2(map.position.x * k - _card.size.x + map.size.x * k, map.end.y * k + 6.0)
	var i := int(key.substr(4))
	if i < _chips.size():
		return _chips[i].global_position
	return global_position


# ---------------------------------------------------------------- the chips

## One chip for each ally, bottom left, the dark box with its colour dot and its charm's name; red when about to leave.
func _update_chips() -> void:
	var signature := ",".join(state.allies.map(func(a): return "%s:%s:%s" % [a.species, a.charm().name, a.loyalty < Allies.LEAVE_BELOW])) if state.floor_map != null else ""
	if signature != _chip_signature:
		_chip_signature = signature
		for c in _chips:
			c.queue_free()
		_chips = []
		for i in state.allies.size():
			var chip := Chip.new()
			chip.setup(state.allies[i])
			chip.hovered.connect(hover_chip.bind(i))
			chip.tapped.connect(toggle.bind("ally%d" % i))
			add_child(chip)
			_chips.append(chip)
	var k := size.x / W
	for i in _chips.size():
		_chips[i].place(i, k)


## An ally over the picture: a colour dot and the charm's name. Hover it, or tap it, for the ally's card.
class Chip:
	extends Control

	signal hovered(on: bool)
	signal tapped

	var dot := Color.WHITE
	var label := ""
	var warn := false
	var k := 1.0

	var _title: Font = Fonts.title()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): hovered.emit(true))
		mouse_exited.connect(func(): hovered.emit(false))

	func setup(a) -> void:
		dot = Color(Content.species(a.species).color)
		label = a.charm().name
		warn = a.loyalty < Allies.LEAVE_BELOW

	## Chip number `i` from the bottom, at scale `k` (the picture's size over 448).
	func place(i: int, scale_k: float) -> void:
		k = scale_k
		var width := _title.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x + 18.0
		position = Vector2(9.0, H - 10.0 - 9.0 - 12.0 * i) * k
		size = Vector2(width, 12.0) * k
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			tapped.emit()
			accept_event()

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
		draw_rect(Rect2(Vector2.ZERO, size / k), Color(0.0, 0.0, 0.0, 0.85)) # a wall line crossing the name would hide it
		draw_circle(Vector2(5.0, 6.0), 3.5, dot)
		draw_string(_title, Vector2(13.0, 9.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Palette.WARN if warn else Palette.DIM)


## A card: a dark box with a white border, drawn from `blocks` (see `foe_blocks`), above everything else.
class Card:
	extends Control

	const PAD := 10.0
	const INNER := 300.0
	const GAP := 6.0
	const BAR_H := 16.0
	enum { POINTER, ABOVE, AT } # where a card sits from the point it is given: below and right of the pointer, above it, on it

	var blocks: Array = []

	var _title: Font = Fonts.title()
	var _body: Font = Fonts.body()
	var _heights: Array = []
	var _signature := ""

	func _init() -> void:
		top_level = true
		z_index = 20
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func set_blocks(new_blocks: Array) -> void:
		var signature := str(new_blocks)
		if signature == _signature:
			return
		_signature = signature
		blocks = new_blocks
		_measure()
		queue_redraw()

	## Put the card near `at` (screen pixels), kept inside the window: by the pointer it hangs below and to the right, above a
	## command or a chip it sits over it, otherwise its top left is `at`. One that would run off the bottom goes above `at`.
	func place(at: Vector2, mode: int) -> void:
		var window := get_viewport_rect().size
		var pos := at
		match mode:
			POINTER:
				pos = at + Vector2(18, 18)
			ABOVE:
				pos = Vector2(at.x, at.y - size.y - 6.0)
		pos.x = clampf(pos.x, 6.0, maxf(6.0, window.x - size.x - 6.0))
		if pos.y + size.y > window.y - 6.0:
			pos.y = at.y - size.y - 12.0
		pos.y = maxf(6.0, pos.y)
		position = pos

	func _text_h(text: String, font: Font, px: int, width: float) -> float:
		return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, px).y

	func _measure() -> void:
		_heights = []
		var total := 0.0
		for b in blocks:
			var h := 0.0
			match b.kind:
				"head":
					h = 14.0
				"text", "note":
					h = _text_h(b.text, _body, 16 if b.kind == "text" else 15, INNER)
				"meters":
					h = 38.0
				"question":
					h = _text_h(b.label, _body, 18, INNER - 56.0) + 2.0
					if str(b.note) != "":
						h += _text_h(b.note, _body, 17, INNER) + 2.0
					h += BAR_H * b.bars.size()
				"bar":
					h = BAR_H
				"swatch":
					h = 18.0
			_heights.append(h)
			total += h + GAP
		size = Vector2(INNER + PAD * 2.0, maxf(0.0, total - GAP) + PAD * 2.0)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Palette.INK, false, 2.0)
		var y := PAD
		for i in blocks.size():
			var b: Dictionary = blocks[i]
			var at := Vector2(PAD, y)
			match b.kind:
				"head":
					draw_string(_title, at + Vector2(0, 10), str(b.left), HORIZONTAL_ALIGNMENT_LEFT, INNER, 9, Palette.INK)
					draw_string(_title, at + Vector2(0, 10), str(b.right), HORIZONTAL_ALIGNMENT_RIGHT, INNER, 8, Palette.WARN if b.get("warn", false) else Palette.DIM)
				"text":
					draw_multiline_string(_body, at + Vector2(0, 14), b.text, HORIZONTAL_ALIGNMENT_LEFT, INNER, 16, -1, Palette.DIM)
				"note":
					draw_multiline_string(_body, at + Vector2(0, 13), b.text, HORIZONTAL_ALIGNMENT_LEFT, INNER, 15, -1, Palette.FAINT.lightened(0.35))
				"meters":
					for c in b.cells.size():
						var x: float = c * 96.0
						draw_string(_body, at + Vector2(x, 12), str(b.cells[c][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.DIM)
						draw_string(_body, at + Vector2(x, 34), str(b.cells[c][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.INK)
				"question":
					var head_h := _text_h(b.label, _body, 18, INNER - 56.0)
					draw_multiline_string(_body, at + Vector2(0, 14), b.label, HORIZONTAL_ALIGNMENT_LEFT, INNER - 56.0, 18, -1, Palette.DIM)
					draw_string(_body, at + Vector2(0, 13), str(b.code), HORIZONTAL_ALIGNMENT_RIGHT, INNER, 15, Palette.YOU)
					var row_y := y + head_h + 2.0
					if str(b.note) != "":
						draw_multiline_string(_body, Vector2(PAD, row_y + 13.0), b.note, HORIZONTAL_ALIGNMENT_LEFT, INNER, 17, -1, Palette.INK)
						row_y += _text_h(b.note, _body, 17, INNER) + 2.0
					for bar in b.bars:
						_bar_row(Vector2(PAD, row_y), str(bar[0]), float(bar[1]), str(bar[2]), bool(bar[3]))
						row_y += BAR_H
				"bar":
					_bar_row(at, b.label, b.p, b.pct, b.get("pick", false))
				"swatch":
					draw_rect(Rect2(at + Vector2(0, 5), Vector2(8, 8)), b.color)
					draw_string(_body, at + Vector2(16, 14), str(b.left), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.INK)
					draw_string(_body, at + Vector2(100, 14), str(b.right), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.DIM)
			y += _heights[i] + GAP

	## A label, a track filled to `p`, and its percentage; the answer that was picked is bright.
	func _bar_row(at: Vector2, label: String, p: float, pct: String, picked: bool) -> void:
		var track_x := at.x + 112.0
		var track_w := INNER - 112.0 - 44.0
		draw_string(_body, at + Vector2(0, 12), label, HORIZONTAL_ALIGNMENT_LEFT, 108.0, 15, Palette.INK if picked else Palette.DIM)
		draw_rect(Rect2(track_x, at.y + 4.0, track_w, 8.0), Palette.FAINT)
		draw_rect(Rect2(track_x, at.y + 4.0, track_w * clampf(p, 0.0, 1.0), 8.0), Palette.YOU if picked else Palette.DIM)
		draw_string(_body, Vector2(at.x, at.y + 12.0), pct, HORIZONTAL_ALIGNMENT_RIGHT, INNER, 15, Palette.INK if picked else Palette.DIM)
