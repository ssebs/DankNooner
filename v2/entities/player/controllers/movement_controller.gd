@tool
## Apply gearing-aware movement to parent CharacterBody3D
class_name MovementController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var trick_controller: TrickController
@export var crash_controller: CrashController

const CLUTCH_KICK_WINDOW: float = 0.4
var speed: float = 0.0
var roll_angle: float = 0.0  # lean left/right
var pitch_angle: float = 0.0  # + = wheelie, - = stoppie
var yaw_angle: float = 0.0  # twist left/right

# spawn protection - todo move?
var _default_spawn_timer: float = 1.0
var _spawn_timer: float = _default_spawn_timer

# Wheelie physics
var _prev_clutch_held: bool = false
var _clutch_kick_window: float = 0.0
var _balance_point_decay_mult: float = 0.2


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
	if player_entity.is_crashed:
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


## Orchestrates pitch_angle: clutch detection → wheelie target → apply
func _pitch_angle_calc(delta: float):
	_update_clutch_dump_detection()

	var bd = player_entity.bike_definition
	var in_wheelie = pitch_angle > deg_to_rad(15)
	var in_balance_point = pitch_angle > deg_to_rad(bd.wheelie_balance_point_deg)

	var wheelie_target = _calc_wheelie_target(delta)

	print(
		(
			"pitch_angle: %.2f | wheelie_target: %.2f | balance_point: %.2f | max_wheelie: %.2f | in_bp: %s"
			% [
				rad_to_deg(pitch_angle),
				rad_to_deg(wheelie_target),
				bd.wheelie_balance_point_deg,
				bd.max_wheelie_angle_deg,
				in_balance_point
			]
		)
	)

	# Lean forward recovery — pull the front wheel down
	if input_controller.nfx_lean > 0 and in_wheelie:
		pitch_angle = move_toward(
			pitch_angle, 0, bd.return_speed * input_controller.nfx_lean * 2.0 * delta
		)

	# Apply wheelie pitch
	if wheelie_target > 0:
		var spd = (
			bd.rotation_speed * _balance_point_decay_mult if in_balance_point else bd.rotation_speed
		)
		# Clutch dump torque boost — massive at low speed, fades with speed
		if _clutch_kick_window > 0:
			var speed_falloff = 1.0 - clampf(speed / (bd.max_speed * 0.3), 0.0, 1.0)
			spd += bd.rotation_speed * 2.0 * speed_falloff
		pitch_angle = move_toward(pitch_angle, wheelie_target, spd * delta)
	elif pitch_angle > 0:
		var decay_speed = (
			bd.return_speed * _balance_point_decay_mult if in_balance_point else bd.return_speed
		)
		pitch_angle = move_toward(pitch_angle, 0, decay_speed * delta)

	# TODO: rear brake pull-down
	# TODO: easy mode clamp


## Detect clutch dump (held → released while on throttle) and manage kick window
func _update_clutch_dump_detection():
	var clutch_held = input_controller.clutch_held

	if _prev_clutch_held and not clutch_held and input_controller.nfx_throttle > 0.5:
		_clutch_kick_window = CLUTCH_KICK_WINDOW

	if _clutch_kick_window > 0:
		_clutch_kick_window -= NetworkTime.ticktime

	_prev_clutch_held = clutch_held


## Calculate wheelie target angle based on RPM, throttle, lean, and balance point
func _calc_wheelie_target(delta: float) -> float:
	var bd = player_entity.bike_definition
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	var balance_point_rad = deg_to_rad(bd.wheelie_balance_point_deg)
	var in_wheelie = pitch_angle > deg_to_rad(15)

	# Initiation checks
	var rpm_above_threshold = gearing_controller._get_rpm_ratio() >= bd.wheelie_rpm_threshold
	var clutch_kick_active = _clutch_kick_window > 0

	# Clutch dump pop — just needs throttle, no lean-back required
	var clutch_pop = clutch_kick_active and input_controller.nfx_throttle > 0.5

	# Power wheelie — lean back + throttle + RPM (threshold eases at higher speed)
	var speed_ratio = clampf(speed / bd.max_speed, 0.0, 1.0)
	var effective_rpm_threshold = lerpf(
		bd.wheelie_rpm_threshold, bd.wheelie_rpm_threshold * 0.5, speed_ratio
	)
	var rpm_for_power = gearing_controller._get_rpm_ratio() >= effective_rpm_threshold
	var power_pop = (
		input_controller.nfx_lean < -0.3 and input_controller.nfx_throttle > 0.7 and rpm_for_power
	)

	var can_pop = clutch_pop or power_pop
	# Can't START while turning, but can continue
	var can_start = abs(roll_angle) < deg_to_rad(10)
	var fast_enough = speed > 1

	if not fast_enough:
		return 0.0
	if not in_wheelie and not (can_pop and can_start):
		return 0.0

	# Normal zone — below balance point
	var wheelie_target = max_wheelie_rad * input_controller.nfx_throttle
	if input_controller.nfx_lean < 0:
		wheelie_target += max_wheelie_rad * abs(input_controller.nfx_lean) * 0.15

	# Balance point zone — above balance_point_deg
	var in_balance_point = pitch_angle > balance_point_rad
	if in_balance_point:
		var lean_influence = input_controller.nfx_lean * (max_wheelie_rad - balance_point_rad)
		var balance_target = pitch_angle + lean_influence * 0.75

		if input_controller.nfx_throttle >= 0.5:
			wheelie_target = maxf(wheelie_target, balance_target)
		else:
			# Unstable — drifts toward edges
			var midpoint = (balance_point_rad + max_wheelie_rad) / 2
			if balance_target < midpoint:
				wheelie_target = move_toward(balance_target, 0, delta)
			elif balance_target > midpoint:
				wheelie_target = move_toward(balance_target, max_wheelie_rad + deg_to_rad(1), delta)
			else:
				wheelie_target += randf_range(deg_to_rad(-25), deg_to_rad(25))

	return wheelie_target


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
	_prev_clutch_held = false
	_clutch_kick_window = 0.0


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
