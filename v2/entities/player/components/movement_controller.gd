@tool
## Apply movement
## NOTE: should be server authorative
class_name MovementController extends RigidBody3D

@export var collision_shape: Shape3D

@export_group("Shape Transform")
@export var shape_global_position: Vector3 = Vector3.ZERO
@export var shape_rotation_degrees: Vector3 = Vector3.ZERO
@export var shape_scale: Vector3 = Vector3.ONE

@onready var collision_shape_3d: CollisionShape3D = %CollisionShape3D


func _ready():
	collision_shape_3d.shape = collision_shape

	collision_shape_3d.global_position = shape_global_position
	collision_shape_3d.rotation_degrees = shape_rotation_degrees
	collision_shape_3d.scale = shape_scale


#region public api movement handlers

#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if collision_shape == null:
		issues.append("collision_shape must not be empty")

	return issues
