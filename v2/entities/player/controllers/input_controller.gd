@tool
class_name InputController extends Node3D

signal throttle_changed(value: float)
signal front_brake_changed(value: float)
signal steer_changed(value: float)  # lean left/right
signal lean_changed(value: float)  # lean back/fwd
signal clutch_held_changed(held: bool, just_pressed: bool)
signal gear_up_pressed
signal gear_down_pressed
signal cam_switch_pressed

@export var player_entity: PlayerEntity
@export var vibration_duration: float = 0.15

var is_gamepad := false

#region Input vars sync'd with netfox
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

var rear_brake: float = 0.0

var trick: bool = false

var gear_up: bool = false
var gear_down: bool = false

var clutch_held: bool = false
#endregion


func _ready():
	if Engine.is_editor_hint():
		return
	NetworkTime.before_tick_loop.connect(_gather)


func _gather():
	if Engine.is_editor_hint():
		return
	if not is_multiplayer_authority():
		return

	_update_input_for_server()


## local input
func _process(_delta):
	if Engine.is_editor_hint():
		return
	if Input.is_action_just_pressed("switch_cam"):
		cam_switch_pressed.emit()


## Update input vars & emit signals
func _update_input_for_server():
	throttle = Input.get_action_strength("throttle_pct")
	front_brake = Input.get_action_strength("brake_front_pct")
	rear_brake = Input.get_action_strength("brake_rear")
	steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	lean = Input.get_action_strength("lean_forward") - Input.get_action_strength("lean_back")
	trick = Input.is_action_pressed("trick_mod")

	# Clutch handling (tap vs hold)
	var clutch_now = Input.is_action_pressed("clutch")
	if clutch_now != clutch_held:
		clutch_held = clutch_now
		clutch_held_changed.emit(clutch_held, clutch_now)

	# Gear shifting as synced input properties (rollback-safe)
	gear_up = Input.is_action_just_pressed("gear_up")
	gear_down = Input.is_action_just_pressed("gear_down")
	if gear_up:
		gear_up_pressed.emit()
	if gear_down:
		gear_down_pressed.emit()


func _unhandled_input(event: InputEvent):
	if !player_entity.is_local_client:
		return
	_detect_gamepad_or_kbm(event)


func _detect_gamepad_or_kbm(event: InputEvent):
	if event is InputEventKey or event is InputEventMouse:
		is_gamepad = false
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		is_gamepad = true


#region controller vibration
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


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if player_entity == null:
		issues.append("player_entity must not be empty")

	return issues
