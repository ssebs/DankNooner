@tool
class_name TrafficIntersection extends Node3D

## Links up to four TrafficRoads by slot, in this node's basis (north = -Z, east = +X). Each road
## connects at whichever end is nearest.

enum Control { NONE, STOP, LIGHT }
enum Slot { NORTH, EAST, SOUTH, WEST }

@export var north: TrafficRoad
@export var east: TrafficRoad
@export var south: TrafficRoad
@export var west: TrafficRoad
## Half-size of the box. Road lanes stop at its edge (the stop line); turn lanes live inside.
@export var radius := 8.0
@export var control := Control.NONE
## LIGHT only: north/south are green together, then east/west.
@export var green_duration := 10.0
@export var amber_duration := 3.0

const SLOT_DIRS: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
# A slotted road's near end must be within MAX_REACH radii, and within ~45° of the slot's direction
const MAX_REACH := 2.0
const MIN_ALIGN := 0.7


# Null when the slot is empty (n/a)
func get_slot_road(slot: Slot) -> TrafficRoad:
	return [north, east, south, west][slot]


func slot_dir(slot: Slot) -> Vector3:
	return (global_basis * SLOT_DIRS[slot]).slide(Vector3.UP).normalized()


# Null when the slot is empty or its road has no points
func slot_end(slot: Slot) -> TrafficRoadPoint:
	var road := get_slot_road(slot)
	return road.nearest_end(global_position) if road else null


func is_slot_in_reach(slot: Slot) -> bool:
	var end := slot_end(slot)
	if end == null:
		return false
	var offset := (end.global_position - global_position).slide(Vector3.UP)
	return offset.length() <= radius * MAX_REACH and offset.normalized().dot(slot_dir(slot)) >= MIN_ALIGN


func draw_editor():
	var size := Vector3(radius * 2.0, 0.5, radius * 2.0)
	DebugDraw3D.draw_box(global_position, global_basis.get_rotation_quaternion(), size, Color.YELLOW, true)
	DebugDraw3D.draw_text(global_position + Vector3.UP * 3.0, Control.keys()[control], 64, Color.YELLOW)
	for slot in Slot.values():
		var tip := global_position + slot_dir(slot) * radius
		if get_slot_road(slot) == null:
			DebugDraw3D.draw_line(global_position, global_position + slot_dir(slot) * radius * 0.5, Color.GRAY)
			continue
		var color := Color.GREEN if is_slot_in_reach(slot) else Color.RED
		DebugDraw3D.draw_line(global_position, tip, color)
		var end := slot_end(slot)
		if end:
			DebugDraw3D.draw_line(tip, end.global_position, color)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not get_parent() is TrafficNetwork:
		warnings.append("Must be a child of a TrafficNetwork.")
	if Slot.values().all(func(s): return get_slot_road(s) == null):
		warnings.append("No roads linked.")
	for slot in Slot.values():
		if get_slot_road(slot) and not is_slot_in_reach(slot):
			warnings.append("%s: the road's nearest end is too far or on the wrong side." % Slot.keys()[slot])
	return warnings
