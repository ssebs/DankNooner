@tool
class_name PlayerEntity extends RigidBody3D

@export var camera_controller: CameraController
@export var movement_controller: MovementController

@export var bike_definition: BikeDefinition

@export var mesh_node: Node3D
@export var collision_shape_3d: CollisionShape3D


func _ready():
	_init_mesh()
	_init_collision_shape()


func _init_mesh():
	for child in mesh_node.get_children():
		child.queue_free()

	var mesh = bike_definition.mesh_scene.instantiate()
	mesh_node.add_child(mesh)
	mesh.position += bike_definition.mesh_position_offset
	mesh.rotation_degrees += bike_definition.mesh_rotation_offset_degrees
	mesh.scale *= bike_definition.mesh_scale_multiplier


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
	if mesh_node == null:
		issues.append("mesh_node must not be empty")
	if collision_shape_3d == null:
		issues.append("collision_shape_3d must not be empty")

	return issues
