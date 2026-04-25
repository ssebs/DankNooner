@tool
class_name BikeSkin extends Node3D

@export var skin_definition: BikeSkinDefinition:
	set(value):
		skin_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_definition()

@export_tool_button("Save skin to u:disk") var save_skin_btn = _save_skin_to_disk
@export var skin_name_for_loading_test = "sport_default"
@export_tool_button("Load skin from u:disk") var load_skin_btn = _load_skin_to_disk

const LENGTH: float = 2.0
const WHEEL_SPIN_MULTIPLIER: float = 3.0
const STEERING_VISUAL_MULTIPLIER: float = 1.0
const STEERING_LERP_SPEED: float = 10.0

@onready var mesh_node: Node3D = %MeshNode

var mesh_skin: SkinColor
var steering_handlebar_marker: Marker3D


func _ready():
	_apply_definition()


func has_steering() -> bool:
	return mesh_skin != null and mesh_skin.steering_rotation_node != null


func get_steering_pivot_local() -> Vector3:
	var mesh_xform = mesh_node.transform * mesh_skin.transform
	return mesh_xform * mesh_skin.steering_rotation_node.position


func get_steering_rotation() -> Vector3:
	return mesh_skin.steering_rotation_node.rotation


func rotate_steering(roll_angle: float, delta: float):
	if not has_steering():
		return
	var target = -mesh_skin.steering_rot_axis * roll_angle * STEERING_VISUAL_MULTIPLIER
	mesh_skin.steering_rotation_node.rotation = mesh_skin.steering_rotation_node.rotation.lerp(
		target, STEERING_LERP_SPEED * delta
	)


func rotate_wheels(speed: float, delta: float, is_in_wheelie: bool = false):
	if mesh_skin == null:
		return
	var spin = -mesh_skin.wheel_rot_axis * speed * WHEEL_SPIN_MULTIPLIER * delta
	if mesh_skin.front_wheel_node:
		if is_in_wheelie:
			mesh_skin.front_wheel_node.rotation = mesh_skin.front_wheel_node.rotation.lerp(
				Vector3.ZERO, WHEEL_SPIN_MULTIPLIER * delta
			)
		else:
			mesh_skin.front_wheel_node.rotation += spin
	if mesh_skin.rear_wheel_node:
		mesh_skin.rear_wheel_node.rotation += spin


#region resource/definition
func _apply_definition():
	_spawn_mesh()
	_set_mesh_colors()
	_create_steering_handlebar_proxy()
	if Engine.is_editor_hint():
		mesh_skin.owner = self


func _save_skin_to_disk():
	skin_definition.save_to_disk()


func _load_skin_to_disk():
	skin_definition.skin_name = skin_name_for_loading_test
	skin_definition.load_from_disk()


#endregion


## Zero-offset Marker3D child of the mesh's steering rotation node. AnimationController's
## hand sync uses `steering_handlebar_marker.get_parent()` (i.e. the steering rotation node)
## as the parent space for saved hand_position/rotation values, so the marker itself only
## exists to expose that parent — its own transform is unused.
func _create_steering_handlebar_proxy():
	if not has_steering():
		steering_handlebar_marker = null
		return
	var proxy = Marker3D.new()
	proxy.name = "SteeringHandleBarProxy"
	mesh_skin.steering_rotation_node.add_child(proxy)
	steering_handlebar_marker = proxy


#region mesh init
func _set_mesh_colors():
	var colors: Array[Color] = skin_definition.colors
	for i in range(colors.size()):
		if colors[i] != Color.TRANSPARENT:
			mesh_skin.update_slot_color(i, colors[i])


func _spawn_mesh():
	for child in mesh_node.get_children():
		child.queue_free()
	mesh_skin = skin_definition.mesh_res.instantiate()
	mesh_node.add_child(mesh_skin)

	mesh_skin.scale *= skin_definition.mesh_scale_multiplier
	mesh_skin.position += skin_definition.mesh_position_offset
	mesh_skin.rotation_degrees += skin_definition.mesh_rotation_offset_degrees


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if skin_definition == null:
		issues.append("skin_definition must be set")
	return issues
