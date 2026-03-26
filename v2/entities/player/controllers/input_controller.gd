@tool
class_name InputController extends Node3D

# Local oneshot signals
## -1 for back, 1 for fwd
signal gear_change_pressed(direction: int)
signal cam_switch_pressed

@export var player_entity: PlayerEntity
@export var vibration_duration: float = 0.15

var is_gamepad := false

#region Netfox sync'd Input vars
var nfx_throttle: float = 0.0
var nfx_front_brake: float = 0.0
var nfx_rear_brake: float = 0.0
var nfx_steer: float = 0.0
var nfx_lean: float = 0.0  # TODO: check inverted

var nfx_trick_held: bool = false
var nfx_clutch_held: bool = false
var nfx_cam_x: float = 0.0
var nfx_cam_y: float = 0.0  # TODO: check inverted
#endregion

#region rb_* pattern sync'd vars
var rb_gear_up_pressed: float = false
var rb_gear_down_pressed: float = false
#endregion


func _ready():
	if Engine.is_editor_hint():
		return
	NetworkTime.before_tick_loop.connect(_gather)


## Netfox's input hook
## Update input vars (nfx_)
func _gather():
	if Engine.is_editor_hint() or multiplayer.multiplayer_peer == null:
		return
	if !is_multiplayer_authority():
		return

	nfx_throttle = Input.get_action_strength("throttle_pct")
	nfx_front_brake = Input.get_action_strength("brake_front_pct")
	nfx_rear_brake = Input.get_action_strength("brake_rear")
	nfx_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	nfx_lean = Input.get_action_strength("lean_forward") - Input.get_action_strength("lean_back")
	nfx_trick_held = Input.is_action_pressed("trick")
	nfx_clutch_held = Input.is_action_pressed("clutch")
	nfx_cam_x = (Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left"))
	nfx_cam_y = Input.get_action_strength("cam_up") - Input.get_action_strength("cam_down")


func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool):
	if Engine.is_editor_hint():
		return

	if rb_gear_up_pressed:
		gear_change_pressed.emit(1)
		rb_gear_up_pressed = false
	if rb_gear_down_pressed:
		gear_change_pressed.emit(-1)
		rb_gear_down_pressed = false


## Local input
func _process(_delta):
	if Engine.is_editor_hint() or multiplayer.multiplayer_peer == null:
		return
	if !is_multiplayer_authority():
		return

	if Input.is_action_just_pressed("switch_cam"):
		cam_switch_pressed.emit()

	if Input.is_action_just_pressed("gear_up"):
		rb_gear_up_pressed = true
	if Input.is_action_just_pressed("gear_down"):
		rb_gear_down_pressed = true


#region KBM/Gamepad switching
func _unhandled_input(event: InputEvent):
	if !player_entity.is_local_client:
		return
	_detect_gamepad_or_kbm(event)


func _detect_gamepad_or_kbm(event: InputEvent):
	if event is InputEventKey or event is InputEventMouse:
		is_gamepad = false
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		is_gamepad = true


#endregion


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
