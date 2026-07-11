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

@export_group("Juice FX")
## How fast accumulated screen-shake trauma bleeds off (per second).
@export var trauma_decay: float = 1.8
## Max camera jitter angle (deg) at full trauma.
@export var shake_max_angle_deg: float = 2.5
## Speed change (units/s²) where accel/decel shake begins.
@export var accel_shake_threshold: float = 12.0
## Speed change (units/s²) where accel/decel shake is maxed.
@export var accel_shake_max: float = 60.0
## Trauma floor held at the most aggressive accel/decel.
@export var accel_max_trauma: float = 0.6
## Fraction of the speed-achievable max lean where hard-cornering shake begins (halfway).
@export_range(0.0, 1.0) var grip_shake_threshold: float = 0.5
## Trauma floor held at full lean for the current speed — tires near their grip limit.
@export var grip_max_trauma: float = 0.3
## Max one-shot trauma burst on a wheelie landing (scaled by front-wheel drop speed).
@export var wheelie_land_trauma: float = 0.35
## Front-wheel drop speed (deg/s) below which a wheelie landing adds no shake.
@export var wheelie_land_drop_min_deg: float = 60.0
## Front-wheel drop speed (deg/s) at which a wheelie landing adds full shake.
@export var wheelie_land_drop_max_deg: float = 400.0
## Fraction of the bike's max_speed where the FOV widen + blur begins.
@export_range(0.0, 1.0) var fov_speed_pct_min: float = 0.2
## Fraction of the bike's max_speed where the FOV widen + blur is maxed out.
@export_range(0.0, 1.0) var fov_speed_pct_max: float = 1.0
## Degrees added to the camera's base FOV at full speed.
@export var fov_max_add: float = 15.0
## Radial blur shader strength at full speed.
@export var blur_max_strength: float = 1.0
## UV radius around screen center kept fully sharp — blur only sits in the outer ring beyond this.
@export_range(0.0, 1.0) var blur_clear_radius: float = 0.7

## Base values when slider is at 0.5 (middle)
const MOUSE_SENS_SCALE: float = 0.003
const JOY_SENS_SCALE: float = 6.0
const DEFAULT_ORBIT_PITCH: float = -0.5
const RADIAL_BLUR_SHADER := preload("res://resources/shaders/radial_blur.gdshader")
## How quickly the smoothed accel estimate tracks raw frame-to-frame speed change.
const ACCEL_SMOOTH_RATE: float = 12.0
## Peak-hold decay (rad/s per second) for the wheelie-drop rate sampled across the land event.
const PITCH_DROP_DECAY: float = 30.0

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

# Juice FX state (local client only)
var _trauma: float = 0.0
var _tps_base_fov: float = 0.0
var _fps_base_fov: float = 0.0
var _blur_layer: CanvasLayer = null
var _blur_mat: ShaderMaterial = null
var _prev_pitch: float = 0.0
var _pitch_drop_rate: float = 0.0  # peak-held downward pitch speed (rad/s) for landing shake
var _prev_speed: float = 0.0
var _accel_smooth: float = 0.0  # low-passed |accel| (units/s²) for accel/decel shake

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
	_update_juice_fx(delta)


func _has_cam_input(mouse: Vector2) -> bool:
	# Trick mod button repurposes the right stick for trick input — lock the camera.
	if input_controller.nfx_trick_held:
		return false
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
		_tps_base_fov = tps_cam.fov
		_fps_base_fov = fps_cam.fov
		player_entity.trick_controller.trick_ended.connect(_on_trick_ended_fx)
		_create_blur_overlay()
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
	# Terrain3D auto-grabs the active camera once and permanently stops processing if
	# none exists yet — levels load before player cameras spawn, so hand it over manually.
	for terrain in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Terrain3D"]):
		terrain.set_camera(fps_cam if is_fps else tps_cam)


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


