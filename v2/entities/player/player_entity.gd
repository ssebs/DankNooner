@tool
class_name PlayerEntity extends CharacterBody3D

@export var bike_definition: BikeDefinition

@export var camera_controller: CameraController
@export var movement_controller: MovementController

@export var mesh_component: MeshComponent

@export var mesh_node: Node3D
@export var collision_shape_3d: CollisionShape3D

var input_manager: InputManager


func _ready():
	mesh_component.mesh_definition = bike_definition.bike_mesh_definition
	_init_collision_shape()

	if Engine.is_editor_hint():
		return

	_init_input_handlers()


func _init_input_handlers():
	input_manager = get_tree().get_first_node_in_group(UtilsConstants.GROUPS["InputManager"])
	if input_manager == null:
		printerr("cant find input_manager in PlayerEntity")
		return

	# Note - throttle, brake, and steer are handled in movement_controller
	input_manager.lean_changed.connect(_on_lean_changed)
	input_manager.rear_brake_pressed.connect(_on_rear_brake_pressed)
	input_manager.trick_mod_pressed.connect(_on_trick_mod_pressed)
	input_manager.clutch_pressed.connect(_on_clutch_pressed)
	input_manager.gear_up_pressed.connect(_on_gear_up_pressed)
	input_manager.gear_down_pressed.connect(_on_gear_down_pressed)
	input_manager.cam_switch_pressed.connect(_on_cam_switch_pressed)


#region input handlers
func _on_lean_changed(_value: float):
	pass


func _on_rear_brake_pressed():
	pass


func _on_trick_mod_pressed():
	pass


func _on_clutch_pressed():
	pass


func _on_gear_up_pressed():
	pass


func _on_gear_down_pressed():
	pass


func _on_cam_switch_pressed():
	camera_controller.toggle_cam()


#endregion


func _init_collision_shape():
	collision_shape_3d.shape = bike_definition.collision_shape

	collision_shape_3d.position = bike_definition.collision_position_offset
	collision_shape_3d.rotation_degrees = bike_definition.collision_rotation_offset_degrees
	collision_shape_3d.scale = bike_definition.collision_scale_multiplier


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if camera_controller == null:
		issues.append("camera_controller must not be empty")
	if movement_controller == null:
		issues.append("movement_controller must not be empty")
	if bike_definition == null:
		issues.append("bike_definition must not be empty")
	if mesh_component == null:
		issues.append("mesh_component must not be empty")
	if mesh_node == null:
		issues.append("mesh_node must not be empty")
	if collision_shape_3d == null:
		issues.append("collision_shape_3d must not be empty")

	return issues
