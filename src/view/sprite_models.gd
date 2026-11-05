## The monsters' bodies shaped after their fight sprites (art.gd), for the flag sprite-look: every outline and line here is given in the
## sprite's own coordinates, so the same monster has the same silhouette and face in both views. A model always turns to the camera
## (stage.gd), so its front is the sprite; depth comes from puffing each outline out into a body, in layers from back to front, and
## what the sprite draws as one stroke (an arm, a tail, a crack) stays one stroke.
## The parts have the names monster_model.gd poses, and each is built with mesh_kit.gd: black inside and outlined, or solid for a line.
extends RefCounted

const MeshKit = preload("res://src/view/mesh_kit.gd")

const MIDDLE := 224.0 # where the sprite's middle is along x
const FEET := 270.0 # where its feet are along y
const SCALE := 0.0072 # world units per sprite unit: the tallest fits under the ceiling
const WING_SCALE := 0.0048 # along x, for what the sprite spreads wider than a corridor: the dragon's wings
const TAIL_SCALE := 0.0036 # and its tail
const LINE := 0.012 # how thick a drawn line is: about the sprite's width in the next cell
const LIMB := LINE * 1.4 # an arm, a leg or a tail: a stroke in the sprite too, a little stronger
const LIFT := 0.012 # how far a line stands in front of what it is drawn on
const SLIME_FEET := 258.0 # the slime's feet along y: its puddle, not the end of its drips
const COIL_DEPTH := 0.26 # how far a snake's coil comes forward
const ROUND := 0.62 # how far in the top of a puffed body starts, as a share of the way from its middle to its outline


# ---------------------------------------------------------------- the pen

## Flat x,y numbers of the sprite as points of the model's front. `ox` and `oy` are the sprite point that goes to the model's origin.
static func _pts(xy: Array, ox := MIDDLE, sx := SCALE, oy := FEET) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		out.append(Vector2((xy[i] - ox) * sx, (oy - xy[i + 1]) * SCALE))
	return out


static func _p(x: float, y: float, z := 0.0, ox := MIDDLE, sx := SCALE, oy := FEET) -> Vector3:
	return Vector3((x - ox) * sx, (oy - y) * SCALE, z)


## A closed outline puffed into a body `depth` thick either way at `z`. `round` below 1 draws its top in towards the middle, for an
## outline with no deep notches; with 1 its faces are flat.
static func _puff(b: MeshKit.Builder, outline: PackedVector2Array, z: float, depth: float, col: Color, round := ROUND) -> void:
	var pts := outline.duplicate()
	if not Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	var n := pts.size()
	var mid := Vector2.ZERO
	for p in pts:
		mid += p / n
	var out_dir := PackedVector2Array()
	for i in n:
		var ahead: Vector2 = (pts[(i + 1) % n] - pts[i]).normalized()
		var behind: Vector2 = (pts[i] - pts[(i + n - 1) % n]).normalized()
		out_dir.append((ahead + behind).orthogonal().normalized() * -1.0) # clockwise, so outward is to the left of the way round
	var cap := Geometry2D.triangulate_polygon(pts)
	if cap.is_empty():
		push_warning("sprite_models: can't fill an outline of %d points" % n)
	for side in [1.0, -1.0]:
		var rim := []
		var top := []
		for i in n:
			var o := out_dir[i]
			rim.append(b.vertex(Vector3(pts[i].x, pts[i].y, z), Vector3(o.x, o.y, 0.0), col))
			var at: Vector2 = mid + (pts[i] - mid) * round
			top.append(b.vertex(Vector3(at.x, at.y, z + side * depth), Vector3(o.x * 0.45, o.y * 0.45, side).normalized(), col))
		for i in n:
			var j := (i + 1) % n
			if side > 0.0:
				b.tri_idx(rim[i], rim[j], top[j])
				b.tri_idx(rim[i], top[j], top[i])
			else:
				b.tri_idx(rim[j], rim[i], top[i])
				b.tri_idx(rim[j], top[i], top[j])
		for i in range(0, cap.size(), 3):
			var one: int = top[cap[i]]
			var two: int = top[cap[i + 1]]
			var three: int = top[cap[i + 2]]
			var clockwise: bool = Geometry2D.is_polygon_clockwise(PackedVector2Array([pts[cap[i]], pts[cap[i + 1]], pts[cap[i + 2]]]))
			if clockwise == (side > 0.0):
				b.tri_idx(one, two, three)
			else:
				b.tri_idx(one, three, two)


