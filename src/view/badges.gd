## The achievements' own pictures: a 7x7 glyph each, drawn in lit squares so they stay crisp at any size, and the badge they
## sit in. Which glyph an achievement has is in data/achievements.json (`icon`); what an earned one is lit in is its group's
## colour. A badge not yet earned is the same picture in grey, and a secret one is a question mark.
extends RefCounted

const Palette = preload("res://src/view/palette.gd")

const LOCKED := Color("#5a5a5a") # a glyph not yet earned
const LOCKED_EDGE := Color("#3a3a3a")
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

## "#" is a lit square.
const GLYPHS := {
	"trophy": ["#######", "#.###.#", "#.###.#", ".#####.", "..###..", "...#...", ".#####."],
	"secret": [".####..", "#....#.", "....#..", "...#...", "...#...", ".......", "...#..."],
	"bubble": ["#######", "#.....#", "#.#.#.#", "#.....#", "###.###", "..##...", "..#...."],
	"paw": [".#...#.", "...#...", ".#...#.", "..###..", ".#####.", ".#####.", "..#.#.."],
	"trio": ["#..#..#", ".......", "##.#.##", "##.#.##", ".......", "#######", "#######"],
	"crown": [".......", "#..#..#", "##.#.##", "#######", "#######", "#######", "......."],
	"gem": [".#####.", "#.#.#.#", "#######", ".#####.", "..###..", "...#...", "......."],
	"scroll": ["#######", ".#...#.", ".#.#.#.", ".#...#.", ".#.#.#.", ".#...#.", "#######"],
	"book": [".......", "###.###", "#..#..#", "#..#..#", "#..#..#", "#######", "...#..."],
	"swords": ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", "##...##", "##...##"],
	"skull": ["..###..", ".#####.", "#..#..#", "#######", ".##.##.", "..#.#..", "..#.#.."],
	"stairs": ["......#", ".....##", "....###", "...####", "..#####", ".######", "#######"],
	"door": [".#####.", ".#...#.", ".#...#.", ".#..##.", ".#...#.", ".#...#.", ".#####."],
	"peace": [".#####.", "#..#..#", "#..#..#", "#.###.#", "##.#.##", "#..#..#", ".#####."],
	"drop": ["...#...", "...#...", "..###..", ".#####.", ".#####.", ".#####.", "..###.."],
	"ghost": ["..###..", ".#####.", "#.#.#.#", "#######", "#######", "#######", "#.#.#.#"],
	"pit": ["#.....#", "#.....#", ".#...#.", ".#...#.", "..#.#..", "..#.#..", "...#..."],
	"meat": ["...###.", "..#####", "..#####", "..####.", ".##....", "##.....", "##....."],
	"bowl": ["..#.#..", ".#.#...", ".......", "#######", "#######", ".#####.", "..###.."],
	"eye": [".......", "..###..", ".#...#.", "#..#..#", ".#...#.", "..###..", "......."],
}


static func known(name: String) -> bool:
	return GLYPHS.has(name)


## The glyph alone, as big as whole squares fit in `box`, in its middle.
static func glyph(c: CanvasItem, name: String, box: Rect2, colour: Color) -> void:
	var rows: Array = GLYPHS.get(name, GLYPHS.secret)
	var px := maxf(1.0, floorf(minf(box.size.x, box.size.y) / 7.0))
	var from := (box.position + (box.size - Vector2(px, px) * 7.0) / 2.0).floor()
	for y in 7:
		var row: String = rows[y]
		for x in 7:
			if row[x] == "#":
				c.draw_rect(Rect2(from + Vector2(x, y) * px, Vector2(px, px)), colour)


## The glyph in its frame: lit in `colour` once earned, with `glow` (0..1) more light for one earned this moment.
static func badge(c: CanvasItem, name: String, box: Rect2, colour: Color, earned: bool, glow := 0.0) -> void:
	c.draw_rect(box, Color.BLACK)
	if earned:
		c.draw_rect(box, Color(colour, 0.12 + 0.3 * glow))
	c.draw_rect(box.grow(-1.0), colour if earned else LOCKED_EDGE, false, 2.0)
	glyph(c, name, box.grow(-floorf(box.size.x * 0.14)), colour.lerp(Color.WHITE, glow * 0.6) if earned else LOCKED)


## "NOV 17 2026" for a moment in Unix seconds, in the player's own time; "" for 0 (the day was never kept).
static func day(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias: int = int(Time.get_time_zone_from_system().bias) * 60
	var d := Time.get_date_dict_from_unix_time(unix + bias)
	return "%s %d %d" % [MONTHS[int(d.month) - 1], int(d.day), int(d.year)]
