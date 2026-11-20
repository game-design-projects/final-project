## Which walls carry what: torches, chains, banners, barred windows, skull niches, and a blemish (moss, or a bat asleep on its
## hook). Which wall gets which is decided by a hash of its place and the floor's seed, so a wall is always decorated the same
## way. wall_art.gd draws them. A cracked wall always shows a fissure in the accent colour, and **no plain wall carries a
## crack** (#160): testers learned the decorative cracks were decoration and stopped walking into the real ones, so the slot the
## crack had draws moss or a bat instead. The wall with the writing on it (rules/lore.gd) carries that and nothing else.
extends RefCounted

const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

const KINDS := ["torch", "torch", "chains", "banner", "window", "niche", "blemish"]
const BLEMISH := ["moss", "bat"] # what a blemish is drawn as, half each
const SHARE := 0.32 # about this share of wall faces carry something

## Which walls carry what: [{"cell": Vector2i, "side": int, "kind": String, "roll": float}], the same every time for a floor.
static func placements(floor_map) -> Array:
	var out := []
	for y in floor_map.size:
		for x in floor_map.size:
			var c := Vector2i(x, y)
			if not floor_map.is_open(c):
				continue
			for side in 4:
				if floor_map.is_open(c + FloorMap.DIRS[side]):
					continue
				if floor_map.is_cracked(c + FloorMap.DIRS[side]):
					out.append({"cell": c, "side": side, "kind": "fissure", "roll": 0.0})
					continue
				if floor_map.lore_at(c) and floor_map.lore.side == side:
					out.append({"cell": c, "side": side, "kind": "lore", "roll": 0.5})
					continue
				var roll := _hash(x, y, side, floor_map.seed_value)
				if roll[0] <= SHARE:
					out.append({"cell": c, "side": side, "kind": _kind(roll), "roll": roll[0]})
	return out


## What a decorated face carries: one of KINDS, and a blemish one of BLEMISH rather than its own name.
static func _kind(roll: Array) -> String:
	var kind: String = KINDS[int(roll[1] * KINDS.size()) % KINDS.size()]
	return BLEMISH[int(roll[2] * BLEMISH.size()) % BLEMISH.size()] if kind == "blemish" else kind


## Three numbers in 0..1 from a wall's place: whether it is decorated, with what, and which of that kind's drawings.
static func _hash(x: int, y: int, side: int, seed_value: int) -> Array:
	var h := (x * 73856093) ^ (y * 19349663) ^ (side * 83492791) ^ (seed_value * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	var a := float(h & 0xFFFF) / 65536.0
	var b := float((h >> 16) & 0xFFFF) / 65536.0
	var c := float((h >> 32) & 0xFFFF) / 65536.0
	return [a, b, c]


## A wall face seen from inside its cell: where (u, v) on it is in the world.
class _Face:
	extends RefCounted
	var a: Vector3 # u = 0, on the floor
	var across: Vector3 # a to the u = 1 end
	var inward: Vector3 # which way is into the cell, for lifting off the wall

	func _init(mid: Vector3, side: int, half: float) -> void:
		var b: Vector3
		match side:
			0: a = mid + Vector3(-half, 0, -half); b = mid + Vector3(half, 0, -half)
			1: a = mid + Vector3(half, 0, -half); b = mid + Vector3(half, 0, half)
			2: a = mid + Vector3(half, 0, half); b = mid + Vector3(-half, 0, half)
			_: a = mid + Vector3(-half, 0, half); b = mid + Vector3(-half, 0, -half)
		across = b - a
		inward = -Vector3(FloorMap.DIRS[side].x, 0, FloorMap.DIRS[side].y)

	## A frame on the face at (u, v), `out` off the wall: +X along the wall as you face it, +Y up, +Z out into the cell.
	func frame(u: float, v: float, out := 0.0) -> Transform3D:
		var at := a + across * u + Vector3(0, DungeonMesh.WALL_H * (1.0 - v), 0) + inward * out
		return Transform3D(Basis(across.normalized(), Vector3.UP, inward), at)
