## Checks the drawn look with no window: that the atlases say what the game needs, how a figure moves (a change of mood never makes its
## eyes jump), how warm the halls are and what that does, what a face shows, and Wick from her first hop to a saved game.
## Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/art_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Ally = preload("res://src/game/ally.gd")
const BattleArt = preload("res://src/view/battle_art.gd")
const Combat = preload("res://src/rules/combat.gd")
const Content = preload("res://src/rules/content.gd")
const Decor = preload("res://src/view/decor.gd")
const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const Figure = preload("res://src/view/figure.gd")
const FigureAnim = preload("res://src/view/figure_anim.gd")
const Flags = preload("res://src/utils/flags.gd")
const FloorGen = preload("res://src/rules/floor_gen.gd")
const Floors = preload("res://src/rules/floors.gd")
const Flow = preload("res://src/game/flow.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Monster = preload("res://src/rules/monster.gd")
const MonsterModel = preload("res://src/view/monster_model.gd")
const Moods = preload("res://src/rules/moods.gd")
const Opening = preload("res://src/view/opening.gd")
const Overlay = preload("res://src/view/overlay.gd")
const Rng = preload("res://src/utils/rng.gd")
const Sprites = preload("res://src/view/sprites.gd")
const State = preload("res://src/game/state.gd")
const WallArt = preload("res://src/view/wall_art.gd")
const Warmth = preload("res://src/rules/warmth.gd")

const FIGURES := ["slime", "bandit", "snake", "rock", "dragon", "witch"]
const ACTIONS := ["idle", "hop", "happy", "scared", "angry", "hurt", "lunge", "hollow"]
const FRAME := 1.0 / 60.0


func _name() -> String:
	return "art_test"


func _run() -> void:
	_the_atlases_are_whole()
	_a_figure_moves_without_jumps()
	_warmth_is_read_off_the_deeds()
	_moods_are_read_off_the_meters()
	_figure_nodes()
	_wall_art_answers_the_warmth()
	await _wick()
	await _the_set_wears_it()
	_the_battle_screen_shows_the_face()
	_the_opening()
	_the_menu_has_her()
	await _the_slice_keeps_the_old_look()
	_finish()


func _flow(seed_value: int, words := []):
	var all := PackedStringArray(["nosave", "nosound", "seed=%d" % seed_value])
	all.append_array(PackedStringArray(words))
	Flags.set_args(all)
	return Flow.new(Rng.new(seed_value), LocalMind.new())


func _monster(species := "slime", boss := false):
	var sp := Content.species(species)
	var m = Monster.make(Rng.new(3), {"species": species, "genre": "bullet", "hp": 10, "boss": boss, "name": "SOMEONE"}, Vector2i(1, 1))
	_check(sp != null, "there is a %s to make" % species)
	return m


func _the_atlases_are_whole() -> void:
	for name in FIGURES:
		var sheet := Sprites.sheet(name)
		var tex := Sprites.texture(name)
		_check(tex != null and tex.get_size() == Vector2(sheet.size[0], sheet.size[1]), "%s's atlas is the size its table says" % name)
		var imported := ConfigFile.new()
		imported.load(str(sheet.file) + ".import")
		_check(imported.get_value("params", "mipmaps/generate", false), "%s's atlas has mipmaps: a figure far off is small" % name)
		var bounds := Rect2(Vector2.ZERO, tex.get_size())
		for act in ACTIONS:
			_check(Sprites.has_action(name, act), "%s can %s" % [name, act])
			var a := Sprites.action(name, act)
			_check(bounds.encloses(Sprites.frame_rect(name, act, int(a.count) - 1)), "%s's last %s frame is on its atlas" % [name, act])
		_check(float(sheet.world_h) > 0.0 and float(sheet.body_h) > 0.0, "%s has a height" % name)
	_check(Sprites.has_action("trader", "idle"), "the trader has a drawing")
	for sheet_name in ["decor", "flame", "props"]:
		var sheet := Sprites.sheet(sheet_name)
		var bounds := Rect2(Vector2.ZERO, Sprites.texture(sheet_name).get_size())
		for drawing in sheet.frames:
			_check(bounds.encloses(Sprites.drawing_rect(sheet_name, drawing)), "%s %s is on its atlas" % [sheet_name, drawing])
	for drawing in WallArt.SIZE:
		_check(Sprites.sheet("decor").frames.has(drawing) and WallArt.DOWN.has(drawing), "the wall has a %s to hang" % drawing)
	_check(Sprites.texture("keyart") != null, "the title has its picture")


## A figure's frames at 60 steps a second: which it shows, and that the frame moves by at most one at a time within an action.
func _watch(anim, from: float, seconds: float) -> Array:
	var out := []
	for i in int(seconds * 60.0):
		var at: Dictionary = anim.tick(from + i * FRAME)
		out.append(at)
	return out


func _a_figure_moves_without_jumps() -> void:
	var anim = FigureAnim.new("bandit", 11)
	var seen := {}
	for at in _watch(anim, 0.0, 14.0):
		seen[at.frame] = true
		_check_quietly(at.act == "idle", "at rest it is idle")
	_check(seen.has(0) and seen.has(2) and seen.has(4) and seen.has(5), "at rest it breathes and blinks (%s)" % [seen.keys()])

	anim = FigureAnim.new("bandit", 1)
	anim.set_mood("happy", 0.0)
	var happy := _watch(anim, 0.0, 2.0)
	_check(happy[0].act == "happy" and happy[0].frame == 0, "a new mood starts from the resting frame")
	_check(_steps_fine(happy), "and it goes frame by frame")
	var last: int = int(Sprites.action("bandit", "happy").count) - 1
	_check(happy[-1].frame >= last - 1, "and stays at its end (%d)" % happy[-1].frame)
	anim.set_mood("angry", 2.0)
	var change := _watch(anim, 2.0, 2.0)
	var first_angry := change.find_custom(func(a): return a.act == "angry")
	_check(change[0].act == "happy" and first_angry > 0 and change[first_angry].frame == 0, "a change of mood goes back to rest before the next")
	_check(_steps_fine(change.slice(0, first_angry)) and _steps_fine(change.slice(first_angry)), "without a jump either way")
	_check(anim.mood_act() == "angry", "and says what it is going to")

	anim = FigureAnim.new("bandit", 1)
	anim.set_mood("hollow", 0.0)
	var blank := _watch(anim, 0.0, 6.0)
	var end_frame: int = int(Sprites.action("bandit", "hollow").count) - 1
	_check(blank[-1].act == "hollow" and blank[-1].frame == end_frame and blank[-40].frame == end_frame, "a blank face holds still")

	anim = FigureAnim.new("slime", 1)
	anim.hop(0.0)
	_check(anim.tick(0.01).act == "hop", "a hop at rest is the drawn hop")
	var hop := _watch(anim, 0.01, 1.0)
	_check(hop[-1].act == "idle" and _steps_fine(hop.slice(0, 20)), "and it lands back at rest")
	anim = FigureAnim.new("slime", 1)
	anim.set_mood("angry", 0.0)
	anim.hop(1.0)
	var arc: Dictionary = anim.tick(1.0 + FigureAnim.HOP_S / 2.0)
	_check(arc.act == "angry" and arc.lift > 0.1, "angry, it hops in code and keeps its face")

	anim = FigureAnim.new("rock", 1)
	anim.notice(0.0)
	var start := _watch(anim, 0.0, 1.5)
	var top := 0
	for at in start:
		if at.act == "happy":
			top = maxi(top, at.frame)
	_check(top == FigureAnim.NOTICE_FRAME and start[-1].act == "idle", "a start goes part of the way into its reaction and back (%d)" % top)

	anim = FigureAnim.new("dragon", 1)
	anim.set_mood("happy", 0.0)
	anim.hurt(0.2)
	_check(anim.tick(0.21).act == "hurt" and anim.tick(0.21).shake != 0.0, "a hit cuts in, shaking")
	_check(anim.tick(3.0).act == "happy", "and the face is back after it")
	anim.lunge(4.0)
	_check(anim.tick(4.01).act == "lunge", "and so does a lunge")

	anim = FigureAnim.new("trader", 1)
	anim.set_mood("hollow", 0.0)
	_check(anim.tick(0.5).act == "idle", "someone with no such drawing stays calm")


var _quiet_fails := []


func _check_quietly(ok: bool, what: String) -> void:
	if not ok and not _quiet_fails.has(what):
		_quiet_fails.append(what)
		_check(false, what)


static func _steps_fine(frames: Array) -> bool:
	for i in range(1, frames.size()):
		if frames[i].act == frames[i - 1].act and absi(frames[i].frame - frames[i - 1].frame) > 1:
			return false
	return true


func _warmth_is_read_off_the_deeds() -> void:
	var s = State.new()
	var table := Warmth.table()
	_check(is_equal_approx(Warmth.of(s), float(table.start)), "a run starts at %.2f" % table.start)
	_check(Warmth.level_id(Warmth.level(Warmth.of(s))) == "kind", "and that is the kind level, so a first torch looks at you")
	s.tally.spared = 4
	_check(Warmth.level_id(Warmth.level(Warmth.of(s))) == "beloved", "sparing warms the halls (%.2f)" % Warmth.of(s))
	s.tally.spared = 0
	s.tally.slain = 2
	_check(Warmth.level_id(Warmth.level(Warmth.of(s))) == "wary", "two killed and the torches look away (%.2f)" % Warmth.of(s))
	s.tally.slain = 4
	_check(Warmth.level_id(Warmth.level(Warmth.of(s))) == "shut", "four, and they shut their eyes (%.2f)" % Warmth.of(s))
	s.tally.slain = 6
	_check(Warmth.level(Warmth.of(s)) == 0 and Warmth.of(s) == 0.0, "six, and the halls are cold wire")
	s.tally.slain = 0
	s.butchered = [{"species": "slime", "name": "A"}]
	var after_one := Warmth.of(s)
	_check(after_one < float(table.start) - 0.2, "a friend in the bag costs more than a kill")
	s.meals = 1
	_check(Warmth.of(s) < after_one, "and feeding them to the others more")
	s.left_behind = ["B"]
	_check(Warmth.of(s) < after_one - 0.1, "leaving one at the gate too")
	var back = State.from_dict(_saved_state_with(s))
	_check(back != null and is_equal_approx(Warmth.of(back), Warmth.of(s)), "and it all comes back with a save, which keeps no warmth of its own")
	var levels: Array = table.levels
	for i in levels.size():
		for words in [levels[i].up, levels[i].down]:
			_check(words == "" or Overlay.banner_fits(words), "'%s' fits the banner" % words)
	_check(Warmth.line(3, 2) == levels[2].down and Warmth.line(2, 3) == levels[3].up and Warmth.line(2, 2) == "", "the words depend on the way it moved")


func _saved_state_with(s) -> Dictionary:
	var flow = _flow(5, ["no-wick"])
	flow.state = State.new()
	flow.state.depth = 1
	flow.state.floor_map = FloorGen.generate(Rng.new(5))
	flow.state.cell = flow.state.floor_map.start
	flow.state.tally = s.tally
	flow.state.butchered = s.butchered
	flow.state.meals = s.meals
	flow.state.left_behind = s.left_behind
	return flow.state.to_dict()


func _moods_are_read_off_the_meters() -> void:
	var m = _monster("bandit")
	m.meters = {"friendliness": 0.0, "anger": 0.0, "fear": 0.0}
	m.threshold = 50.0
	_check(Moods.of(m) == "calm", "nothing strong: calm")
	m.meters.friendliness = 60.0
	_check(Moods.of(m) == "happy", "friendly enough: happy")
	m.meters.fear = 70.0
	_check(Moods.of(m) == "scared", "afraid beats friendly")
	m.meters.anger = 70.0
	_check(Moods.of(m) == "angry", "angry beats both")
	m.meters = {"friendliness": 0.0, "anger": 0.0, "fear": 0.0}
	m.hunting = true
	_check(Moods.of(m) == "angry", "and hunting you is angry")
	m.hunting = false
	_check(not Moods.hollow(m, Moods.HOLLOW_TO + 0.01), "warm halls: no face is blank")
	_check(Moods.hollow(m, Moods.HOLLOW_FROM), "cold ones: every plain monster's is")
	_check(Moods.hollow(m, 0.2) == Moods.hollow(m, 0.2), "one goes at the same point each time")
	var boss = _monster("dragon", true)
	_check(not Moods.hollow(boss, Moods.HOLLOW_FROM) and Moods.hollow(boss, 0.0), "a champion's goes last")
	var at := {}
	for n in ["A", "BOB", "GLOP", "HISS", "OLD SHALE", "MOTH", "RUST", "VEX"]:
		var other = _monster("rock")
		other.name = n
		var w := Moods.HOLLOW_TO
		while w > Moods.HOLLOW_FROM and not Moods.hollow(other, w):
			w -= 0.01
		at[snappedf(w, 0.05)] = true
	_check(at.size() >= 3, "faces go one at a time, not all at once (%s)" % [at.keys()])


func _figure_nodes() -> void:
	var f: Node3D = Figure.make("slime", Color.WHITE, 4)
	var body: MeshInstance3D = f.get_node("Rig/Body")
	var quad: QuadMesh = body.mesh
	var s := Sprites.sheet("slime")
	var per_px := Sprites.world_per_px("slime")
	_check(is_equal_approx(quad.size.y, float(s.cell[1]) * per_px), "a quad the size of its frame")
	var feet_y := body.position.y - quad.size.y / 2.0 + (float(s.cell[1]) - float(s.feet[1])) * per_px
	_check(absf(feet_y) < 0.001, "its feet at the node's origin (%.3f)" % feet_y)
	_check(f.top() > float(s.world_h) * 0.8, "a name floats over it (%.2f)" % f.top())
	f.anim.hurt(0.0)
	f.pose(0.1)
	_check(f.get_meta("material").get_shader_parameter("cell") == Sprites.uv_rect("slime", Sprites.frame_rect("slime", "hurt", 1)), "pose shows the frame of the moment")
	f.free()
	var chest: Node3D = Figure.prop("props", "chest", Color.WHITE, 0.7)
	var part: MeshInstance3D = chest.get_node("Rig/Body")
	var ink := Sprites.ink("props", "chest")
	var cell_h: float = part.mesh.size.y
	var per: float = 0.7 / ink.size.y
	var ink_bottom := part.position.y + cell_h / 2.0 - ink.end.y * per
	_check(absf(ink_bottom) < 0.001, "a chest's drawing stands on the floor (%.3f)" % ink_bottom)
	chest.free()


func _wall_art_answers_the_warmth() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound"]))
	var f = FloorGen.generate(Rng.new(9))
	var torches := []
	var warm: Node3D = WallArt.build(f, Color.WHITE, Color.WHITE, torches, 3)
	var plain := []
	Decor.build(f, Color.WHITE, Color.WHITE, plain).free()
	_check(torches.size() == plain.size() and torches.size() > 0, "every torch of a floor is lit (%d)" % torches.size())
	var props: MeshInstance3D = warm.get_node("Props")
	_check(props.material_override.get_shader_parameter("sheet") == Sprites.texture("decor"), "what hangs on the wall comes from the decor atlas")
	var flames: MeshInstance3D = warm.get_node("Flames")
	_check(flames.material_override.get_shader_parameter("eyes") == WallArt.EYES_AT_LEVEL[3], "warm, the flames look at you")
	warm.free()
	var cold: Node3D = WallArt.build(f, Color.WHITE, Color.WHITE, [], 0)
	_check(cold.get_node("Flames").material_override.shader != load("res://src/view/shaders/flame_drawn.gdshader"), "at the coldest they are the old wire flames")
	cold.free()
	_check(WallArt.EYES_AT_LEVEL.size() == Warmth.table().levels.size(), "there is a face for every level")


func _wick() -> void:
	var friend := Floors.friend()
	_check(Overlay.banner_fits(friend.line) and Overlay.banner_fits(friend.line_film), "her words, and the ones after the opening film, fit the banner")
	var flow = _flow(5)
	await flow.new_run()
	var s = flow.state
	_check(s.has_ally("witch") and s.allies.size() == 1, "a run opens with her")
	_check(s.party_size() == 0 and s.allies[0].name == str(Content.table("friends").witch.name), "and she takes nobody's place")
	_check(s.allies[0].charm().name != "" and Content.species("witch") != null, "she has a charm and a card")
	_check(s.banner != null and s.banner.title == Floors.premise().title, "the words about the door come first")
	flow.tick(float(s.banner.t0) + 100.0)
	_check(s.banner.title == Floors.premise().title, "and stay while they are up")
	flow.tick(float(s.banner.t0) + Flow.DOOR_THEN_WICK_MS + 1.0)
	_check(s.banner.title == friend.title and s.banner.text == friend.line, "then hers")
	_check(s.lines.any(func(l): return l.text == friend.joined) and s.lines.size() == 2, "and the log says she came along, and where you are")
	var again = s.banner.t0
	flow.tick(float(again) + Flow.WICK_BANNER_MS + 1.0)
	_check(s.banner.t0 == again, "once")
	for i in 3:
		s.allies.append(Ally.make("rock", "R%d" % i, 70.0))
	_check(s.party_size() == Combat.PARTY_MAX, "three monsters are a full party with her along")
	var back = State.from_dict(s.to_dict())
	_check(back != null and back.has_ally("witch") and back.allies.size() == 4, "a save keeps her and all three")
	var crowded: Dictionary = s.to_dict()
	crowded.allies.append(crowded.allies[1].duplicate())
	back = State.from_dict(crowded)
	_check(back != null and back.party_size() == Combat.PARTY_MAX and back.has_ally("witch"), "a save with too many keeps her and three")
	var old: Dictionary = s.to_dict()
	old.allies = []
	back = State.from_dict(old)
	_check(back != null and back.allies.is_empty(), "a save from before her goes on without her")
	s.allies = [s.allies[0]]
	s.left_behind = ["Wick"]
	_check(Warmth.of(s) < float(Warmth.table().start), "leaving her at a gate is a cold thing to do")
	flow = _flow(6, ["no-wick"])
	await flow.new_run()
	_check(flow.state.allies.is_empty() and flow.state.banner.title == Floors.premise().title, "no-wick: you start alone")
	_check(flow.state.banner.ms == Flow.STORY_BANNER_MS, "and the door's words have the time to themselves")


func _the_set_wears_it() -> void:
	var flow = _flow(7)
	await flow.new_run()
	var s = flow.state
	var stage = load("res://src/view/stage.gd").new()
	root.add_child(stage)
	stage.update(s, 0.0, FRAME)
	var m = s.floor_map.monsters.filter(func(o): return not o.lurking and not o.boss)[0]
	m.cell = s.floor_map.start + Vector2i(1, 0)
	stage.update(s, 0.1, FRAME)
	_check(stage._models[m] is Figure, "a monster is a figure")
	_check(stage._wall_mat.get_shader_parameter("drawn") == 1.0 and stage._flat_mat.get_shader_parameter("drawn") == 1.0, "the walls and floors have their stones")
	_check(stage._decor.get_node("Props").material_override.get_shader_parameter("sheet") == Sprites.texture("decor"), "what hangs on them is drawn")
	m.meters.anger = 90.0
	stage.update(s, 0.2, FRAME)
	_check(stage._models[m].anim.mood_act() == "angry", "its face follows its meters")
	stage.update(s, 1.2, FRAME) # the hop that brought it next to you has landed
	var goal: Vector3 = DungeonMesh.center(m.cell + Vector2i(0, 1))
	m.cell += Vector2i(0, 1)
	stage.update(s, 1.3, FRAME)
	var anim = stage._models[m].anim
	_check(anim._code_hop == 1.3 or anim._shot == "hop", "it hops to the next cell (%s, %s, %s)" % [anim._code_hop, anim._shot, anim.mood_act()])
	for i in 20:
		stage.update(s, 1.3 + i * FRAME, FRAME)
	_check(stage._models[m].position == goal, "and arrives in the time of a step")
	var was_decor: Node3D = stage._decor
	var torches: int = stage._torches.size()
	s.tally.slain = 2
	stage.update(s, 2.0, FRAME)
	_check(stage._decor != was_decor and stage._torches.size() == torches, "the halls cooling hangs the walls again, with as many torches")
	_check(stage._warmth_shown > Warmth.of(s), "and the stones fade slowly (%.2f)" % stage._warmth_shown)
	s.tally.slain = 6
	stage.update(s, 2.1, FRAME)
	_check(stage._models[m].anim.mood_act() == "hollow", "cold enough, the face is gone")
	for i in 600:
		stage.update(s, 2.2 + i * 0.1, 0.1)
	_check(stage._wall_mat.get_shader_parameter("warmth") == 0.0, "and at the end only the wire is left")
	stage.off_set = m
	stage.update(s, 70.0, FRAME)
	_check(not stage._models[m].visible and not stage._tags[m].visible, "the foe on the battle screen is not on the set too")
	stage.off_set = null
	stage.free()


func _the_battle_screen_shows_the_face() -> void:
	Flags.set_args(PackedStringArray(["nosave", "nosound"]))
	var overlay = Overlay.new()
	root.add_child(overlay)
	var s = State.new()
	s.views["hand-drawn"] = true
	s.views["warmth"] = true
	s.stage = "menu"
	var m = _monster("bandit")
	m.meters = {"friendliness": 0.0, "anger": 0.0, "fear": 0.0}
	m.threshold = 50.0
	s.foe = m
	overlay.state = s
	var art = overlay._art
	overlay.clock_ms = 1000.0
	_check(overlay.drawn_foe(), "a foe with a drawing is drawn")
	art._process(FRAME)
	_check(art.face() == "idle", "calm, it is at rest")
	overlay.emote("good")
	art._process(FRAME)
	_check(art.face() == "happy", "a deed that lands makes it glad")
	overlay.clock_ms += Overlay.EMOTE_MS + 1.0
	overlay.emote("bad")
	art._process(FRAME)
	_check(art.face() == "angry", "one that doesn't, angry")
	overlay.clock_ms += Overlay.EMOTE_MS + 1.0
	s.tally.slain = 6
	art._process(FRAME)
	_check(art.face() == "hollow", "and in cold halls its face is gone")
	s.tally.slain = 0
	m.gone = "spared"
	art._process(FRAME)
	_check(art.face() == "happy", "spared, glad")
	m.gone = "slain"
	art._process(FRAME)
	_check(art.face() == "hollow", "slain, blank")
	m.gone = ""
	overlay.hurt_until = overlay.clock_ms + 300.0
	art._process(FRAME)
	_check(art._anim.tick(overlay.clock_ms / 1000.0 + 0.01).act == "hurt", "a hit shows")
	s.dodge = {"genre": "bullet"}
	art._process(FRAME)
	_check(art._small > 0.0, "and for a dodge it shrinks up out of the way")
	s.dodge = null
	s.foe = _monster("no such thing") if false else null
	art._process(FRAME)
	_check(art._anim == null, "out of the fight there is nothing to draw")
	_check(not BattleArt.can_draw("no such thing"), "and a foe with no drawing keeps the line art")
	overlay.free()


func _the_opening() -> void:
	var f = FloorGen.generate(Rng.new(9))
	var cell: Vector2i = f.start
	var facing: int = f.start_facing()
	var way: Array = Opening.path(f, cell, facing)
	var stop: Vector3 = way[-1]
	_check(stop.distance_to(DungeonMesh.center(cell)) <= Opening.STOP_AHEAD + 0.01, "she stops within reach")
	_check(way.size() <= Opening.MOST_CELLS + 1, "and comes from no farther than she can be seen (%d)" % way.size())
	for i in range(1, way.size()):
		_check(way[i].distance_to(stop) < way[i - 1].distance_to(stop), "each hop nearer")
	var o: Node3D = Opening.begin(f, cell, facing, Color.WHITE, 0.0)
	root.add_child(o)
	var camera: Vector3 = stop + Vector3(0, 0.85, 2.0)
	var t := 0.0
	while not o.given() and t < 10.0:
		_check_quietly(o.tick(t, camera, false), "she doesn't leave before she arrives")
		t += FRAME
	_check(o.given() and o._figure.position == stop, "she reaches you (%.1f s)" % t)
	_check(o.tick(t, camera, false) and o.tick(t + Opening.GIVE_S / 2.0, camera, false), "and stands there with the heart")
	var still: bool = o.tick(t + Opening.GIVE_S / 2.0 + 0.01, camera, true)
	_check(still, "moving makes her go")
	_check(not o.tick(t + Opening.GIVE_S / 2.0 + Opening.GOING_S + 0.1, camera, true), "and soon she is gone: she is with you")
	o.free()


func _the_menu_has_her() -> void:
	var wick = load("res://src/menu/menu_wick.gd").new()
	wick.size = Vector2(1180, 820)
	_check(wick.stands_at().x > 890.0 and wick.stands_at().x < 1180.0, "beside the menu's page, Wick stands in the room it leaves")
	wick.size = Vector2(700, 820)
	_check(wick.stands_at().x < 0.0, "and a narrow window leaves her out")
	wick.free()


## The personality slice is the reference run: no friend along, and the set, the monsters and the fight as they were before the drawings.
func _the_slice_keeps_the_old_look() -> void:
	var flow = _flow(5, ["personality-slice"])
	await flow.new_run()
	var s = flow.state
	_check(s.allies.is_empty() and not s.viewing("hand-drawn") and not s.viewing("warmth"), "the personality slice: nobody along, nothing drawn")
	var stage = load("res://src/view/stage.gd").new()
	root.add_child(stage)
	stage.update(s, 0.0, FRAME)
	var m = s.floor_map.monsters.filter(func(o): return not o.lurking)[0]
	m.cell = s.floor_map.start + Vector2i(1, 0)
	stage.update(s, 0.1, FRAME)
	_check(not stage._models[m] is Figure and stage._models[m].has_node("Rig"), "the old model")
	_check(stage._wall_mat.get_shader_parameter("drawn") in [null, 0.0], "the plain wire")
	s.tally.slain = 6
	var decor: Node3D = stage._decor
	stage.update(s, 0.2, FRAME)
	_check(stage._decor == decor, "and nothing answers what you do")
	stage.free()
	var overlay = Overlay.new()
	root.add_child(overlay)
	s.foe = m
	s.stage = "menu"
	overlay.state = s
	_check(not overlay.drawn_foe(), "a fight is the line art on black")
	overlay.free()
