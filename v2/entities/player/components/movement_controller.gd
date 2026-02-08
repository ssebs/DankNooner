@tool
## Apply movement to parent CharacterBody3D with manual inertia
class_name MovementController extends Node

@export var player_entity: PlayerEntity

@export var max_speed: float = 100
@export var acceleration: float = 2
@export var brake_decel: float = 2
@export var engine_brake_decel: float = 1
@export var turn_speed: float = 4
@export var turn_friction: float = 4

var current_speed: float = 0
var angular_velocity: float = 0

var input_manager: InputManager


func _ready():
	if Engine.is_editor_hint():
		return

	input_manager = get_tree().get_first_node_in_group(UtilsConstants.GROUPS["InputManager"])
	if input_manager == null:
		printerr("cant find input_manager in MovementController")


func _physics_process(delta: float):
	if Engine.is_editor_hint():
		return

	# Gravity
	if not player_entity.is_on_floor():
		player_entity.velocity.y -= 9.8 * delta

	# Throttle => accelerate
	if input_manager.throttle > 0:
		current_speed = lerp(
			current_speed, max_speed, acceleration * delta * input_manager.throttle
		)
	# Brake => decelerate fast
	elif input_manager.front_brake > 0:
		current_speed = lerp(current_speed, 0.0, brake_decel * delta * input_manager.front_brake)
	# No input => engine braking
	else:
		current_speed = lerp(current_speed, 0.0, engine_brake_decel * delta)

	# Steering with inertia
	angular_velocity = lerp(
		angular_velocity, input_manager.steer * turn_speed, turn_friction * delta
	)
	player_entity.rotate_y(-angular_velocity * delta)

	# Apply forward velocity
	var forward = -player_entity.global_transform.basis.z
	player_entity.velocity.x = forward.x * current_speed
	player_entity.velocity.z = forward.z * current_speed

	player_entity.move_and_slide()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if player_entity == null:
		issues.append("player_entity must not be empty")

	return issues
