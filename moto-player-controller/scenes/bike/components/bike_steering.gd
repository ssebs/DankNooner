class_name BikeSteering extends Node

# Steering tuning
@export var steering_speed: float = 5.5
@export var max_steering_angle: float = deg_to_rad(35)
@export var low_speed_lean_angle: float = deg_to_rad(70)   # Max lean at low speed
@export var high_speed_lean_angle: float = deg_to_rad(15)  # Max lean at max speed
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
	# Speed-based lean limit (inverse: more lean allowed at low speed, less at high speed)
	var speed_ratio = clamp(bike_physics.speed / bike_physics.max_speed, 0.0, 1.0)
	var effective_max_lean = lerpf(low_speed_lean_angle, high_speed_lean_angle, speed_ratio)

	# Auto-lean into turns when moving
	var turn_lean = 0.0
	if bike_physics.speed > 1:
		turn_lean = -steering_angle * 0.6

	# Calculate target lean from input and turn
	var target_lean = -effective_max_lean * steer_input * 0.4 + turn_lean

	# Clamp to speed-based limit
	target_lean = clamp(target_lean, -effective_max_lean, effective_max_lean)

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
