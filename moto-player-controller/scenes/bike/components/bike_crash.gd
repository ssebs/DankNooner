class_name BikeCrash extends Node

signal crashed(pitch_direction: float, lean_direction: float)
signal respawned

# Crash thresholds
@export var crash_wheelie_threshold: float = deg_to_rad(75)
@export var crash_stoppie_threshold: float = deg_to_rad(55)
@export var crash_lean_threshold: float = deg_to_rad(80)
@export var respawn_delay: float = 2.0

# Component references
@onready var bike_physics: BikePhysics = %BikePhysics

# State
var is_crashed: bool = false
var crash_timer: float = 0.0
var crash_pitch_direction: float = 0.0
var crash_lean_direction: float = 0.0
var front_brake_hold_time: float = 0.0
var brake_danger_level: float = 0.0

# Brake grab detection
var last_front_brake: float = 0.0
var brake_grab_level: float = 0.0  # How aggressively brake was grabbed (0-1)
const BRAKE_GRAB_THRESHOLD: float = 4.0  # Rate per second that counts as "grabbing"
const BRAKE_GRAB_CRASH_THRESHOLD: float = 0.9  # Grab level that causes instant crash/skid


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

	# Turning while in a stoppie - lowside crash
	elif pitch_angle < deg_to_rad(-15) and abs(steering_angle) > deg_to_rad(15):
		crash_reason = "stoppie_turn"
		crash_pitch_direction = 0
		crash_lean_direction = sign(steering_angle)

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
	# Detect brake grab (how fast brake input is increasing)
	var brake_rate = (front_brake - last_front_brake) / delta if delta > 0 else 0.0
	last_front_brake = front_brake

	# Only care about increasing brake input at speed
	if brake_rate > BRAKE_GRAB_THRESHOLD and bike_physics.speed > 10:
		# Accumulate grab level based on how aggressive the grab is
		var grab_intensity = (brake_rate - BRAKE_GRAB_THRESHOLD) / BRAKE_GRAB_THRESHOLD
		brake_grab_level = clamp(brake_grab_level + grab_intensity * delta * 5.0, 0.0, 1.0)
	elif front_brake < 0.3:
		# Only decay grab level when brake is mostly released
		brake_grab_level = move_toward(brake_grab_level, 0.0, 3.0 * delta)
	# else: brake is held but not increasing - maintain current grab level

	var turn_factor = abs(steering_angle) / bike_physics.max_steering_angle
	var lean_factor = abs(lean_angle) / crash_lean_threshold
	var instability = max(turn_factor, lean_factor)

	# Instant crash if brake grabbed while turning
	if brake_grab_level > BRAKE_GRAB_CRASH_THRESHOLD and bike_physics.speed > 20:
		if instability > 0.4:
			# Lowside crash from grabbing brake in turn
			crash_pitch_direction = 0
			crash_lean_direction = -sign(steering_angle) if steering_angle != 0 else sign(lean_angle)
			trigger_crash()
			return true

	# Original hold-time based danger (for sustained hard braking)
	if front_brake > 0.7 and bike_physics.speed > 25:
		front_brake_hold_time += delta

		var speed_factor = clamp((bike_physics.speed - 25) / (bike_physics.max_speed - 25), 0.0, 1.0)
		var base_threshold = 0.8 * (1.0 - speed_factor * 0.3)
		var crash_time_threshold = base_threshold * (1.0 - instability * 0.5)

		# Brake grab makes danger build faster
		var grab_multiplier = 1.0 + brake_grab_level * 1.5
		brake_danger_level = clamp((front_brake_hold_time * grab_multiplier) / crash_time_threshold, 0.0, 1.0)

		if front_brake_hold_time > crash_time_threshold:
			if instability > 0.5:
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

	if front_brake > 0.8 and bike_physics.speed > 25 and brake_danger_level >= 1.0:
		var turn_factor = abs(steer_input)
		return turn_factor <= 0.2  # Only when going straight
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
	last_front_brake = 0.0
	brake_grab_level = 0.0
	respawned.emit()


func is_front_wheel_locked() -> bool:
	"""Returns true if front brake was grabbed hard enough to lock wheel (skid)"""
	return brake_grab_level > BRAKE_GRAB_CRASH_THRESHOLD


func check_airborne_crash(lean_angle: float, idle_tip_angle: float, pitch_angle: float) -> bool:
	"""Check if bike should crash when landing from a jump while leaning"""
	var total_lean = abs(lean_angle + idle_tip_angle)

	# Crash if leaning too far while airborne - will crash on landing
	if total_lean > deg_to_rad(45):
		crash_pitch_direction = 0
		crash_lean_direction = sign(lean_angle + idle_tip_angle)
		trigger_crash()
		return true

	# Also crash if pitched too far
	if pitch_angle > crash_wheelie_threshold * 0.8 or pitch_angle < -crash_stoppie_threshold * 0.8:
		crash_pitch_direction = sign(pitch_angle)
		crash_lean_direction = 0
		trigger_crash()
		return true

	return false


func trigger_collision_crash(collision_normal: Vector3):
	"""Trigger crash from hitting an obstacle"""
	# Determine crash direction from collision normal
	var local_normal = collision_normal

	# If hit from front, flip over handlebars
	if local_normal.z > 0.5:
		crash_pitch_direction = -1
		crash_lean_direction = 0
	# If hit from side, lowside in that direction
	elif abs(local_normal.x) > 0.3:
		crash_pitch_direction = 0
		crash_lean_direction = sign(local_normal.x)
	# Otherwise default to forward flip
	else:
		crash_pitch_direction = -1
		crash_lean_direction = 0

	trigger_crash()
