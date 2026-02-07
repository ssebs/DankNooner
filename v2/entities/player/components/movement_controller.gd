@tool
## Apply movement to parent RigidBody3D (?)
class_name MovementController extends Node

@export var player_entity: PlayerEntity

#region public api movement handlers

#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if player_entity == null:
		issues.append("player_entity must not be empty")

	return issues
