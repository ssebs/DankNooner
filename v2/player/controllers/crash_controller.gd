@tool
class_name CrashController extends Node

signal crashed

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var animation_controller: AnimationController
@export var movement_controller: MovementController

@export var is_sim_difficulty: bool = false
@export var crash_lean_threshold_deg: float = 80.0
@export var brake_grab_rate_threshold: float = 20
@export var brake_lean_sensitivity: float = 0.7

var _prev_front_brake: float = 0.0
var _brake_was_grabbed: bool = false

var _crash_min_speed: float = 10.0
var _crash_angle: float = 60.0


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

	var brake_delta = (front_brake - _prev_front_brake) / delta
	_prev_front_brake = front_brake

	if front_brake < 0.2:
		_brake_was_grabbed = false
	elif front_brake > 0.9 and brake_delta > brake_grab_rate_threshold:
		_brake_was_grabbed = true

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
		DebugUtils.DebugMsg("wheelie crash")
		trigger_crash()
		return

	# Stoppie crash
	if movement_controller.pitch_angle < -deg_to_rad(bd.max_stoppie_angle_deg):
		DebugUtils.DebugMsg("stoppie crash")
		trigger_crash()
		return

	# Lean crash
	if abs(movement_controller.roll_angle) >= deg_to_rad(crash_lean_threshold_deg):
		DebugUtils.DebugMsg("lean crash")
		trigger_crash()
		return

	# Upside-down landing — bike's up_direction vs global UP > 120°
	# Skip if riding a steep surface (loop) — inverted up_direction is expected there
	var bike_up_angle = player_entity.up_direction.angle_to(Vector3.UP)
	if bike_up_angle > deg_to_rad(120) and movement_controller.is_on_floor_netfox():
		var surface_angle = player_entity.get_floor_normal().angle_to(Vector3.UP)
		if surface_angle < deg_to_rad(45):
			DebugUtils.DebugMsg("upside-down crash (angle=%.1f°)" % rad_to_deg(bike_up_angle))
			trigger_crash()
			return

	# Collision with layer 2 obstacle — only head-on hits at speed
	if movement_controller.speed >= _crash_min_speed:
		for i in player_entity.get_slide_collision_count():
			var collision = player_entity.get_slide_collision(i)
			var collider = collision.get_collider()
			if collider is CollisionObject3D and collider.collision_layer & 2:
				var angle = rad_to_deg(
					collision.get_normal().angle_to(-player_entity.velocity.normalized())
				)
				if angle < _crash_angle:
					DebugUtils.DebugMsg("obstacle crash (angle=%.1f)" % angle)
					trigger_crash()
					return
				DebugUtils.DebugMsg("no crash (angle=%.1f)" % angle)

	# Brake grab while turning (sim difficulty + gamepad only)
	if (
		_brake_was_grabbed
		# and is_sim_difficulty
		and input_controller.is_gamepad
		and abs(movement_controller.roll_angle) > deg_to_rad(15)
	):
		DebugUtils.DebugMsg("brake grab crash")
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
	_prev_front_brake = 0.0
	_brake_was_grabbed = false


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
