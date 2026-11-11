## The gameplay scene: one run of the game on screen. It builds the game (Flow with a mind), the picture (a 3D set in a small
## viewport, a flat layer over it, a post-processing pass) and the text around it, turns key presses, clicks and the touch pad
## into the game's keys, runs the clock, and turns the game's events into flashes and floating numbers. It also holds the
## tooltips over the picture, the pause menu and the autosave, and goes back to the main menu when the player leaves. The rules
## are not here: it only reads `flow.state` and listens to `flow.happened`.
extends Control

const Audio = preload("res://src/audio/audio.gd")
const Automap = preload("res://src/view/automap.gd")
const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const Hud = preload("res://src/view/hud.gd")
const Menus = preload("res://src/menu/menus.gd")
const MenuPanel = preload("res://src/menu/menu_panel.gd")
const Minds = preload("res://src/mind/minds.gd")
const Network = preload("res://src/network/network.gd")
const SocialDemo = preload("res://src/game/social_demo.gd")
const SocialPopup = preload("res://src/view/social_popup.gd")
const Overlay = preload("res://src/view/overlay.gd")
const Pad = preload("res://src/view/pad.gd")
const Palette = preload("res://src/view/palette.gd")
const Progress = preload("res://src/menu/progress.gd")
const PersonalitySlice = preload("res://src/game/personality_slice.gd")
const PostFx = preload("res://src/view/postfx.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")
const Saves = preload("res://src/menu/saves.gd")
const Session = preload("res://src/menu/session.gd")
const Settings = preload("res://src/menu/settings.gd")
const StageScript = preload("res://src/view/stage.gd")
const Vision = preload("res://src/rules/vision.gd")
const Tips = preload("res://src/view/tips.gd")
const Warmth = preload("res://src/rules/warmth.gd")

const MENU_SCENE := "res://src/menu/main_menu.tscn"
const VIEW_W := 448
const VIEW_H := 288
const WIDEST := 2.4 # with wide-view the picture follows the panel's shape up to this: FOV 68 is its height, so its width grows with it
const FILM_RISE_S := 0.9 # the run comes up out of the opening film's black this slowly when the film played to its end
const FILM_RISE_SKIPPED_S := 0.35 # and this quickly when a key skipped it
const WIDTH_STEP := 16 # and its width moves in steps this big, so a line more or less in the dock doesn't remake the picture
const FRAME_MARGIN := 8
const FRAME_PAD_X := 14 # between the white frame and what is inside it, left and right
const FRAME_ROUND := 10 # hand-drawn, the frame has soft corners and the run's wall colour, dimmed
const FRAME_DIM := 0.28


## How wide the picture is, in its pixels, to fill a panel this shape with wide-view on. Its height stays VIEW_H.
static func picture_width(room: Vector2) -> int:
	if room.x <= 0.0 or room.y <= 0.0:
		return VIEW_W
	var shape := clampf(room.x / room.y, float(VIEW_W) / VIEW_H, WIDEST)
	return maxi(VIEW_W, snappedi(VIEW_H * shape, WIDTH_STEP))


## How wide the dock (the log, the commands) is in a window this wide.
static func dock_width(window_w: float) -> float:
	return window_w - FRAME_MARGIN * 2.0 - FRAME_PAD_X * 2.0


const KEYS := {
	KEY_UP: "up", KEY_W: "up", KEY_DOWN: "down", KEY_S: "down", KEY_LEFT: "left", KEY_A: "left", KEY_RIGHT: "right", KEY_D: "right",
	KEY_ENTER: "confirm", KEY_KP_ENTER: "confirm", KEY_SPACE: "confirm", KEY_Z: "confirm", KEY_ESCAPE: "cancel", KEY_X: "cancel",
}
const INFO_KEY := KEY_I # shows the foe's card, then each ally's, then the map's legend (tips.gd); also the pad's INFO
const REPEATING := ["explore", "dodge"] # stages where holding a key keeps acting

## What to start with: {"kind": "new"} or {"kind": "load", "state": Dictionary}, set by the menu through session.gd. With
## nothing pending (the scene opened on its own) the title card shows first and any key starts a new run.
var request := {}

