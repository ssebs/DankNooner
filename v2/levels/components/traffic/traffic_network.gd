@tool
class_name TrafficNetwork extends Node3D

## One per level. Parent of every TrafficRoad and TrafficIntersection; draws them in the editor.

@export var show_in_editor := true

# Warnings depend on other nodes' positions, so they're re-polled while editing
const WARNING_POLL_SECONDS := 0.5

var _warning_timer := 0.0
var _last_warnings := {}


func _ready():
	set_process(Engine.is_editor_hint())


func _process(delta: float):
	if show_in_editor:
		for road in get_roads():
			road.draw_editor()
		for intersection in get_intersections():
			intersection.draw_editor()

	_warning_timer -= delta
	if _warning_timer <= 0.0:
		_warning_timer = WARNING_POLL_SECONDS
		_poll_warnings()


func get_roads() -> Array[TrafficRoad]:
	var roads: Array[TrafficRoad] = []
	roads.assign(get_children().filter(func(c): return c is TrafficRoad))
	return roads


func get_intersections() -> Array[TrafficIntersection]:
	var intersections: Array[TrafficIntersection] = []
	intersections.assign(get_children().filter(func(c): return c is TrafficIntersection))
	return intersections


# Only pushes changed warnings, so the scene dock isn't rebuilt every poll
func _poll_warnings():
	var nodes: Array[Node] = []
	nodes.append_array(get_intersections())
	for road in get_roads():
		nodes.append(road)
		nodes.append_array(road.get_points())
	for node in nodes:
		var warnings := node._get_configuration_warnings()
		if warnings != _last_warnings.get(node, PackedStringArray()):
			_last_warnings[node] = warnings
			node.update_configuration_warnings()
