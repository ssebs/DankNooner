@tool
class_name InputController extends Node3D

signal throttle_changed(value: float)
signal front_brake_changed(value: float)
signal steer_changed(value: float)  # lean left/right
signal lean_changed(value: float)  # lean back/fwd
signal rear_brake_pressed
signal trick_mod_pressed
signal clutch_pressed
signal gear_up_pressed
signal gear_down_pressed
signal cam_switch_pressed
# signal difficulty_pressed
# signal bike_switch_pressed

@export var vibration_duration: float = 0.15

var is_gamepad := false

#region Input vars that aren't bools
var throttle: float = 0.0:
	set(value):
		if throttle != value:
			throttle = value
			throttle_changed.emit(value)

var front_brake: float = 0.0:
	set(value):
		if front_brake != value:
			front_brake = value
			front_brake_changed.emit(value)

var steer: float = 0.0:
	set(value):
		if steer != value:
			steer = value
			steer_changed.emit(value)

var lean: float = 0.0:
	set(value):
		if lean != value:
			lean = value
			lean_changed.emit(value)


#region input detection & signal emission
func _process(_delta: float):
	if Engine.is_editor_hint():
		return
	_update_input()


## Update input vars & emit signals during _process
func _update_input():
	throttle = Input.get_action_strength("throttle_pct")
	front_brake = Input.get_action_strength("brake_front_pct")
	steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	lean = Input.get_action_strength("lean_forward") - Input.get_action_strength("lean_back")

	if Input.get_action_strength("brake_rear"):
		rear_brake_pressed.emit()
	if Input.is_action_pressed("clutch"):
		clutch_pressed.emit()
	if Input.is_action_pressed("trick_mod"):
		trick_mod_pressed.emit()
	if Input.is_action_just_pressed("gear_up"):
		gear_up_pressed.emit()
	if Input.is_action_just_pressed("gear_down"):
		gear_down_pressed.emit()
	if Input.is_action_just_pressed("switch_cam"):
		cam_switch_pressed.emit()


func _unhandled_input(event: InputEvent):
	_detect_gamepad_or_kbm(event)


func _detect_gamepad_or_kbm(event: InputEvent):
	if event is InputEventKey or event is InputEventMouse:
		is_gamepad = false
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		is_gamepad = true


#endregion


## Add vibration intensity. Call this each frame vibration is needed.
func add_vibration(weak: float, strong: float):
	if weak > 0.01 or strong > 0.01:
		Input.start_joy_vibration(
			0, clamp(weak, 0.0, 1.0), clamp(strong, 0.0, 1.0), vibration_duration
		)
	else:
		stop_vibration()


func stop_vibration():
	Input.stop_joy_vibration(0)
