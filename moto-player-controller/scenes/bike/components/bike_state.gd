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

# Difficulty
var is_easy_mode: bool = true