var flow
var audio
var _rng
var _clock_ms := 0.0
var _viewport: SubViewport
var _stage
var _frame: Control
var _frame_box: StyleBoxFlat
var _rule: ColorRect
var _overlay
var _automap
var _postfx
var _picture: TextureRect
var _room: Control
var _aspect: AspectRatioContainer
var _header
var _status
var _dock
var _social: Control
var _pause: MenuPanel
var _tips
var _pad
var _debug := false # the flag `debug`
var _fresh_floor := false # a new floor has begun and its start is not autosaved yet
var _on_title := false # the title card is up, waiting for a key


func _ready() -> void:
	Settings.apply()
	var pending := Session.take()
	if not pending.is_empty():
		request = pending
	_build_screen()
	var slice := PersonalitySlice.pending()
	_rng = Rng.new(PersonalitySlice.seed_value()) if slice else Rng.new()
	flow = Flow.new(_rng, Minds.create(_rng, str(Store.get_value("jev_url", "")), slice or Flags.on("social-demo")))
	audio = Audio.new()
	add_child(audio)
	audio.bind(flow)
	flow.happened.connect(_on_event)
	for id in Settings.get_value("seen_tips"):
		flow.coach.seen[str(id)] = true
	for id in Progress.earned():
		flow.trophies.earned[str(id)] = true
	flow.legacy_ranks = Progress.ranks()
	_fit_picture()
	_debug = Flags.on("debug")
	_tips.debug = _debug
	_tips.mind_label = flow.mind.label()
	_bind_views()
	if request.get("cg", "") != "":
		_rise_from_film()
	if _debug:
		print("gameplay: debug on, the foe's mind panel stays open and every game event is logged")
	if request.is_empty() and Flags.value("meet") == "" and not slice and not Flags.on("social-demo"):
		_on_title = true
		_overlay.title_card = true
		_tips.visible = false
		flow.state.say([State.sys_line("Press any key to start.")])
		flow.state.hint = "ANY KEY START"
		return
	await _begin()


## The opening film ended on black (menu/intro_cg.gd): the run comes up out of it, over as long as the film took to go (a skipped
## film left quickly, so this is quick too).
func _rise_from_film() -> void:
	var veil := ColorRect.new()
	veil.color = Color.BLACK
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var seconds := FILM_RISE_S if request.cg == "whole" else FILM_RISE_SKIPPED_S
	var rise := create_tween()
	rise.tween_property(veil, "color:a", 0.0, seconds)
	rise.finished.connect(veil.queue_free)
	print("gameplay: the run rises out of black after the film (%s, %.2f s)" % [request.cg, seconds])


## Start the run the request asks for (a new one, or a saved one).
func _begin() -> void:
	_on_title = false
	_overlay.title_card = false
	_tips.visible = true
	await flow.exclusive(_start_request)
	await flow.exclusive(_after_start)


func _start_request() -> void:
	if request.get("kind", "new") == "load":
		if not await flow.load_state(request.state):
			push_warning("gameplay: that save can't be loaded, starting a new run")
			await flow.new_run()
	else:
		flow.film_seen = request.get("cg", "") == "whole"
		await flow.new_run(_practice_due())


## The practice floor comes with the tips, until it has been played once (stages/end.gd reaches B1F from it).
func _practice_due() -> bool:
	return Settings.get_value("tips") and not flow.coach.seen.has(flow.PRACTICE_SEEN)


## Handle the testing flags `meet=<species>` and `personality-slice`. It runs as an exclusive action: a tick must not run a
## stage's own tick while the mind is still answering the stage's `enter`.
func _after_start() -> void:
	if Flags.on("social-demo") and request.get("kind", "new") == "new":
		await SocialDemo.start(flow)
		return
	if PersonalitySlice.pending() and request.get("kind", "new") == "new":
		await PersonalitySlice.start(flow)
		return
	var species := Flags.value("meet")
	if species != "":
		for m in flow.state.floor_map.monsters:
			if m.species == species and not m.is_gone():
				await flow.go("intro", {"foe": m})
				break


