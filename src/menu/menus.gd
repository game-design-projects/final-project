## Every page of the main menu and the pause menu, as builders for menu_panel.gd. A page function takes the panel and `ctx`,
## a Dictionary of Callables the owner provides (the owner is the scene that really starts runs and writes saves):
##   new_game()           start a run                    load_slot(slot)   load that save and play it
##   save_slot(slot)      write the run into a slot      resume()          (pause) close the menu
##   to_main_menu()       (pause) leave for the main menu    quit()        leave the program (absent on the web)
## `save_slot` and `resume` exist only while a run is on screen, and `save_slot` only while walking, so the pages show what fits.
extends RefCounted

const Saves = preload("res://src/menu/saves.gd")
const Settings = preload("res://src/menu/settings.gd")

const KEYS_HINT := "UP / DOWN CHOOSE · ENTER PICK · ESC BACK"
const ADJUST_HINT := "UP / DOWN CHOOSE · LEFT / RIGHT CHANGE · ESC BACK"


static func _go(panel, builder: Callable) -> Callable:
	return func(): panel.push(builder)


# ---------------------------------------------------------------- the two top pages

static func main(panel, ctx: Dictionary) -> Dictionary:
	var latest := Saves.latest()
	var any_save := not Saves.list().filter(func(i): return not i.empty).is_empty()
	var items := [
		{
			"label": "CONTINUE", "disabled": latest.is_empty(),
			"sub": ("%s  %s" % [latest.summary, Saves.when(latest.saved_at)]) if not latest.is_empty() else "No save yet",
			"act": func(): ctx.load_slot.call(latest.slot),
		},
		{"label": "NEW GAME", "sub": "One floor, one run", "act": func(): ctx.new_game.call()},
		{"label": "LOAD GAME", "disabled": not any_save, "act": _go(panel, func(): return slot_list(panel, ctx, "load"))},
		{"label": "SAVE MANAGER", "sub": "Copy, rename, delete", "act": _go(panel, func(): return slot_list(panel, ctx, "manage"))},
		{"label": "SETTINGS", "act": _go(panel, func(): return settings(panel))},
		{"label": "CREDITS", "act": _go(panel, func(): return credits())},
	]
	if ctx.has("quit"):
		items.append({"label": "QUIT GAME", "act": func(): ctx.quit.call()})
	return {"title": "DONJON", "items": items, "hint": KEYS_HINT}


static func pause(panel, ctx: Dictionary) -> Dictionary:
	var can_save: bool = ctx.has("save_slot")
	var items := [
		{"label": "RESUME", "act": func(): ctx.resume.call()},
		{"label": "SAVE GAME", "disabled": not can_save, "sub": "" if can_save else "Only while walking, not in a fight", "act": _go(panel, func(): return slot_list(panel, ctx, "save"))},
		{"label": "LOAD GAME", "act": _go(panel, func(): return slot_list(panel, ctx, "load"))},
		{"label": "SETTINGS", "act": _go(panel, func(): return settings(panel))},
		{
			"label": "MAIN MENU", "sub": "Progress since the last save is lost",
			"act": _go(panel, func(): return confirm(panel, "LEAVE THE RUN?", "Anything since your last save is lost.", "MAIN MENU", func(): ctx.to_main_menu.call())),
		},
	]
	if ctx.has("quit"):
		items.append({
			"label": "QUIT GAME", "sub": "Progress since the last save is lost",
			"act": _go(panel, func(): return confirm(panel, "QUIT THE GAME?", "Anything since your last save is lost.", "QUIT GAME", func(): ctx.quit.call())),
		})
	return {"title": "PAUSED", "items": items, "hint": "UP / DOWN CHOOSE · ENTER PICK · ESC RESUME", "back": func(): ctx.resume.call()}


## NO comes first, so it is the one highlighted.
static func confirm(panel, title: String, text: String, yes_label: String, on_yes: Callable) -> Dictionary:
	return {"title": title, "hint": text, "items": [
		{"label": "NO, GO BACK", "act": func(): panel.pop()},
		{"label": yes_label, "act": on_yes},
	]}


# ---------------------------------------------------------------- saves

## `mode`: "load" (Enter loads), "save" (Enter writes), "manage" (Enter opens the slot's actions).
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
				item.disabled = info.empty or info.corrupt
				item.act = func(): _load(panel, ctx, info)
			"save":
				item.disabled = slot == Saves.AUTO
				item.act = func(): _save(panel, ctx, info)
			_:
				item.disabled = info.empty
				item.act = _go(panel, func(): return slot_actions(panel, ctx, slot))
		items.append(item)
	var titles := {"load": "LOAD GAME", "save": "SAVE GAME", "manage": "SAVE MANAGER"}
	var enter := {"load": "LOADS", "save": "SAVES HERE", "manage": "OPENS THE SLOT"}
	return {"title": titles[mode], "items": items, "hint": "ENTER %s · ESC BACK" % enter[mode]}


static func _load(panel, ctx: Dictionary, info: Dictionary) -> void:
	if ctx.has("resume"): # in a run: loading throws the run away, so ask
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
		{"label": "LOAD", "disabled": info.empty or info.corrupt, "act": func(): _load(panel, ctx, info)},
		{"label": "COPY TO...", "act": _go(panel, func(): return copy_target(panel, slot))},
		{"label": "RENAME", "disabled": not manual or info.corrupt, "act": func(): panel.push(func(): return rename_page(panel, slot, info.name))},
		{"label": "DELETE", "act": func(): panel.push(func(): return confirm(panel, "DELETE THIS SAVE?", "It can't be brought back.", "DELETE", _do_delete.bind(panel, slot)))},
	]
	var hint := ("%s  %s" % [info.summary, Saves.when(info.saved_at)]) if not info.empty else ""
	return {"title": "AUTOSAVE" if not manual else "SLOT " + slot, "items": items, "hint": hint}


