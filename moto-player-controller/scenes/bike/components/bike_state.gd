class_name BikeState extends Resource

# Physics state
var speed: float = 0.0
var max_speed: float = 60.0
var steering_angle: float = 0.0
var max_steering_angle: float = deg_to_rad(35)
var lean_angle: float = 0.0
var idle_tip_angle: float = 0.0

# Gearing state
var current_gear: int = 1
var current_rpm: float = 1000.0
var idle_rpm: float = 1000.0
var max_rpm: float = 9000.0
var clutch_value: float = 0.0
var is_stalled: bool = false

# Tricks state
var pitch_angle: float = 0.0
var fishtail_angle: float = 0.0
var max_fishtail_angle: float = deg_to_rad(90)

# Crash state
var is_crashed: bool = false
var brake_danger_level: float = 0.0
var brake_grab_level: float = 0.0

# Thresholds (set once from components)
var crash_lean_threshold: float = deg_to_rad(80)
var brake_grab_crash_threshold: float = 0.9

# Difficulty
var is_easy_mode: bool = true


func get_rpm_ratio() -> float:
	if max_rpm <= idle_rpm:
		return 0.0
	return (current_rpm - idle_rpm) / (max_rpm - idle_rpm)


func is_front_wheel_locked() -> bool:
	return brake_grab_level > brake_grab_crash_threshold