func _build_screen() -> void:
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VIEW_W, VIEW_H)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X # the lines are thin: without this they shimmer as the camera moves
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_stage = StageScript.new()
	_viewport.add_child(_stage)
	_overlay = Overlay.new() # flat layer drawn into the same small picture, so the glow and scanlines reach it too
	_overlay.size = Vector2(VIEW_W, VIEW_H)
	_viewport.add_child(_overlay)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, FRAME_MARGIN)
	add_child(margin)
	var crt := PanelContainer.new() # the white frame round everything
	var box := StyleBoxFlat.new()
	box.bg_color = Color.BLACK
	box.border_color = Palette.INK
	box.set_border_width_all(2)
	box.content_margin_left = FRAME_PAD_X
	box.content_margin_right = FRAME_PAD_X
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	_frame_box = box
	crt.add_theme_stylebox_override("panel", box)
	margin.add_child(crt)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	crt.add_child(column)

	_header = Hud.new()
	_header.part = Hud.Part.HEADER
	_header.custom_minimum_size = Vector2(0, 14)
	column.add_child(_header)
	var rule := ColorRect.new()
	_rule = rule
	rule.color = Palette.INK
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)

	var room := Control.new() # takes what the dock leaves; the picture keeps its shape inside
	_room = room
	room.resized.connect(_fit_picture)
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.custom_minimum_size = Vector2(320, 206)
	room.clip_contents = true
	column.add_child(room)
	var aspect := AspectRatioContainer.new()
	_aspect = aspect
	aspect.ratio = float(VIEW_W) / VIEW_H
	aspect.set_anchors_preset(Control.PRESET_FULL_RECT)
	room.add_child(aspect)
	_frame = Control.new()
	aspect.add_child(_frame)
	var picture := TextureRect.new()
	_picture = picture
	picture.texture = _viewport.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_STOP # a click on it is OK in the strike bar and on the title card; hovering shows tooltips
	picture.gui_input.connect(_on_picture_input)
	picture.mouse_exited.connect(func(): _tips.hover(Vector2(-1, -1)))
	_frame.add_child(picture)
	_postfx = PostFx.new()
	_automap = Automap.new() # over the picture, not in it: the post-processing doesn't touch it
	_automap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	_automap.custom_minimum_size = Vector2(Automap.PANEL, Automap.PANEL)
	_automap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_frame.add_child(_automap)
	_tips = Tips.new() # the ally chips and the tooltips, over the picture
	_frame.add_child(_tips)

	_status = Hud.new()
	_status.part = Hud.Part.STATUS
	_status.custom_minimum_size = Vector2(0, 18)
	column.add_child(_status)
	_dock = Hud.new()
	_dock.part = Hud.Part.DOCK
	_dock.custom_minimum_size = Vector2(0, Hud.DOCK_H)
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_dock.picked.connect(func(i): _press(str(i + 1)))
	_dock.said.connect(func(text): flow.submit_text(text))
	_dock.cancelled.connect(func(): _press("cancel"))
	_dock.hovered.connect(_on_dock_hover)
	_dock.page_selected.connect(func(i): flow.select(i))
	column.add_child(_dock)
	_pad = Pad.new()
	_pad.visible = DisplayServer.is_touchscreen_available() or Flags.on("pad")
	_pad.pressed.connect(_on_pad)
	_pad.repeated.connect(_on_pad_repeat)
	column.add_child(_pad)

	_social = SocialPopup.new()
	_social.hovered.connect(func(i): flow.select(i))
	_social.picked.connect(func(i): _press(str(i + 1)))
	_social.said.connect(func(text): flow.submit_text(text))
	_social.cancelled.connect(func(): _press("cancel"))
	add_child(_social)
	_pause = MenuPanel.new()
	_pause.visible = false
	_pause.backdrop = 0.85
	_pause.closed.connect(_resume)
	add_child(_pause)


