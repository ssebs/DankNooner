@tool
## Apply movement to parent RigidBody3D (?)
class_name MovementController extends Node

@export var player_entity: PlayerEntity

@export var max_speed: float = 100
@export var max_steer_angle_deg: float = 30

#region public api movement handlers


## apply impluse (every frame) by throttle amount.
## caps out at max_speed
func apply_throttle(throttle: float):
	pass


## add force backward (every frame) by brake amount
## caps out at 0
func apply_brake(brake: float):
	pass


## add torque (ever frame) depending on steer angle
## caps out at max_steer_angle_deg
func steer(steer_angle: float):
	pass


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if player_entity == null:
		issues.append("player_entity must not be empty")

	return issues
