## Every page of the main menu and the pause menu, as builders for `menu_panel.gd`. A page function takes the panel and
## a context Dictionary of Callables the owner provides, and returns the page Dictionary:
##   new_game()            start a run                      load_slot(slot)       load that save and play it
##   save_slot(slot)->bool write the run into a slot        resume()              (pause) close the menu
##   to_main_menu()        (pause) leave for the main menu  quit()                leave the program (absent on the web)
## `save_slot` and `resume` exist only while a run is on screen (the pause menu); the pages show the actions that fit.
extends RefCounted

const Settings = preload("res://src/menu/settings.gd")
const Saves = preload("res://src/menu/saves.gd")

const KEYS_HINT := "UP / DOWN CHOOSE   ENTER PICK   ESC BACK"
const ADJUST_HINT := "UP / DOWN CHOOSE   LEFT / RIGHT CHANGE   ESC BACK"


static func _go(panel, builder: Callable) -> Callable:
	return func(): panel.push(builder)


# ---------------------------------------------------------------- the two top pages

static func main(panel, ctx: Dictionary) -> Dictionary:
	var latest := Saves.latest()
	var any_save := not Saves.list().filter(func(i): return not i.empty).is_empty()
	var items := [
		{
			"label": "CONTINUE", "enabled": not latest.is_empty(),
			"sub": ("%s  %s" % [latest.summary, Saves.when(latest.saved_at)]) if not latest.is_empty() else "No save yet",
			"run": func(): ctx.load_slot.call(latest.slot),
		},
		{"label": "NEW GAME", "sub": "One floor, one run", "run": func(): ctx.new_game.call()},
		{"label": "LOAD GAME", "enabled": any_save, "run": _go(panel, func(): return slot_list(panel, ctx, "load"))},
		{"label": "SAVE MANAGER", "sub": "Copy, rename, delete", "run": _go(panel, func(): return slot_list(panel, ctx, "manage"))},
		{"label": "SETTINGS", "run": _go(panel, func(): return settings(panel, ctx))},
		{"label": "CREDITS", "run": _go(panel, func(): return credits())},
	]
	if ctx.has("quit"):
		items.append({"label": "QUIT", "run": func(): ctx.quit.call()})
	return {"title": "DONJON", "items": items, "hint": KEYS_HINT}


static func pause(panel, ctx: Dictionary) -> Dictionary:
	var items := [
		{"label": "RESUME", "run": func(): ctx.resume.call()},
		{
			"label": "SAVE GAME", "enabled": ctx.has("save_slot"), "sub": "" if ctx.has("save_slot") else "Only while walking, not in a fight",
			"run": _go(panel, func(): return slot_list(panel, ctx, "save")),
		},
		{"label": "LOAD GAME", "run": _go(panel, func(): return slot_list(panel, ctx, "load"))},
		{"label": "SETTINGS", "run": _go(panel, func(): return settings(panel, ctx))},
		{
			"label": "MAIN MENU", "sub": "Progress since the last save is lost",
			"run": _go(panel, func(): return confirm(panel, "LEAVE THE RUN?", "Anything since your last save is lost.", "MAIN MENU", func(): ctx.to_main_menu.call())),
		},
	]
	return {"title": "PAUSED", "items": items, "hint": KEYS_HINT, "back": func(): ctx.resume.call()}


## NO first (the highlighted one), then the action
static func confirm(panel, title: String, text: String, yes_label: String, on_yes: Callable) -> Dictionary:
	return {
		"title": title,
		"hint": text,
		"items": [
			{"label": "NO, GO BACK", "run": func(): panel.pop()},
			{"label": yes_label, "run": on_yes},
		],
	}


# ---------------------------------------------------------------- saves