#region Juice FX
## Drives the high-speed FOV widen + radial blur and the screen shake each frame.
## Runs after the camera transform is set so shake jitter doesn't accumulate.
func _update_juice_fx(delta: float):
	var cam: Camera3D = fps_cam if current_cam_mode == CameraMode.FPS else tps_cam
	var base_fov: float = _fps_base_fov if current_cam_mode == CameraMode.FPS else _tps_base_fov

	# Scale off speed as a fraction of this skin's max_speed so the effect is bike-relative.
	var speed_factor: float = clampf(
		remap(
			player_entity.movement_controller._speed_pct,
			fov_speed_pct_min,
			fov_speed_pct_max,
			0.0,
			1.0
		),
		0.0,
		1.0
	)
	cam.fov = base_fov + fov_max_add * speed_factor
	_blur_mat.set_shader_parameter("strength", speed_factor * blur_max_strength)

	# Track the front-wheel drop speed (peak-held) so the wheelie-landing burst can scale by it.
	var pitch: float = player_entity.movement_controller.pitch_angle
	var instant_drop: float = maxf((_prev_pitch - pitch) / maxf(delta, 0.0001), 0.0)
	_pitch_drop_rate = maxf(instant_drop, _pitch_drop_rate - PITCH_DROP_DECAY * delta)
	_prev_pitch = pitch

	# Aggressive accel/decel holds a trauma floor; the wheelie-landing burst decays on top of it.
	# Reversing is gentle by nature, so it never shakes.
	var spd: float = player_entity.movement_controller.speed
	var accel: float = absf(spd - _prev_speed) / maxf(delta, 0.0001)
	_prev_speed = spd
	_accel_smooth = lerpf(_accel_smooth, accel, clampf(delta * ACCEL_SMOOTH_RATE, 0.0, 1.0))
	if not player_entity.movement_controller.is_reversing and _accel_smooth > accel_shake_threshold:
		_trauma = maxf(
			_trauma,
			clampf(
				remap(_accel_smooth, accel_shake_threshold, accel_shake_max, 0.0, accel_max_trauma),
				0.0,
				accel_max_trauma
			)
		)

	# Hard cornering holds a trauma floor: the closer the lean gets to the max the bike can
	# hold at this speed, the more the tires strain — the tightest turn radius this speed allows.
	var mc := player_entity.movement_controller
	var bd := player_entity.bike_definition
	var lean_factor: float = bd.lean_curve.sample(mc._speed_pct)
	var max_lean_for_speed: float = bd.max_lean_angle_rad * lean_factor
	var grip_strain: float = (
		absf(mc.roll_angle) / max_lean_for_speed if max_lean_for_speed > 0.001 else 0.0
	)
	if grip_strain > grip_shake_threshold:
		_trauma = maxf(
			_trauma,
			clampf(
				remap(grip_strain, grip_shake_threshold, 1.0, 0.0, grip_max_trauma),
				0.0,
				grip_max_trauma
			)
		)

	var shake: float = _trauma * _trauma
	if shake > 0.0:
		var amp: float = deg_to_rad(shake_max_angle_deg) * shake
		cam.rotate_object_local(Vector3.RIGHT, randf_range(-amp, amp))
		cam.rotate_object_local(Vector3.UP, randf_range(-amp, amp))
		cam.rotate_object_local(Vector3.FORWARD, randf_range(-amp, amp) * 0.5)

	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)


## Full-screen radial blur overlay, created locally so remote players don't pay for it.
## CanvasLayer -1 keeps it above the 3D world but below the HUD (canvas layer 0).
func _create_blur_overlay():
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = RADIAL_BLUR_SHADER
	_blur_mat.set_shader_parameter("strength", 0.0)
	# Set explicitly — relying on the shader's uniform default isn't reliable at runtime.
	_blur_mat.set_shader_parameter("clear_radius", blur_clear_radius)

	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _blur_mat
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_blur_layer = CanvasLayer.new()
	_blur_layer.layer = -1
	_blur_layer.add_child(rect)
	add_child(_blur_layer)


func _on_trick_ended_fx(trick_type: TrickController.Trick):
	if (
		trick_type in [TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD]
		and player_entity.movement_controller._is_on_floor
	):
		# Stronger burst the faster the front wheel slammed back down.
		var landing: float = clampf(
			remap(
				_pitch_drop_rate,
				deg_to_rad(wheelie_land_drop_min_deg),
				deg_to_rad(wheelie_land_drop_max_deg),
				0.0,
				1.0
			),
			0.0,
			1.0
		)
		_trauma = minf(_trauma + wheelie_land_trauma * landing, 1.0)


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
