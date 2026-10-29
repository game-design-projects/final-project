## Monochrome line-art monsters, drawn on a 448x288 canvas. One color each, no fills.
## Ported from crawler/public/art.js. `ctx` is a Canvas2D.
##
## `ART.pixel` > 1 (the gallery's jagged look, drawn at 1/N resolution through getImageData) is not ported: the
## monsters are drawn with smooth lines at any `pixel`, which is what the game uses (`ART.pixel` is 1).
extends RefCounted

const J = preload("res://src/core/js.gd")
const Species = preload("res://src/rules/species.gd")

const SHINY_COLOR = "#f5b72a"
const BOSS_COLOR = "#ff2a2a"

## How jagged the monsters look. 1 = smooth vector lines (the game's look). Values above 1 are accepted and draw smooth.
static var ART := {"pixel": 1}

# Shiny variants twinkle: little four-point glints around the monster.
const GLINTS = [[-120, -40], [118, -70], [-60, -120], [140, 30], [-140, 40], [60, -10]]

## Where a monster stands when several share the view: cx is its center, s its scale (bottoms stay aligned).
const SLOTS = {
	1: [{"cx": 224, "s": 1}],
	2: [{"cx": 116, "s": 0.6}, {"cx": 332, "s": 0.6}],
	3: [{"cx": 76, "s": 0.46}, {"cx": 224, "s": 0.46}, {"cx": 372, "s": 0.46}],
}


static func _path(ctx, pts: Array, close := false) -> void:
	ctx.begin_path()
	ctx.move_to(pts[0][0], pts[0][1])
	for i in range(1, pts.size()):
		ctx.line_to(pts[i][0], pts[i][1])
	if close:
		ctx.close_path()
	ctx.stroke()


static func _circle(ctx, x: float, y: float, r: float) -> void:
	ctx.begin_path()
	ctx.arc(x, y, r, 0, TAU)
	ctx.stroke()


static func _dot(ctx, x: float, y: float, r := 2.0) -> void:
	ctx.begin_path()
	ctx.arc(x, y, r, 0, TAU)
	ctx.fill()


static func _ellipse(ctx, x: float, y: float, rx: float, ry: float) -> void:
	ctx.begin_path()
	ctx.ellipse(x, y, rx, ry, 0, 0, TAU)
	ctx.stroke()


# Orange slime: a wobbling dome with a blank, unblinking stare.
static func _slime(ctx, t: float) -> void:
	var wob := sin(t / 380.0) * 4.0
	ctx.save()
	ctx.translate(224, 236)
	ctx.scale(1.0 + wob / 200.0, 1.0 - wob / 160.0)
	ctx.translate(-224, -236)
	ctx.begin_path()
	ctx.move_to(136, 236)
	ctx.bezier_curve_to(128, 160, 172, 96, 224, 96)
	ctx.bezier_curve_to(276, 96, 320, 160, 312, 236)
	ctx.bezier_curve_to(292, 244, 272, 230, 252, 240)
	ctx.bezier_curve_to(232, 250, 212, 232, 192, 240)
	ctx.bezier_curve_to(172, 248, 154, 238, 136, 236)
	ctx.stroke()
	# shine
	ctx.begin_path()
	ctx.arc(224, 190, 76, PI * 1.18, PI * 1.36)
	ctx.stroke()
	# drips
	_path(ctx, [[170, 243], [170, 256]])
	_circle(ctx, 170, 260, 3)
	_path(ctx, [[262, 238], [262, 250]])
	_circle(ctx, 262, 254, 2.5)
	# the blank stare: big empty eyes with pinprick pupils dead center
	_circle(ctx, 196, 162, 14)
	_circle(ctx, 252, 162, 14)
	_dot(ctx, 196, 162, 1.8)
	_dot(ctx, 252, 162, 1.8)
	_path(ctx, [[214, 200], [234, 200]])
	ctx.restore()
	# puddle
	ctx.begin_path()
	ctx.ellipse(224, 252, 104, 9, 0, 0, TAU)
	ctx.stroke()