## `mode`: "load" (Enter loads), "save" (Enter writes), "manage" (Enter opens the slot's actions)
static func slot_list(panel, ctx: Dictionary, mode: String) -> Dictionary:
	var items := []
	for i in Saves.list():
		var info: Dictionary = i
		var slot: String = info.slot
		var label := "AUTOSAVE" if slot == Saves.AUTO else "SLOT " + slot
		if info.name != "":
			label += "  " + info.name.to_upper()
		var item := {"label": label, "value": Saves.when(info.saved_at), "sub": "EMPTY" if info.empty else info.summary}
		match mode:
			"load":
				item.enabled = not info.empty and not info.corrupt
				item.run = func(): _load(panel, ctx, info)
			"save":
				item.enabled = slot != Saves.AUTO
				item.run = func(): _save(panel, ctx, info)
			_:
				item.enabled = not info.empty
				item.run = _go(panel, func(): return slot_actions(panel, ctx, slot))
		items.append(item)
	var titles := {"load": "LOAD GAME", "save": "SAVE GAME", "manage": "SAVE MANAGER"}
	return {"title": titles[mode], "items": items, "hint": "ENTER " + {"load": "LOADS", "save": "SAVES HERE", "manage": "OPENS THE SLOT"}[mode] + "   ESC BACK"}


static func _load(panel, ctx: Dictionary, info: Dictionary) -> void:
	if ctx.has("resume"):
		panel.push(func(): return confirm(panel, "LOAD THIS SAVE?", "Anything since your last save is lost.", "LOAD", func(): ctx.load_slot.call(info.slot)))
	else:
		ctx.load_slot.call(info.slot)


static func _save(panel, ctx: Dictionary, info: Dictionary) -> void:
	if info.empty:
		ctx.save_slot.call(info.slot)
		panel.refresh()
	else:
		panel.push(func(): return confirm(panel, "OVERWRITE SLOT %s?" % info.slot, "The old save is replaced.", "OVERWRITE", _do_overwrite.bind(panel, ctx, info.slot)))


static func _do_overwrite(panel, ctx: Dictionary, slot: String) -> void:
	ctx.save_slot.call(slot)
	panel.pop() # the confirm
	panel.refresh()


static func slot_actions(panel, ctx: Dictionary, slot: String) -> Dictionary:
	var info := Saves.info(slot)
	var manual := slot != Saves.AUTO
	var items := [
		{"label": "LOAD", "enabled": not info.empty and not info.corrupt, "run": func(): _load(panel, ctx, info)},
		{"label": "COPY TO...", "run": _go(panel, func(): return copy_target(panel, ctx, slot))},
		{"label": "RENAME", "enabled": manual and not info.corrupt, "run": func(): panel.push(func(): return rename_page(panel, slot, info.name))},
		{
			"label": "DELETE",
			"run": func(): panel.push(func(): return confirm(panel, "DELETE THIS SAVE?", "It can't be brought back.", "DELETE", _do_delete.bind(panel, slot))),
		},
	]
	var name := "AUTOSAVE" if not manual else "SLOT " + slot
	return {"title": name, "items": items, "hint": ("%s  %s" % [info.summary, Saves.when(info.saved_at)]) if not info.empty else ""}


static func rename_page(panel, slot: String, current: String) -> Dictionary:
	return {"title": "NAME THIS SAVE", "items": [], "hint": "ENTER KEEPS THE NAME   ESC CANCELS", "input": {"text": current, "submit": _do_rename.bind(panel, slot)}}


static func _do_rename(text: String, panel, slot: String) -> void:
	Saves.rename(slot, text)
	panel.refresh()


## Back from the confirm and the slot's actions to the list
static func _do_delete(panel, slot: String) -> void:
	Saves.delete(slot)
	panel.pop()
	panel.pop()
	panel.refresh()


static func copy_target(panel, ctx: Dictionary, from: String) -> Dictionary:
	var items := []
	for i in Saves.list():
		var info: Dictionary = i
		if info.slot == Saves.AUTO or info.slot == from:
			continue
		var to: String = info.slot
		var item := {"label": "SLOT " + to, "sub": "EMPTY" if info.empty else "Replaces: " + info.summary}
		if info.empty:
			item.run = _do_copy.bind(panel, from, to, 2)
		else:
			item.run = func(): panel.push(func(): return confirm(panel, "REPLACE SLOT %s?" % to, "The old save is replaced.", "REPLACE", _do_copy.bind(panel, from, to, 3)))
		items.append(item)
	return {"title": "COPY TO", "items": items, "hint": KEYS_HINT}


## `pops`: pages to go back (the target list and the slot's actions, plus the confirm when there was one)
static func _do_copy(panel, from: String, to: String, pops: int) -> void:
	Saves.copy(from, to)
	for _i in pops:
		panel.pop()
	panel.refresh()


