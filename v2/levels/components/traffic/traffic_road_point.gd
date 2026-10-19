@tool
class_name TrafficRoadPoint extends Node3D

## Total lanes across both directions (4 = 2 each way); must be even. 0 = same as the previous
## point. A change between two points is a merge/split there.
@export var lane_count := 0

const ROAD_LAYER_MASK: int = 64 # 1 << 6 (layer 7 "road")
const RAY_START_HEIGHT := 5.0
const RAY_LENGTH := 100.0


func resolved_lane_count() -> int:
	var points := (get_parent() as TrafficRoad).get_points()
	for i in range(points.find(self), -1, -1):
		if points[i].lane_count != 0:
			return points[i].lane_count
	return 0


# Empty when there's no road surface below this point
func road_hit() -> Dictionary:
	var from := global_position + Vector3.UP * RAY_START_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_LENGTH, ROAD_LAYER_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query)


func draw_editor():
	if road_hit().is_empty():
		DebugDraw3D.draw_sphere(global_position, 1.0, Color.RED)
	# Grey = inherited from a previous point
	var color := Color.WHITE if lane_count != 0 else Color.GRAY
	DebugDraw3D.draw_text(global_position + Vector3.UP * 2.0, str(resolved_lane_count()), 64, color)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not get_parent() is TrafficRoad:
		warnings.append("Must be a child of a TrafficRoad.")
		return warnings
	if lane_count % 2 != 0:
		warnings.append("lane_count must be even (it counts both directions).")
	if lane_count == 0 and (get_parent() as TrafficRoad).get_points()[0] == self:
		warnings.append("The first point must set lane_count.")
	return warnings