# Huge brown goblin: fills the corridor, club raised.
static func _goblin(ctx, t: float) -> void:
	var sway := sin(t / 700.0) * 2.0
	ctx.save()
	ctx.translate(sway, 0)
	# head
	_path(ctx, [[176, 64], [200, 44], [248, 44], [272, 64], [282, 100], [276, 134], [258, 158], [224, 168], [190, 158], [172, 134], [166, 100]], true)
	# ears
	_path(ctx, [[168, 86], [94, 58], [170, 118]])
	_path(ctx, [[280, 86], [354, 58], [278, 118]])
	_path(ctx, [[150, 82], [120, 72]])
	_path(ctx, [[298, 82], [328, 72]])
	# brow and beady eyes
	_path(ctx, [[184, 88], [214, 98]])
	_path(ctx, [[234, 98], [264, 88]])
	_circle(ctx, 202, 106, 5)
	_circle(ctx, 246, 106, 5)
	_dot(ctx, 202, 106, 2)
	_dot(ctx, 246, 106, 2)
	# hooked nose
	_path(ctx, [[224, 106], [214, 128], [232, 130]])
	# grin with jagged teeth
	_path(ctx, [[184, 138], [206, 148], [242, 148], [264, 138]])
	_path(ctx, [[192, 141], [197, 132], [202, 145], [210, 134], [216, 148], [224, 136], [232, 148], [238, 134], [246, 145], [251, 132], [256, 141]])
	# shoulders and body
	_path(ctx, [[196, 162], [150, 172], [62, 196], [34, 288]])
	_path(ctx, [[252, 162], [298, 172], [376, 190], [398, 214]])
	_path(ctx, [[120, 288], [132, 226], [150, 206]])
	_path(ctx, [[328, 288], [316, 226], [300, 208]])
	# potato-sack tunic: gathered drawstring neck, rope belt, patches, frayed hem
	_path(ctx, [[176, 180], [186, 186], [196, 179], [206, 187], [216, 179], [226, 187], [236, 179], [246, 187], [256, 179], [266, 186], [274, 180]])
	_path(ctx, [[176, 180], [158, 212], [148, 266]])
	_path(ctx, [[274, 180], [292, 212], [302, 266]])
	_path(ctx, [[148, 266], [156, 276], [166, 266], [176, 278], [188, 266], [200, 277], [212, 266], [224, 278], [236, 266], [248, 277], [260, 266], [272, 278], [284, 266], [294, 276], [302, 266]])
	_path(ctx, [[188, 196], [262, 196]]) # printed stripes
	_path(ctx, [[184, 208], [266, 208]])
	_path(ctx, [[152, 232], [224, 238], [298, 232]]) # rope belt
	_path(ctx, [[151, 240], [224, 246], [299, 240]])
	_circle(ctx, 224, 242, 6)
	_path(ctx, [[220, 248], [214, 262]])
	_path(ctx, [[228, 248], [234, 262]])
	_path(ctx, [[176, 248], [198, 248], [198, 262], [176, 262]], true) # patch
	_path(ctx, [[180, 245], [180, 251]])
	_path(ctx, [[194, 245], [194, 251]])
	_path(ctx, [[252, 208], [270, 208], [270, 222], [252, 222]], true) # patch
	_path(ctx, [[256, 205], [256, 211]])
	_path(ctx, [[266, 205], [266, 211]])
	# right arm raised with a knotted club
	_path(ctx, [[398, 214], [414, 162], [408, 132]])
	_path(ctx, [[376, 190], [392, 158], [390, 134]])
	_circle(ctx, 400, 126, 13)
	_path(ctx, [[392, 118], [384, 44], [398, 14], [428, 18], [440, 50], [410, 118]], true)
	_circle(ctx, 404, 50, 5)
	_circle(ctx, 424, 34, 4)
	_circle(ctx, 402, 88, 4)
	# left fist
	_circle(ctx, 42, 276, 14)
	ctx.restore()