# ---------------------------------------------------------------- settings

static func _setting(panel, key: String, label: String, sub := "") -> Dictionary:
	return {
		"label": label, "sub": sub, "value": Settings.label(key, Settings.get_value(key)),
		"adjust": func(dir): Settings.set_value(key, Settings.cycled(key, dir)),
	}


static func settings(panel, ctx: Dictionary) -> Dictionary:
	var items := [
		{"label": "DISPLAY", "sub": "Window, sync, frame rate", "run": _go(panel, func(): return display(panel))},
		{"label": "EFFECTS", "sub": "The glow, hit flashes, shaking", "run": _go(panel, func(): return effects(panel))},
		{"label": "SOUND", "run": _go(panel, func(): return sound(panel))},
		{"label": "CONTROLS", "run": _go(panel, func(): return controls())},
		{"label": "DATA", "sub": "Saves and settings", "run": _go(panel, func(): return data(panel, ctx))},
	]
	return {"title": "SETTINGS", "items": items, "hint": KEYS_HINT + "   Changes apply at once and are kept."}


static func display(panel) -> Dictionary:
	return {"title": "DISPLAY", "hint": ADJUST_HINT, "items": [
		_setting(panel, "window_mode", "WINDOW"),
		_setting(panel, "vsync", "VSYNC", "Stops tearing; off can lower input lag"),
		_setting(panel, "fps_cap", "FRAME RATE"),
	]}


static func effects(panel) -> Dictionary:
	return {"title": "EFFECTS", "hint": ADJUST_HINT, "items": [
		_setting(panel, "crt", "CRT GLOW", "The glow and scanlines over the dungeon"),
		_setting(panel, "calm", "CALM HITS", "Softer flashes and no color split on hits"),
		_setting(panel, "shake", "SCREEN SHAKE"),
	]}


static func sound(panel) -> Dictionary:
	return {"title": "SOUND", "hint": ADJUST_HINT, "items": [
		_setting(panel, "sfx", "SOUND EFFECTS"),
		_setting(panel, "sfx_volume", "VOLUME"),
	]}


static func controls() -> Dictionary:
	var body := "[color=#ffd27a]Walking[/color]\nUp / W  forward      Down / S  back\nLeft / A  turn left      Right / D  turn right\n\n"
	body += "[color=#ffd27a]Menus[/color]\nUp / Down  choose      Enter / Space / Z  pick\nEsc / X  back      1-9  pick that one\n\n"
	body += "[color=#ffd27a]In a fight[/color]\nFight: Enter when the line crosses the middle\nDodge: arrows or WASD move your heart\nEsc  pause menu (walking and the fight menu)"
	return {"title": "CONTROLS", "body": body, "items": [], "hint": "ESC BACK"}


static func data(panel, _ctx: Dictionary) -> Dictionary:
	var items := []
	if not OS.has_feature("web"):
		items.append({"label": "OPEN SAVE FOLDER", "run": func(): OS.shell_open(ProjectSettings.globalize_path(Saves.dir()))})
	items.append({
		"label": "RESET SETTINGS",
		"run": func(): panel.push(func(): return confirm(panel, "RESET SETTINGS?", "Everything on the settings pages goes back to its default.", "RESET", _do_reset.bind(panel))),
	})
	items.append({
		"label": "DELETE ALL SAVES",
		"run": func(): panel.push(func(): return confirm(panel, "DELETE ALL SAVES?", "Every slot, the autosave too. It can't be brought back.", "DELETE ALL", _do_delete_all.bind(panel))),
	})
	return {"title": "DATA", "items": items, "hint": KEYS_HINT}


static func _do_reset(panel) -> void:
	Settings.reset()
	panel.pop()
	panel.refresh()


static func _do_delete_all(panel) -> void:
	Saves.delete_all()
	panel.pop()
	panel.refresh()


# ---------------------------------------------------------------- credits

static func credits() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://assets/CREDITS.txt")
	text = text.replace("[", "[lb]")
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return {"title": "CREDITS", "body": "[color=#ffd27a]Donjon %s[/color]\n\n%s" % [version, text], "items": [], "hint": "UP / DOWN SCROLL   ESC BACK"}
