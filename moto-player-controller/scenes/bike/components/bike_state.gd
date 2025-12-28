class_name BikeState extends Resource

# Physics state
var speed: float = 0.0
var steering_angle: float = 0.0
var lean_angle: float = 0.0
var fall_angle: float = 0.0 # Bike falling over due to lack of gyroscopic stability

# Gearing state
var current_gear: int = 1
var current_rpm: float = 1000.0
var clutch_value: float = 0.0
var is_stalled: bool = false

# Tricks state
var pitch_angle: float = 0.0
var fishtail_angle: float = 0.0

# Crash state
var is_crashed: bool = false
var brake_danger_level: float = 0.0
var brake_grab_level: float = 0.0

# Thresholds (set once from components)
var crash_lean_threshold: float = deg_to_rad(80)
var brake_grab_crash_threshold: float = 0.9

# Difficulty
var is_easy_mode: bool = true


func is_front_wheel_locked() -> bool:
	return brake_grab_level > brake_grab_crash_threshold
