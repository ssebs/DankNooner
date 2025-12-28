class_name BikeCrash extends Node

signal crashed(pitch_direction: float, lean_direction: float)
signal respawned

# Crash thresholds
@export var crash_wheelie_threshold: float = deg_to_rad(75)
@export var crash_stoppie_threshold: float = deg_to_rad(45)
@export var crash_lean_threshold: float = deg_to_rad(80)
@export var respawn_delay: float = 2.0

# Component references
@onready var bike_physics: BikePhysics = %BikePhysics
@onready var bike_steering: BikeSteering = %BikeSteering

# State
var is_crashed: bool = false
var crash_timer: float = 0.0
var crash_pitch_direction: float = 0.0
var crash_lean_direction: float = 0.0
var front_brake_hold_time: float = 0.0
var brake_danger_level: float = 0.0


func check_crash_conditions(delta, pitch_angle: float, lean_angle: float, idle_tip_angle: float,
							steering_angle: float, front_brake: float) -> String:
	"""Returns crash reason or empty string if no crash"""
	var crash_reason = ""

	# Wheelie too far
	if pitch_angle > crash_wheelie_threshold:
		crash_reason = "wheelie"
		crash_pitch_direction = 1
		crash_lean_direction = 0

	# Stoppie too far
	elif pitch_angle < -crash_stoppie_threshold:
		crash_reason = "stoppie"
		crash_pitch_direction = -1
		crash_lean_direction = 0

	# Front brake danger
	_update_brake_danger(delta, front_brake, steering_angle, lean_angle)

	# Idle tipping over
	if crash_reason == "" and abs(idle_tip_angle) >= crash_lean_threshold:
		crash_reason = "idle_tip"
		crash_pitch_direction = 0
		crash_lean_direction = sign(idle_tip_angle)

	# Total lean too far
	if crash_reason == "" and abs(lean_angle + idle_tip_angle) >= crash_lean_threshold:
		crash_reason = "lean"
		crash_pitch_direction = 0
		crash_lean_direction = sign(lean_angle + idle_tip_angle)

	if crash_reason != "":
		trigger_crash()

	return crash_reason


func _update_brake_danger(delta, front_brake: float, steering_angle: float, lean_angle: float) -> bool:
	"""Returns true if brake crash should occur"""
	if front_brake > 0.7 and bike_physics.speed > 20:
		front_brake_hold_time += delta

		var turn_factor = abs(steering_angle) / bike_steering.max_steering_angle
		var lean_factor = abs(lean_angle) / crash_lean_threshold
		var instability = max(turn_factor, lean_factor)

		var speed_factor = clamp((bike_physics.speed - 20) / (bike_physics.max_speed - 20), 0.0, 1.0)
		var base_threshold = 0.5 * (1.0 - speed_factor * 0.3)
		var crash_time_threshold = base_threshold * (1.0 - instability * 0.7)

		brake_danger_level = clamp(front_brake_hold_time / crash_time_threshold, 0.0, 1.0)

		if front_brake_hold_time > crash_time_threshold:
			if instability > 0.3:
				# Lowside crash
				crash_pitch_direction = 0
				crash_lean_direction = -sign(steering_angle) if steering_angle != 0 else sign(lean_angle)
				trigger_crash()
				return true
			# else: will force stoppie in parent
	else:
		front_brake_hold_time = 0.0
		brake_danger_level = move_toward(brake_danger_level, 0.0, 5.0 * delta)

	return false


func should_force_stoppie() -> bool:
	"""Returns true if brake danger should force into stoppie"""
	var front_brake = Input.get_action_strength("brake_front_pct")
	var steer_input = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")

	if front_brake > 0.7 and bike_physics.speed > 20 and brake_danger_level >= 1.0:
		var turn_factor = abs(steer_input)
		return turn_factor <= 0.3  # Only when going straight
	return false


func trigger_crash():
	is_crashed = true
	crash_timer = 0.0
	crashed.emit(crash_pitch_direction, crash_lean_direction)


func handle_crash_state(delta) -> bool:
	"""Returns true when respawn should occur"""
	crash_timer += delta

	# Lowside respawn condition: when bike stops
	if crash_lean_direction != 0 and crash_pitch_direction == 0:
		if bike_physics.speed < 0.1:
			return true
	else:
		# Wheelie/stoppie crashes: use timer
		if crash_timer >= respawn_delay:
			return true

	return false


func is_lowside_crash() -> bool:
	return crash_lean_direction != 0 and crash_pitch_direction == 0


func reset():
	is_crashed = false
	crash_timer = 0.0
	crash_pitch_direction = 0.0
	crash_lean_direction = 0.0
	front_brake_hold_time = 0.0
	brake_danger_level = 0.0
	respawned.emit()