# Yellow dragon: wings spread, horned head, coiled tail.
static func _dragon(ctx, t: float) -> void:
	var flap := sin(t / 600.0) * 6.0
	# wings
	_path(ctx, [[196, 160], [140, 90 - flap], [60, 40 - flap], [72, 110], [30, 150], [88, 144], [70, 190], [124, 168], [118, 210], [170, 182]])
	_path(ctx, [[140, 90 - flap], [88, 144]])
	_path(ctx, [[140, 90 - flap], [124, 168]])
	_path(ctx, [[252, 160], [308, 90 - flap], [388, 40 - flap], [376, 110], [418, 150], [360, 144], [378, 190], [324, 168], [330, 210], [278, 182]])
	_path(ctx, [[308, 90 - flap], [360, 144]])
	_path(ctx, [[308, 90 - flap], [324, 168]])
	# body
	ctx.begin_path()
	ctx.ellipse(224, 212, 66, 44, 0, 0, TAU)
	ctx.stroke()
	_path(ctx, [[196, 190], [206, 226], [224, 236], [242, 226], [252, 190]]) # belly plates
	_path(ctx, [[204, 206], [244, 206]])
	_path(ctx, [[210, 222], [238, 222]])
	# neck
	_path(ctx, [[204, 176], [210, 140], [214, 114]])
	_path(ctx, [[244, 176], [238, 140], [234, 114]])
	# head
	_path(ctx, [[208, 112], [198, 84], [210, 66], [238, 66], [250, 84], [240, 112], [232, 126], [216, 126]], true)
	_path(ctx, [[206, 70], [182, 30], [214, 64]]) # horns
	_path(ctx, [[242, 70], [266, 30], [234, 64]])
	_path(ctx, [[208, 86], [218, 84]]) # slit eyes
	_path(ctx, [[230, 84], [240, 86]])
	_dot(ctx, 218, 118, 1.8)
	_dot(ctx, 230, 118, 1.8)
	_path(ctx, [[212, 112], [216, 106], [220, 112], [224, 106], [228, 112], [232, 106], [236, 112]]) # teeth
	# legs and claws
	_path(ctx, [[180, 240], [170, 262], [160, 270]])
	_path(ctx, [[170, 262], [170, 274]])
	_path(ctx, [[170, 262], [182, 272]])
	_path(ctx, [[268, 240], [278, 262], [288, 270]])
	_path(ctx, [[278, 262], [278, 274]])
	_path(ctx, [[278, 262], [266, 272]])
	# tail
	ctx.begin_path()
	ctx.move_to(284, 228)
	ctx.bezier_curve_to(350, 262, 404, 262, 414, 226)
	ctx.stroke()
	_path(ctx, [[406, 232], [428, 214], [418, 240]], true)


# Green snake person: a hooded serpent torso rising from its coils, tongue flicking.
static func _snake(ctx, t: float) -> void:
	var sway := sin(t / 500.0) * 4.0
	_ellipse(ctx, 224, 252, 112, 18)
	_ellipse(ctx, 224, 236, 90, 15)
	_ellipse(ctx, 230, 222, 66, 12)
	_path(ctx, [[322, 254], [354, 248], [374, 236], [380, 222], [370, 214]]) # tail tip
	ctx.save()
	ctx.translate(sway, 0)
	_path(ctx, [[202, 222], [196, 190], [204, 160], [212, 140]]) # body rising
	_path(ctx, [[254, 222], [252, 190], [244, 160], [236, 140]])
	for y in [208, 192, 176, 160]: # belly scales
		_path(ctx, [[204, y], [224, y + 6], [248, y]])
	_path(ctx, [[212, 140], [184, 132], [170, 140]]) # shoulders
	_path(ctx, [[236, 140], [264, 132], [278, 140]])
	_path(ctx, [[172, 140], [150, 170], [156, 196]]) # clawed arms
	_path(ctx, [[156, 196], [148, 206]])
	_path(ctx, [[156, 196], [156, 208]])
	_path(ctx, [[156, 196], [164, 206]])
	_path(ctx, [[276, 140], [300, 166], [294, 194]])
	_path(ctx, [[294, 194], [286, 204]])
	_path(ctx, [[294, 194], [294, 206]])
	_path(ctx, [[294, 194], [302, 204]])
	_path(ctx, [[214, 132], [216, 118]]) # neck
	_path(ctx, [[234, 132], [232, 118]])
	_path(ctx, [[216, 118], [190, 104], [180, 80], [194, 56], [224, 46], [254, 56], [268, 80], [258, 104], [232, 118]]) # cobra hood
	_path(ctx, [[196, 70], [206, 86]]) # hood markings
	_path(ctx, [[252, 70], [242, 86]])
	_path(ctx, [[210, 96], [210, 74], [224, 64], [238, 74], [238, 96], [224, 106]], true) # head
	_path(ctx, [[213, 82], [221, 84]]) # slit eyes
	_path(ctx, [[227, 84], [235, 82]])
	_dot(ctx, 217, 83, 1.6)
	_dot(ctx, 231, 83, 1.6)
	if sin(t / 220.0) > 0.2:
		_path(ctx, [[224, 106], [224, 118], [218, 124]]) # forked tongue
		_path(ctx, [[224, 118], [230, 124]])
	ctx.restore()


