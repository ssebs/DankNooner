@tool
class_name InputController extends Node3D

# Local oneshot signals
signal cam_switch_pressed
signal reset_cam_pressed

@export var player_entity: PlayerEntity
@export var vibration_duration: float = 0.15

## Automatic transmission thresholds (RPM ratio, 0-1). Upshift sits just under the rev
## limiter's 0.98 cut so the auto box shifts instead of bouncing off it.
const AUTO_UPSHIFT_RPM_RATIO: float = 0.95
const AUTO_DOWNSHIFT_RPM_RATIO: float = 0.5
## Minimum seconds between automatic shifts — stops a shift from being re-evaluated before
## the RPM has settled into the new gear.
const AUTO_SHIFT_COOLDOWN: float = 0.4

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
var nfx_boost_held: bool = false
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
var _auto_shift_cooldown: float = 0.0


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
	nfx_boost_held = Input.is_action_pressed("boost")
	nfx_cam_x = (Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left"))
	nfx_cam_y = Input.get_action_strength("cam_up") - Input.get_action_strength("cam_down")


## Reset requested gear on respawn — respawned fires from do_respawn (rollback), so defer
## the write to _gather() where it gets recorded into netfox input history.
func _on_respawned():
	if !is_multiplayer_authority():
		return
	_pending_gear_reset = true
	_auto_shift_cooldown = 0.0


## Local input
func _process(delta):
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

	if player_entity.settings_manager.current_settings["auto_transmission"]:
		_auto_shift(delta)

	nfx_target_gear = clampi(nfx_target_gear, 1, player_entity.bike_definition.num_gears)


## Automatic transmission: shift up at redline, down at half RPM.
##
## Lives here rather than in GearingController because nfx_target_gear is a netfox INPUT
## property owned by the local client — the server must never write it. Driving the same
## absolute-valued var the manual shift keys use means the auto box inherits the whole
## existing sync path for free, including its immunity to stale-input reuse.
func _auto_shift(delta: float):
	_auto_shift_cooldown = maxf(_auto_shift_cooldown - delta, 0.0)
	if _auto_shift_cooldown > 0.0:
		return

	var rpm_ratio := player_entity.gearing_controller.get_rpm_ratio()
	var num_gears := player_entity.bike_definition.num_gears

	# Compared against nfx_target_gear, not GearingController.current_gear: current_gear
	# only catches up on the next rollback tick, so using it would re-request a shift that
	# is already in flight.
	if rpm_ratio >= AUTO_UPSHIFT_RPM_RATIO and nfx_target_gear < num_gears:
		nfx_target_gear += 1
		_auto_shift_cooldown = AUTO_SHIFT_COOLDOWN
	elif rpm_ratio <= AUTO_DOWNSHIFT_RPM_RATIO and nfx_target_gear > 1:
		nfx_target_gear -= 1
		_auto_shift_cooldown = AUTO_SHIFT_COOLDOWN


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