static func rename_page(panel, slot: String, current: String) -> Dictionary:
	return {"title": "NAME THIS SAVE", "items": [], "hint": "ENTER KEEPS THE NAME · ESC CANCELS", "input": {"text": current, "submit": _do_rename.bind(slot)}}


static func _do_rename(text: String, slot: String) -> void:
	Saves.rename(slot, text)


## Back from the confirm and the slot's actions to the list.
static func _do_delete(panel, slot: String) -> void:
	Saves.delete(slot)
	panel.pop()
	panel.pop()
	panel.refresh()


static func copy_target(panel, from: String) -> Dictionary:
	var items := []
	for i in Saves.list():
		var info: Dictionary = i
		if info.slot == Saves.AUTO or info.slot == from:
			continue
		var to: String = info.slot
		var item := {"label": "SLOT " + to, "sub": "EMPTY" if info.empty else "Replaces: " + info.summary}
		if info.empty:
			item.act = _do_copy.bind(panel, from, to, 2)
		else:
			item.act = func(): panel.push(func(): return confirm(panel, "REPLACE SLOT %s?" % to, "The old save is replaced.", "REPLACE", _do_copy.bind(panel, from, to, 3)))
		items.append(item)
	return {"title": "COPY TO", "items": items, "hint": KEYS_HINT}


## `pops`: pages to go back (the target list and the slot's actions, plus the confirm when there was one).
static func _do_copy(panel, from: String, to: String, pops: int) -> void:
	Saves.copy(from, to)
	for _i in pops:
		panel.pop()
	panel.refresh()


# ---------------------------------------------------------------- settings

static func _setting(key: String, label: String, sub := "") -> Dictionary:
	return {"label": label, "sub": sub, "value": Settings.label(key), "adjust": func(dir): Settings.set_value(key, Settings.cycled(key, dir))}


static func settings(panel) -> Dictionary:
	return {"title": "SETTINGS", "hint": KEYS_HINT + " · Changes save at once.", "items": [
		{"label": "DISPLAY", "sub": "Window, sync, frame rate", "act": _go(panel, func(): return display())},
		{"label": "EFFECTS", "sub": "The glow, hit flashes, shaking", "act": _go(panel, func(): return effects())},
		{"label": "SOUND", "act": _go(panel, func(): return sound())},
		{"label": "CONTROLS", "act": _go(panel, func(): return controls())},
		{"label": "DATA", "sub": "Saves and settings", "act": _go(panel, func(): return data(panel))},
	]}


static func display() -> Dictionary:
	return {"title": "DISPLAY", "hint": ADJUST_HINT, "items": [
		_setting("window_mode", "WINDOW"),
		_setting("vsync", "VSYNC", "Stops tearing; off can lower input lag"),
		_setting("fps_cap", "FRAME RATE"),
	]}


static func effects() -> Dictionary:
	return {"title": "EFFECTS", "hint": ADJUST_HINT, "items": [
		_setting("crt", "CRT GLOW", "The glow and scanlines over the picture"),
		_setting("calm", "CALM HITS", "Softer flashes and no colour split on hits"),
		_setting("shake", "SCREEN SHAKE"),
	]}


static func sound() -> Dictionary:
	return {"title": "SOUND", "hint": ADJUST_HINT, "items": [
		_setting("sfx", "SOUND EFFECTS", "Effects and music"),
		_setting("sfx_volume", "VOLUME"),
	]}


static func controls() -> Dictionary:
	var gold := "[color=#ffd27a]"
	var body := gold + "Walking[/color]\nUp / W  forward      Down / S  back\nLeft / A  turn left      Right / D  turn right\n\n"
	body += gold + "Menus[/color]\nUp / Down  choose      Enter / Space / Z  pick\nEsc / X  back      1-9  pick that one\n\n"
	body += gold + "In a fight[/color]\nFight: Enter when the line crosses the middle\nDodge: arrows or WASD move your heart\nEsc  pause menu (walking and the fight menu)"
	return {"title": "CONTROLS", "body": body, "items": [], "hint": "UP / DOWN SCROLL · ESC BACK"}


static func data(panel) -> Dictionary:
	var items := []
	if not OS.has_feature("web"):
		items.append({"label": "OPEN SAVE FOLDER", "act": func(): OS.shell_open(ProjectSettings.globalize_path(Saves.dir_path))})
	items.append({"label": "RESET SETTINGS", "act": func(): panel.push(func(): return confirm(panel, "RESET SETTINGS?", "Everything on the settings pages goes back to its default.", "RESET", _do_reset.bind(panel)))})
	items.append({"label": "DELETE ALL SAVES", "act": func(): panel.push(func(): return confirm(panel, "DELETE ALL SAVES?", "Every slot, the autosave too. It can't be brought back.", "DELETE ALL", _do_delete_all.bind(panel)))})
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
	var text := FileAccess.get_file_as_string("res://assets/CREDITS.txt").replace("[", "[lb]")
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	return {"title": "CREDITS", "body": "[color=#ffd27a]Donjon %s[/color]\n\n%s" % [version, text], "items": [], "hint": "UP / DOWN SCROLL · ESC BACK"}
