## Where every part of the screen goes for a window size: the web page's layout (style.css .wrap, .crt, .mid,
## .main-col, .side, .dock, .jev) worked out in pixels. Pure, so it is tested without a window (tests/ui).
##   var L := Layout.compute(get_viewport_rect().size, {"jev": true, "dock_h": 96.0})
## Everything is a Rect2 in viewport pixels. At the base window (1180x820) it matches the page in a 1180-wide
## browser; wider windows centre it, and short ones shrink the view (keeping its 448:288 shape) so the dock fits.
extends RefCounted

const MARGIN := 16.0 # .wrap padding
const GAP := 16.0 # .wrap gap, between the CRT and the Jev panel
const CRT_MAX := 860.0 # .crt width: min(100%, 860px)
const CRT_MIN := 640.0 # narrower than this and the Jev panel floats over the CRT instead of beside it
const CRT_BORDER := 2.0
const PAD_X := 12.0 # .crt padding 10px 12px 12px
const PAD_TOP := 10.0
const PAD_BOTTOM := 12.0
const BAR_H := 40.0 # .bar.top: 38px tall, then a 2px rule
const MID_PAD := 10.0 # .mid padding-top
const COL_GAP := 10.0 # .mid grid gap
const MAIN_FR := 1.55 # .mid columns: 1.55fr 1fr
const SIDE_FR := 1.0
const VIEW_BORDER := 2.0
const VIEW_W := 448.0
const VIEW_H := 288.0
const MAP := 105.0 # #map 105x105
const COL_INNER_GAP := 8.0 # .main-col gap, .side gap
const LEGEND_GAP := 12.0 # .mapbox gap
const DOCK_MARGIN := 8.0 # .dock margin-top
const DOCK_MIN_H := 80.0
const JEV_W := 300.0
const JEV_WIDE := 440.0
const VIEW_MIN_H := 160.0


## opts: jev (the Jev panel is open), wide (its REQUESTS tab: 440 px when there is room), dock_h (the dock's own
## height, border included, as it measured its content; at least 80).
static func compute(size: Vector2, opts := {}) -> Dictionary:
	var jev: bool = opts.get("jev", false)
	var wide: bool = opts.get("wide", false)
	var dock_h := maxf(DOCK_MIN_H, float(opts.get("dock_h", DOCK_MIN_H)))
	var m := MARGIN if size.x >= CRT_MAX + 2.0 * MARGIN and size.y >= 700.0 else 8.0

	# Across: the CRT, then the Jev panel beside it if both fit, otherwise floating over the CRT's right side
	var jev_w := JEV_W
	if jev and wide and size.x >= 2.0 * m + CRT_MAX + GAP + JEV_WIDE:
		jev_w = JEV_WIDE
	var beside := jev and size.x >= 2.0 * m + CRT_MIN + GAP + jev_w
	var crt_w := minf(CRT_MAX, size.x - 2.0 * m - (GAP + jev_w if beside else 0.0))
	var group_w := crt_w + (GAP + jev_w if beside else 0.0)
	var x0 := floorf((size.x - group_w) / 2.0)

	var inner_x := x0 + CRT_BORDER + PAD_X
	var inner_w := crt_w - 2.0 * (CRT_BORDER + PAD_X)
	var main_w := floorf((inner_w - COL_GAP) * MAIN_FR / (MAIN_FR + SIDE_FR))
	var side_w := inner_w - COL_GAP - main_w

	# Down: the bar, the view with the map under it (the side column beside them takes their height), the dock
	var top := m
	var bar := Rect2(inner_x, top + CRT_BORDER + PAD_TOP, inner_w, BAR_H)
	var mid_y := bar.end.y + MID_PAD
	var view_w := main_w
	var view_h := _view_h(view_w)
	var fixed := CRT_BORDER + PAD_TOP + BAR_H + MID_PAD + COL_INNER_GAP + MAP + DOCK_MARGIN + dock_h + PAD_BOTTOM + CRT_BORDER
	var room := size.y - 2.0 * m - fixed
	if view_h > room:
		# A short window: the view gives way first (same shape, left-aligned in its column)
		view_h = maxf(VIEW_MIN_H, floorf(room))
		view_w = minf(main_w, floorf((view_h - 2.0 * VIEW_BORDER) * VIEW_W / VIEW_H + 2.0 * VIEW_BORDER))
		view_h = _view_h(view_w)
	var view := Rect2(inner_x, mid_y, view_w, view_h)
	var map := Rect2(inner_x, view.end.y + COL_INNER_GAP, MAP, MAP)
	var legend := Rect2(map.end.x + LEGEND_GAP, map.position.y, main_w - MAP - LEGEND_GAP, MAP)
	var main_h := map.end.y - mid_y
	var side := Rect2(inner_x + main_w + COL_GAP, mid_y, side_w, main_h)
	var dock := Rect2(inner_x, map.end.y + DOCK_MARGIN, inner_w, dock_h)
	var crt := Rect2(x0, top, crt_w, dock.end.y + PAD_BOTTOM + CRT_BORDER - top)

	var out := {
		"size": size,
		"margin": m,
		"crt": crt,
		"bar": bar,
		"mid": Rect2(inner_x, bar.end.y, inner_w, main_h + MID_PAD),
		"view": view,
		# the picture inside the view's 2px border, where the SubViewport is shown
		"picture": view.grow(-VIEW_BORDER),
		"map": map,
		"legend": legend,
		"side": side,
		"dock": dock,
		# the achievements list covers the view and the side column (.ach-screen: inset 10px 0 0 in .mid)
		"ach": Rect2(inner_x, mid_y, inner_w, main_h),
		"jev": null,
		"jev_beside": beside,
	}
	if jev:
		out.jev = Rect2(crt.end.x + GAP, top, jev_w, size.y - 2.0 * top) if beside else Rect2(size.x - jev_w - 8.0, 8.0, jev_w, size.y - 16.0)
	return out


## The view's height for a width: the 448x288 picture scaled to fit inside a 2px border
static func _view_h(w: float) -> float:
	return roundf((w - 2.0 * VIEW_BORDER) * VIEW_H / VIEW_W) + 2.0 * VIEW_BORDER


## Every rect a layout places on screen, by name (for the overflow checks in tests)
static func rects(L: Dictionary) -> Dictionary:
	var out := {}
	for k in ["crt", "bar", "view", "map", "legend", "side", "dock", "ach", "jev"]:
		if L.get(k) is Rect2:
			out[k] = L[k]
	return out
