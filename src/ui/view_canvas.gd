## The dungeon view's picture, drawn as 3D in a 2D style: the floor, the monsters and the champion are a cel-shaded
## 3D set (Stage3D, in the same SubViewport), and this node paints game.js's 2D layer over it at the view's own
## 448x288 (drawMonsterTag, drawFloaters, drawIcon, drawRoll, the dice): names and health bars, floating numbers, the
## Roll of Fate, a shiny's glints. Before the game starts the set is the title corridor and this draws the title card.
## main calls `frame(now)` every frame: the set follows the game (where you stand, who you fight), then this repaints.
extends Node2D

const J = preload("res://src/core/js.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")
const Render = preload("res://src/view/render.gd")
const Art = preload("res://src/view/art.gd")
const Status = preload("res://src/rules/status.gd")
const Dice = preload("res://src/rules/dice.gd")
const Stage3D = preload("res://src/view/stage3d.gd")

const W := 448.0
const H := 288.0
## How long a hit shows on a monster (game.hurt_until is when it ends)
const HURT_MS := 300.0

## main.gd: the game, the shake, the hit-stop, the sound effects
var ui
## The 3D set this draws over (main puts both in the view's SubViewport)
var stage: Stage3D
## How many floor cells the automap had last frame (the map redraws when the view reveals more)
var _seen_count := -1
var _seen_pos := ""
## The shiny monsters on stage this frame, for their glints: [{x, y, s}]
var _glints := []


## The set follows the game at time t (J.now_ms()), then the 2D layer repaints
func frame(t: float) -> void:
	_glints = []
	var game = ui.game if ui != null else null
	if stage != null:
		if game == null or game.G == null:
			stage.title(t)
		else:
			_stage_game(game, t)
	queue_redraw()


func _stage_game(game, t: float) -> void:
	var G: Dictionary = game.G
	stage.use_map(G.map)
	stage.place(G.x, G.y, G.dir, t, game.present().size() if G.combat != null else 0)
	var off: Array = ui.shake.offset(t)
	stage.set_shake(off[0], off[1])
	stage.light(t)
	if G.combat != null:
		stage.set_fight_visible(true)
		var here: Array = game.present()
		var slots: Array = Art.SLOTS[mini(3, maxi(1, here.size()))]
		var at: float = ui.hitstop.clock(t) # big blows freeze the monsters for a few frames
		var list := []
		for i in here.size():
			var e: Dictionary = here[i]
			var until: float = game.hurt_until.get(e.id, 0.0)
			var look := {"shiny": J.truthy(e.get("shiny"))}
			if J.truthy(e.get("boss")):
				look.color = Art.BOSS_COLOR
			var hurt := clampf((until - t) / HURT_MS, 0.0, 1.0) if t < until and t >= until - HURT_MS else 0.0
			list.append({"id": e.id, "species": e.species, "look": look, "slot": slots[i], "hurt": hurt})
			if look.shiny:
				var place := stage.fight_place(slots[i])
				var c := stage.project(place.pos + Vector3(0, 0.75 * place.scale, 0))
				_glints.append({"x": c.x, "y": c.y, "s": Stage3D.slot_scale(slots[i].s)})
		stage.show_fight(list, at)
	else:
		stage.set_fight_visible(false)
		stage.show_champion(G.map.get("boss"), t)
		_mark_seen(G)


## The floor cells in view join the automap (once per spot); the map redraws when that adds any
func _mark_seen(G: Dictionary) -> void:
	var pos := "%d,%d,%d" % [G.x, G.y, G.dir]
	if pos != _seen_pos:
		_seen_pos = pos
		for c in Render.visible_cells(G.map, G.x, G.y, G.dir):
			G.seen[c[1] * G.map.n + c[0]] = true
	if G.seen.size() != _seen_count:
		_seen_count = G.seen.size()
		ui.map_changed()


func _draw() -> void:
	var now := J.now_ms()
	var ctx = Canvas2D.new(self, Vector2(W, H))
	var game = ui.game if ui != null else null
	if game == null or game.G == null:
		Render.draw_title(ctx, now, "PRESS ANY KEY", stage == null)
		return
	draw_view(ctx, now)