# Grey rock entity: a living heap of boulders with one glowing crack for an eye.
static func _rock(ctx, t: float) -> void:
	var breathe := sin(t / 900.0) * 2.0
	_path(ctx, [[96, 264], [352, 264]]) # ground
	_path(ctx, [[150, 264], [160, 256], [172, 264]]) # pebbles
	_path(ctx, [[272, 264], [284, 255], [296, 264]])
	ctx.save()
	ctx.translate(0, breathe)
	_path(ctx, [[142, 252], [128, 202], [146, 152], [178, 120], [224, 106], [272, 118], [304, 150], [320, 200], [308, 252]], true) # body
	_path(ctx, [[200, 142], [212, 168], [204, 190], [218, 214]]) # cracks
	_path(ctx, [[278, 152], [264, 178], [272, 202]])
	_path(ctx, [[162, 200], [182, 212], [176, 230]])
	_dot(ctx, 250, 230, 2)
	_dot(ctx, 190, 238, 2)
	_dot(ctx, 286, 228, 2)
	_path(ctx, [[190, 120], [184, 88], [204, 62], [238, 58], [262, 80], [262, 114]], true) # head
	_path(ctx, [[198, 90], [210, 84], [218, 92], [230, 82], [242, 90], [252, 86]]) # glowing crack eye
	_path(ctx, [[204, 94], [216, 98], [230, 92], [244, 96]])
	_path(ctx, [[134, 160], [104, 168], [92, 202], [112, 216], [132, 202]], true) # left arm
	_path(ctx, [[96, 214], [84, 242], [100, 260], [124, 252], [120, 222]], true)
	_path(ctx, [[314, 160], [344, 168], [356, 202], [336, 216], [316, 202]], true) # right arm
	_path(ctx, [[352, 214], [364, 242], [348, 260], [324, 252], [328, 222]], true)
	ctx.restore()


