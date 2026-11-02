extends "res://tests/test_case.gd"

const Settings = preload("res://src/menu/settings.gd")
const MemoryStore = preload("res://src/core/store.gd").Memory


func before_each() -> void:
	Settings.store_override = MemoryStore.new()
	Settings.apply_enabled = false
	Settings.forget()


func after_each() -> void:
	Settings.store_override = null
	Settings.apply_enabled = true
	Settings.forget()


func test_defaults_when_nothing_is_stored() -> void:
	eq(Settings.current(), Settings.DEFAULTS)
	ok(Settings.get_value("crt"), "the CRT pass is on by default")


func test_set_value_saves_and_survives_a_reload() -> void:
	ok(Settings.set_value("window_mode", "fullscreen"))
	ok(Settings.set_value("sfx_volume", 8))
	Settings.forget()
	eq(Settings.get_value("window_mode"), "fullscreen")
	eq(Settings.get_value("sfx_volume"), 8)
	eq(Settings.get_value("vsync"), true, "the rest stays at the default")


func test_invalid_values_are_refused() -> void:
	ok(not Settings.set_value("window_mode", "sideways"))
	ok(not Settings.set_value("sfx_volume", 11))
	ok(not Settings.set_value("crt", "yes"))
	ok(not Settings.set_value("nonsense", 1))
	eq(Settings.current(), Settings.DEFAULTS)


func test_a_damaged_store_falls_back_per_key() -> void:
	Settings.store_override.set_item(Settings.KEY, '{"window_mode":"fullscreen","fps_cap":77,"crt":"no","extra":1,"sfx_volume":3.0}')
	Settings.forget()
	var d := Settings.current()
	eq(d.window_mode, "fullscreen", "the good key stays")
	eq(d.fps_cap, 0, "an option that isn't on the list falls back")
	eq(d.crt, true, "a wrong type falls back")
	eq(d.sfx_volume, 3, "JSON floats become ints")
	ok(not d.has("extra"), "unknown keys are dropped")
	Settings.store_override.set_item(Settings.KEY, "{not json")
	Settings.forget()
	eq(Settings.current(), Settings.DEFAULTS)


func test_cycled_walks_the_options_and_wraps() -> void:
	eq(Settings.cycled("window_mode", 1), "maximized")
	eq(Settings.cycled("window_mode", -1), "fullscreen")
	eq(Settings.cycled("vsync"), false)
	Settings.set_value("sfx_volume", 10)
	eq(Settings.cycled("sfx_volume", 1), 0)


func test_reset_and_labels_and_gain() -> void:
	Settings.set_value("sfx", false)
	near(Settings.sfx_gain(Settings.current()), 0.0, 1e-9, "sound off is silent")
	Settings.reset()
	eq(Settings.current(), Settings.DEFAULTS)
	near(Settings.sfx_gain(Settings.current()), 0.5, 1e-9)
	eq(Settings.label("window_mode", "fullscreen"), "FULLSCREEN")
	eq(Settings.label("fps_cap", 0), "NO CAP")
	eq(Settings.label("crt", true), "ON")
	eq(Settings.label("sfx_volume", 5), "5 / 10")
