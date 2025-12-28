class_name BikeSteering extends Node

# Steering tuning
@export var steering_speed: float = 5.5
@export var max_steering_angle: float = deg_to_rad(35)
@export var max_lean_angle: float = deg_to_rad(50)
@export var rotation_speed: float = 2.0

# Turn radius (affects actual turning, not just visual steering)
@export var min_turn_radius: float = 0.25  # Tight turns at low speed
@export var max_turn_radius: float = 3.0   # Wide turns at high speed
@export var turn_speed: float = 2.0

# Component references
@onready var bike_physics: BikePhysics = %BikePhysics

# State
var steering_angle: float = 0.0
var lean_angle: float = 0.0


func handle_steering(delta, idle_tip_angle: float):
	var steer_input = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")

	# Snappier steering at low speeds
	var speed_factor = 1.0 + (1.0 - clamp(bike_physics.speed / 10.0, 0.0, 1.0)) * 1.5
	var effective_steering_speed = steering_speed * speed_factor

	# Lean/tip induces steering (bike steers into the lean)
	var lean_induced_steer = -idle_tip_angle * 0.5

	var target_steer = max_steering_angle * steer_input + lean_induced_steer
	target_steer = clamp(target_steer, -max_steering_angle, max_steering_angle)

	if steer_input != 0 or abs(idle_tip_angle) > 0.01:
		steering_angle = move_toward(steering_angle, target_steer, effective_steering_speed * delta)
	else:
		steering_angle = move_toward(steering_angle, 0, effective_steering_speed * 2 * delta)


func update_lean(delta, steer_input: float, pitch_angle: float, idle_tip_angle: float):
	"""Update lean angle based on steering and speed"""
	# Auto-lean into turns when moving
	var turn_lean = 0.0
	if bike_physics.speed > 1:
		turn_lean = -steering_angle * 0.6

	# At low speed, leaning is dangerous
	var low_speed_threshold = 5.0
	var target_lean = -max_lean_angle * steer_input * 0.4 + turn_lean

	if bike_physics.speed < low_speed_threshold:
		var speed_authority = clamp(bike_physics.speed / low_speed_threshold, 0.1, 1.0)
		target_lean *= speed_authority

	lean_angle = move_toward(lean_angle, target_lean, rotation_speed * delta)


func get_turn_rate() -> float:
	"""Returns how fast the bike should rotate based on speed and steering"""
	var speed_pct = bike_physics.speed / bike_physics.max_speed
	var turn_radius = lerp(min_turn_radius, max_turn_radius, speed_pct)
	return turn_speed / turn_radius


func is_turning() -> bool:
	return abs(steering_angle) > 0.2


func get_steer_input() -> float:
	return Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")


func reset():
	steering_angle = 0.0
	lean_angle = 0.0
