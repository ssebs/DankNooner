class_name BikePhysics extends Node

signal brake_stopped  # Emitted when bike comes to a controlled stop via braking

# Movement tuning
@export var max_speed: float = 60.0
@export var acceleration: float = 15.0
@export var brake_strength: float = 25.0
@export var friction: float = 5.0

# Idle tipping
@export var idle_tip_speed_threshold: float = 8.0
@export var idle_tip_rate: float = 0.75
@export var crash_lean_threshold: float = deg_to_rad(80)
@export var throttle_recovery_multiplier: float = 8.0

# State
var speed: float = 0.0
var idle_tip_angle: float = 0.0
var has_started_moving: bool = false

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func handle_acceleration(delta, throttle: float, front_brake: float, rear_brake: float,
						  power_output: float, gear_max_speed: float, clutch_engaged: float, is_stalled: bool,
						  front_wheel_locked: bool = false):
	# Brake first
	var total_brake = clamp(front_brake + rear_brake, 0, 1)
	if total_brake > 0:
		# Front wheel lock reduces braking effectiveness (skidding is worse than rolling)
		var brake_effectiveness = 1.0
		if front_wheel_locked:
			brake_effectiveness = 0.6  # Locked wheel = 60% as effective
		speed = move_toward(speed, 0, brake_strength * total_brake * brake_effectiveness * delta)

	# Can't accelerate when stalled
	if is_stalled:
		speed = move_toward(speed, 0, friction * delta)
		return

	# Apply power
	if power_output > 0:
		var accel_force = acceleration * power_output
		if speed < gear_max_speed:
			speed += accel_force * delta
			speed = min(speed, gear_max_speed)
		elif speed > gear_max_speed:
			speed = move_toward(speed, gear_max_speed, friction * 2.0 * delta)

	# Natural friction when no throttle/brake
	if throttle == 0 and total_brake == 0:
		var engagement = 1.0 - clutch_engaged
		var drag = friction * (1.0 + engagement * 0.5)
		speed = move_toward(speed, 0, drag * delta)


func handle_idle_tipping(delta, throttle: float, steer_input: float, lean_angle: float):
	# Track if bike has ever started moving
	if speed > 1.0:
		has_started_moving = true

	# At spawn or standstill before moving, stay upright
	if !has_started_moving:
		idle_tip_angle = 0.0
		return

	# Gyroscopic stability: faster = more stable (0 at idle, 1 at max speed)
	var stability = clamp(speed / max_speed, 0.0, 1.0)
	var instability = 1.0 - stability

	# Throttle provides stabilizing force (simulates rider control/balance)
	var throttle_stability = throttle * throttle  # Quadratic for smoother response

	# Total lean angle (input lean + tip angle)
	var total_lean = lean_angle + idle_tip_angle

	# At very low speed with no throttle, bike wants to fall over
	if speed < idle_tip_speed_threshold and throttle < 0.1:
		# Initialize tip direction based on lean or random
		if idle_tip_angle == 0:
			if abs(total_lean) > 0.01:
				idle_tip_angle = sign(total_lean) * 0.01
			else:
				idle_tip_angle = 0.01 if randf() > 0.5 else -0.01

	# Steering affects balance: turning into the fall recovers, turning away accelerates fall
	# Falling left (negative) + steer left (negative) = same sign = recovery
	# Falling left (negative) + steer right (positive) = opposite sign = worse
	var steer_tip_interaction = steer_input * sign(idle_tip_angle) if idle_tip_angle != 0 else 0.0
	# steer_tip_interaction > 0 when steering into fall (recovery)
	# steer_tip_interaction < 0 when steering away from fall (worse)

	# Calculate tip target (gravity pulling toward ground)
	var tip_target = sign(idle_tip_angle) * crash_lean_threshold if idle_tip_angle != 0 else 0.0

	# Tip rate: base rate * instability, accelerates with angle (gravity effect)
	var angle_ratio = abs(idle_tip_angle) / crash_lean_threshold
	var gravity_acceleration = 1.0 + angle_ratio * 3.0  # Further angle = faster fall
	var base_tip_rate = idle_tip_rate * instability * gravity_acceleration

	# Steering effectiveness scales with speed (need momentum to countersteer)
	var steer_effectiveness = clamp(speed / idle_tip_speed_threshold, 0.0, 1.0)

	# Steering can reduce or increase tip rate
	var steer_modifier = 1.0 - steer_tip_interaction * steer_effectiveness
	steer_modifier = clamp(steer_modifier, 0.5, 1.5)
	var tip_rate = base_tip_rate * steer_modifier

	# Apply tipping
	idle_tip_angle = move_toward(idle_tip_angle, tip_target, tip_rate * delta)

	# Steering recovery: any steering input helps right the bike (needs speed to work)
	# Steering into fall is more effective, countersteering still helps but less
	var steer_recovery_multiplier = 2.0 if steer_tip_interaction > 0 else 1.0
	var steer_recovery = idle_tip_rate * steer_recovery_multiplier * abs(steer_input) * steer_effectiveness
	idle_tip_angle = move_toward(idle_tip_angle, 0, steer_recovery * delta)

	# Throttle-based recovery (rider accelerating to regain balance)
	var recovery_rate = idle_tip_rate * throttle_recovery_multiplier * throttle_stability * (1.0 + stability)
	idle_tip_angle = move_toward(idle_tip_angle, 0, recovery_rate * delta)

	# Speed-based recovery (gyroscopic effect straightens the bike)
	var gyro_recovery = idle_tip_rate * stability * 2.0
	idle_tip_angle = move_toward(idle_tip_angle, 0, gyro_recovery * delta)


func apply_fishtail_friction(delta, fishtail_speed_loss: float):
	speed = move_toward(speed * delta, 0, fishtail_speed_loss)


func check_brake_stop(steering_angle: float, lean_angle: float):
	"""Check if bike just came to a controlled stop via braking"""
	var front_brake = Input.get_action_strength("brake_front_pct")
	var rear_brake = Input.get_action_strength("brake_rear")
	var total_brake = front_brake + rear_brake

	# Conditions for controlled brake stop:
	# - Speed just dropped to near zero
	# - Brakes are applied
	# - No significant steering
	# - Lean within 15 degrees
	var is_upright = abs(lean_angle + idle_tip_angle) < deg_to_rad(15)
	var is_straight = abs(steering_angle) < deg_to_rad(10)

	if speed < 0.5 and total_brake > 0.3 and is_upright and is_straight and has_started_moving:
		speed = 0.0
		idle_tip_angle = 0.0
		has_started_moving = false
		brake_stopped.emit()


func apply_gravity(delta, velocity: Vector3, is_on_floor: bool) -> Vector3:
	if !is_on_floor:
		velocity.y -= gravity * delta
	return velocity


func reset():
	speed = 0.0
	idle_tip_angle = 0.0
	has_started_moving = false
