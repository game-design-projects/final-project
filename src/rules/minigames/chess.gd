## Chess: a piece lands near you and the squares it reaches light up. A rook lines up with you from an edge, a bishop stands on
## your diagonal, a knight a jump away. Its shape, and lines to its squares, say what it reaches (view/overlay.gd).
extends RefCounted

const Dodge = preload("res://src/rules/dodge.gd")
const Rng = preload("res://src/utils/rng.gd")


static func spawn(run, t: float, rng: Rng, _events: Array) -> void:
	if t < run.next_t:
		return
	run.next_t = t + 760.0 / (run.intensity * run.pace)
	var soul: Vector2i = run.soul
	var kind: String = rng.pick(["rook", "rook", "bishop", "bishop", "knight"])
	if kind == "rook":
		# a rook enters from an edge, lined up with you on a row or a column
		var at: Vector2i
		if rng.chance(0.5):
			at = Vector2i(rng.pick([0, Dodge.COLS - 1]), soul.y)
		else:
			at = Vector2i(soul.x, rng.pick([0, Dodge.ROWS - 1]))
		run.add_hazard(t, Dodge.rook_cells(at), 950.0, 320.0, "chess", {"glyph": "R", "at": Dodge.index(at.x, at.y)})
	elif kind == "bishop":
		var d: Vector2i = rng.pick(Dodge.BISHOP_DIRS)
		var k := rng.int_range(1, 3)
		while k > 0 and not Dodge.in_box(soul.x + d.x * k, soul.y + d.y * k):
			k -= 1
		var at := soul + d * k
		run.add_hazard(t, Dodge.bishop_cells(at), 950.0, 320.0, "chess", {"glyph": "B", "at": Dodge.index(at.x, at.y)})
	else:
		var options := []
		for j in Dodge.KNIGHT_JUMPS:
			if Dodge.in_box(soul.x + j.x, soul.y + j.y):
				options.append(soul + j)
		var at: Vector2i = rng.pick(options)
		run.add_hazard(t, Dodge.knight_cells(at), 900.0, 320.0, "chess", {"glyph": "N", "at": Dodge.index(at.x, at.y)})