## A line through flat x,y numbers of the sprite, drawn at `z`: solid in `col`.
static func _line(b: MeshKit.Builder, xy: Array, z: float, col: Color, ox := MIDDLE, sx := SCALE, oy := FEET, width := LINE) -> void:
	for i in range(0, xy.size() - 2, 2):
		b.limb(_p(xy[i], xy[i + 1], z, ox, sx, oy), _p(xy[i + 2], xy[i + 3], z, ox, sx, oy), width, width, col, 4)


## An ellipse drawn on the front.
static func _ellipse(b: MeshKit.Builder, x: float, y: float, rx: float, ry: float, z: float, col: Color) -> void:
	var xy := []
	for i in 21:
		var a := TAU * i / 20.0
		xy.append_array([x + cos(a) * rx, y + sin(a) * ry])
	_line(b, xy, z, col)


## A circle drawn on the front, the way the sprite draws an eye.
static func _ring(b: MeshKit.Builder, x: float, y: float, r: float, z: float, col: Color) -> void:
	var scaled := r * SCALE
	b.torus(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), _p(x, y, z)), scaled - LINE * 2.0, scaled, col, 20, 4)


static func _dot(b: MeshKit.Builder, x: float, y: float, r: float, z: float, col: Color) -> void:
	b.sphere(Transform3D(Basis(), _p(x, y, z)), Vector3.ONE * r * SCALE, col, 8, 4)


## Points along a cubic curve of the sprite, as flat numbers (`_curve` in art.gd draws the same).
static func _bend(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, steps := 8) -> Array:
	var out := []
	for i in steps + 1:
		var q := p0.bezier_interpolate(c1, c2, p1, float(i) / steps)
		out.append_array([q.x, q.y])
	return out


# ---------------------------------------------------------------- the species

## The parts of `species`: name -> [Builder, Transform3D], as monster_model.gd takes them. `ln` is its colour for outlines.
static func parts(species: String, ln: Color) -> Dictionary:
	var dot := MeshKit.drawn(ln) # and for what is drawn on them
	match species:
		"slime":
			return _slime(ln, dot)
		"bandit":
			return _bandit(ln, dot)
		"snake":
			return _snake(ln, dot)
		"rock":
			return _rock(ln, dot)
		"dragon":
			return _dragon(ln, dot)
	return {}


## The dome and its stare, its wavy hem and its drips, in a thin puddle. The sprite's dome stands in its puddle, higher than its feet.
static func _slime(ln: Color, dot: Color) -> Dictionary:
	var b := MeshKit.Builder.new()
	var outline := _bend(Vector2(136, 236), Vector2(128, 160), Vector2(172, 96), Vector2(224, 96))
	outline.append_array(_bend(Vector2(224, 96), Vector2(276, 96), Vector2(320, 160), Vector2(312, 236)).slice(2))
	outline.append_array(_bend(Vector2(312, 236), Vector2(292, 244), Vector2(272, 230), Vector2(252, 240), 3).slice(2))
	outline.append_array(_bend(Vector2(252, 240), Vector2(232, 250), Vector2(212, 232), Vector2(192, 240), 3).slice(2))
	outline.append_array(_bend(Vector2(192, 240), Vector2(172, 248), Vector2(154, 238), Vector2(136, 236), 3).slice(2, -2))
	var depth := 0.46
	_puff(b, _pts(outline), 0.0, depth, ln, 0.8)
	var front := depth + LIFT
	for x in [196.0, 252.0]:
		_ring(b, x, 162, 14, front, dot)
		_dot(b, x, 162, 2.0, front, dot)
	_line(b, [214, 200, 234, 200], front, dot)
	var shine := []
	for i in 9:
		var a := lerpf(PI * 1.18, PI * 1.36, i / 8.0)
		shine.append_array([224 + cos(a) * 76, 190 + sin(a) * 76])
	_line(b, shine, front, dot)
	_line(b, [170, 243, 170, 256], front, dot) # drips
	_ring(b, 170, 260, 3, front, dot)
	_line(b, [262, 238, 262, 250], front, dot)
	_ring(b, 262, 254, 2.5, front, dot)
	var puddle := MeshKit.Builder.new()
	puddle.sphere(Transform3D(Basis(), _p(224, 252)), Vector3(104.0 * SCALE, 0.015, 0.6), ln, 32, 4)
	var settled := Transform3D(Basis(), Vector3(0.0, -(FEET - SLIME_FEET) * SCALE, 0.0))
	return {"Puddle": [puddle, settled], "Body": [b, settled]}


