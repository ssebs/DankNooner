@tool
class_name CameraController extends Node3D

enum CameraMode { FPS, TPS }

@export var default_camera_mode: CameraMode = CameraMode.TPS
@export var fps_cam: Camera3D
@export var tps_cam: Camera3D

@export var fps_marker: Marker3D
@export var tps_marker: Marker3D

var current_camera: Camera3D
var current_cam_mode: CameraMode


func _ready():
	fps_cam.global_transform = fps_marker.global_transform
	tps_cam.global_transform = tps_marker.global_transform

	if Engine.is_editor_hint():
		return

	switch_to_cam(default_camera_mode)


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

	return issues
