## The dungeon view's picture: game.js's drawing functions for the 448x288 canvas (drawView, drawExplore,
## drawMonsterTag, drawBossAhead, drawFloaters, drawIcon, drawRoll, beginTransition), painted with Canvas2D into
## the SubViewport main shows through the PostFx shader. Before the game starts it draws the title card.
## It repaints every frame (main asks), so monsters wobble, torches flicker and dice tumble.
extends Node2D

const J = preload("res://src/core/js.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")
const Render = preload("res://src/view/render.gd")
const Art = preload("res://src/view/art.gd")
const Status = preload("res://src/rules/status.gd")
const Dice = preload("res://src/rules/dice.gd")
const Juice = preload("res://src/rules/juice.gd")

const W := 448.0
const H := 288.0

## main.gd: the game, the shake, the hit-stop, the sound effects
var ui
## The frame on screen before a step or turn, drawn over (or beside) the new view while the move eases
var prev_frame: Texture2D = null
var transition = null # {kind, dir, t0}
## How many floor cells the automap had last frame (the map redraws when the view reveals more)
var _seen_count := -1


func _draw() -> void:
	var now := J.now_ms()
	var ctx = Canvas2D.new(self, Vector2(W, H))
	var game = ui.game if ui != null else null
	if game == null or game.G == null:
		Render.draw_title(ctx, now)
		return
	draw_view(ctx, now)


## beginTransition: keep the frame on screen, to ease from it to the new view
func begin_transition(kind: String, dir: int, frame: Texture2D) -> void:
	if frame == null:
		return
	prev_frame = frame
	transition = {"kind": kind, "dir": dir, "t0": J.now_ms()}


func draw_view(ctx, t: float) -> void:
	var game = ui.game
	var G: Dictionary = game.G
	var off: Array = ui.shake.offset(t)
	var shaking: bool = off[0] != 0.0 or off[1] != 0.0
	if shaking:
		ctx.save()
		ctx.translate(off[0], off[1])
	if G.combat != null:
		Render.clear(ctx)
		var here: Array = game.present()
		var slots: Array = Art.SLOTS[mini(3, maxi(1, here.size()))]
		var at: float = ui.hitstop.clock(t) # big blows freeze the monsters for a few frames
		for i in here.size():
			var e: Dictionary = here[i]
			var slot: Dictionary = slots[i]
			var until: float = game.hurt_until.get(e.id, 0.0)
			var look := {"shiny": J.truthy(e.get("shiny"))}
			if J.truthy(e.get("boss")):
				look.color = Art.BOSS_COLOR
			Art.draw_monster(ctx, e.species, at, 1.0 if t < until and t >= until - 300.0 else 0.0, slot, Art.ART.pixel, look)
			draw_monster_tag(ctx, e, slot, i, here.size())
	else:
		var seen := draw_explore(ctx, t)
		draw_boss_ahead(ctx, t)
		if G.roll != null:
			draw_roll(ctx, t)
		for c in seen:
			G.seen[c[1] * G.map.n + c[0]] = true
		if G.seen.size() != _seen_count:
			_seen_count = G.seen.size()
			ui.map_changed()
	game.dice.draw(ctx, t, {"ink": G.map.palette.wall, "hot": G.map.palette.accent})
	draw_floaters(ctx, t)
	if shaking:
		ctx.restore()


## The corridor, eased from the last view while a step or turn plays out
func draw_explore(ctx, t: float) -> Array:
	var G: Dictionary = ui.game.G
	var tr = Juice.transition_at(transition, t)
	if tr == null:
		transition = null
	if tr == null or prev_frame == null:
		return Render.draw_corridor(ctx, G.map, G.x, G.y, G.dir, t)
	var seen: Array
	ctx.save()
	if tr.kind == "turn":
		# A pan: the new view slides in from the side you turned to, the old one slides out the other way
		Render.clear(ctx)
		ctx.save()
		ctx.translate(J.round_js((tr.shift + transition.dir) * W), 0)
		seen = Render.draw_corridor(ctx, G.map, G.x, G.y, G.dir, t)
		ctx.restore()
		ctx.draw_image(prev_frame, J.round_js(tr.shift * W), 0)
	elif tr.kind == "step":
		# A dolly: the old view grows past you (or shrinks away, stepping back) and fades into the new one
		seen = Render.draw_corridor(ctx, G.map, G.x, G.y, G.dir, t)
		ctx.global_alpha = tr.alpha
		ctx.translate(W / 2.0, H / 2.0)
		ctx.scale(tr.scale, tr.scale)
		ctx.draw_image(prev_frame, -W / 2.0, -H / 2.0)
	else:
		# A bump: the view lunges at the wall and springs back
		ctx.translate(W / 2.0, H / 2.0)
		ctx.scale(tr.scale, tr.scale)
		ctx.translate(-W / 2.0, -H / 2.0)
		seen = Render.draw_corridor(ctx, G.map, G.x, G.y, G.dir, t)
	ctx.restore()
	return seen


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


## The floor's champion, seen standing down the corridor before you reach it
func draw_boss_ahead(ctx, t: float) -> void:
	var G: Dictionary = ui.game.G
	var b = G.map.get("boss")
	if b == null or J.truthy(b.get("defeated")):
		return
	var f: Array = Render.DIRS[G.dir]
	for dd in range(1, Render.VIEW + 1):
		var cx: int = G.x + f[0] * dd
		var cy: int = G.y + f[1] * dd
		if cy < 0 or cy >= G.map.grid.size() or cx < 0 or cx >= G.map.grid[cy].size() or G.map.grid[cy][cx] != 1:
			return
		if cx == b.x and cy == b.y:
			# Standing in the middle of its cell, feet on the floor there
			var s := Render.scale_at(dd + 0.5)
			Art.draw_monster(ctx, b.species, t, 0.0, {"cx": 224, "s": s * 0.92, "by": 144 + 140 * s}, Art.ART.pixel, {"color": Art.BOSS_COLOR})
			return


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
