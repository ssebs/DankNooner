class_name BikeTricks extends Node

signal skid_mark_requested(position: Vector3, rotation: Vector3)
signal tire_screech_start(volume: float)
signal tire_screech_stop
signal stoppie_stopped  # Emitted when bike comes to rest during a stoppie

# Rotation tuning
@export var max_wheelie_angle: float = deg_to_rad(80)
@export var max_stoppie_angle: float = deg_to_rad(50)
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0

# Fishtail/drift tuning
@export var max_fishtail_angle: float = deg_to_rad(90)
@export var fishtail_speed: float = 8.0
@export var fishtail_recovery_speed: float = 3.0

# Component references
@onready var bike_physics: BikePhysics = %BikePhysics
@onready var bike_steering: BikeSteering = %BikeSteering

# Skid marks
const SKID_SPAWN_INTERVAL: float = 0.025
var skid_spawn_timer: float = 0.0

# State
var pitch_angle: float = 0.0
var fishtail_angle: float = 0.0

# Input tracking for clutch dump detection
var last_throttle_input: float = 0.0
var last_clutch_input: float = 0.0


func handle_wheelie_stoppie(delta, rpm_ratio: float, clutch_value: float, is_turning: bool, front_wheel_locked: bool = false):
	var lean_input = Input.get_action_strength("lean_back") - Input.get_action_strength("lean_forward")
	var throttle = Input.get_action_strength("throttle_pct")
	var front_brake = Input.get_action_strength("brake_front_pct")
	var rear_brake = Input.get_action_strength("brake_rear")
	var total_brake = clamp(front_brake + rear_brake, 0.0, 1.0)

	# Detect clutch dump
	var clutch_dump = last_clutch_input > 0.7 and clutch_value < 0.3 and throttle > 0.5
	last_throttle_input = throttle
	last_clutch_input = clutch_value

	# Can't START a wheelie/stoppie while turning, but can continue one
	var is_in_wheelie = pitch_angle > deg_to_rad(5)
	var is_in_stoppie = pitch_angle < deg_to_rad(-5)
	var can_start_trick = not is_turning

	# Wheelie logic
	var wheelie_target = 0.0
	var at_high_rpm = rpm_ratio > 0.85
	var can_pop_wheelie = lean_input > 0.3 and throttle > 0.7 and (at_high_rpm or clutch_dump)

	if bike_physics.speed > 1 and (is_in_wheelie or (can_pop_wheelie and can_start_trick)):
		if throttle > 0.3:
			wheelie_target = max_wheelie_angle * throttle * (1.0 - total_brake)
			wheelie_target += max_wheelie_angle * lean_input * 0.15

	# Stoppie logic - only works with progressive braking (not grabbed)
	# If front wheel is locked (brake grabbed), no stoppie - just skid
	var stoppie_target = 0.0
	var wants_stoppie = lean_input < -0.1 and front_brake > 0.5 and not front_wheel_locked
	if bike_physics.speed > 1 and (is_in_stoppie or (wants_stoppie and can_start_trick)):
		# Can't maintain stoppie if wheel locks mid-trick
		if front_wheel_locked:
			# Wheel locked - abort stoppie, bike drops back down
			stoppie_target = 0.0
		else:
			stoppie_target = -max_stoppie_angle * front_brake * (1.0 - throttle * 0.5)
			stoppie_target += -max_stoppie_angle * (-lean_input) * 0.15

	# Apply pitch
	var was_in_stoppie = pitch_angle < deg_to_rad(-5)
	if wheelie_target > 0:
		pitch_angle = move_toward(pitch_angle, wheelie_target, rotation_speed * delta)
	elif stoppie_target < 0:
		pitch_angle = move_toward(pitch_angle, stoppie_target, rotation_speed * delta)
		if not was_in_stoppie:
			tire_screech_start.emit(0.5)
		# Check if bike stopped during stoppie - soft reset without position change
		if bike_physics.speed < 0.5 and is_in_stoppie:
			pitch_angle = 0.0
			tire_screech_stop.emit()
			stoppie_stopped.emit()
	else:
		pitch_angle = move_toward(pitch_angle, 0, return_speed * delta)
		if was_in_stoppie and pitch_angle >= deg_to_rad(-5):
			tire_screech_stop.emit()


func handle_skidding(delta, rear_wheel_position: Vector3, bike_rotation: Vector3, is_on_floor: bool):
	var rear_brake = Input.get_action_strength("brake_rear")
	var is_skidding = rear_brake > 0.5 and bike_physics.speed > 2 and is_on_floor

	if is_skidding:
		# Spawn skid marks
		skid_spawn_timer += delta
		if skid_spawn_timer >= SKID_SPAWN_INTERVAL:
			skid_spawn_timer = 0.0
			skid_mark_requested.emit(rear_wheel_position, bike_rotation)

		# Fishtail calculation
		var steer_influence = bike_steering.steering_angle / bike_steering.max_steering_angle
		var target_fishtail = -steer_influence * max_fishtail_angle * rear_brake

		var speed_factor = clamp(bike_physics.speed / 20.0, 0.5, 1.5)
		target_fishtail *= speed_factor

		if abs(fishtail_angle) > deg_to_rad(15):
			target_fishtail *= 1.1  # Amplify once sliding

		fishtail_angle = move_toward(fishtail_angle, target_fishtail, fishtail_speed * delta)

		tire_screech_start.emit(0.7)
	else:
		skid_spawn_timer = 0.0
		fishtail_angle = move_toward(fishtail_angle, 0, fishtail_recovery_speed * delta)


func get_fishtail_speed_loss(delta) -> float:
	"""Returns how much speed to lose due to fishtail sliding"""
	if abs(fishtail_angle) > 0.01:
		var slide_friction = abs(fishtail_angle) / max_fishtail_angle
		return slide_friction * 15.0 * delta
	return 0.0


func is_in_wheelie() -> bool:
	return pitch_angle > deg_to_rad(5)


func is_in_stoppie() -> bool:
	return pitch_angle < deg_to_rad(-5)


func force_pitch(target: float, rate: float, delta):
	"""Force pitch toward a target (used by crash system)"""
	pitch_angle = move_toward(pitch_angle, target, rate * delta)


func reset():
	pitch_angle = 0.0
	fishtail_angle = 0.0
	skid_spawn_timer = 0.0
	last_throttle_input = 0.0
	last_clutch_input = 0.0
