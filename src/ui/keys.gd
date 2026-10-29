## Keyboard events as the strings the web game read from them: KeyboardEvent.key, lower-cased ("arrowup", "enter",
## "escape", " ", "a", "1", "!"). game.gd's key() and KEYMAP speak this language. Pure, tested in tests/ui.
extends RefCounted

const NAMES := {
	KEY_UP: "arrowup",
	KEY_DOWN: "arrowdown",
	KEY_LEFT: "arrowleft",
	KEY_RIGHT: "arrowright",
	KEY_ENTER: "enter",
	KEY_KP_ENTER: "enter",
	KEY_ESCAPE: "escape",
	KEY_SPACE: " ",
	KEY_BACKSPACE: "backspace",
	KEY_TAB: "tab",
	KEY_DELETE: "delete",
	KEY_INSERT: "insert",
	KEY_HOME: "home",
	KEY_END: "end",
	KEY_PAGEUP: "pageup",
	KEY_PAGEDOWN: "pagedown",
	KEY_SHIFT: "shift",
	KEY_CTRL: "control",
	KEY_ALT: "alt",
	KEY_META: "meta",
	KEY_CAPSLOCK: "capslock",
	KEY_NUMLOCK: "numlock",
	KEY_SCROLLLOCK: "scrolllock",
	KEY_PAUSE: "pause",
	KEY_PRINT: "printscreen",
	KEY_MENU: "contextmenu",
}


## e.key.toLowerCase() for a key event ("" when there is nothing to call it)
static func js_key(ev: InputEventKey) -> String:
	var code := ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
	if NAMES.has(code):
		return NAMES[code]
	if ev.unicode >= 32:
		return String.chr(ev.unicode).to_lower()
	if code >= KEY_F1 and code <= KEY_F35:
		return "f%d" % (code - KEY_F1 + 1)
	if code == KEY_NONE:
		return ""
	return OS.get_keycode_string(code).to_lower().replace(" ", "")


## The web game ignored keys pressed with Cmd, Ctrl or Alt (the browser's own shortcuts); Shift is fine.
static func is_shortcut(ev: InputEventKey) -> bool:
	return ev.meta_pressed or ev.ctrl_pressed or ev.alt_pressed


## KeyboardEvent.code === "Space"
static func is_space(ev: InputEventKey) -> bool:
	return ev.physical_keycode == KEY_SPACE or (ev.physical_keycode == KEY_NONE and ev.keycode == KEY_SPACE)
