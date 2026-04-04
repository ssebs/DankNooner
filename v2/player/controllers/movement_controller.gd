@tool
## Apply gearing-aware movement to parent CharacterBody3D
class_name MovementController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var crash_controller: CrashController
@export var rear_raycast: RayCast3D
@export var front_raycast: RayCast3D

const CLUTCH_KICK_WINDOW: float = 0.2
const FALL_GRAVITY: float = 9.8
const AIR_DRAG: float = 4.0  # speed loss per second while airborne
# Ramp / loop tuning
const SURFACE_BLEND_SPEED_MIN: float = 3.0  # up_direction alignment speed at rest
const SURFACE_BLEND_SPEED_MAX: float = 40.0  # alignment speed at full speed (must track loops)
const SURFACE_BLEND_SPEED_FALL: float = 0.25  # airborne alignment back to global UP
const ADHESION_ANGLE: float = 80.0  # degrees — adhesion speed check kicks in here
const RAMP_SLOWDOWN: float = 0.25  # multiplier on slope gravity
const MIN_LOOP_SPEED: float = 20.0  # speed needed at fully inverted (180°)
# Trick tuning
const TRICK_DISABLE_ANGLE: float = 30.0  # (degrees)
var speed: float = 0.0
var roll_angle: float = 0.0  # lean left/right
var pitch_angle: float = 0.0  # + = wheelie, - = stoppie

var air_forward: Vector3 = Vector3.FORWARD  # forward direction when leaving a surface

# spawn protection - todo move?
var _default_spawn_timer: float = 1.0
var _spawn_timer: float = _default_spawn_timer

# Wheelie physics
var _prev_clutch_held: bool = false
var _clutch_kick_window: float = 0.0
var _balance_point_decay_mult: float = 0.2
var _is_on_floor: bool = false  # cached once per tick to avoid redundant move_and_slide calls
var _floor_normal: Vector3 = Vector3.UP  # cached per tick — only valid when _is_on_floor
var _speed_pct: float = 0.0  # speed / max_speed, cached per tick


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

	_is_on_floor = is_on_floor_netfox()
	if _is_on_floor:
		_floor_normal = _get_blended_surface_normal()
	_speed_calc(delta)
	_speed_pct = clampf(speed / player_entity.bike_definition.max_speed, 0.0, 1.0)
	_update_surface_alignment(delta)
	_steer_calc(delta)
	_velocity_calc(delta)
	_pitch_angle_calc(delta)

	# Apply movement
	player_entity.velocity *= NetworkTime.physics_factor
	player_entity.move_and_slide()
	player_entity.velocity /= NetworkTime.physics_factor

	_handle_player_collision(delta)


## Blend normals from front + rear raycasts for smoother ramp transitions.
## Falls back to CharacterBody3D floor normal if neither raycast hits.
func _get_blended_surface_normal() -> Vector3:
	var front_hit = front_raycast.is_colliding()
	var rear_hit = rear_raycast.is_colliding()

	if front_hit and rear_hit:
		return (
			front_raycast
			. get_collision_normal()
			. lerp(rear_raycast.get_collision_normal(), 0.5)
			. normalized()
		)
	if front_hit:
		return front_raycast.get_collision_normal()
	if rear_hit:
		return rear_raycast.get_collision_normal()

	return player_entity.get_floor_normal()


## Align bike's up_direction to surface normal for ramp/loop riding
func _update_surface_alignment(delta: float):
	var pe = player_entity

	if _is_on_floor:
		var surface_angle = _floor_normal.angle_to(Vector3.UP)
		if surface_angle > deg_to_rad(5.0):
			DebugUtils.DebugMsg(
				(
					"Surface: angle=%.1f° normal=%s F=%s R=%s"
					% [
						rad_to_deg(surface_angle),
						_floor_normal.snapped(Vector3.ONE * 0.01),
						front_raycast.is_colliding(),
						rear_raycast.is_colliding()
					]
				),
				OS.has_feature("debug")
			)

		# Adhesion check — need enough speed to ride steep/inverted surfaces
		if surface_angle > deg_to_rad(ADHESION_ANGLE):
			var steepness = clampf(
				(surface_angle - deg_to_rad(ADHESION_ANGLE)) / deg_to_rad(180.0 - ADHESION_ANGLE),
				0.0,
				1.0
			)
			var required_speed = MIN_LOOP_SPEED * steepness
			if speed < required_speed:
				# Too slow — peel off the surface
				pe.up_direction = pe.up_direction.slerp(Vector3.UP, 2.0 * delta).normalized()
				DebugUtils.DebugMsg("peel off: speed=%.1f required=%.1f" % [speed, required_speed])
				return

		# Blend up_direction toward surface normal — faster at speed (must track loops)
		# Skip slerp when vectors are nearly identical (avoids non-normalized axis error)
		if pe.up_direction.dot(_floor_normal) < 0.9999:
			var blend_speed = lerpf(SURFACE_BLEND_SPEED_MIN, SURFACE_BLEND_SPEED_MAX, _speed_pct)
			var t = clampf(blend_speed * delta, 0.0, 1.0)
			pe.up_direction = pe.up_direction.slerp(_floor_normal, t).normalized()
	else:
		_detach_from_surface(delta)


