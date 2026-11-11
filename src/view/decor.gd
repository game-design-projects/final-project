## Which walls carry what: torches, chains, banners, cracks, barred windows, skull niches. Which wall gets which is decided
## by a hash of its place and the floor's seed, so a wall is always decorated the same way. wall_art.gd draws them; a cracked
## wall always shows a fissure, in the accent colour: it can be breakable only if it can be told apart from the cracks that are
## only cracks. The wall with the writing on it (rules/lore.gd) carries that and nothing else.
extends RefCounted

const DungeonMesh = preload("res://src/view/dungeon_mesh.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")

const KINDS := ["torch", "torch", "chains", "banner", "crack", "window", "niche"]
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
					out.append({"cell": c, "side": side, "kind": KINDS[int(roll[1] * KINDS.size()) % KINDS.size()], "roll": roll[0]})
	return out


## Two numbers in 0..1 from a wall's place: whether it is decorated, and with what.
static func _hash(x: int, y: int, side: int, seed_value: int) -> Array:
	var h := (x * 73856093) ^ (y * 19349663) ^ (side * 83492791) ^ (seed_value * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	var a := float(h & 0xFFFF) / 65536.0
	var b := float((h >> 16) & 0xFFFF) / 65536.0
	return [a, b]


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
