extends "res://tests/test_case.gd"

const Keys = preload("res://src/ui/keys.gd")


func _key(keycode: Key, unicode := 0, shift := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = unicode
	ev.shift_pressed = shift
	ev.pressed = true
	return ev


func test_named_keys_match_keyboard_event_key_lowercased():
	eq(Keys.js_key(_key(KEY_UP)), "arrowup")
	eq(Keys.js_key(_key(KEY_DOWN)), "arrowdown")
	eq(Keys.js_key(_key(KEY_LEFT)), "arrowleft")
	eq(Keys.js_key(_key(KEY_RIGHT)), "arrowright")
	eq(Keys.js_key(_key(KEY_ENTER)), "enter")
	eq(Keys.js_key(_key(KEY_KP_ENTER)), "enter")
	eq(Keys.js_key(_key(KEY_ESCAPE)), "escape")
	eq(Keys.js_key(_key(KEY_SPACE, 32)), " ")
	eq(Keys.js_key(_key(KEY_BACKSPACE)), "backspace")
	eq(Keys.js_key(_key(KEY_SHIFT)), "shift")
	eq(Keys.js_key(_key(KEY_F5)), "f5")


func test_printable_keys_use_the_typed_character():
	eq(Keys.js_key(_key(KEY_A, 97)), "a")
	eq(Keys.js_key(_key(KEY_A, 65, true)), "a", "shift+A lower-cased")
	eq(Keys.js_key(_key(KEY_1, 49)), "1")
	eq(Keys.js_key(_key(KEY_1, 33, true)), "!", "shift+1 is !")
	eq(Keys.js_key(_key(KEY_KP_3, 51)), "3")


func test_shortcuts_and_space():
	var ev := _key(KEY_R, 114)
	ok(not Keys.is_shortcut(ev))
	ev.meta_pressed = true
	ok(Keys.is_shortcut(ev), "cmd+R is the browser's")
	ok(Keys.is_space(_key(KEY_SPACE, 32)))
	ok(not Keys.is_space(_key(KEY_ENTER)))
