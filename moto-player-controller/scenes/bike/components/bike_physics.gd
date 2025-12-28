class_name BikePhysics extends Node

signal brake_stopped

# Movement tuning
@export var max_speed: float = 60.0
@export var acceleration: float = 20.0
@export var brake_strength: float = 25.0
@export var friction: float = 5.0

# Idle tipping
@export var idle_tip_speed_threshold: float = 10.0
@export var idle_tip_rate: float = 0.8
@export var crash_lean_threshold: float = deg_to_rad(80)
@export var throttle_recovery_amount: float = 2.0

# State
var speed: float = 0.0
var idle_tip_angle: float = 0.0
var has_started_moving: bool = false

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func handle_acceleration(delta, throttle: float, front_brake: float, rear_brake: float,
						  power_output: float, gear_max_speed: float, clutch_engaged: float, is_stalled: bool,
						  front_wheel_locked: bool = false):
	# Braking
	if front_brake > 0 or rear_brake > 0:
		var front_effectiveness = 0.6 if front_wheel_locked else 1.0
		var rear_effectiveness = 0.6 if rear_brake > 0.5 else 1.0
		var total_braking = clamp(front_brake * front_effectiveness + rear_brake * rear_effectiveness, 0, 1)
		speed = move_toward(speed, 0, brake_strength * total_braking * delta)

	if is_stalled:
		speed = move_toward(speed, 0, friction * delta)
		return

	# Acceleration
	if power_output > 0:
		if speed < gear_max_speed:
			speed += acceleration * power_output * delta
			speed = min(speed, gear_max_speed)
		else:
			speed = move_toward(speed, gear_max_speed, friction * 2.0 * delta)

	# Friction when coasting
	if throttle == 0 and front_brake == 0 and rear_brake == 0:
		var drag = friction * (1.5 - clutch_engaged * 0.5)
		speed = move_toward(speed, 0, drag * delta)


func handle_idle_tipping(delta, throttle: float, _steer_input: float, lean_angle: float):
	if speed > 0.25:
		has_started_moving = true

	if !has_started_moving:
		idle_tip_angle = 0.0
		return

	# Stability from speed (gyroscopic effect)
	var stability = clamp(speed / idle_tip_speed_threshold, 0.0, 1.0)

	# Combined lean (steering lean + tip) determines fall direction
	var total_lean = lean_angle + idle_tip_angle

	# At low speed, gravity pulls bike over - accelerating fall
	if speed < idle_tip_speed_threshold:
		# Fall accelerates based on how far you're leaning (like a pendulum)
		var fall_acceleration = total_lean * idle_tip_rate * (1.0 - stability)
		idle_tip_angle += fall_acceleration * delta

	# # Clamp to crash threshold
	# idle_tip_angle = clamp(idle_tip_angle, -crash_lean_threshold, crash_lean_threshold)

	# Recovery from throttle (rider stabilizing) - only when not steering
	if throttle > 0 :#and abs(steer_input) < 0.1:
		idle_tip_angle = move_toward(idle_tip_angle, 0, throttle * throttle_recovery_amount * delta)

	# # Recovery from speed (gyroscopic) - only when not actively leaning
	# # Rider must be going straight for gyro to stabilize
	# if stability > 0 and abs(steer_input) < 0.1 and abs(lean_angle) < deg_to_rad(10):
	# 	idle_tip_angle = move_toward(idle_tip_angle, 0, stability * 2.0 * delta)


func apply_fishtail_friction(_delta, fishtail_speed_loss: float):
	speed = move_toward(speed, 0, fishtail_speed_loss)


func check_brake_stop(steering_angle: float, lean_angle: float):
	var front_brake = Input.get_action_strength("brake_front_pct")
	var rear_brake = Input.get_action_strength("brake_rear")
	var total_brake = front_brake + rear_brake

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
