@tool
class_name InputController extends Node3D

# Local oneshot signals
signal cam_switch_pressed
signal reset_cam_pressed

@export var player_entity: PlayerEntity
@export var vibration_duration: float = 0.15

var is_gamepad := false
var input_disabled := false

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

## Requested gear, absolute-valued (NOT edge-triggered). Netfox reuses the latest input
## snapshot on server ticks where fresh client input hasn't arrived yet, and drops
## superseded snapshots — one-tick "pressed" flags get double-applied or lost entirely,
## desyncing the server's current_gear from the client's. An absolute target is idempotent
## under both. GearingController applies it in its rollback tick.
var nfx_target_gear: int = 1
#endregion

## Set on respawn; consumed by the next _gather() (outside the rollback loop, so the
## reset actually lands in recorded input history instead of being overwritten by it).
var _pending_gear_reset: bool = false


func _ready():
	if Engine.is_editor_hint():
		return
	NetworkTime.before_tick_loop.connect(_gather)
	player_entity.respawned.connect(_on_respawned)


## Netfox's input hook
## Update input vars (nfx_)
func _gather():
	if Engine.is_editor_hint() or multiplayer.multiplayer_peer == null:
		return
	if !is_multiplayer_authority():
		return
	if input_disabled:
		return
	if _text_field_focused():
		return

	if _pending_gear_reset:
		nfx_target_gear = 1
		_pending_gear_reset = false

	nfx_throttle = Input.get_action_strength("throttle_pct")
	nfx_front_brake = Input.get_action_strength("brake_front_pct")
	nfx_rear_brake = Input.get_action_strength("brake_rear")
	nfx_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	nfx_lean = Input.get_action_strength("lean_forward") - Input.get_action_strength("lean_back")
	nfx_trick_held = Input.is_action_pressed("trick")
	nfx_clutch_held = Input.is_action_pressed("clutch")
	nfx_cam_x = (Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left"))
	nfx_cam_y = Input.get_action_strength("cam_up") - Input.get_action_strength("cam_down")


## Reset requested gear on respawn — respawned fires from do_respawn (rollback), so defer
## the write to _gather() where it gets recorded into netfox input history.
func _on_respawned():
	if !is_multiplayer_authority():
		return
	_pending_gear_reset = true


## Local input
func _process(_delta):
	if Engine.is_editor_hint() or multiplayer.multiplayer_peer == null:
		return
	if !is_multiplayer_authority():
		return
	if _text_field_focused():
		return

	if Input.is_action_just_pressed("switch_cam"):
		cam_switch_pressed.emit()
	if Input.is_action_just_pressed("reset_cam"):
		reset_cam_pressed.emit()

	if Input.is_action_just_pressed("gear_up"):
		nfx_target_gear += 1
	if Input.is_action_just_pressed("gear_down"):
		nfx_target_gear -= 1
	nfx_target_gear = clampi(nfx_target_gear, 1, player_entity.bike_definition.num_gears)


## True when a text field has keyboard focus (e.g. username/code entry) — game
## input polls global Input and bypasses GUI focus, so block it while typing.
func _text_field_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


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
