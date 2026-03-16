@tool
## Apply gearing-aware movement to parent CharacterBody3D
class_name MovementController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var trick_controller: TrickController
@export var crash_controller: CrashController

var speed: float = 0.0
var roll_angle: float = 0.0  # lean left/right
var pitch_angle: float = 0.0  # + = wheelie, - = stoppie
var yaw_angle: float = 0.0  # twist left/right

# spawn protection - todo move?
var _default_spawn_timer: float = 1.0
var _spawn_timer: float = _default_spawn_timer


func _ready():
	if Engine.is_editor_hint():
		return

	player_entity.respawned.connect(_on_respawn)


func _on_respawn():
	_spawn_timer = _default_spawn_timer


## TODO - split this into multiple funcs for each thing that it does
func on_movement_rollback_tick(delta: float):
	if Engine.is_editor_hint():
		return

	_speed_calc(delta)
	_steer_calc(delta)
	_velocity_calc(delta)
	_pitch_angle_calc(delta)

	# Apply movement
	player_entity.velocity *= NetworkTime.physics_factor
	player_entity.move_and_slide()
	player_entity.velocity /= NetworkTime.physics_factor

	_handle_player_collision(delta)


## Calculate speed from input / power output
func _speed_calc(delta: float):
	var bd = player_entity.bike_definition

	# Derive speed from synced velocity
	speed = Vector2(player_entity.velocity.x, player_entity.velocity.z).length()

	# Acceleration (uses gearing power output)
	var power = gearing_controller.get_power_output()
	var gear_max_speed = gearing_controller.get_gear_max_speed()
	if power > 0 and speed < gear_max_speed:
		speed += bd.acceleration * power * delta
		speed = minf(speed, gear_max_speed)
	# Engine braking — applies when not on throttle, stronger at higher RPM
	elif power <= 0 and speed > 0.5:
		# print("engine brake")
		var rpm_factor = gearing_controller._get_rpm_ratio()
		speed = move_toward(speed, 0, bd.engine_brake_strength * rpm_factor * delta)

	# Braking
	var total_brake = input_controller.nfx_front_brake + input_controller.nfx_rear_brake
	if total_brake > 0:
		speed = move_toward(speed, 0, bd.brake_strength * total_brake * delta)

	print("speed %.2f" % speed)


## Calculate roll_angle & set player_entity.rotation
func _steer_calc(delta: float):
	var bd = player_entity.bike_definition

	# Curve-based speed factor for steering and lean
	var speed_pct = clampf(speed / bd.max_speed, 0.0, 1.0)
	var lean_factor = bd.lean_curve.sample(speed_pct)

	# Steering (only when moving)
	if speed > 0.5:
		var turn_radius = lerpf(bd.min_turn_radius, bd.max_turn_radius, speed_pct)
		var turn_rate = bd.turn_speed / turn_radius
		player_entity.rotate_y(-roll_angle * turn_rate * delta)

	# Lean
	var target_lean = input_controller.nfx_steer * bd.max_lean_angle_rad * lean_factor
	roll_angle = lerpf(roll_angle, target_lean, bd.lean_speed * delta)


## Calculate player_entity.velocity & set slope angle
func _velocity_calc(delta: float):
	# Apply velocity following slope
	var forward = -player_entity.global_transform.basis.z
	if player_entity.is_on_floor():
		player_entity.velocity = (
			forward.slide(player_entity.get_floor_normal()).normalized() * speed
		)
	else:
		player_entity.velocity = forward * speed

	# Gravity
	if !player_entity.is_on_floor():
		player_entity.velocity.y -= 9.8 * delta * 4.0


func _pitch_angle_calc(delta: float):
	print("nfx_lean")
	print(input_controller.nfx_lean)
	pitch_angle -= input_controller.nfx_lean * delta


## Stops players from spawning in eachother during _spawn_timer
func _handle_player_collision(delta: float):
	if _spawn_timer <= 0:
		return

	_spawn_timer -= delta

	var collision = player_entity.get_last_slide_collision()
	if collision == null:
		return

	var collider = collision.get_collider()
	if collider is PlayerEntity:
		var random_angle = randf() * TAU
		var offset = Vector3(cos(random_angle), 0.5, sin(random_angle))
		player_entity.global_position += offset


## Called from player_entity.gd's do_respawn
func do_reset():
	speed = 0.0
	roll_angle = 0.0
	pitch_angle = 0.0
	yaw_angle = 0.0


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