## Blend up_direction back to global up (airborne or detaching).
## More inverted = slower correction — rider falls on their head off a loop.
func _detach_from_surface(delta: float):
	var inversion = player_entity.up_direction.angle_to(Vector3.UP) / PI  # 0=upright, 1=inverted
	# Upright: corrects quickly. Fully inverted: nearly frozen so they fall on their head.
	var correction_speed = lerpf(
		SURFACE_BLEND_SPEED_FALL, SURFACE_BLEND_SPEED_FALL * 0.05, inversion
	)
	player_entity.up_direction = (
		player_entity.up_direction.slerp(Vector3.UP, correction_speed * delta).normalized()
	)


## Calculate speed from input / power output
func _speed_calc(delta: float):
	var bd = player_entity.bike_definition

	# Airborne: re-derive speed from velocity along launch heading
	# On floor: keep previous speed — move_and_slide clips velocity on surface seams
	if not _is_on_floor:
		speed = maxf(player_entity.velocity.dot(air_forward), 0.0)

	# Acceleration (uses gearing power output)
	var power = gearing_controller.get_power_output()
	var gear_max_speed = gearing_controller.get_gear_max_speed()
	if power > 0 and speed < gear_max_speed:
		speed += bd.acceleration * power * delta
		speed = minf(speed, gear_max_speed)
	# Engine braking — applies when not on throttle, stronger at higher RPM
	elif power <= 0 and speed > 0.5:
		# DebugUtils.DebugMsg("engine brake")
		var rpm_factor = gearing_controller._get_rpm_ratio()
		speed = move_toward(speed, 0, bd.engine_brake_strength * rpm_factor * delta)

	# Braking
	var total_brake = input_controller.nfx_front_brake + input_controller.nfx_rear_brake
	if total_brake > 0:
		speed = move_toward(speed, 0, bd.brake_strength * total_brake * delta)

	# Slope gravity — uses blended surface normal + velocity direction
	if _is_on_floor and player_entity.velocity.length_squared() > 0.01:
		var gravity_on_surface = Vector3.DOWN - _floor_normal * Vector3.DOWN.dot(_floor_normal)
		var vel_dir = player_entity.velocity.normalized()
		speed += FALL_GRAVITY * gravity_on_surface.dot(vel_dir) * RAMP_SLOWDOWN * delta
		speed = maxf(speed, 0.0)

	speed = minf(speed, bd.max_speed)


## Calculate roll_angle & set player_entity.rotation
func _steer_calc(delta: float):
	var bd = player_entity.bike_definition

	# Curve-based speed factor for steering and lean
	var lean_factor = bd.lean_curve.sample(_speed_pct)

	# Steering — bell curve: low at standstill, peaks mid-low speed, tapers at top speed
	if speed > 0.5:
		var steer_factor = bd.steer_curve.sample(_speed_pct) if bd.steer_curve else 1.0
		var turn_rate = bd.turn_speed * steer_factor
		DebugUtils.DebugMsg(
			(
				"Steer: spd=%.1f spd%%=%.0f%% curve=%.2f rate=%.2f"
				% [speed, _speed_pct * 100, steer_factor, turn_rate]
			)
		)
		player_entity.rotate_y(-roll_angle * turn_rate * delta)

	# Lean
	var target_lean = input_controller.nfx_steer * bd.max_lean_angle_rad * lean_factor
	roll_angle = lerpf(roll_angle, target_lean, bd.lean_speed * delta)

	# Align bike basis so local Y points along up_direction (ramp riding)
	var target_up = player_entity.up_direction
	var current_forward = -player_entity.global_transform.basis.z
	var right = current_forward.cross(target_up)
	if right.length_squared() > 0.001:
		right = right.normalized()
		var adjusted_forward = target_up.cross(right).normalized()
		player_entity.global_transform.basis = Basis(right, target_up, -adjusted_forward)


## Calculate player_entity.velocity & set slope angle
func _velocity_calc(delta: float):
	# Apply velocity following slope
	var forward = -player_entity.global_transform.basis.z
	if _is_on_floor:
		if player_entity.velocity.length_squared() > 0.01:
			air_forward = player_entity.velocity.normalized()
		else:
			air_forward = forward
		player_entity.velocity = forward.slide(_floor_normal).normalized() * speed
	else:
		# Use the last on-surface forward so basis slerp doesn't deflect trajectory mid-air
		speed = move_toward(speed, 0, AIR_DRAG * delta)
		player_entity.velocity = air_forward * speed

	# Gravity — straight down when airborne (slope speed handled in _speed_calc)
	if !_is_on_floor:
		player_entity.velocity += Vector3.DOWN * FALL_GRAVITY