func draw_view(ctx, t: float) -> void:
	var game = ui.game
	var G: Dictionary = game.G
	var off: Array = ui.shake.offset(t)
	var shaking: bool = off[0] != 0.0 or off[1] != 0.0
	if shaking:
		ctx.save()
		ctx.translate(off[0], off[1])
	if G.combat != null:
		var here: Array = game.present()
		var slots: Array = Art.SLOTS[mini(3, maxi(1, here.size()))]
		for i in here.size():
			draw_monster_tag(ctx, here[i], slots[i], i, here.size())
		for g in _glints:
			draw_glints(ctx, g.x, g.y, g.s, t)
	elif G.roll != null:
		draw_roll(ctx, t)
	game.dice.draw(ctx, t, {"ink": G.map.palette.wall, "hot": G.map.palette.accent})
	draw_floaters(ctx, t)
	if shaking:
		ctx.restore()


## A shiny monster twinkles: four-point glints around it (art.gd's, drawn over the 3D model)
func draw_glints(ctx, cx: float, cy: float, s: float, t: float) -> void:
	ctx.save()
	ctx.stroke_style = Art.SHINY_COLOR
	ctx.line_width = 1.5
	for i in Art.GLINTS.size():
		var on := sin(t / 260.0 + i * 1.7)
		if on < 0.35:
			continue
		var r := (4.0 + on * 6.0) * maxf(s, 0.6)
		var x: float = cx + Art.GLINTS[i][0] * s
		var y: float = cy + Art.GLINTS[i][1] * s
		ctx.begin_path()
		ctx.move_to(x - r, y)
		ctx.line_to(x + r, y)
		ctx.move_to(x, y - r)
		ctx.line_to(x, y + r)
		ctx.stroke()
	ctx.restore()


## Name, health bar and conditions above each monster in a fight
func draw_monster_tag(ctx, e: Dictionary, slot: Dictionary, i: int, count: int) -> void:
	var game = ui.game
	var color: String = game.color_of(e)
	ctx.save()
	ctx.text_align = "center"
	ctx.fill_style = color
	ctx.stroke_style = color
	ctx.font = "8px \"Press Start 2P\", monospace"
	var label := "%s%s" % ["%d " % (i + 1) if count > 1 else "", J.up(e.name)]
	ctx.fill_text(">%s<" % label if e.id == game.G.combat.target and count > 1 else label, slot.cx, 13)
	# Health bar: its length and its color (green, yellow, red) both say how close to falling it is
	var st := Status.hp_state(e)
	var w := 72.0
	var x0 := J.round_js(slot.cx - w / 2.0)
	ctx.line_width = 1
	ctx.stroke_rect(x0 + 0.5, 18.5, w, 5)
	ctx.fill_style = st.color
	ctx.fill_rect(x0 + 2, 20, maxf(0.0, J.round_js((w - 3.0) * st.pct)), 3)
	# Veteran mark and conditions: an icon each, with its word while there is room
	var tags := []
	if J.truthy(e.get("elite")):
		tags.append({"icon": "star", "word": "VETERAN", "color": "#e8e8e8"})
	tags.append_array(Status.cond_list(e.get("cond")))
	tags = tags.slice(0, 3)
	if not tags.is_empty():
		var with_words := 1 if count > 2 else 2
		ctx.font = "7px \"Press Start 2P\", monospace"
		ctx.text_align = "left"
		var widths := []
		var total := 0.0
		for j in tags.size():
			var wj: float = 7.0 + (3.0 + ctx.measure_text(tags[j].word).width if j < with_words else 0.0)
			widths.append(wj)
			total += wj
		var x := float(J.round_js(slot.cx - (total + 6.0 * (tags.size() - 1)) / 2.0))
		for j in tags.size():
			draw_icon(ctx, tags[j].icon, x, 28, tags[j].color)
			if j < with_words:
				ctx.fill_text(tags[j].word, x + 10, 35)
			x += widths[j] + 6.0
	ctx.restore()


## Numbers and words that float up from monsters and party members: damage, misses, feelings
func draw_floaters(ctx, t: float) -> void:
	var floaters: Array = ui.game.floaters
	ctx.save()
	ctx.text_align = "center"
	for i in range(floaters.size() - 1, -1, -1):
		var f: Dictionary = floaters[i]
		var age: float = (t - f.t0) / 1000.0
		if age < 0.0:
			continue # waiting for its die to land
		if age > 1.3:
			floaters.remove_at(i)
			continue
		var y: float = f.y - age * 26.0
		ctx.global_alpha = clampf(2.6 - age * 2.0, 0.0, 1.0)
		ctx.font = "%dpx \"Press Start 2P\", monospace" % int(f.size)
		ctx.fill_style = "#000"
		ctx.fill_text(f.text, f.x + 1, y + 1)
		ctx.fill_style = f.color
		ctx.fill_text(f.text, f.x, y)
	ctx.restore()


