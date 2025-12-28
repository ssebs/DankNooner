class_name BikeSteering extends Node

# Steering tuning
@export var steering_speed: float = 4.0
@export var max_steering_angle: float = deg_to_rad(35)
@export var max_lean_angle: float = deg_to_rad(45)
@export var lean_speed: float = 2.5

# Turn radius
@export var min_turn_radius: float = 0.25
@export var max_turn_radius: float = 3.0
@export var turn_speed: float = 2.0

# Component references
@onready var bike_physics: BikePhysics = %BikePhysics

# State
var steering_angle: float = 0.0
var lean_angle: float = 0.0


func handle_steering(delta, idle_tip_angle: float):
	var steer_input = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")

	# Tip angle pulls steering in that direction (bike falls, bars turn)
	var tip_induced_steer = -idle_tip_angle * 0.5
	var target_steer = clamp(max_steering_angle * steer_input + tip_induced_steer, -max_steering_angle, max_steering_angle)

	# Smooth interpolation to target
	steering_angle = lerpf(steering_angle, target_steer, steering_speed * delta)


func update_lean(delta, steer_input: float, _pitch_angle: float, idle_tip_angle: float):
	# Lean from steering input and turn
	var speed_factor = clamp(bike_physics.speed / 20.0, 0.0, 1.0)
	var steer_lean = -steering_angle * speed_factor * 1.2
	var input_lean = -steer_input * max_lean_angle * 0.3

	# Tip angle adds directly to lean
	var target_lean = steer_lean + input_lean + idle_tip_angle * 0.5
	target_lean = clamp(target_lean, -max_lean_angle, max_lean_angle)

	# Smooth interpolation
	lean_angle = lerpf(lean_angle, target_lean, lean_speed * delta)


func get_turn_rate() -> float:
	var speed_pct = bike_physics.speed / bike_physics.max_speed
	var turn_radius = lerpf(min_turn_radius, max_turn_radius, speed_pct)
	return turn_speed / turn_radius


func is_turning() -> bool:
	return abs(steering_angle) > 0.2


func get_steer_input() -> float:
	return Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")


func reset():
	steering_angle = 0.0
	lean_angle = 0.0