# Red bandit: hooded, masked, a knife in each hand.
static func _bandit(ctx, t: float) -> void:
	var shift := sin(t / 450.0) * 3.0
	ctx.save()
	ctx.translate(shift, 0)
	_path(ctx, [[224, 38], [190, 66], [176, 106], [184, 138]]) # hood
	_path(ctx, [[224, 38], [258, 66], [272, 106], [264, 138]])
	_ellipse(ctx, 224, 98, 26, 32) # face opening
	_path(ctx, [[208, 90], [218, 88]]) # narrowed eyes
	_path(ctx, [[230, 88], [240, 90]])
	_dot(ctx, 213, 90, 1.8)
	_dot(ctx, 235, 90, 1.8)
	_path(ctx, [[199, 104], [249, 104]]) # bandana mask
	_path(ctx, [[200, 104], [206, 122], [224, 128], [242, 122], [248, 104]])
	_path(ctx, [[249, 106], [268, 112], [262, 122]]) # knot tails
	_path(ctx, [[249, 106], [272, 104]])
	_path(ctx, [[184, 138], [150, 150], [130, 190], [124, 262]]) # cloak
	_path(ctx, [[264, 138], [298, 150], [318, 190], [324, 262]])
	_path(ctx, [[124, 262], [140, 254], [152, 264], [166, 254], [180, 262]]) # ragged hem
	_path(ctx, [[268, 262], [282, 254], [296, 264], [310, 254], [324, 262]])
	_path(ctx, [[198, 140], [224, 170], [250, 140]]) # tunic neck
	_path(ctx, [[190, 146], [194, 252]])
	_path(ctx, [[258, 146], [254, 252]])
	_path(ctx, [[188, 204], [260, 204]]) # belt
	_path(ctx, [[188, 212], [260, 212]])
	_path(ctx, [[216, 202], [232, 202], [232, 214], [216, 214]], true) # buckle
	_path(ctx, [[240, 214], [256, 214], [256, 230], [240, 230]], true) # coin pouch
	_path(ctx, [[202, 252], [198, 270]]) # legs
	_path(ctx, [[246, 252], [250, 270]])
	_path(ctx, [[150, 150], [140, 190], [158, 212]]) # left arm, knife forward
	_circle(ctx, 162, 214, 6)
	_path(ctx, [[166, 208], [194, 184]])
	_path(ctx, [[160, 200], [172, 212]])
	_path(ctx, [[298, 150], [322, 128], [332, 100]]) # right arm, knife raised
	_circle(ctx, 334, 96, 6)
	_path(ctx, [[338, 90], [352, 60]])
	_path(ctx, [[328, 88], [344, 96]])
	ctx.restore()


static func _glints(ctx, t: float) -> void:
	for i in GLINTS.size():
		var on := sin(t / 260.0 + i * 1.7)
		if on < 0.35:
			continue
		var r := 4.0 + on * 6.0
		var x: float = 224 + GLINTS[i][0]
		var y: float = 160 + GLINTS[i][1]
		_path(ctx, [[x - r, y], [x + r, y]])
		_path(ctx, [[x, y - r], [x, y + r]])


static func _draw_species(ctx, species: String, t: float) -> void:
	match species:
		"slime":
			_slime(ctx, t)
		"goblin":
			_goblin(ctx, t)
		"dragon":
			_dragon(ctx, t)
		"snake":
			_snake(ctx, t)
		"rock":
			_rock(ctx, t)
		"bandit":
			_bandit(ctx, t)
		_:
			push_error("art: no monster called %s" % species)


## The color a monster is drawn in: `look.color`, else gold when shiny, else its species' color
static func color_of(species: String, look := {}) -> String:
	var c = look.get("color")
	if c != null:
		return c
	return SHINY_COLOR if J.truthy(look.get("shiny", false)) else Species.SPECIES[species]["color"]


static func _draw_vector(ctx, species: String, t: float, hurt: float, slot: Dictionary, line_width: float, look: Dictionary) -> void:
	var color := color_of(species, look)
	ctx.save()
	ctx.stroke_style = color
	ctx.fill_style = color
	ctx.line_width = line_width
	ctx.line_join = "round"
	var s: float = slot["s"]
	# slot.by moves the monster's feet up from the bottom of the view (to stand further down a corridor)
	ctx.translate(slot["cx"] - 224.0 * s, J.nz(slot.get("by"), 284) - 284.0 * s)
	ctx.scale(s, s)
	if hurt > 0:
		ctx.translate(sin(t / 20.0) * hurt * 6.0, 0)
	_draw_species(ctx, species, t)
	if J.truthy(look.get("shiny", false)):
		_glints(ctx, t)
	ctx.restore()


## `slot` places a monster when several share the view: cx is its center, s its scale (bottoms stay aligned).
## `look.shiny` draws the rare gold variant with glints; `look.color` overrides the color (the red champion).
## `pixel` (default ART.pixel) is accepted for the JS signature; the lines are always smooth.
static func draw_monster(ctx, species: String, t: float, hurt := 0.0, slot := {"cx": 224, "s": 1}, pixel = null, look := {}) -> void:
	if pixel == null:
		pixel = ART["pixel"]
	if pixel > 1:
		print_verbose("art: pixel %s drawn smooth" % pixel)
	_draw_vector(ctx, species, t, hurt, slot, 2.0 / maxf(slot["s"], 0.6), look)