func _process(dt: float) -> void:
	if flow == null or _pause.visible:
		return
	_dock.thinking_ms = Network.waiting_ms()
	flow.easy_dodge = Settings.get_value("easy")
	flow.coach.enabled = Settings.get_value("tips")
	var large: bool = flow.feature("text-size") and Settings.get_value("text_size") == "large"
	Hud.large_text = large
	Overlay.large_text = large
	if not flow.coach.seen.is_empty() and Settings.get_value("seen_tips").is_empty():
		flow.coach.seen = {} # SHOW THE TIPS AGAIN, from the pause menu
	_clock_ms += dt * 1000.0
	flow.tick(_clock_ms)
	var s = flow.state
	var fighting: bool = _overlay.in_fight()
	_stage.visible = not fighting or _overlay.drawn_foe() # drawn, a fight has the halls dimmed behind it
	_stage.off_set = s.foe if fighting else null
	_stage.calm = Settings.get_value("calm")
	_stage.update(s, _clock_ms / 1000.0, dt)
	_overlay.clock_ms = _clock_ms
	_automap.visible = s.floor_map != null and s.stage in ["explore", "end", "trade", "request", "camp"]
	_apply_fx()
	_postfx.set_danger((0.5 - float(s.hp) / s.max_hp) * 2.0)
	if s.viewing("warmth"):
		_postfx.set_warmth(Warmth.of(s))
	_postfx.update(dt)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or flow == null or _pause.visible:
		return
	if _on_title:
		if event.keycode == KEY_ESCAPE:
			_leave() # the card's own hint: ESC goes to the menu
		elif starts_run(event):
			_begin()
		else:
			return # Shift, Cmd, a function key: not "any key"
		get_viewport().set_input_as_handled()
		return
	if event.echo and not flow.state.stage in REPEATING:
		return
	if event.echo and flow.state.stage == "explore" and _stage.moving():
		return # a held arrow repeats once the camera has arrived; acting on every repeat would run ahead of it
	if event.meta_pressed or event.ctrl_pressed or event.alt_pressed:
		return
	if flow.state.stage in ["intro", "wait"] and flow.state.hint == "ANY KEY CONTINUE" and (starts_run(event) or event.keycode == KEY_ESCAPE):
		_press("confirm")
		get_viewport().set_input_as_handled()
		return
	if event.keycode == INFO_KEY:
		if not event.echo:
			_tips.cycle()
		get_viewport().set_input_as_handled()
		return
	var key := key_name(event)
	if key != "":
		_press(key, event.echo)
		get_viewport().set_input_as_handled()


## Whether this key press starts a run from the title card: a letter, a number, an arrow, Enter or Space, and not a modifier
## on its own, a function key, or a shortcut such as Cmd+Tab.
static func starts_run(event: InputEventKey) -> bool:
	if event.meta_pressed or event.ctrl_pressed or event.alt_pressed:
		return false
	return event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] or event.unicode > 31


## The game's key for this key press ("up", "confirm", "3"...), or "" when it is not one of the game's keys.
static func key_name(event: InputEventKey) -> String:
	if KEYS.has(event.keycode):
		return KEYS[event.keycode]
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		return str(event.keycode - KEY_0)
	if event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
		return str(event.keycode - KEY_KP_0)
	return ""


## A key of the game, from the keyboard, the pad or a click: it closes a card that was kept open, then acts.
func _press(key: String, held := false) -> void:
	_tips.unpin()
	flow.press(key, held)


## The pointer over the picture, and a click or tap on it. Where the strike bar sweeps (and on the title card) the picture is
## the big OK button; on the foe or the automap, a click keeps its card open (touch has no hover).
func _on_picture_input(event: InputEvent) -> void:
	if flow == null or _pause.visible:
		return
	if event is InputEventMouseMotion:
		_tips.hover(_in_picture(event.position))
		return
	var tapped := false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch: # with the mouse emulated from touch the same tap has already arrived as a click
		tapped = event.pressed and not Input.is_emulating_mouse_from_touch()
	if not tapped:
		return
	if _on_title:
		_begin()
	elif flow.state.stage == "fightbar" or (flow.state.stage in ["intro", "wait"] and flow.state.hint == "ANY KEY CONTINUE"):
		_press("confirm")
	else:
		_tips.tap(_in_picture(event.position))


## A point of the picture control as a point of the overlay's 448 x 288, which sits in the middle of a wider picture.
func _in_picture(at: Vector2) -> Vector2:
	if _picture.size.x <= 0.0 or _picture.size.y <= 0.0:
		return Vector2(-1, -1)
	return at / _picture.size * Vector2(_viewport.size) - Vector2(_overlay.extra_x, 0.0)


