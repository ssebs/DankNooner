class_name BikePhysics extends Node

# Movement tuning
@export var max_speed: float = 60.0
@export var acceleration: float = 15.0
@export var brake_strength: float = 25.0
@export var friction: float = 5.0

# Idle tipping
@export var idle_tip_speed_threshold: float = 3.0
@export var idle_tip_rate: float = 0.5
@export var crash_lean_threshold: float = deg_to_rad(80)

# State
var speed: float = 0.0
var idle_tip_angle: float = 0.0
var has_started_moving: bool = false

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func handle_acceleration(delta, throttle: float, front_brake: float, rear_brake: float,
						  power_output: float, gear_max_speed: float, clutch_engaged: float, is_stalled: bool):
	# Brake first
	var total_brake = clamp(front_brake + rear_brake, 0, 1)
	if total_brake > 0:
		speed = move_toward(speed, 0, brake_strength * total_brake * delta)

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


func handle_idle_tipping(delta, throttle: float, lean_angle: float, max_lean_angle: float):
	var low_speed_threshold = 5.0

	# Track if bike has ever started moving
	if speed > 3.0:
		has_started_moving = true

	# At spawn or standstill before moving, stay upright
	if not has_started_moving:
		idle_tip_angle = 0.0
		return

	if speed < low_speed_threshold:
		var lean_tip_contribution = 0.0
		if throttle < 0.3:
			lean_tip_contribution = lean_angle * 0.5

		if speed < idle_tip_speed_threshold and throttle == 0:
			if idle_tip_angle == 0 and abs(lean_angle) < deg_to_rad(5):
				idle_tip_angle = 0.01 if randf() > 0.5 else -0.01
			elif abs(lean_angle) >= deg_to_rad(5):
				idle_tip_angle = move_toward(idle_tip_angle, lean_angle, idle_tip_rate * 2.0 * delta)

		var tip_target = sign(idle_tip_angle + lean_tip_contribution) * crash_lean_threshold
		var tip_rate = idle_tip_rate * (1.0 + abs(lean_angle) / max_lean_angle)
		idle_tip_angle = move_toward(idle_tip_angle, tip_target, tip_rate * delta)

		# Throttle fights the tip
		if throttle > 0.3:
			var recovery_rate = idle_tip_rate * 3.0 * throttle
			idle_tip_angle = move_toward(idle_tip_angle, 0, recovery_rate * delta)
	else:
		idle_tip_angle = move_toward(idle_tip_angle, 0, idle_tip_rate * 3.0 * delta)


func apply_fishtail_friction(delta, fishtail_speed_loss: float):
	speed = move_toward(speed, 0, fishtail_speed_loss)


func apply_gravity(delta, velocity: Vector3, is_on_floor: bool) -> Vector3:
	if not is_on_floor:
		velocity.y -= gravity * delta
	return velocity


func reset():
	speed = 0.0
	idle_tip_angle = 0.0
	has_started_moving = false
