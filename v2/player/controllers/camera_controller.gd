@tool
class_name CameraController extends Node3D

enum CameraMode { TPS = 0, FPS, NONE }

@export var player_entity: PlayerEntity
@export var input_controller: InputController

@export var default_camera_mode: CameraMode = CameraMode.TPS
@export var fps_cam: Camera3D
@export var tps_cam: Camera3D

@export var fps_marker: Marker3D
@export var tps_marker: Marker3D

@export_group("TPS Orbit")
@export var pitch_min_deg: float = -20.0
@export var pitch_max_deg: float = 60.0
@export var tps_look_height: float = 0.7

@export_group("FPS Look")
@export var fps_pitch_min_deg: float = -30.0
@export var fps_pitch_max_deg: float = 45.0
@export var fps_yaw_limit_deg: float = 120.0

@export_group("Camera Reset")
@export var reset_delay: float = 3.0
@export var reset_speed: float = 3.0

## Base values when slider is at 0.5 (middle)
const MOUSE_SENS_SCALE: float = 0.003
const JOY_SENS_SCALE: float = 6.0
const DEFAULT_ORBIT_PITCH: float = -0.5

var current_cam_mode: CameraMode
var invert_cam: int = -1:
	set(value):
		invert_cam = 1 if value else -1

var _mouse_cam_sens: float = 0.0015
var _joy_cam_sens: float = 2.0
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = 0.0
var _default_orbit_pitch: float = -15
var _mouse_delta: Vector2 = Vector2.ZERO
var _no_input_timer: float = 0.0

var _fps_yaw_offset: float = 0.0
var _fps_pitch_offset: float = 0.0
var _fps_cam_offset := 0.75

# TODO - zoom out w/ speed / current_trick != None


func _ready():
	if Engine.is_editor_hint():
		return


func _input(event: InputEvent):
	if Engine.is_editor_hint():
		return
	if !player_entity.is_local_client:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative


func _process(delta: float):
	if Engine.is_editor_hint():
		return
	if !player_entity.is_local_client:
		return

	var adjusted_mouse := Vector2(_mouse_delta.x, _mouse_delta.y * invert_cam)

	match current_cam_mode:
		CameraMode.TPS:
			_update_tps_input(delta, adjusted_mouse)
			_update_tps_camera()
		CameraMode.FPS:
			_update_fps_input(delta, adjusted_mouse)
			_update_fps_camera()

	_mouse_delta = Vector2.ZERO


func _has_cam_input(mouse: Vector2) -> bool:
	return (
		mouse.length_squared() > 0.01
		or absf(input_controller.nfx_cam_x) > 0.05
		or absf(input_controller.nfx_cam_y) > 0.05
	)


#region TPS orbit
func _update_tps_input(delta: float, mouse: Vector2):
	if _has_cam_input(mouse):
		_orbit_yaw -= mouse.x * _mouse_cam_sens
		_orbit_pitch -= mouse.y * _mouse_cam_sens

		_orbit_yaw -= input_controller.nfx_cam_x * _joy_cam_sens * delta
		_orbit_pitch += input_controller.nfx_cam_y * invert_cam * _joy_cam_sens * delta

		_orbit_pitch = clampf(_orbit_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		_orbit_yaw = wrapf(_orbit_yaw, -PI, PI)
		_no_input_timer = 0.0
	else:
		_no_input_timer += delta
		if _no_input_timer >= reset_delay:
			var t: float = reset_speed * delta
			_orbit_yaw = lerpf(_orbit_yaw, 0.0, t)
			_orbit_pitch = lerpf(_orbit_pitch, _default_orbit_pitch, t)


func _update_tps_camera():
	var marker_offset: Vector3 = tps_marker.position
	var distance: float = -marker_offset.z
	var height: float = marker_offset.y

	var focus: Vector3 = _get_tps_focus_position()
	var look_target: Vector3 = focus + Vector3.UP * tps_look_height
	var yaw: float = _get_tps_base_yaw() + _orbit_yaw

	var orbit_rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -_orbit_pitch)
	var cam_offset: Vector3 = orbit_rot * Vector3(0, 0, distance)
	cam_offset.y += height

	tps_cam.global_position = focus + cam_offset
	tps_cam.look_at(look_target)


## When crashed, follow the ragdoll's hips so the camera tracks the tumbling character
## rather than the frozen player_entity.
func _get_tps_focus_position() -> Vector3:
	if player_entity.is_crashed:
		return player_entity.character_skin.ragdoll_controller.get_hips_global_position()
	return player_entity.global_position


## Player rotation is meaningless once ragdolling — drop the body yaw so the orbit stays
## stable around the hips instead of snapping with the frozen entity transform.
func _get_tps_base_yaw() -> float:
	if player_entity.is_crashed:
		return 0.0
	return player_entity.global_rotation.y


