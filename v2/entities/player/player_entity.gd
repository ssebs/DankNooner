@tool
class_name PlayerEntity extends RigidBody3D

@export var bike_definition: BikeDefinition

@export var camera_controller: CameraController
@export var movement_controller: MovementController

@export var mesh_component: MeshComponent

@export var mesh_node: Node3D
@export var collision_shape_3d: CollisionShape3D


func _ready():
	mesh_component.mesh_definition = bike_definition.bike_mesh_definition
	_init_collision_shape()


func _get_player_inputs_for_movement():
	pass


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