## The peaked hood, the cloak with its torn hem, the masked face, the belt and pouch, a knife in each hand.
static func _bandit(ln: Color, dot: Color) -> Dictionary:
	var b := MeshKit.Builder.new()
	_line(b, [202, 250, 198, 270], 0.0, dot, MIDDLE, SCALE, FEET, LIMB) # legs under the hem
	_line(b, [246, 250, 250, 270], 0.0, dot, MIDDLE, SCALE, FEET, LIMB)
	_puff(b, _pts([184, 138, 150, 150, 130, 190, 124, 262, 140, 254, 152, 264, 166, 254, 180, 262, 194, 252, 254, 252, 268, 262, 282, 254, 296, 264, 310, 254, 324, 262, 318, 190, 298, 150, 264, 138, 224, 134]), 0.0, 0.2, ln, 1.0)
	var coat := 0.2 + LIFT
	_line(b, [198, 140, 224, 170, 250, 140], coat, dot) # the collar
	_line(b, [190, 146, 194, 252], coat, dot) # where the cloak opens
	_line(b, [258, 146, 254, 252], coat, dot)
	_line(b, [188, 204, 260, 204], coat, dot) # belt, buckle, coin pouch
	_line(b, [188, 212, 260, 212], coat, dot)
	_line(b, [216, 202, 232, 202, 232, 214, 216, 214, 216, 202], coat + LIFT, dot)
	_line(b, [240, 214, 256, 214, 256, 230, 240, 230, 240, 214], coat, dot)
	_puff(b, _pts([224, 38, 258, 66, 272, 106, 264, 138, 224, 146, 184, 138, 176, 106, 190, 66]), 0.2, 0.09, ln, 0.8) # the hood
	var face := 0.3
	b.sphere(Transform3D(Basis(), _p(224, 98, face)), Vector3(26.0 * SCALE, 32.0 * SCALE, 0.08), ln, 16, 8)
	var eyes := face + 0.08 + LIFT
	_line(b, [208, 90, 218, 88], eyes, dot)
	_line(b, [230, 88, 240, 90], eyes, dot)
	_dot(b, 213, 90, 2.2, eyes, dot)
	_dot(b, 235, 90, 2.2, eyes, dot)
	_puff(b, _pts([199, 104, 249, 104, 242, 122, 224, 128, 206, 122]), eyes, 0.012, ln, 1.0) # the mask
	_line(b, [249, 106, 268, 112, 262, 122], eyes, dot) # its knot
	_line(b, [249, 106, 272, 104], eyes, dot)
	var arms := 0.26
	_line(b, [150, 150, 140, 190, 158, 212], arms, dot, MIDDLE, SCALE, FEET, LIMB) # left arm, knife forward
	_ring(b, 162, 214, 6, arms + 0.03, dot)
	_line(b, [166, 208, 194, 184], arms + 0.03, dot, MIDDLE, SCALE, FEET, LINE * 1.3)
	_line(b, [160, 200, 172, 212], arms + 0.03, dot)
	_line(b, [298, 150, 322, 128, 332, 100], arms, dot, MIDDLE, SCALE, FEET, LIMB) # right arm, knife raised
	_ring(b, 334, 96, 6, arms + 0.03, dot)
	_line(b, [338, 90, 352, 60], arms + 0.03, dot, MIDDLE, SCALE, FEET, LINE * 1.3)
	_line(b, [328, 88, 344, 96], arms + 0.03, dot)
	return {"Body": [b, Transform3D()]}


