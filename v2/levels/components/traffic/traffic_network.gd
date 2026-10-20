@tool
class_name TrafficNetwork extends Node3D

## One per level. Parent of every TrafficRoad and TrafficIntersection. Bake saves them as
## TrafficNetworkData next to the level scene; the editor previews the same build, redrawing only
## when one of them changes.

@export_tool_button("Bake") var bake_btn = bake
@export var show_in_editor := true:
	set(v):
		show_in_editor = v
		request_redraw(self)
@export var baked: TrafficNetworkData

# Drawings live until the next redraw clears them
const DRAW_SECONDS := 1.0e9
# Indexed by TrafficJunctionData.Light
const LIGHT_COLORS: Array[Color] = [Color.GREEN, Color.YELLOW, Color.RED]

## Runtime: LevelManager's dbg_traffic console command draws each light at its stop lines.
var show_lights := false:
	set(v):
		show_lights = v
		set_process(v)

var _redraw_queued := false
var _last_warnings := {}


func _enter_tree():
	if Engine.is_editor_hint():
		queue_redraw()


func _ready():
	# Only show_lights processes, never the editor
	set_process(false)
	if Engine.is_editor_hint():
		child_order_changed.connect(queue_redraw)


func _process(_delta: float):
	# Seen through the road and props. Held only to keep the scope alive
	@warning_ignore("unused_variable")
	var cfg := DebugDraw3D.new_scoped_config().set_no_depth_test(true)
	for i in baked.lanes.size():
		var lane := baked.lanes[i]
		if lane.junction >= 0 and baked.control(i) == TrafficIntersection.ControlType.LIGHT:
			DebugDraw3D.draw_sphere(lane.points[0] + Vector3.UP * 2.0, 0.5, LIGHT_COLORS[baked.light(i, NetworkTime.time)])


func _exit_tree():
	if Engine.is_editor_hint():
		DebugDraw3D.clear_all()


func _get_configuration_warnings() -> PackedStringArray:
	if baked == null:
		return ["Not baked yet. Press Bake."]
	if baked.source_hash != TrafficNetworkBaker.source_hash(self):
		return ["Bake is out of date. Press Bake."]
	return []


# Called by traffic nodes on edit; finds the owning network
static func request_redraw(node: Node):
	if not Engine.is_editor_hint() or not node.is_inside_tree():
		return
	var network := node
	while network and not network is TrafficNetwork:
		network = network.get_parent()
	# Null while a node sits outside a network; its config warning covers that
	if network:
		network.queue_redraw()


# Deferred so a burst of edits in one frame redraws once
func queue_redraw():
	if _redraw_queued:
		return
	_redraw_queued = true
	_redraw.call_deferred()


func get_roads() -> Array[TrafficRoad]:
	var roads: Array[TrafficRoad] = []
	roads.assign(get_children().filter(func(c): return c is TrafficRoad))
	return roads


func get_intersections() -> Array[TrafficIntersection]:
	var intersections: Array[TrafficIntersection] = []
	intersections.assign(get_children().filter(func(c): return c is TrafficIntersection))
	return intersections


func bake():
	var problems := PackedStringArray()
	for node in _authoring_nodes():
		for warning in node._get_configuration_warnings():
			problems.append("%s: %s" % [node.name, warning])
	if not problems.is_empty():
		push_error("TrafficNetwork: fix these before baking:\n" + "\n".join(problems))
		return

	var baker := TrafficNetworkBaker.new(self)
	var data := baker.build(true)
	for point in baker.missed_points:
		push_warning("TrafficNetwork: no road under %s/%s, baked at its own height" % [point.get_parent().name, point.name])
	for lane in data.lanes:
		if lane.points.size() < 2:
			problems.append("A lane is entirely inside an intersection box; move the road end out of it.")
		elif lane.successors.is_empty():
			problems.append("Lane starting at %s has no turn out of the next intersection." % lane.points[0])
	if not problems.is_empty():
		push_error("TrafficNetwork: bake failed:\n" + "\n".join(problems))
		return

	var path := owner.scene_file_path.get_basename() + "_traffic.tres"
	var err := ResourceSaver.save(data, path)
	if err != OK:
		push_error("TrafficNetwork: failed to save %s, error: %d" % [path, err])
		return
	data.take_over_path(path)
	baked = data
	# Looked up by name: the EditorInterface identifier doesn't exist in exported builds
	Engine.get_singleton("EditorInterface").mark_scene_as_unsaved()
	DebugUtils.DebugMsg("TrafficNetwork: baked %d lanes to %s" % [data.lanes.size(), path])
	queue_redraw()


func _authoring_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	nodes.append_array(get_intersections())
	for road in get_roads():
		nodes.append(road)
		nodes.append_array(road.get_points())
	return nodes


func _redraw():
	_redraw_queued = false
	# Scene tab switched away before the deferred call ran
	if not is_inside_tree():
		return
	DebugDraw3D.clear_all()
	if show_in_editor:
		# Points usually sit on/under the road mesh, so skip the depth test. Held only to keep the scope alive
		@warning_ignore("unused_variable")
		var cfg := DebugDraw3D.new_scoped_config().set_no_depth_test(true).set_thickness(0.3)
		for road in get_roads():
			road.draw_editor()
		for intersection in get_intersections():
			intersection.draw_editor()
		_draw_preview()
	_update_warnings()


func _draw_preview():
	var baker := TrafficNetworkBaker.new(self)
	for lane in baker.build(false).lanes:
		# Clipped away; Bake reports it
		if lane.points.size() < 2:
			continue
		var color := Color.ORANGE if lane.junction >= 0 else Color.LIME_GREEN
		DebugDraw3D.draw_line_path(lane.points, color, DRAW_SECONDS)
		var mid := int(lane.points.size() / 2.0)
		DebugDraw3D.draw_arrow(lane.points[mid - 1], lane.points[mid], color, 1.0, true, DRAW_SECONDS)
	for point in baker.missed_points:
		DebugDraw3D.draw_sphere(point.global_position, 1.0, Color.RED, DRAW_SECONDS)


# Only pushes changed warnings, so the scene dock isn't rebuilt on every redraw
func _update_warnings():
	var nodes := _authoring_nodes()
	nodes.append(self)
	for node in nodes:
		var warnings: PackedStringArray = node._get_configuration_warnings()
		if warnings != _last_warnings.get(node, PackedStringArray()):
			_last_warnings[node] = warnings
			node.update_configuration_warnings()
