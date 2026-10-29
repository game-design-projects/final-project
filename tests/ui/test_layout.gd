extends "res://tests/test_case.gd"

const Layout = preload("res://src/ui/layout.gd")


func _inside(L: Dictionary, label: String) -> void:
	var screen := Rect2(Vector2.ZERO, L.size)
	for k in Layout.rects(L):
		var r: Rect2 = L[k]
		ok(screen.encloses(r), "%s: %s fits in %s (%s)" % [label, k, L.size, r])


func _no_overlap(L: Dictionary, a: String, b: String, label: String) -> void:
	var ra: Rect2 = L[a]
	var rb: Rect2 = L[b]
	ok(not ra.intersects(rb), "%s: %s %s and %s %s don't overlap" % [label, a, ra, b, rb])


func test_base_window_matches_the_page():
	var L := Layout.compute(Vector2(1180, 820), {"dock_h": 80})
	eq(L.crt.size.x, 860.0, "the CRT is 860 wide")
	eq(L.crt.position.y, 16.0)
	eq(L.view.size.x, L.side.position.x - 10.0 - L.view.position.x, "view fills the main column")
	near(L.view.size.x / L.side.size.x, 1.55, 0.02, "columns 1.55fr : 1fr")
	near((L.picture.size.x) / L.picture.size.y, 448.0 / 288.0, 0.01, "the picture keeps its shape")
	eq(L.map.size, Vector2(105, 105))
	eq(L.side.size.y, L.map.end.y - L.view.position.y, "the side column is as tall as view + map")
	_inside(L, "1180x820")
	_no_overlap(L, "view", "side", "1180x820")
	_no_overlap(L, "map", "dock", "1180x820")


func test_jev_panel_beside_at_1180():
	var L := Layout.compute(Vector2(1180, 820), {"jev": true, "dock_h": 220})
	ok(L.jev_beside)
	eq(L.jev.size.x, 300.0)
	_inside(L, "1180x820 + jev")
	_no_overlap(L, "crt", "jev", "1180x820 + jev")
	eq(L.crt.size.x, 860.0, "the CRT keeps its width, the margins give way")
	eq(L.crt.position.x, 2.0)
	eq(L.jev.position.x, 878.0, "the panel 16px after the CRT, as on the page")
	var wide := Layout.compute(Vector2(1180, 820), {"jev": true, "wide": true})
	eq(wide.jev.size.x, 300.0, "no room for the wide REQUESTS panel at 1180")
	var big := Layout.compute(Vector2(1460, 820), {"jev": true, "wide": true})
	eq(big.jev.size.x, 440.0)
	eq(big.crt.size.x, 860.0)


func test_tall_dock_still_fits():
	# CHOOSE MOVES with eight spells: the tallest the dock gets
	var L := Layout.compute(Vector2(1180, 820), {"jev": true, "dock_h": 240})
	_inside(L, "1180x820 tall dock")


func test_900x700_shrinks_and_floats_the_panel():
	for dock_h in [80.0, 240.0]:
		var L := Layout.compute(Vector2(900, 700), {"jev": true, "dock_h": dock_h})
		_inside(L, "900x700 dock %s" % dock_h)
		ok(not L.jev_beside, "the Jev panel floats when it can't sit beside")
		_no_overlap(L, "view", "side", "900x700")
		_no_overlap(L, "map", "dock", "900x700")
		near(L.picture.size.x / L.picture.size.y, 448.0 / 288.0, 0.02, "the picture keeps its shape at 900x700")


func test_wide_window_centres():
	var L := Layout.compute(Vector2(1600, 900), {})
	near(L.crt.get_center().x, 800.0, 1.0)
	_inside(L, "1600x900")
