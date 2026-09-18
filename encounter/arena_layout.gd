class_name DmjArenaLayout
extends RefCounted

## Shared placement helper for the industrial combat rooms.
##
## The arena helper is intentionally tiny: the enemy actors and the rail art
## both ask it for the same anchors so the scenery and the combatants never
## drift apart.

const ARENA_NAMES := [
	"LOADING BAY",
	"TURBINE HALL",
	"REACTOR DECK",
]
const ROOM_STRIDE := 34.0

const ARENA_DEPTHS := [
	[0.78, 0.62, 0.86],
	[0.63, 0.86, 0.72],
	[0.83, 0.66, 0.78],
]


static func arena_name(arena_index: int) -> String:
	return ARENA_NAMES[posmod(arena_index, ARENA_NAMES.size())]


static func world_origin(arena_index: int) -> Vector3:
	return Vector3(0, 0, -float(arena_index) * ROOM_STRIDE)


static func world_position(lane: int, arena_index: int, slot := 0) -> Vector3:
	var x := float(lane - 1) * 6.2
	if slot > 0:
		var side := (1.0 if lane == 0 else -1.0) if lane != 1 else (
			1.0 if slot % 2 == 1 else -1.0
		)
		x += side * (3.2 + float(slot - 1) * 0.35)
	var z := -2.0 - (1.0 - depth(lane, arena_index, slot)) * 12.0
	return world_origin(arena_index) + Vector3(x, 0, z)


static func depth(lane: int, arena_index: int, slot: int = 0) -> float:
	var room := posmod(arena_index, ARENA_DEPTHS.size())
	var lane_index := posmod(lane, ARENA_DEPTHS[room].size())
	var value := float(ARENA_DEPTHS[room][lane_index])
	if slot > 0:
		value -= 0.18 * float(slot)
	return clampf(value, 0.30, 0.92)


static func position(
	field: Rect2,
	lane: int,
	lane_count: int,
	arena_index: int,
	slot: int = 0
) -> Vector2:
	var safe_lane_count := maxi(lane_count, 1)
	var lane_index := posmod(lane, safe_lane_count)
	var lane_width := field.size.x / float(safe_lane_count)
	var center_x := field.position.x + lane_width * (float(lane_index) + 0.5)
	var room := posmod(arena_index, ARENA_NAMES.size())
	var room_bias := (float(room) - 1.0) * lane_width * 0.015
	var lane_bias := (float(lane_index) - float(safe_lane_count - 1) * 0.5) * lane_width * 0.018
	var slot_dir := -1.0 if posmod(lane_index + room, 2) == 0 else 1.0
	var slot_bias := 0.0
	if slot > 0:
		if safe_lane_count > 1 and lane_index in [0, safe_lane_count - 1]:
			var inward := 1.0 if lane_index == 0 else -1.0
			slot_bias = inward * float(slot) * lane_width * 0.32
		else:
			var row := ceili(float(slot) * 0.5)
			var side := slot_dir if slot % 2 == 1 else -slot_dir
			slot_bias = side * (0.32 + 0.26 * float(row - 1)) * lane_width
	var x := center_x + room_bias + lane_bias + slot_bias
	var margin := lane_width * 0.14
	x = clampf(x, field.position.x + margin, field.end.x - margin)
	var y := lerpf(field.position.y, field.end.y, depth(lane_index, arena_index, slot))
	return Vector2(x, y)