## One of the 7x7 status icons (status.gd), drawn on the canvas at `px` pixels per dot
func draw_icon(ctx, name: String, x: float, y: float, color, px := 1) -> void:
	ctx.fill_style = color
	var rows: Array = Status.ICONS.get(name, Status.ICONS["dot"])
	for j in rows.size():
		var row: String = rows[j]
		for i in row.length():
			if row[i] == "#":
				ctx.fill_rect(x + i * px, y + j * px, px, px)


## The Roll of Fate: boon names spin, slow down and land with a slam
func draw_roll(ctx, t: float) -> void:
	var game = ui.game
	var G: Dictionary = game.G
	var r: Dictionary = G.roll
	var pal: Dictionary = G.map.palette
	var shiny: bool = r.get("kind") == "shiny"
	var great := J.truthy(r.get("great"))
	var ink: String = Art.BOSS_COLOR if great else (Art.SHINY_COLOR if shiny else pal.wall)
	var hot: String = "#ffd27a" if great else ("#ffffff" if shiny else pal.accent)
	ctx.fill_style = "rgba(0,0,0,0.9)"
	ctx.fill_rect(36, 36, W - 72, H - 72)
	ctx.stroke_style = ink
	ctx.line_width = 2
	ctx.stroke_rect(36.5, 36.5, W - 72, H - 72)
	if great:
		ctx.stroke_rect(41.5, 41.5, W - 82, H - 82)
	ctx.text_align = "center"
	ctx.fill_style = ink
	ctx.font = "9px \"Press Start 2P\", monospace"
	var tier := J.num(r.result.tier)
	ctx.fill_text("B%sF CHAMPION OVERCOME" % tier if great else ("A SHINY JOINED YOUR PARTY" if shiny else "B%sF CLEARED" % tier), W / 2.0, 64)
	ctx.font = "12px \"Press Start 2P\", monospace"
	ctx.fill_text("GREAT ROLL OF FATE" if great else ("SHINY ROLL OF FATE" if shiny else "ROLL OF FATE"), W / 2.0, 86)
	var elapsed: float = t - r.start
	# The names spin fast, then slow down before landing; each change ticks
	var names: Array = r.names
	var idx := floori(sqrt(maxf(0.0, elapsed)) * 0.9) % names.size()
	var landed := J.truthy(r.get("landed"))
	if not landed and idx != int(r.get("lastIdx", -1)):
		r.lastIdx = idx
		if ui.sfx != null:
			ui.sfx.play("tick")
	var name: String = r.result.name if landed else names[idx]
	ctx.fill_style = hot if landed else ink
	ctx.font = "%dpx \"Press Start 2P\", monospace" % (15 if name.length() > 14 else 18)
	# The landing: the name slams down (scale punch), the panel flashes, and a great roll glows
	var since: float = t - r.landedAt if landed and r.get("landedAt") != null else -1.0
	if since >= 0.0 and since < Dice.DIE_ANIM_MS:
		ctx.global_alpha = (0.4 if great else 0.25) * (1.0 - since / Dice.DIE_ANIM_MS)
		ctx.fill_rect(37, 37, W - 74, H - 74)
		ctx.global_alpha = 1
	var punch := Dice.land_punch(since, 0.7 if great else 0.45)
	ctx.save()
	ctx.translate(W / 2.0, 136)
	ctx.scale(punch, punch)
	if landed and great:
		ctx.shadow_color = hot
		ctx.shadow_blur = 12
	ctx.fill_text(name, 0, 0)
	ctx.restore()
	if landed:
		ctx.fill_style = ink
		ctx.font = "8px \"Press Start 2P\", monospace"
		var lines := [""]
		for w in str(r.result.text).split(" "):
			var joined: String = (lines[lines.size() - 1] + " " + w).strip_edges()
			if joined.length() > 40:
				lines.append(w)
			else:
				lines[lines.size() - 1] = joined
		for i in lines.size():
			ctx.fill_text(lines[i], W / 2.0, 170 + i * 14)
		if floori(t / 500.0) % 2 == 0:
			ctx.fill_text("PRESS ANY KEY", W / 2.0, H - 52)
	ctx.text_align = "left"
