## How party members and monsters look at a glance: health states, conditions, loyalty and spell slots
## as plain words plus a color. Pure data and helpers, so the party panel and the canvas share them.
extends RefCounted

const J = preload("res://src/core/js.gd")
const Canvas2D = preload("res://src/view/canvas2d.gd")

const HP_COLORS = {
	"healthy": "#6bd36b",
	"hurt": "#ffd23f",
	"critical": "#ff5a4a",
	"dying": "#ff5a4a",
	"stable": "#c08a8a",
	"dead": "#5a5a5a",
}

const HP_WORDS = {"healthy": "HEALTHY", "hurt": "HURT", "critical": "CRITICAL", "dying": "DYING", "stable": "STABLE", "dead": "DEAD"}


## Healthy from 75% of max health, hurt from 35%, critical below that. Down members are dying until stable.
## Returns {id, word, color, pct}.
static func hp_state(m: Dictionary) -> Dictionary:
	var max_hp = m.get("maxHp", 0)
	var pct := clampf(float(m.get("hp", 0)) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
	var id: String
	if J.truthy(m.get("dead")):
		id = "dead"
	elif J.truthy(m.get("down")):
		id = "stable" if J.truthy(m.get("stable")) else "dying"
	else:
		id = "healthy" if pct >= 0.75 else ("hurt" if pct >= 0.35 else "critical")
	return {"id": id, "word": HP_WORDS[id], "color": HP_COLORS[id], "pct": pct}


## Every condition a party member or monster can have, in display order. Party troubles first, then monster states.
const CONDITIONS = {
	"asleep": {
		"word": "ASLEEP",
		"icon": "zzz",
		"color": "#8fd3ff",
		"tip": "ASLEEP: SKIPS ITS TURNS UNTIL HURT. HITS ON IT ARE CRITICAL",
	},
	"held": {
		"word": "PARALYZED",
		"icon": "bolt",
		"color": "#8fd3ff",
		"tip": "PARALYZED: SKIPS ITS TURNS. HITS ON IT ARE CRITICAL",
	},
	"poisoned": {
		"word": "POISONED",
		"icon": "drop",
		"color": "#9ed36b",
		"tip": "POISONED: ROLLS TWICE AND KEEPS THE WORSE ON ATTACKS",
	},
	"restrained": {"word": "ENTANGLED", "icon": "chain", "color": "#d39a6a", "tip": "ENTANGLED: WORSE ATTACKS, AND EASIER TO HIT"},
	"prone": {
		"word": "KNOCKED DOWN",
		"icon": "down",
		"color": "#ffb347",
		"tip": "KNOCKED DOWN: LOSES ITS NEXT TURN GETTING UP",
	},
	"charmed": {"word": "CHARMED", "icon": "heart", "color": "#ff9de2", "tip": "CHARMED: WON'T ATTACK THIS ROUND"},
	"laughing": {"word": "LAUGHING", "icon": "smile", "color": "#ffe14a", "tip": "LAUGHING: TOO BUSY LAUGHING TO FIGHT"},
	"confused": {"word": "CONFUSED", "icon": "what", "color": "#b79cf0", "tip": "CONFUSED: LOSES ITS TURN"},
	"frightened": {"word": "SCARED", "icon": "alarm", "color": "#cfe8ff", "tip": "SCARED: ITS ATTACKS ARE WORSE"},
	"demoralized": {"word": "SADDENED", "icon": "frown", "color": "#7f9cff", "tip": "SADDENED: ITS ATTACKS ARE WORSE"},
	"spiteful": {"word": "SPITEFUL", "icon": "flame", "color": "#ff8a5a", "tip": "SPITEFUL: HITS YOU 2 HARDER"},
	"enraged": {
		"word": "ENRAGED",
		"icon": "flame",
		"color": "#ff5a4a",
		"tip": "ENRAGED: ATTACKS BETTER AND HITS 3 HARDER, BUT IS EASIER TO HIT",
	},
	"exposed": {"word": "OFF GUARD", "icon": "target", "color": "#ffd27a", "tip": "OFF GUARD: YOUR ATTACKS ON IT ARE BETTER"},
	"weakspot": {
		"word": "WEAK SPOT",
		"icon": "target",
		"color": "#ffd27a",
		"tip": "WEAK SPOT: +2 TO HIT IT FOR THE REST OF THE FIGHT",
	},
	"lit": {"word": "GLOWING", "icon": "star", "color": "#fff3a0", "tip": "GLOWING: THE NEXT ATTACK ON IT IS BETTER"},
	"dodging": {
		"word": "DODGING",
		"icon": "dodge",
		"color": "#aaaaaa",
		"tip": "DODGING: YOUR ATTACKS ON IT ARE WORSE THIS ROUND",
	},
}


## A creature's conditions as [{ id, word, icon, color, tip }], at most `max_count` of them.
static func cond_list(cond, max_count := 1 << 30) -> Array:
	var out := []
	if cond == null:
		return out
	for k in CONDITIONS:
		if out.size() >= max_count:
			break
		if J.truthy(cond.get(k)):
			var c: Dictionary = {"id": k}
			c.merge(CONDITIONS[k])
			out.append(c)
	return out


## How a monster ally feels about staying with you.
static func loyalty_state(l) -> Dictionary:
	if l == null:
		return {"word": "MAY LEAVE", "color": "#ff5a4a"}
	if l >= 75:
		return {"word": "DEVOTED", "color": "#6bd36b"}
	if l >= 50:
		return {"word": "CONTENT", "color": "#a8d38f"}
	if l >= 30:
		return {"word": "UNEASY", "color": "#ffd23f"}
	if l >= 15:
		return {"word": "RESENTFUL", "color": "#ff9a3d"}
	return {"word": "MAY LEAVE", "color": "#ff5a4a"}


## One color per spell circle, so a circle-3 spell in a menu matches the gold pips in the party panel.
const CIRCLE_COLORS = ["#8fd3ff", "#c79cff", "#ffd27a"]
const CIRCLE_WORDS = ["FIRST", "SECOND", "THIRD"]


## Spell slots as one group per circle: [{circle, left, max, color, pips: [bool]}]. `slots` is what is left per circle
## (null for none), `max_slots` the most per circle (null or empty for none).
static func slot_groups(slots, max_slots) -> Array:
	var out := []
	if max_slots == null:
		return out
	for i in max_slots.size():
		var top := int(max_slots[i])
		var left := clampi(int(slots[i]) if slots != null and i < slots.size() and slots[i] != null else 0, 0, top)
		var pips := []
		for j in top:
			pips.append(j < left)
		out.append({"circle": i + 1, "left": left, "max": top, "color": CIRCLE_COLORS[i] if i < CIRCLE_COLORS.size() else "#e8e8e8", "pips": pips})
	return out


const CLASS_WORDS = {"fighter": "FIGHTER", "cleric": "CLERIC", "wizard": "WIZARD"}
const SPECIES_WORDS = {"slime": "SLIME", "goblin": "GOBLIN", "dragon": "DRAGON", "snake": "SNAKE PERSON", "rock": "ROCK ENTITY", "bandit": "BANDIT"}


static func class_word(m: Dictionary) -> String:
	if m.get("kind") == "human":
		return CLASS_WORDS.get(m.get("clsId"), str(m.get("clsId")).to_upper())
	return SPECIES_WORDS.get(m.get("species"), str(m.get("species")).to_upper())


static func facing_word(dir) -> String:
	var words := ["NORTH", "EAST", "SOUTH", "WEST"]
	return "" if dir == null or int(dir) < 0 or int(dir) >= words.size() else words[int(dir)]


static func floor_name(n) -> String:
	return "FLOOR %s" % J.num(n)


## 7x7 pixel icons, so states read by shape before you read a word. "#" is a lit pixel.
const ICONS = {
	"note": ["...###.", "...#..#", "...#...", "...#...", ".###...", "####...", ".##...."],
	"speaker": ["...#...", "..##.#.", "####..#", "####..#", "####..#", "..##.#.", "...#..."],
	"bubble": [".#####.", "#######", "##.#.##", "#######", ".#####.", "..##...", ".#....."],
	"question": ["..###..", ".#...#.", ".....#.", "...##..", "...#...", ".......", "...#..."],
	"eye": [".......", ".#####.", "#..#..#", "#.###.#", "#..#..#", ".#####.", "......."],
	"heart": [".##.##.", "#######", "#######", ".#####.", "..###..", "...#...", "......."],
	"skull": ["..###..", ".#####.", "#..#..#", "#######", ".##.##.", "..#.#..", "..#.#.."],
	"zzz": ["####...", "..#....", ".#.....", "####...", "....###", ".....#.", "....###"],
	"drop": ["...#...", "..###..", ".#####.", ".#####.", "#######", ".#####.", "..###.."],
	"chain": [".##....", "#..#...", "#..##..", ".##..#.", "...#..#", "...#..#", "....##."],
	"shield": ["#######", "#######", "#######", "#######", ".#####.", "..###..", "...#..."],
	"down": ["...#...", "...#...", "...#...", "#######", ".#####.", "..###..", "...#..."],
	"up": ["...#...", "..###..", ".#####.", "#######", "...#...", "...#...", "...#..."],
	"left": ["...#...", "..##...", ".######", "#######", ".######", "..##...", "...#..."],
	"right": ["...#...", "...##..", "######.", "#######", "######.", "...##..", "...#..."],
	"coin": ["..###..", ".#####.", "##.####", "##.####", "##.####", ".#####.", "..###.."],
	"star": ["...#...", "...#...", "#######", ".#####.", "..###..", ".##.##.", ".#...#."],
	"bolt": ["...###.", "..###..", ".###...", "#######", "...###.", "..###..", ".##...."],
	"flame": ["...#...", "..##...", "..###.#", ".#####.", "#######", "#######", ".#####."],
	"target": [".#####.", "#.....#", "#.###.#", "#.###.#", "#.###.#", "#.....#", ".#####."],
	"smile": [".#####.", "#.....#", "#.#.#.#", "#.....#", "#.#.#.#", "#..#..#", ".#####."],
	"frown": [".#####.", "#.....#", "#.#.#.#", "#.....#", "#..#..#", "#.#.#.#", ".#####."],
	"what": [".####..", "#....#.", "....#..", "...#...", "...#...", ".......", "...#..."],
	"alarm": ["...#...", "...#...", "...#...", "...#...", "...#...", ".......", "...#..."],
	"dodge": ["#......", "##.....", "###....", "####...", "###....", "##.....", "#......"],
	"dot": [".......", "..###..", ".#####.", ".#####.", ".#####.", "..###..", "......."],
}

static var _icon_images := {}
static var _icon_textures := {}


## An icon as a 7x7 Image (1 pixel per dot) in the given color (CSS string or Color); unknown names fall back to a dot.
static func icon_image(name: String, color = "#e8e8e8") -> Image:
	if not ICONS.has(name):
		name = "dot"
	var col := Canvas2D.css(color)
	var key := "%s|%s" % [name, col.to_html()]
	if _icon_images.has(key):
		return _icon_images[key]
	var rows: Array = ICONS.get(name, ICONS.dot)
	var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	for y in 7:
		for x in 7:
			if rows[y][x] == "#":
				img.set_pixel(x, y, col)
	_icon_images[key] = img
	return img


## An icon as a crisp texture, 1 texel per dot, in the given color; cached per name and color. Put it on a TextureRect
## with nearest filtering (or `texture_filter = NEAREST`) to scale it.
static func icon_texture(name: String, color = "#e8e8e8") -> Texture2D:
	if not ICONS.has(name):
		name = "dot"
	var key := "%s|%s" % [name, Canvas2D.css(color).to_html()]
	if _icon_textures.has(key):
		return _icon_textures[key]
	var tex := ImageTexture.create_from_image(icon_image(name, color))
	_icon_textures[key] = tex
	return tex


## Draws an icon with its top-left corner at `pos`, each dot `px` pixels square. For use inside `_draw()`.
static func draw_icon(item: CanvasItem, name: String, pos: Vector2, color = "#e8e8e8", px := 1) -> void:
	var rows: Array = ICONS.get(name, ICONS.dot)
	var col := Canvas2D.css(color)
	for y in 7:
		for x in 7:
			if rows[y][x] == "#":
				item.draw_rect(Rect2(pos + Vector2(x, y) * px, Vector2(px, px)), col)


## Moving the highlight in a menu: wraps at both ends.
static func menu_step(sel, delta: int, count: int) -> int:
	var s: int = -delta if sel == null else int(sel)
	return ((s + delta) % count + count) % count


## The party holds six. Adventurers keep their seats (even fallen ones); monster allies fill the rest.
const PARTY_MAX = 6


## {allies, max, full} for a party (Array of members).
static func ally_room(party: Array) -> Dictionary:
	var allies := 0
	for m in party:
		if m.get("kind") == "monster":
			allies += 1
	return {"allies": allies, "max": PARTY_MAX - (party.size() - allies), "full": party.size() >= PARTY_MAX}
