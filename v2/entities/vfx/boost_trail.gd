@tool
## Boost streak: a thin camera-facing ribbon laid down in world space from the taillight while
## `emitting`. Each point thins to nothing over `lifetime`, so the tail shrinks away after a burn.
## Must be top_level and sit after the rider's TickInterpolator/visuals in the tree, so the head
## samples this frame's smoothed taillight position.
class_name BoostTrail extends MeshInstance3D

@export var bike_skin: BikeSkin
@export var lifetime: float = 1.5
@export var width: float = 0.04
## Metres between recorded points; the live head always tracks the source.
@export var min_spacing: float = 0.25

## Set every frame by the owning entity from its synced is_boosting.
var emitting: bool = false:
	set(value):
		if value:
			set_process(true)
		emitting = value

var _imesh := ImmediateMesh.new()
var _points := PackedVector3Array()
var _births := PackedFloat32Array()
## First point of each burn, so back-to-back burns don't get bridged by a segment.
var _strip_starts: Array[bool] = []
var _now: float = 0.0
var _was_emitting: bool = false


func _ready() -> void:
	mesh = _imesh
	set_process(false)


func _process(delta: float) -> void:
	_now += delta
	while !_births.is_empty() and _now - _births[0] >= lifetime:
		_points.remove_at(0)
		_births.remove_at(0)
		_strip_starts.pop_front()

	var head := Vector3.ZERO
	if emitting:
		head = _source_position()
		var new_strip := !_was_emitting or _points.is_empty()
		if new_strip or _points[-1].distance_to(head) >= min_spacing:
			_points.append(head)
			_births.append(_now)
			_strip_starts.append(new_strip)
	_was_emitting = emitting

	_draw(head)
	if !emitting and _points.is_empty():
		set_process(false)


func _draw(head: Vector3) -> void:
	_imesh.clear_surfaces()
	var pts := _points.duplicate()
	var births := _births.duplicate()
	var starts := _strip_starts.duplicate()
	if emitting:
		pts.append(head)
		births.append(_now)
		starts.append(false)
	if pts.size() < 2:
		return

	var cam_pos := get_viewport().get_camera_3d().global_position
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size()):
		if starts[i]:
			continue
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var side := (b - a).cross(cam_pos - a).normalized()
		var sa := side * _half_width(births[i - 1])
		var sb := side * _half_width(births[i])
		_imesh.surface_add_vertex(a - sa)
		_imesh.surface_add_vertex(a + sa)
		_imesh.surface_add_vertex(b + sb)
		_imesh.surface_add_vertex(a - sa)
		_imesh.surface_add_vertex(b + sb)
		_imesh.surface_add_vertex(b - sb)
	_imesh.surface_end()


func _half_width(birth: float) -> float:
	return width * 0.5 * (1.0 - (_now - birth) / lifetime)


## The taillight mesh's origin isn't the lamp itself, so use its bounds' centre. Bikes without a
## taillight emit from the definition's exhaust tip, which is authored in BikeSkin's frame.
func _source_position() -> Vector3:
	var taillight := bike_skin.mesh_skin.taillight_mesh
	if taillight == null:
		return bike_skin.global_transform * bike_skin.skin_definition.exhaust_tip_position
	return taillight.global_transform * taillight.get_aabb().get_center()


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if bike_skin == null:
		issues.append("bike_skin must be set")
	return issues
