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


# Vibration settings
@export var vibration_duration: float = 0.15


func _physics_process(_delta):
    update_input()


func update_input():
    throttle = Input.get_action_strength("throttle_pct")
    front_brake = Input.get_action_strength("brake_front_pct")
    rear_brake = Input.get_action_strength("brake_rear")

    steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
    lean = Input.get_action_strength("lean_back") - Input.get_action_strength("lean_forward")

    clutch = Input.get_action_strength("clutch")

    gear_up_pressed = Input.is_action_just_pressed("gear_up")
    gear_down_pressed = Input.is_action_just_pressed("gear_down")


func add_vibration(weak: float, strong: float):
    """Add vibration intensity from external sources. Call this each frame vibration is needed."""
    if weak > 0.01 or strong > 0.01:
        Input.start_joy_vibration(0, clamp(weak, 0.0, 1.0), clamp(strong, 0.0, 1.0), vibration_duration)
    else:
        stop_vibration()

func stop_vibration():
    Input.stop_joy_vibration(0)

func reset():
    stop_vibration()
