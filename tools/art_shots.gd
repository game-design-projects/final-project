## Renders the drawn look in motion, for docs/art and for looking at: a run's first moment, a walk past a torch, a fight, and the same spot at every
## warmth. It needs a real window and a fixed clock, so what it records is smooth however slow the machine (see DEVELOPMENT.md):
##   godot --path . --fixed-fps 20 -s res://tools/art_shots.gd -- out=/some/dir seed=7 [only=opening,walk,fight,warmth]
## Each clip is a numbered run of PNGs in out/<clip>/; tools/art/reels.sh makes them GIFs. Nothing reaches the player's saves.
extends SceneTree

const Decor = preload("res://src/view/decor.gd")
const Flags = preload("res://src/utils/flags.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

var _out := ""
var _game
var _only := []


func _initialize() -> void:
	Flags.set_args(OS.get_cmdline_user_args() as PackedStringArray + PackedStringArray(["nosave"]))
	_out = Flags.value("out", ProjectSettings.globalize_path("user://art_shots"))
	var only := Flags.value("only", "")
	_only = only.split(",") if only != "" else []
	_go.call_deferred()


func _wanted(clip: String) -> bool:
	return _only.is_empty() or _only.has(clip)


func _go() -> void:
	var scene = load("res://src/gameplay/gameplay.tscn").instantiate()
	scene.request = {"kind": "new"}
	root.add_child(scene)
	_game = scene
	await _new_run_settled()
	if _wanted("opening"):
		await _record("opening", 8.0)
	else:
		await _frames(int(8.0 * Engine.get_frames_per_second()))
	var torch: Dictionary = _a_torch()
	if _wanted("walk"):
		await _walk(torch)
	if _wanted("warmth"):
		await _warmth(torch)
	if _wanted("fight"):
		await _fight()
	print("art_shots: written to %s" % _out)
	quit()


func _new_run_settled() -> void:
	while _game.flow == null or _game.flow.state.stage != "explore":
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## `seconds` of the game, every frame a PNG.
func _record(clip: String, seconds: float) -> void:
	var dir := "%s/%s" % [_out, clip]
	DirAccess.make_dir_recursive_absolute(dir)
	var from := DirAccess.get_files_at(dir).size()
	var n := roundi(seconds * Engine.physics_ticks_per_second / 3.0)
	for i in n:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%04d.png" % [dir, from + i])
	print("art_shots: %s, %d frames" % [clip, n])


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("art_shots: %s" % name)


## A torch with two open cells before it, to walk up to.
func _a_torch() -> Dictionary:
	var f = _game.flow.state.floor_map
	var best := {}
	for p in Decor.placements(f):
		if p.kind == "torch" and f.is_open(p.cell - FloorMap.DIRS[p.side]):
			best = p
			if f.is_open(p.cell - FloorMap.DIRS[p.side] * 2):
				return p
	return best


func _stand(cell: Vector2i, facing: int) -> void:
	var s = _game.flow.state
	s.cell = cell
	s.facing = facing
	s.look()


func _walk(torch: Dictionary) -> void:
	var s = _game.flow.state
	var way: Vector2i = FloorMap.DIRS[torch.side]
	var far: Vector2i = torch.cell - way * (2 if s.floor_map.is_open(torch.cell - way * 2) else 1)
	_stand(far, torch.side)
	await _frames(10)
	await _record("walk", 1.2)
	while s.cell != torch.cell:
		await _game.flow.press("up")
		await _record("walk", 1.0)
	await _record("walk", 1.5)


func _warmth(torch: Dictionary) -> void:
	var s = _game.flow.state
	var way: Vector2i = FloorMap.DIRS[torch.side]
	_stand(torch.cell - way if s.floor_map.is_open(torch.cell - way) else torch.cell, torch.side)
	var m = s.floor_map.monsters.filter(func(o): return not o.boss and not o.lurking)[0]
	var was_at: Vector2i = m.cell
	var was_species: String = m.species
	m.cell = torch.cell
	m.species = "bandit"
	_forget(m)
	for level in [["beloved", {"spared": 4}], ["kind", {}], ["wary", {"slain": 2}], ["shut", {"slain": 4}], ["cold", {"slain": 6}]]:
		s.tally.spared = level[1].get("spared", 0)
		s.tally.slain = level[1].get("slain", 0)
		await _frames(int(4.0 * Engine.physics_ticks_per_second / 3.0))
		await _shot("warmth_%s" % level[0])
	s.tally.spared = 0
	s.tally.slain = 0
	m.cell = was_at
	m.species = was_species
	_forget(m)
	await _frames(int(4.0 * Engine.physics_ticks_per_second / 3.0))


## The set builds a monster's model once; drop it, so a changed species shows.
func _forget(m) -> void:
	var stage = _game._stage
	if stage._models.has(m):
		stage._models[m].queue_free()
		stage._tags[m].queue_free()
		stage._models.erase(m)
		stage._tags.erase(m)
		stage._tag_light.erase(m)


func _fight() -> void:
	var flow = _game.flow
	var s = flow.state
	var m = s.floor_map.monsters.filter(func(o): return not o.boss and not o.lurking and o.species == "bandit").front()
	if m == null:
		m = s.floor_map.monsters.filter(func(o): return not o.boss and not o.lurking)[0]
	s.max_hp = 9999
	s.hp = 9999
	await flow.go("intro", {"foe": m})
	await _record("fight", 2.0)
	_game._overlay.emote("good")
	await _record("fight", 1.6)
	_game._overlay.emote("bad")
	await _record("fight", 1.6)
	await flow.press("1")
	await _record("fight", 0.7)
	await flow.press("confirm")
	await _record("fight", 1.2)
	while s.stage != "dodge" and s.stage != "menu":
		await process_frame
	if s.stage == "dodge":
		await _record("fight", 2.0)
