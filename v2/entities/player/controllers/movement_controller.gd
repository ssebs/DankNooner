@tool
## Apply gearing-aware movement to parent CharacterBody3D
class_name MovementController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var trick_controller: TrickController
@export var crash_controller: CrashController

# spawn protection
var default_spawn_timer: float = 1.0
var spawn_timer: float = default_spawn_timer


func _ready():
	if Engine.is_editor_hint():
		return


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool):
	if Engine.is_editor_hint():
		return

	if player_entity.rb_do_respawn:
		player_entity.do_respawn()
		player_entity.rb_do_respawn = false

	if player_entity.is_crashed:
		return

	if player_entity.rb_activate_boost:
		trick_controller.activate_boost()
		player_entity.rb_activate_boost = false

	# Process systems (ORDER MATTERS)
	gearing_controller.process_gearing(delta)
	trick_controller.process_tricks(delta)
	_physics_calculations(delta)
	crash_controller.check_crash(delta)

	# Apply movement
	player_entity.velocity *= NetworkTime.physics_factor
	player_entity.move_and_slide()
	player_entity.velocity /= NetworkTime.physics_factor

	_handle_player_collision(delta)


func _physics_calculations(delta: float):
	var bd = player_entity.bike_definition

	# Derive speed from synced velocity
	player_entity.speed = Vector2(player_entity.velocity.x, player_entity.velocity.z).length()

	# Gravity
	if not player_entity.is_on_floor():
		player_entity.velocity.y -= 9.8 * delta * 4.0
		return

	# Acceleration (uses gearing power output)
	var power = gearing_controller.get_power_output()
	var effective_max = trick_controller.get_effective_max_speed()

	if power > 0 and player_entity.speed < effective_max:
		player_entity.speed += bd.acceleration * power * delta
		player_entity.speed = minf(player_entity.speed, effective_max)

	# Braking
	var total_brake = input_controller.front_brake + input_controller.rear_brake
	if total_brake > 0:
		player_entity.speed = move_toward(
			player_entity.speed, 0, bd.brake_strength * total_brake * delta
		)
	elif input_controller.throttle == 0:
		# Engine braking
		player_entity.speed = move_toward(player_entity.speed, 0, bd.engine_brake_strength * delta)

	# Curve-based speed factor for steering and lean
	var speed_pct = clampf(player_entity.speed / bd.max_speed, 0.0, 1.0)
	var lean_factor = bd.lean_curve.sample(speed_pct)

	# Steering (only when moving)
	if player_entity.speed > 2:
		var turn_rate = _get_turn_rate()
		player_entity.rotate_y(-player_entity.lean_angle * turn_rate * delta)

	# Lean
	var target_lean = input_controller.steer * bd.max_lean_angle_rad * lean_factor
	if player_entity.is_boosting:
		target_lean *= 0.5  # Reduce steering during boost
	player_entity.lean_angle = lerpf(player_entity.lean_angle, target_lean, bd.lean_speed * delta)

	# Apply velocity following slope
	var forward = -player_entity.global_transform.basis.z
	if player_entity.is_on_floor():
		player_entity.velocity = (
			forward.slide(player_entity.get_floor_normal()).normalized() * player_entity.speed
		)
	else:
		player_entity.velocity = forward * player_entity.speed


func _get_turn_rate() -> float:
	var bd = player_entity.bike_definition
	var speed_pct = player_entity.speed / bd.max_speed
	var turn_radius = lerpf(bd.min_turn_radius, bd.max_turn_radius, speed_pct)
	return bd.turn_speed / turn_radius


func _handle_player_collision(delta: float):
	if spawn_timer <= 0:
		return

	spawn_timer -= delta

	var collision = player_entity.get_last_slide_collision()
	if collision == null:
		return

	var collider = collision.get_collider()
	if collider is PlayerEntity:
		var random_angle = randf() * TAU
		var offset = Vector3(cos(random_angle), 0, sin(random_angle))
		player_entity.global_position += offset


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if gearing_controller == null:
		issues.append("gearing_controller must not be empty")
	if trick_controller == null:
		issues.append("trick_controller must not be empty")
	if crash_controller == null:
		issues.append("crash_controller must not be empty")
	return issues