#endregion


#region FPS look
func _update_fps_input(delta: float, mouse: Vector2):
	if _has_cam_input(mouse):
		_fps_yaw_offset -= mouse.x * _mouse_cam_sens
		_fps_pitch_offset -= mouse.y * _mouse_cam_sens

		_fps_yaw_offset -= input_controller.nfx_cam_x * _joy_cam_sens * _fps_cam_offset * delta
		_fps_pitch_offset += (
			input_controller.nfx_cam_y * invert_cam * _joy_cam_sens * _fps_cam_offset * delta
		)

		_fps_yaw_offset = clampf(
			_fps_yaw_offset, deg_to_rad(-fps_yaw_limit_deg), deg_to_rad(fps_yaw_limit_deg)
		)
		_fps_pitch_offset = clampf(
			_fps_pitch_offset, deg_to_rad(fps_pitch_min_deg), deg_to_rad(fps_pitch_max_deg)
		)
		_no_input_timer = 0.0
	else:
		_no_input_timer += delta
		if _no_input_timer >= reset_delay:
			var t: float = reset_speed * delta
			_fps_yaw_offset = lerpf(_fps_yaw_offset, 0.0, t)
			_fps_pitch_offset = lerpf(_fps_pitch_offset, 0.0, t)


func _update_fps_camera():
	fps_cam.global_transform = fps_marker.global_transform
	fps_cam.rotate_object_local(Vector3.UP, _fps_yaw_offset)
	fps_cam.rotate_object_local(Vector3.RIGHT, -_fps_pitch_offset)


#endregion


#region public API
## HACK - called from player_entity
func deferred_init():
	if player_entity.is_local_client:
		DebugUtils.DebugMsg("is_local_client %s" % multiplayer.multiplayer_peer.get_unique_id())
		do_reset()
		input_controller.cam_switch_pressed.connect(_on_cam_switch_pressed)
		input_controller.reset_cam_pressed.connect(_on_reset_cam_pressed)
		player_entity.settings_manager.setting_updated.connect(_on_setting_updated)
		player_entity.settings_manager.all_settings_changed.connect(func(_s): _load_cam_settings())
		_load_cam_settings()
	else:
		DebugUtils.DebugMsg("disable_cameras %s" % multiplayer.multiplayer_peer.get_unique_id())
		disable_cameras()


func disable_cameras():
	tps_cam.current = false
	fps_cam.current = false


func switch_to_cam(cam_mode: CameraMode):
	var is_fps: bool = cam_mode == CameraMode.FPS
	fps_cam.current = is_fps
	tps_cam.current = !is_fps
	current_cam_mode = cam_mode


## Force-switch to TPS without persisting to settings — used for crash so the player can
## see their ragdoll regardless of their saved cam preference.
func force_tps():
	if !player_entity.is_local_client:
		return
	switch_to_cam(CameraMode.TPS)


## Called from player_entity.gd's do_respawn
func do_reset():
	if !player_entity.is_local_client:
		return
	_default_orbit_pitch = deg_to_rad(DEFAULT_ORBIT_PITCH)
	_on_reset_cam_pressed()
	switch_to_cam(_int_to_cam_mode(player_entity.settings_manager.current_settings["cam_mode"]))


#endregion


func _on_cam_switch_pressed():
	var new_cam_mode: int = 1 if current_cam_mode == 0 else 0
	player_entity.settings_manager.update_setting("cam_mode", new_cam_mode, true, true)


func _on_reset_cam_pressed():
	_orbit_yaw = 0.0
	_orbit_pitch = _default_orbit_pitch
	_no_input_timer = 0.0
	_fps_yaw_offset = 0.0
	_fps_pitch_offset = 0.0


func _load_cam_settings():
	var settings := player_entity.settings_manager.current_settings
	_mouse_cam_sens = settings["mouse_cam_sens"] * MOUSE_SENS_SCALE
	_joy_cam_sens = settings["joy_cam_sens"] * JOY_SENS_SCALE
	invert_cam = settings["invert_cam"]

	current_cam_mode = _int_to_cam_mode(settings["cam_mode"])
	switch_to_cam(current_cam_mode)


func _int_to_cam_mode(inp: int) -> CameraMode:
	match inp:
		0:
			return CameraMode.TPS
		1:
			return CameraMode.FPS
	return CameraMode.NONE


func _on_setting_updated(key: String, _value: Variant):
	if key in ["mouse_cam_sens", "joy_cam_sens", "invert_cam"]:
		_load_cam_settings()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if fps_cam == null:
		issues.append("fps_cam must not be empty")
	if tps_cam == null:
		issues.append("tps_cam must not be empty")
	if fps_marker == null:
		issues.append("fps_marker must not be empty")
	if tps_marker == null:
		issues.append("tps_marker must not be empty")
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")

	return issues
