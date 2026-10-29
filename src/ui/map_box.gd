## The automap under the view and its key (.mapbox in style.css): the map render.gd draws (only floor you have
## seen), in a 105px box with a faint frame, and the legend beside it, aligned to the box's bottom. M hides both
## (keeping their place); in a fight the whole box steps aside, keeping its space so nothing jumps.
extends "res://src/ui/widget.gd"

const Canvas2D = preload("res://src/view/canvas2d.gd")
const Render = preload("res://src/view/render.gd")

const MAP := 105.0
const LEGEND_GAP := 12.0
const LEGEND_FONT := 7

## main.gd's game
var hidden_map := false
var fighting := false
var canvas: MapCanvas


## The map itself, inside the 1px frame (the canvas is 105px; what doesn't fit the frame's inside is clipped)
class MapCanvas:
	extends Control
	var ui

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		var game = ui.game if ui != null else null
		if game == null or game.G == null or game.G.get("map") == null:
			return
		var G: Dictionary = game.G
		var ctx = Canvas2D.new(self, Vector2(105, 105))
		Render.draw_map(ctx, G.map, G.seen, G.visited, G.x, G.y, G.dir)


func _init() -> void:
	super()
	canvas = MapCanvas.new()
	canvas.position = Vector2(1, 1)
	canvas.size = Vector2(MAP - 2.0, MAP - 2.0)
	add_child(canvas)


func _ready() -> void:
	canvas.ui = ui


func refresh() -> void:
	canvas.visible = not hidden_map and not fighting
	canvas.queue_redraw()
	queue_redraw()


func paint() -> void:
	if fighting or hidden_map:
		return
	var box := Rect2(0, 0, MAP, MAP)
	draw_rect(box, Css.BG)
	Css.frame(self, box, Css.FAINT, 1.0)
	add_hit(box, {"id": "#map", "panel": "#map"})
	# The key: you, the stairs down, the champion, and how to hide it all
	var font := Css.ps()
	var items := [["you", "YOU"], ["stairs", "STAIRS DOWN"], ["boss", "CHAMPION"], ["", "M HIDES THE MAP"]]
	var x := MAP + LEGEND_GAP
	var line := 8.0
	var y := MAP - (items.size() * line + (items.size() - 1) * 6.0 + 2.0)
	for it in items:
		if it[0] == "":
			y += 2.0 # .legend .key { margin-top: 2px }
		var tx := x
		match it[0]:
			"you":
				var c := Vector2(x + 5.0, y)
				draw_colored_polygon(PackedVector2Array([c, Vector2(x + 10.0, y + 8.0), Vector2(x, y + 8.0)]), Color.WHITE)
				tx += 16.0
			"stairs":
				Css.frame(self, Rect2(x, y, 8, 8), Css.INK, 2.0)
				tx += 14.0
			"boss":
				draw_rect(Rect2(x, y, 8, 8), Color("#ff2a2a"))
				tx += 14.0
		Css.text(self, font, LEGEND_FONT, tx, y, it[1], Css.DIM, line)
		y += line + 6.0
