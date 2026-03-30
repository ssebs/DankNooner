@tool
class_name CameraController extends Node3D

enum CameraMode { FPS, TPS }

@export var player_entity: PlayerEntity
@export var input_controller: InputController

@export var default_camera_mode: CameraMode = CameraMode.TPS
@export var fps_cam: Camera3D
@export var tps_cam: Camera3D

@export var fps_marker: Marker3D
@export var tps_marker: Marker3D

@export_tool_button("SetCamToMarker") var b_sctm = func(): set_cam_transforms_from_markers(-1)

var current_camera: Camera3D
var current_cam_mode: CameraMode

var _cam_tracking: bool = true

var _fps_offset: Transform3D
var _tps_offset: Transform3D


func _ready():
	_fps_offset = player_entity.global_transform.affine_inverse() * fps_marker.global_transform
	_tps_offset = player_entity.global_transform.affine_inverse() * tps_marker.global_transform
	set_cam_transforms_from_markers(-1)

	if Engine.is_editor_hint():
		return


func _process(delta: float):
	if _cam_tracking:
		set_cam_transforms_from_markers(delta)


#region public API
## HACK - called from player_entity
func deferred_init():
	if player_entity.is_local_client:
		do_reset()
		input_controller.cam_switch_pressed.connect(toggle_cam)
	else:
		disable_cameras()


func set_cam_tracking(val: bool):
	_cam_tracking = val


func set_cam_transforms_from_markers(delta: float):
	if delta == -1:
		fps_cam.global_transform = fps_marker.global_transform
		tps_cam.global_transform = tps_marker.global_transform
		return

	# LERP from current pos to marker pos
	# FPS
	# follow fully
	var weight: float = clampf(delta * 90.0, 0.0, 1.0)
	fps_cam.global_transform = fps_cam.global_transform.interpolate_with(
		fps_marker.global_transform, weight
	)
	tps_cam.global_transform = tps_cam.global_transform.interpolate_with(
		tps_marker.global_transform, weight
	)

	# # TPS
	# # only follow Y rotation (yaw) — ignore pitch (X) and roll (Z)
	# # tps_cam.global_position = tps_cam.global_position.lerp(tps_marker.global_position, weight)
	# var target_pos = tps_cam.global_position.lerp(tps_marker.global_position, weight)
	# tps_cam.global_position = Vector3(
	# 	target_pos.x, tps_cam.global_position.y * _tps_offset.origin.y, target_pos.z
	# )

	# var target_y: float = lerp_angle(
	# 	tps_cam.global_rotation.y, tps_marker.global_rotation.y, weight
	# )
	# var target_x: float = lerp_angle(
	# 	tps_cam.global_rotation.x, player_entity.global_rotation.x, weight
	# )
	# tps_cam.global_rotation = Vector3(target_x, target_y, tps_cam.global_rotation.z)


func disable_cameras():
	tps_cam.current = false
	fps_cam.current = false


func switch_to_cam(cam_mode: CameraMode):
	if cam_mode == CameraMode.FPS:
		switch_to_fps_cam()
	else:
		switch_to_tps_cam()


func switch_to_fps_cam():
	fps_cam.current = true
	tps_cam.current = false
	current_camera = fps_cam
	current_cam_mode = CameraMode.FPS


func switch_to_tps_cam():
	tps_cam.current = true
	fps_cam.current = false
	current_camera = tps_cam
	current_cam_mode = CameraMode.TPS


func toggle_cam():
	if current_cam_mode == CameraMode.FPS:
		switch_to_tps_cam()
	else:
		switch_to_fps_cam()


## Called from player_entity.gd's do_respawn
func do_reset():
	# TODO - set this from a setting, not always to TPS
	switch_to_tps_cam()


#endregion


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
