@tool
class_name TrafficRoad extends Node3D

## Child TrafficRoadPoints in tree order are the road. Never links to anything; intersections
## link to roads.

@export var lane_width := 4.0:
	set(v):
		lane_width = v
		TrafficNetwork.request_redraw(self)


func _ready():
	if Engine.is_editor_hint():
		child_order_changed.connect(TrafficNetwork.request_redraw.bind(self))


func get_points() -> Array[TrafficRoadPoint]:
	var points: Array[TrafficRoadPoint] = []
	points.assign(get_children().filter(func(c): return c is TrafficRoadPoint))
	return points


# Null for a road with no points yet, a valid mid-authoring state
func nearest_end(pos: Vector3) -> TrafficRoadPoint:
	var points := get_points()
	if points.is_empty():
		return null
	var first := points[0]
	var last := points[-1]
	if first.global_position.distance_squared_to(pos) <= last.global_position.distance_squared_to(pos):
		return first
	return last


func draw_editor():
	var path := PackedVector3Array()
	for point in get_points():
		path.append(point.global_position)
	DebugDraw3D.draw_line_path(path, Color.CYAN, TrafficNetwork.DRAW_SECONDS)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not get_parent() is TrafficNetwork:
		warnings.append("Must be a child of a TrafficNetwork.")
		return warnings
	var points := get_points()
	if points.size() < 2:
		warnings.append("Needs at least 2 TrafficRoadPoint children.")
		return warnings
	var counts := points.map(func(p): return p.resolved_lane_count())
	if counts[0] != counts[1] or counts[-1] != counts[-2]:
		warnings.append("Lane count can't change on the first or last segment.")
	for end in [points[0], points[-1]]:
		if not _is_end_claimed(end):
			warnings.append("End point %s isn't linked by any TrafficIntersection." % end.name)
	return warnings


func _is_end_claimed(end: TrafficRoadPoint) -> bool:
	for intersection in (get_parent() as TrafficNetwork).get_intersections():
		for slot in TrafficIntersection.Slot.values():
			if intersection.get_slot_road(slot) == self and intersection.slot_end(slot) == end:
				return true
	return false
