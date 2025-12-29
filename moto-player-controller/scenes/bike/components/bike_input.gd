class_name BikeInput extends Node

signal difficulty_toggled

# Input signals - emitted every physics frame with current values
signal throttle_changed(value: float)
signal front_brake_changed(value: float)
signal rear_brake_changed(value: float)
signal steer_changed(value: float)
signal lean_changed(value: float)
signal clutch_held_changed(held: bool, just_pressed: bool)
signal gear_up_pressed
signal gear_down_pressed

# Vibration settings
@export var vibration_duration: float = 0.15


func _physics_process(_delta):
    _update_input()


func _update_input():
    throttle_changed.emit(Input.get_action_strength("throttle_pct"))
    front_brake_changed.emit(Input.get_action_strength("brake_front_pct"))
    rear_brake_changed.emit(Input.get_action_strength("brake_rear"))

    steer_changed.emit(Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"))
    lean_changed.emit(Input.get_action_strength("lean_back") - Input.get_action_strength("lean_forward"))

    clutch_held_changed.emit(
        Input.is_action_pressed("clutch"),
        Input.is_action_just_pressed("clutch")
    )

    if Input.is_action_just_pressed("gear_up"):
        gear_up_pressed.emit()
    if Input.is_action_just_pressed("gear_down"):
        gear_down_pressed.emit()

    if Input.is_action_just_pressed("change_difficulty"):
        difficulty_toggled.emit()


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