## Fill the panel, with wide-view: the 3D picture, the way the overlay and the tips sit in it, and what the party's sight takes in.
func _fit_picture() -> void:
	if flow == null:
		return
	var width: int = picture_width(_room.size) if flow.feature("wide-view") else VIEW_W
	if width == _viewport.size.x:
		return
	_viewport.size = Vector2i(width, VIEW_H)
	_aspect.ratio = float(width) / VIEW_H
	_overlay.extra_x = (width - VIEW_W) / 2.0
	_overlay.position.x = _overlay.extra_x
	_tips.fit(width)
	Vision.view_tan = Vision.VIEW_TAN * width / VIEW_W
	_postfx.fit()
	print("gameplay: the picture is %dx%d in a panel of %s" % [width, VIEW_H, _room.size])


## The pointer is over command `index` of the dock (-1: it left them): it becomes the picked one, and its help shows.
func _on_dock_hover(index: int) -> void:
	if index >= 0:
		flow.select(index)
	_tips.hover_command(index, _dock.command_screen_rect(index))


func _on_pad(key: String) -> void:
	if _pause.visible:
		return
	if _on_title:
		if key == "cancel":
			_leave()
		else:
			_begin()
		return
	if key == "info":
		_tips.cycle()
	else:
		_press(key)


## A held arrow of the pad: it keeps walking and dodging the way a held key does.
func _on_pad_repeat(key: String) -> void:
	if not _pause.visible and not _on_title and flow.state.stage in REPEATING:
		flow.press(key, true)


func _on_event(name: String, data: Dictionary) -> void:
	var now := _clock_ms / 1000.0
	var s = flow.state
	if _debug:
		print("gameplay: event %s %s (stage %s, hp %d/%d)" % [name, data, s.stage, s.hp, s.max_hp])
	match name:
		"state_replaced":
			_fit_picture()
			_bind_views()
			_fresh_floor = data.how in ["new", "floor"] and not PersonalitySlice.pending() # the slice marks its floor after it starts: never saved
			if data.how == "new":
				if flow.film_seen:
					print("gameplay: the opening film showed Wick, she doesn't hop in again")
				else:
					_stage.play_opening(now)
		"stage":
			if data.to == "explore":
				_postfx.set_accent(Palette.for_run(s.palette_id).accent) # back from a fight, the monster's colour goes
			if data.to == "explore" and (data.from != "" or _fresh_floor):
				_fresh_floor = false
				_autosave()
			_dock.set_talking(data.to == "talk")
		"bump":
			_stage.bump(now)
		"encounter":
			_postfx.set_accent(Palette.monster(s.foe))
			_overlay.intro_at = _clock_ms
			_overlay.intro_strength = 0.5 * _softness()
		"strike":
			_stage.flash_foe(s.foe, now)
			_overlay.hurt_until = _clock_ms + 300.0
			_shake()
			_postfx.flash(Color.WHITE, (0.5 if data.crit else 0.25) * _softness())
			_overlay.popup(("CRIT %d" if data.crit else "%d") % data.damage, Palette.MERCY if data.crit else Palette.INK, Vector2(224, 96))
		"miss":
			_overlay.popup("MISS", Palette.DIM, Vector2(224, 96))
		"player_hurt":
			_shake()
			_postfx.hurt()
			_overlay.popup("-%d" % data.damage, Palette.WARN, Vector2(224, 200))
			if s.viewing("clear-hp"):
				_overlay.comet(_overlay.soul_at())
		"shield":
			_overlay.popup("BLOCKED", Palette.MERCY, Vector2(224, 200))
		"beat":
			_postfx.beat()
		"spared":
			_postfx.flash(Palette.MERCY, 0.4 * _softness())
		"slain":
			_postfx.flash(Palette.BOSS, 0.4 * _softness())
		"said":
			if s.viewing("chat"):
				_overlay.send_words(data.text)
		"mood":
			_overlay.emote(data.tone)
			if data.tone == "good" and s.viewing("clear-hp"):
				_postfx.flash(Palette.MERCY, 0.14 * _softness())
		"recruited":
			if s.viewing("clear-hp"):
				_postfx.flash(Palette.MERCY, 0.45 * _softness())
		"coach":
			Settings.set_value("seen_tips", flow.coach.seen.keys())
		"trophy":
			Progress.earn(data.id)
		"run_closed":
			Progress.pay(s.run_seed, data.embers)
			flow.legacy_ranks = Progress.ranks()
		"mercy_changed":
			var up: bool = data.to > data.from
			_overlay.popup("%+d%% MERCY" % (roundi(data.to * 100.0) - roundi(data.from * 100.0)), Palette.MERCY if up else Palette.DIM, Vector2(150, 62))
		"mercy_refused":
			_overlay.popup("REFUSED", Palette.DIM, Vector2(224, 96))
		"pause_requested":
			_open_pause()
		"leave":
			_leave()


