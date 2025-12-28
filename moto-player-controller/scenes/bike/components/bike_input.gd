class_name BikeInput extends Node

# Throttle and brakes (0-1 range)
var throttle: float = 0.0
var front_brake: float = 0.0
var rear_brake: float = 0.0

# Steering (-1 to 1, left to right)
var steer: float = 0.0

# Lean (-1 to 1, forward to back)
var lean: float = 0.0

# Clutch (0-1)
var clutch: float = 0.0

# Gear shifting (just pressed this frame)
var gear_up_pressed: bool = false
var gear_down_pressed: bool = false

# Computed values
var total_brake: float = 0.0

# Vibration settings
@export var vibration_duration: float = 0.15


func _physics_process(_delta):
	update_input()


func update_input():
	throttle = Input.get_action_strength("throttle_pct")
	front_brake = Input.get_action_strength("brake_front_pct")
	rear_brake = Input.get_action_strength("brake_rear")
	total_brake = clamp(front_brake + rear_brake, 0.0, 1.0)

	steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	lean = Input.get_action_strength("lean_back") - Input.get_action_strength("lean_forward")

	clutch = Input.get_action_strength("clutch")

	gear_up_pressed = Input.is_action_just_pressed("gear_up")
	gear_down_pressed = Input.is_action_just_pressed("gear_down")

func update_vibration():
	var weak_total = 0.0
	var strong_total = 0.0
	var _brake_vibe_intensity = 2.0

	# Brake danger vibration
	if state.brake_danger_level > 0.1:
		weak_total += state.brake_danger_level * _brake_vibe_intensity
		strong_total += state.brake_danger_level * state.brake_danger_level * _brake_vibe_intensity

	# Fishtail vibration
	var fishtail_intensity = abs(state.fishtail_angle) / state.max_fishtail_angle if state.max_fishtail_angle > 0 else 0.0
	if fishtail_intensity > 0.1:
		weak_total += fishtail_intensity * 0.6
		strong_total += fishtail_intensity * fishtail_intensity * 0.8

	# Apply vibration
	if weak_total > 0.01 or strong_total > 0.01:
		Input.start_joy_vibration(0, clamp(weak_total, 0.0, 1.0), clamp(strong_total, 0.0, 1.0), vibration_duration)
	else:
		stop_vibration()


func stop_vibration():
	Input.stop_joy_vibration(0)
