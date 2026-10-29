## Base for the panels that paint themselves in `_draw()` the way the page's CSS draws its boxes. While painting,
## a panel registers regions (`add_hit`): a button with its key, a hint for the dock's hint line, a tooltip text.
## The base turns mouse input over those regions into hover (redraws), clicks (`_pressed`), the hand cursor and
## the pixel tooltips. Clicks pass through anywhere a panel registered nothing unless `solid` is set.
extends Control

const Css = preload("res://src/ui/css.gd")

## main.gd: the game, the tooltip, the tip focus
var ui
## Take the mouse over the whole rect, not only over the regions (a panel with a background)
var solid := false
var hits: Array = [] # [{rect, id, key?, hint?, tip?, ...}], in paint order (later ones are on top)
var hover_id := ""
var press_id := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## Registers a region painted this frame. `data` may carry: id (defaults to key or tip), key, hint, tip, anything else.
func add_hit(r: Rect2, data: Dictionary) -> void:
	var d := data.duplicate()
	d.rect = r
	if not d.has("id"):
		d.id = str(d.get("key", d.get("tip", "r%d" % hits.size())))
	hits.append(d)


func hit_at(p: Vector2):
	for i in range(hits.size() - 1, -1, -1):
		if (hits[i].rect as Rect2).has_point(p):
			return hits[i]
	return null


func hovered():
	for h in hits:
		if h.id == hover_id:
			return h
	return null


func _has_point(p: Vector2) -> bool:
	if not visible:
		return false
	if solid:
		return Rect2(Vector2.ZERO, size).has_point(p)
	return hit_at(p) != null


func _draw() -> void:
	hits.clear()
	paint()
	if ui != null and ui.has_method("paint_focus"):
		ui.paint_focus(self)


## Override: paint the panel and register its regions
func paint() -> void:
	pass


## Override: a region was clicked (press and release on it)
func _pressed(_h: Dictionary) -> void:
	pass


## Override: the mouse went down on a region (the mic button listens while held)
func _down(_h: Dictionary) -> void:
	pass


## Override: the mouse came up after `_down`
func _up(_h) -> void:
	pass


## Override: the region under the mouse changed (null: none)
func _hover_changed(_h) -> void:
	pass


## Override: the mouse wheel over the panel (dy > 0 scrolls down)
func _wheel(_dy: float) -> bool:
	return false


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_track(ev.position)
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed and _wheel(-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0):
				accept_event()
				if ui != null:
					ui.hide_tooltip()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var h = hit_at(mb.position)
		if mb.pressed:
			press_id = h.id if h != null else ""
			if h != null:
				_down(h)
				accept_event()
		else:
			var was := press_id
			press_id = ""
			_up(h)
			if h != null and h.id == was:
				accept_event()
				_pressed(h)


func _track(p: Vector2) -> void:
	var h = hit_at(p)
	var id: String = h.id if h != null else ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != null and (h.has("key") or h.get("click", false)) else Control.CURSOR_ARROW
	if id == hover_id:
		return
	hover_id = id
	queue_redraw()
	_hover_changed(h)
	if ui != null:
		if h != null and str(h.get("tip", "")) != "":
			ui.show_tooltip(self, h.rect, h.tip)
		else:
			ui.leave_tooltip(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover_id != "":
		hover_id = ""
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		queue_redraw()
		_hover_changed(null)
		if ui != null:
			ui.leave_tooltip(self)


## Re-checks what is under the mouse after a repaint moved things (a new dock under a still mouse)
func retrack() -> void:
	if not is_visible_in_tree():
		return
	var p := get_local_mouse_position()
	if Rect2(Vector2.ZERO, size).has_point(p):
		_track(p)


func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0
