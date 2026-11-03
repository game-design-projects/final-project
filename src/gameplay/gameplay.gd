## The gameplay scene: one run of the game on screen. It builds the game (Flow with a mind), the picture (a 3D set in a small
## viewport, a flat layer over it, a post-processing pass) and the text around it, turns key presses into the game's keys,
## runs the clock, and turns the game's events into flashes and floating numbers. It also holds the pause menu and the
## autosave, and goes back to the main menu when the player leaves. The rules are not here: it only reads `flow.state`
## and listens to `flow.happened`.
extends Control

const Audio = preload("res://src/audio/audio.gd")
const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const Hud = preload("res://src/view/hud.gd")
const Menus = preload("res://src/menu/menus.gd")
const MenuPanel = preload("res://src/menu/menu_panel.gd")
const Minds = preload("res://src/mind/minds.gd")
const Overlay = preload("res://src/view/overlay.gd")
const Palette = preload("res://src/view/palette.gd")
const PersonalitySlice = preload("res://src/game/personality_slice.gd")
const PostFx = preload("res://src/view/postfx.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")
const Saves = preload("res://src/menu/saves.gd")
const Session = preload("res://src/menu/session.gd")
const Settings = preload("res://src/menu/settings.gd")
const StageScript = preload("res://src/view/stage.gd")

const MENU_SCENE := "res://src/menu/main_menu.tscn"
const VIEW_W := 448
const VIEW_H := 288
const FRAME_MARGIN := 8

const KEYS := {
	KEY_UP: "up", KEY_W: "up", KEY_DOWN: "down", KEY_S: "down", KEY_LEFT: "left", KEY_A: "left", KEY_RIGHT: "right", KEY_D: "right",
	KEY_ENTER: "confirm", KEY_KP_ENTER: "confirm", KEY_SPACE: "confirm", KEY_Z: "confirm", KEY_ESCAPE: "cancel", KEY_X: "cancel",
}
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
var _overlay
var _postfx
var _picture: TextureRect
var _header
var _status
var _dock
var _pause: MenuPanel
var _on_title := false # the title card is up, waiting for a key


func _ready() -> void:
	Settings.apply()
	var pending := Session.take()
	if not pending.is_empty():
		request = pending
	_build_screen()
	var slice := PersonalitySlice.pending()
	_rng = Rng.new(PersonalitySlice.seed_value()) if slice else Rng.new()
	flow = Flow.new(_rng, Minds.create(_rng, str(Store.get_value("jev_url", "")), slice))
	audio = Audio.new()
	add_child(audio)
	audio.bind(flow)
	flow.happened.connect(_on_event)
	_overlay.state = flow.state
	_header.state = flow.state
	_status.state = flow.state
	_dock.state = flow.state
	if request.is_empty() and Flags.value("meet") == "" and not slice:
		_on_title = true
		_overlay.title_card = true
		flow.state.say([State.sys_line("Press any key to start.")])
		flow.state.hint = "ANY KEY START"
		return
	await _begin()


## Start the run the request asks for (a new one, or a saved one).
func _begin() -> void:
	_on_title = false
	_overlay.title_card = false
	if request.get("kind", "new") == "load":
		if not await flow.load_state(request.state):
			push_warning("gameplay: that save can't be loaded, starting a new run")
			await flow.new_run()
	else:
		await flow.new_run()
	_after_start()


## Wire the views to the state the flow now holds, and handle the testing flags `meet=<species>` and `personality-slice`.
func _after_start() -> void:
	_overlay.state = flow.state
	_header.state = flow.state
	_status.state = flow.state
	_dock.state = flow.state
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
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
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
	rule.color = Palette.INK
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)

	var room := Control.new() # takes what the dock leaves; the picture keeps its shape inside
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.custom_minimum_size = Vector2(320, 206)
	room.clip_contents = true
	column.add_child(room)
	var aspect := AspectRatioContainer.new()
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
	_frame.add_child(picture)
	_postfx = PostFx.new()

	_status = Hud.new()
	_status.part = Hud.Part.STATUS
	_status.custom_minimum_size = Vector2(0, 18)
	column.add_child(_status)
	_dock = Hud.new()
	_dock.part = Hud.Part.DOCK
	_dock.custom_minimum_size = Vector2(0, Hud.DOCK_H)
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_dock.picked.connect(func(i): flow.press(str(i + 1)))
	_dock.said.connect(func(text): flow.submit_text(text))
	_dock.cancelled.connect(func(): flow.press("cancel"))
	column.add_child(_dock)

	_pause = MenuPanel.new()
	_pause.visible = false
	_pause.backdrop = 0.85
	_pause.closed.connect(_resume)
	add_child(_pause)


