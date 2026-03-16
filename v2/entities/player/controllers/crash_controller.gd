@tool
class_name CrashController extends Node

signal crashed

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var animation_controller: AnimationController
@export var movement_controller: MovementController

@export var crash_lean_threshold_deg: float = 80.0
@export var brake_grab_time_threshold: float = 0.85
@export var brake_lean_sensitivity: float = 0.7

var _brake_grab_timer: float = 0.0
var _brake_was_zero: bool = true
var _brake_was_grabbed: bool = false


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController after physics
func on_movement_rollback_tick(delta: float):
	if player_entity.is_crashed:
		return

	_update_brake_grab(delta)
	_detect_crash()


## Sets player_entity.grip_usage
func _update_brake_grab(delta: float):
	var front_brake = input_controller.nfx_front_brake

	if front_brake < 0.5:
		_brake_was_zero = true
		_brake_grab_timer = 0.0
		_brake_was_grabbed = false
	elif _brake_was_zero and front_brake > 0.1:
		_brake_was_zero = false
		_brake_grab_timer = 0.0
	elif not _brake_was_zero:
		_brake_grab_timer += delta
		if front_brake > 0.9 and not _brake_was_grabbed:
			_brake_was_grabbed = _brake_grab_timer < brake_grab_time_threshold

	# Compute brake danger (grip_usage) for HUD display
	var lean_ratio = abs(movement_controller.roll_angle) / deg_to_rad(crash_lean_threshold_deg)
	var max_safe_brake = 1.0 - (lean_ratio * brake_lean_sensitivity)
	if front_brake > 0.1:
		player_entity.grip_usage = clamp(front_brake / max(max_safe_brake, 0.01), 0.0, 1.0)
	else:
		player_entity.grip_usage = move_toward(player_entity.grip_usage, 0.0, 3.0 * delta)


func _detect_crash():
	var bd = player_entity.bike_definition

	# Wheelie crash
	if movement_controller.pitch_angle > deg_to_rad(bd.max_wheelie_angle_deg):
		print("wheelie crash")
		trigger_crash()
		return

	# Stoppie crash
	if movement_controller.pitch_angle < -deg_to_rad(bd.max_stoppie_angle_deg):
		print("stoppie crash")
		trigger_crash()
		return

	# Lean crash
	if abs(movement_controller.roll_angle) >= deg_to_rad(crash_lean_threshold_deg):
		print("lean crash")
		trigger_crash()
		return

	# Brake grab while turning
	if _brake_was_grabbed and abs(movement_controller.roll_angle) > deg_to_rad(15):
		print("brake grab crash")
		trigger_crash()


func trigger_crash():
	player_entity.is_crashed = true
	player_entity.velocity = Vector3.ZERO
	animation_controller.start_ragdoll()
	crashed.emit()

	# TODO - move logic to gamemode manager using crashed signal
	# Auto-respawn after delay
	get_tree().create_timer(3.0).timeout.connect(_auto_respawn)


func _auto_respawn():
	if player_entity.is_crashed:
		player_entity.rb_do_respawn = true


## Called from player_entity.gd's do_respawn
func do_reset():
	pass


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if animation_controller == null:
		issues.append("animation_controller must not be empty")
	if movement_controller == null:
		issues.append("movement_controller must not be empty")
	return issues