## Three flat coils, a tail, the ribbed body with clawed arms, the eight-sided hood and the head in it, and the tongue.
static func _snake(ln: Color, dot: Color) -> Dictionary:
	var coils := MeshKit.Builder.new()
	coils.sphere(Transform3D(Basis(), _p(224, 252)), Vector3(112.0 * SCALE, 18.0 * SCALE, COIL_DEPTH), ln, 28, 10)
	coils.sphere(Transform3D(Basis(), _p(224, 236)), Vector3(90.0 * SCALE, 15.0 * SCALE, COIL_DEPTH), MeshKit.bare(ln), 24, 8)
	coils.sphere(Transform3D(Basis(), _p(230, 222)), Vector3(66.0 * SCALE, 12.0 * SCALE, COIL_DEPTH), MeshKit.bare(ln), 20, 8)
	_ellipse(coils, 224, 236, 90, 15, COIL_DEPTH + LIFT, dot)
	_ellipse(coils, 230, 222, 66, 12, COIL_DEPTH + LIFT * 2.0, dot)
	_line(coils, [322, 254, 350, 248, 362, 238, 366, 224, 358, 216], COIL_DEPTH + LIFT, dot, MIDDLE, SCALE, FEET, LIMB)
	var up := MeshKit.Builder.new()
	_puff(up, _pts([202, 222, 196, 190, 204, 160, 212, 140, 236, 140, 244, 160, 252, 190, 254, 222]), 0.1, 0.14, ln)
	var chest := 0.24 + LIFT
	for y in [208, 192, 176, 160]:
		_line(up, [204, y, 224, y + 6, 248, y], chest, dot)
	var arms := 0.14
	_line(up, [212, 140, 184, 132, 170, 140, 150, 170, 156, 196], arms, dot, MIDDLE, SCALE, FEET, LIMB)
	_line(up, [236, 140, 264, 132, 278, 140, 300, 166, 294, 194], arms, dot, MIDDLE, SCALE, FEET, LIMB)
	for claw in [[156, 196, 148, 206], [156, 196, 156, 208], [156, 196, 164, 206], [294, 194, 286, 204], [294, 194, 294, 206], [294, 194, 302, 204]]:
		_line(up, claw, arms + 0.03, dot)
	_line(up, [214, 132, 216, 118], 0.1, dot) # the neck
	_line(up, [234, 132, 232, 118], 0.1, dot)
	_puff(up, _pts([216, 118, 190, 104, 180, 80, 194, 56, 224, 46, 254, 56, 268, 80, 258, 104, 232, 118]), 0.14, 0.05, ln, 0.85) # the hood
	var marks := 0.19 + LIFT
	_line(up, [196, 70, 206, 86], marks, dot)
	_line(up, [252, 70, 242, 86], marks, dot)
	_puff(up, _pts([210, 96, 210, 74, 224, 64, 238, 74, 238, 96, 224, 106]), 0.2, 0.05, ln, 0.8) # the head
	var eyes := 0.25 + LIFT
	_line(up, [213, 82, 221, 84], eyes, dot)
	_line(up, [227, 84, 235, 82], eyes, dot)
	_dot(up, 217, 83, 2.0, eyes, dot)
	_dot(up, 231, 83, 2.0, eyes, dot)
	var tongue := MeshKit.Builder.new()
	_line(tongue, [224, 106, 224, 118, 218, 124], eyes, dot)
	_line(tongue, [224, 118, 230, 124], eyes, dot)
	return {"Coils": [coils, Transform3D()], "Upper": [up, Transform3D()], "Tongue": [tongue, Transform3D()]}


## The heap and the head on it, cracked, with two boulders for each arm, on its own patch of ground.
static func _rock(ln: Color, dot: Color) -> Dictionary:
	var low := MeshKit.Builder.new()
	_line(low, [96, 266, 352, 266], 0.3, dot)
	_line(low, [150, 266, 160, 258, 172, 266], 0.3, dot)
	_line(low, [272, 266, 284, 257, 296, 266], 0.3, dot)
	var up := MeshKit.Builder.new()
	_puff(up, _pts([142, 252, 128, 202, 146, 152, 178, 120, 224, 106, 272, 118, 304, 150, 320, 200, 308, 252]), 0.0, 0.34, ln, 0.72)
	var face := 0.34 + LIFT
	_line(up, [200, 142, 212, 168, 204, 190, 218, 214], face, dot) # cracks
	_line(up, [278, 152, 264, 178, 272, 202], face, dot)
	_line(up, [162, 200, 182, 212, 176, 230], face, dot)
	_dot(up, 250, 230, 2.4, face, dot)
	_dot(up, 190, 238, 2.4, face, dot)
	_dot(up, 286, 228, 2.4, face, dot)
	_puff(up, _pts([190, 120, 184, 88, 204, 62, 238, 58, 262, 80, 262, 114]), 0.14, 0.2, ln, 0.72) # head
	var eye := 0.34 + LIFT
	_line(up, [198, 90, 210, 84, 218, 92, 230, 82, 242, 90, 252, 86], eye, dot) # the crack that is its eye
	_line(up, [204, 94, 216, 98, 230, 92, 244, 96], eye, dot)
	_puff(up, _pts([134, 160, 104, 168, 92, 202, 112, 216, 132, 202]), 0.1, 0.14, ln, 0.7) # arms
	_puff(up, _pts([96, 214, 84, 242, 100, 260, 124, 252, 120, 222]), 0.12, 0.16, ln, 0.7)
	_puff(up, _pts([314, 160, 344, 168, 356, 202, 336, 216, 316, 202]), 0.1, 0.14, ln, 0.7)
	_puff(up, _pts([352, 214, 364, 242, 348, 260, 324, 252, 328, 222]), 0.12, 0.16, ln, 0.7)
	return {"Low": [low, Transform3D()], "Upper": [up, Transform3D()]}