## Orchestrates pitch_angle: clutch detection → wheelie target → stoppie → apply
func _pitch_angle_calc(delta: float):
	_update_clutch_dump_detection()

	var bd = player_entity.bike_definition
	var in_wheelie = pitch_angle > deg_to_rad(15)
	var in_stoppie = pitch_angle < deg_to_rad(-5)
	var bp_low = deg_to_rad(bd.wheelie_balance_point_deg - bd.wheelie_balance_point_width_deg)
	var bp_high = deg_to_rad(bd.wheelie_balance_point_deg + bd.wheelie_balance_point_width_deg)
	var in_balance_point = pitch_angle >= bp_low and pitch_angle <= bp_high
	var above_balance_point = pitch_angle > bp_high

	# Disable tricks on steep surfaces — decay pitch back to neutral
	var surface_angle = player_entity.up_direction.angle_to(Vector3.UP)
	if surface_angle > deg_to_rad(TRICK_DISABLE_ANGLE):
		if pitch_angle != 0:
			pitch_angle = move_toward(pitch_angle, 0, bd.return_speed * delta)
		return

	# --- Wheelie ---
	var wheelie_target = 0.0
	if _can_initiate_wheelie(in_wheelie) and not in_stoppie:
		wheelie_target = _calc_normal_wheelie_target(bd)
		if in_balance_point or above_balance_point:
			wheelie_target = _calc_balance_point_target(
				bd, in_balance_point, bp_low, bp_high
			)

	# DebugUtils.DebugMsg(
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

	# Speed-dependent wheelie gravity — less speed = front wheel drops
	# Only applies when rider isn't actively pulling back or flooring throttle
	if in_wheelie and input_controller.nfx_lean >= 0 and input_controller.nfx_throttle < 0.5:
		var speed_ratio = clampf(speed / (bd.max_speed * 0.5), 0.0, 1.0)
		var wheelie_gravity = bd.return_speed * (1.0 - speed_ratio)
		pitch_angle = move_toward(pitch_angle, 0, wheelie_gravity / 2 * delta)

	# Rev limiter drop — hitting the top of a gear during a wheelie kills the power
	# Rider needs to shift up or back off throttle to maintain the wheelie
	if in_wheelie and gearing_controller._get_rpm_ratio() >= 0.95:
		var drop_speed = bd.return_speed * 3.0
		pitch_angle = move_toward(pitch_angle, 0, drop_speed * delta)
		speed = move_toward(speed, speed * 0.95, bd.max_speed * 0.1 * delta)

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
	var effective_rpm_threshold = lerpf(
		bd.wheelie_rpm_threshold, bd.wheelie_rpm_threshold * 0.5, _speed_pct
	)
	var rpm_for_power = gearing_controller._get_rpm_ratio() >= effective_rpm_threshold
	var power_pop = (
		input_controller.nfx_lean < -0.3 and input_controller.nfx_throttle > 0.7 and rpm_for_power
	)

	# Can't START while turning
	var can_start = abs(roll_angle) < deg_to_rad(10)
	return (clutch_pop or power_pop) and can_start


## Calculate wheelie target in the normal zone (below balance point).
## Lean-back is the primary driver; throttle alone only provides a small assist.
func _calc_normal_wheelie_target(bd: BikeSkinDefinition) -> float:
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	# Throttle torque lifts the front — too much gas loops you out
	var throttle_lift = max_wheelie_rad * input_controller.nfx_throttle * 0.4
	# Lean-back is the main driver for reaching and holding higher angles
	var lean_lift = 0.0
	if input_controller.nfx_lean < 0:
		lean_lift = max_wheelie_rad * abs(input_controller.nfx_lean) * 0.75
	return throttle_lift + lean_lift


## Three-zone balance point:
## - In range (bp_low..bp_high): stable sweet spot — drifts toward center, but lean can push past
## - Above range: unstable — drifts toward crash unless rider corrects
func _calc_balance_point_target(
	bd: BikeSkinDefinition,
	in_range: bool,
	bp_low: float,
	bp_high: float,
) -> float:
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	var balance_center = (bp_low + bp_high) / 2.0

	if in_range:
		# Sweet spot — bike wants to settle here, but lean and throttle push past it
		var target = balance_center
		target -= input_controller.nfx_lean * (max_wheelie_rad - bp_low)
		target += input_controller.nfx_throttle * (max_wheelie_rad - bp_low) * 0.5
		target += randf_range(deg_to_rad(-2.0), deg_to_rad(2.0))
		return target

	# Above balance point — unstable, drifts toward crash
	var drift_target = max_wheelie_rad + deg_to_rad(1)
	if input_controller.nfx_lean > 0:
		return balance_center
	if input_controller.nfx_lean < 0:
		return drift_target
	# No input — drifts toward crash on its own
	return drift_target


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
	_prev_clutch_held = false
	_clutch_kick_window = 0.0
	air_forward = Vector3.FORWARD
	player_entity.up_direction = Vector3.UP


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if gearing_controller == null:
		issues.append("gearing_controller must not be empty")
	if crash_controller == null:
		issues.append("crash_controller must not be empty")
	if rear_raycast == null:
		issues.append("rear_raycast must not be empty")
	if front_raycast == null:
		issues.append("front_raycast must not be empty")
	return issues