# ---------------------------------------------------------------- pause, saving, leaving

## The glow and scanlines: on unless a flag or the settings turn them off.
func _fx_on() -> bool:
	return not Flags.on("nofx") and Settings.get_value("crt")


## The settings can change at any pause, so each frame the last pass is put on or taken off to match them.
func _apply_fx() -> void:
	_postfx.calm = Settings.get_value("calm")
	if _fx_on() != _postfx.attached():
		if _fx_on():
			_postfx.attach(_picture)
		else:
			_postfx.detach()


## Calm hits: flashes only a little as bright.
func _softness() -> float:
	return 0.35 if Settings.get_value("calm") else 1.0


func _shake() -> void:
	if Settings.get_value("shake"):
		_overlay.shake_until = _clock_ms + 250.0


func _open_pause() -> void:
	_dock.set_talking(false)
	_tips.visible = false
	var ctx := {"resume": _resume, "to_main_menu": _leave, "load_slot": _load_slot}
	if flow.state.stage == "explore": # a fight can't be saved (it would come back as a walk)
		ctx["save_slot"] = _save_slot
	if not OS.has_feature("web"):
		ctx["quit"] = func(): get_tree().quit()
	_pause.open(func(): return Menus.pause(_pause, ctx))
	_pause.visible = true
	_social.suspended = true
	print("gameplay: paused")


func _resume() -> void:
	_social.suspended = false
	_pause.visible = false
	_tips.visible = true
	_dock.set_talking(flow.state.stage == "talk")
	print("gameplay: resumed")


## Save into a slot from the pause menu; the log says whether it worked.
func _save_slot(slot: String) -> bool:
	var wrote := Saves.write(slot, flow.state.to_dict(), flow.state.summary())
	flow.state.say([State.sys_line("Saved to slot %s." % slot if wrote else "Couldn't save to slot %s." % slot)])
	print("gameplay: %s slot %s" % ["saved" if wrote else "could not save", slot])
	return wrote


## Load a slot from the pause menu. A slot that can't be read, or isn't a state the game can play, leaves the run and the menu
## as they were and says so on a page of its own.
func _load_slot(slot: String) -> void:
	var saved := Saves.read(slot)
	var result := {"ok": false}
	if saved.is_empty():
		push_warning("gameplay: slot '%s' can't be read" % slot)
	else:
		await flow.exclusive(func(): result.ok = await flow.load_state(saved))
	if not result.ok:
		_pause.push(func(): return Menus.notice(_pause, "CAN'T LOAD", "That save can't be read, or isn't one this version can play. Your run is as it was."))
		return
	_resume()


## The views read the flow's current state; a new floor or a loaded save replaces it (`state_replaced`), so they are pointed at it again.
func _bind_views() -> void:
	_dress_frame()
	_header.state = flow.state
	_status.state = flow.state
	_dock.state = flow.state
	_social.state = flow.state
	_overlay.state = flow.state
	_automap.state = flow.state
	_tips.state = flow.state


## Hand-drawn, the frame round everything is the colour of this run's walls, with soft corners, instead of plain white.
func _dress_frame() -> void:
	var drawn: bool = flow.state.viewing("hand-drawn")
	var line: Color = Palette.for_run(flow.state.palette_id).wall.darkened(FRAME_DIM) if drawn else Palette.INK
	_frame_box.border_color = line
	_frame_box.set_corner_radius_all(FRAME_ROUND if drawn else 0)
	_rule.color = line


func _autosave() -> void:
	if not flow.autosave_allowed():
		return
	Saves.write(Saves.AUTO, flow.state.to_dict(), flow.state.summary())


func _leave() -> void:
	print("gameplay: back to the main menu")
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