## The wings spread wide, the thin neck, the sharp head and tall horns, the plated belly, and the long tail with its barb.
static func _dragon(ln: Color, dot: Color) -> Dictionary:
	var b := MeshKit.Builder.new()
	# legs and claws
	_line(b, [180, 240, 170, 262, 160, 270], 0.1, dot, MIDDLE, SCALE, FEET, LIMB)
	_line(b, [268, 240, 278, 262, 288, 270], 0.1, dot, MIDDLE, SCALE, FEET, LIMB)
	for claw in [[170, 262, 170, 270], [170, 262, 182, 270], [278, 262, 278, 270], [278, 262, 266, 270]]:
		_line(b, claw, 0.16, dot)
	# the tail, from the body out and round, narrower than the sprite's so it stays out of the walls
	var from := _p(284, 228)
	var tail := _bend(Vector2(284, 228), Vector2(350, 262), Vector2(404, 262), Vector2(414, 226))
	_line(b, tail, 0.0, dot, 284.0 - from.x / TAIL_SCALE, TAIL_SCALE, FEET, LIMB)
	_puff(b, _pts([406, 232, 428, 214, 418, 240], 284.0 - from.x / TAIL_SCALE, TAIL_SCALE), -0.06, 0.02, ln, 1.0)
	# the neck, then the body in front of it
	_puff(b, _pts([204, 176, 210, 140, 214, 114, 234, 114, 238, 140, 244, 176]), 0.06, 0.07, ln, 0.9)
	var body := _p(224, 212)
	b.sphere(Transform3D(Basis(), body), Vector3(66.0 * SCALE, 44.0 * SCALE, 0.34), ln, 32, 16)
	var belly := 0.34 + LIFT
	_line(b, [196, 190, 206, 226, 224, 236, 242, 226, 252, 190], belly, dot)
	_line(b, [204, 206, 244, 206], belly, dot)
	_line(b, [210, 222, 238, 222], belly, dot)
	var head := MeshKit.Builder.new()
	_puff(head, _pts([206, 70, 182, 30, 214, 64]), 0.06, 0.02, ln, 1.0) # horns
	_puff(head, _pts([242, 70, 266, 30, 234, 64]), 0.06, 0.02, ln, 1.0)
	_puff(head, _pts([208, 112, 198, 84, 210, 66, 238, 66, 250, 84, 240, 112, 232, 126, 216, 126]), 0.14, 0.09, ln, 0.75)
	var face := 0.23 + LIFT
	_line(head, [208, 86, 218, 84], face, dot)
	_line(head, [230, 84, 240, 86], face, dot)
	_dot(head, 218, 118, 2.2, face, dot)
	_dot(head, 230, 118, 2.2, face, dot)
	_line(head, [212, 112, 216, 106, 220, 112, 224, 106, 228, 112, 232, 106, 236, 112], face, dot) # teeth
	var parts := {"Body": [b, Transform3D()], "Head": [head, Transform3D()]}
	var left := [196, 160, 140, 90, 60, 40, 72, 110, 30, 150, 88, 144, 70, 190, 124, 168, 118, 210, 170, 182]
	var right := [252, 160, 308, 90, 388, 40, 376, 110, 418, 150, 360, 144, 378, 190, 324, 168, 330, 210, 278, 182]
	parts.WingL = [_wing(left, [[140, 90, 88, 144], [140, 90, 124, 168]], 196.0, ln, dot), Transform3D(Basis(), _p(196, 160, -0.16))]
	parts.WingR = [_wing(right, [[308, 90, 360, 144], [308, 90, 324, 168]], 252.0, ln, dot), Transform3D(Basis(), _p(252, 160, -0.16))]
	return parts


## In the wing's own frame, with the shoulder at the origin: its outline, thin, and the bones drawn on it.
static func _wing(outline: Array, bones: Array, shoulder_x: float, ln: Color, dot: Color) -> MeshKit.Builder:
	var w := MeshKit.Builder.new()
	_puff(w, _pts(outline, shoulder_x, WING_SCALE, 160.0), 0.0, 0.012, ln, 1.0)
	for bone in bones:
		_line(w, bone, 0.012 + LIFT, dot, shoulder_x, WING_SCALE, 160.0)
	return w
