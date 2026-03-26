@tool
## Apply gearing-aware movement to parent CharacterBody3D
class_name MovementController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var trick_controller: TrickController
@export var crash_controller: CrashController

const CLUTCH_KICK_WINDOW: float = 0.4
const GRAVITY: float = 128.0
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

	# print("speed %.2f" % speed)


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
	if is_on_floor_netfox():
		player_entity.velocity = (
			forward.slide(player_entity.get_floor_normal()).normalized() * speed
		)
	else:
		player_entity.velocity = forward * speed

	# Gravity
	if !is_on_floor_netfox():
		player_entity.velocity.y -= delta * GRAVITY


## Orchestrates pitch_angle: clutch detection → wheelie target → stoppie → apply
func _pitch_angle_calc(delta: float):
	_update_clutch_dump_detection()

	var bd = player_entity.bike_definition
	var in_wheelie = pitch_angle > deg_to_rad(15)
	var in_stoppie = pitch_angle < deg_to_rad(-5)
	var in_balance_point = pitch_angle > deg_to_rad(bd.wheelie_balance_point_deg)

	# --- Wheelie ---
	var wheelie_target = 0.0
	if _can_initiate_wheelie(in_wheelie) and not in_stoppie:
		wheelie_target = _calc_normal_wheelie_target(bd)
		if in_balance_point:
			wheelie_target = _calc_balance_point_target(bd, wheelie_target, delta)

	# print(
	# 	(
	# 		"pitch_angle: %.2f | wheelie_target: %.2f | balance_point: %.2f | \
	# max_wheelie: %.2f | in_bp: %s"
	# 		% [
	# 			rad_to_deg(pitch_angle),
	# 			rad_to_deg(wheelie_target),
	# 			bd.wheelie_balance_point_deg,
	# 			bd.max_wheelie_angle_deg,
	# 			in_balance_point
	# 		]
	# 	)
	# )

	# Lean forward recovery — pull the front wheel down
	if input_controller.nfx_lean > 0 and in_wheelie:
		pitch_angle = move_toward(
			pitch_angle, 0, bd.return_speed * input_controller.nfx_lean * 2.0 * delta
		)

	_apply_wheelie_pitch(bd, wheelie_target, in_balance_point, delta)

	# --- Stoppie ---
	if not in_wheelie:
		_stoppie_calc(bd, in_stoppie, delta)

	# TODO: easy mode clamp


## Apply wheelie pitch toward target, or decay back to 0
func _apply_wheelie_pitch(
	bd: BikeSkinDefinition, wheelie_target: float, in_balance_point: bool, delta: float
):
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


## Stoppie physics: brake hard + lean forward to lift the rear wheel
func _stoppie_calc(bd: BikeSkinDefinition, in_stoppie: bool, delta: float):
	var total_brake = input_controller.nfx_front_brake + input_controller.nfx_rear_brake
	var max_stoppie_rad = deg_to_rad(bd.max_stoppie_angle_deg)

	# Dynamic brake threshold: need more brake to start, less to sustain at deeper angles
	var stoppie_ratio = clampf(abs(pitch_angle) / max_stoppie_rad, 0.0, 1.0)
	var required_brake = lerpf(0.5, 0.15, stoppie_ratio)

	var can_stoppie = (
		total_brake > required_brake
		and input_controller.nfx_lean > 0.3
		and speed > 3.0
		and abs(roll_angle) < deg_to_rad(10)
	)

	if can_stoppie or in_stoppie:
		# Target deepens with brake + lean — speed just needs a minimum
		var speed_factor = clampf(speed / (bd.max_speed * 0.25), 0.0, 1.0)
		var brake_pct = clampf(total_brake * 1.5, 0.0, 1.0)
		# Target can exceed max — crash controller will trigger if you go over
		var stoppie_target = -max_stoppie_rad * (0.5 + brake_pct * 0.7) * speed_factor

		# Lean back recovery — push the rear wheel down
		if input_controller.nfx_lean < 0 and in_stoppie:
			pitch_angle = move_toward(
				pitch_angle, 0, bd.return_speed * abs(input_controller.nfx_lean) * 2.0 * delta
			)

		if can_stoppie:
			pitch_angle = move_toward(pitch_angle, stoppie_target, bd.rotation_speed * 1.5 * delta)
		elif in_stoppie:
			# Brake dropped below threshold — decay back to 0
			pitch_angle = move_toward(pitch_angle, 0, bd.return_speed * delta)


## Detect clutch dump (held → released while on throttle) and manage kick window
func _update_clutch_dump_detection():
	var clutch_held = input_controller.nfx_clutch_held

	if _prev_clutch_held and not clutch_held and input_controller.nfx_throttle > 0.5:
		_clutch_kick_window = CLUTCH_KICK_WINDOW

	if _clutch_kick_window > 0:
		_clutch_kick_window -= NetworkTime.ticktime

	_prev_clutch_held = clutch_held


## Check if a wheelie can start or is already in progress
func _can_initiate_wheelie(in_wheelie: bool) -> bool:
	var bd = player_entity.bike_definition

	if speed <= 1:
		return false
	if in_wheelie:
		return true

	# Clutch dump pop — just needs throttle, no lean-back required
	var clutch_pop = _clutch_kick_window > 0 and input_controller.nfx_throttle > 0.5

	# Power wheelie — lean back + throttle + RPM (threshold eases at higher speed)
	var speed_ratio = clampf(speed / bd.max_speed, 0.0, 1.0)
	var effective_rpm_threshold = lerpf(
		bd.wheelie_rpm_threshold, bd.wheelie_rpm_threshold * 0.5, speed_ratio
	)
	var rpm_for_power = gearing_controller._get_rpm_ratio() >= effective_rpm_threshold
	var power_pop = (
		input_controller.nfx_lean < -0.3 and input_controller.nfx_throttle > 0.7 and rpm_for_power
	)

	# Can't START while turning
	var can_start = abs(roll_angle) < deg_to_rad(10)
	return (clutch_pop or power_pop) and can_start


## Calculate wheelie target in the normal zone (below balance point)
func _calc_normal_wheelie_target(bd: BikeSkinDefinition) -> float:
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	var wheelie_target = max_wheelie_rad * input_controller.nfx_throttle
	if input_controller.nfx_lean < 0:
		wheelie_target += max_wheelie_rad * abs(input_controller.nfx_lean) * 0.15
	return wheelie_target


## Override wheelie target when above balance point — unstable without throttle
func _calc_balance_point_target(
	bd: BikeSkinDefinition, normal_target: float, delta: float
) -> float:
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	var balance_point_rad = deg_to_rad(bd.wheelie_balance_point_deg)

	var lean_influence = input_controller.nfx_lean * (max_wheelie_rad - balance_point_rad)
	var balance_target = pitch_angle + lean_influence * 0.75

	if input_controller.nfx_throttle >= 0.5:
		return maxf(normal_target, balance_target)

	# Unstable — drifts toward edges
	var midpoint = (balance_point_rad + max_wheelie_rad) / 2
	if balance_target < midpoint:
		return move_toward(balance_target, 0, delta)

	if balance_target > midpoint:
		return move_toward(balance_target, max_wheelie_rad + deg_to_rad(1), delta)

	return normal_target + randf_range(deg_to_rad(-25), deg_to_rad(25))


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


## Netfox's version of is_on_floor()
func is_on_floor_netfox() -> bool:
	var old_velocity = player_entity.velocity
	player_entity.velocity = Vector3.ZERO
	player_entity.move_and_slide()
	player_entity.velocity = old_velocity

	return player_entity.is_on_floor()


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