func _process(dt: float) -> void:
	if flow == null or _pause.visible:
		return
	_clock_ms += dt * 1000.0
	flow.tick(_clock_ms)
	var s = flow.state
	_stage.update(s, _clock_ms / 1000.0, dt)
	if _stage.palette.has("wall"):
		_overlay.wall_color = _stage.palette.wall
		_overlay.accent_color = _stage.palette.accent
	_overlay.clock_ms = _clock_ms
	_stage.visible = not _overlay.in_fight()
	_picture.material = _postfx.material if _fx_on() else null
	_postfx.set_danger((0.5 - float(s.hp) / s.max_hp) * 2.0)
	_postfx.update(dt)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or flow == null or _pause.visible:
		return
	if _on_title:
		if event.keycode == KEY_ESCAPE:
			_leave() # the card's own hint: ESC goes to the menu
		else:
			_begin()
		get_viewport().set_input_as_handled()
		return
	if event.echo and not flow.state.stage in REPEATING:
		return
	if event.meta_pressed or event.ctrl_pressed or event.alt_pressed:
		return
	var key := ""
	if KEYS.has(event.keycode):
		key = KEYS[event.keycode]
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		key = str(event.keycode - KEY_0)
	if key != "":
		flow.press(key)
		get_viewport().set_input_as_handled()


func _on_event(name: String, data: Dictionary) -> void:
	var now := _clock_ms / 1000.0
	var s = flow.state
	match name:
		"stage":
			if data.to == "explore" and data.from != "":
				_autosave()
			_dock.set_talking(data.to == "talk")
		"encounter":
			_postfx.set_accent(Palette.monster(s.foe))
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
			if not Settings.get_value("calm"):
				_postfx.hurt()
			_overlay.popup("-%d" % data.damage, Palette.WARN, Vector2(224, 200))
		"shield":
			_overlay.popup("BLOCKED", Palette.MERCY, Vector2(224, 200))
		"beat":
			_postfx.beat()
		"spared":
			_postfx.flash(Palette.MERCY, 0.4 * _softness())
		"slain":
			_postfx.flash(Palette.BOSS, 0.4 * _softness())
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


## Calm hits: flashes only a little as bright.
func _softness() -> float:
	return 0.35 if Settings.get_value("calm") else 1.0


func _shake() -> void:
	if Settings.get_value("shake"):
		_overlay.shake_until = _clock_ms + 250.0


func _open_pause() -> void:
	_dock.set_talking(false)
	var ctx := {"resume": _resume, "to_main_menu": _leave, "load_slot": _load_slot}
	if flow.state.stage == "explore": # a fight can't be saved (it would come back as a walk)
		ctx["save_slot"] = func(slot): Saves.write(slot, flow.state.to_dict(), flow.state.summary())
	if not OS.has_feature("web"):
		ctx["quit"] = func(): get_tree().quit()
	_pause.open(func(): return Menus.pause(_pause, ctx))
	_pause.visible = true
	print("gameplay: paused")


func _resume() -> void:
	_pause.visible = false
	_dock.set_talking(flow.state.stage == "talk")
	print("gameplay: resumed")


func _load_slot(slot: String) -> void:
	var saved := Saves.read(slot)
	if saved.is_empty():
		push_warning("gameplay: slot '%s' can't be read" % slot)
		return
	_pause.visible = false
	await flow.load_state(saved)
	_header.state = flow.state
	_status.state = flow.state
	_dock.state = flow.state
	_overlay.state = flow.state


func _autosave() -> void:
	if flow.slice_floor: # the playtest slice's floor leaves no save behind
		return
	Saves.write(Saves.AUTO, flow.state.to_dict(), flow.state.summary())


func _leave() -> void:
	print("gameplay: back to the main menu")
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
