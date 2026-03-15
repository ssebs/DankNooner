@tool
## Central API for all rider animation - procedural dynamics, polish animations, and tricks.
class_name AnimationController extends Node

signal state_changed(new_state: RiderState)

enum RiderState {
	RIDING,  # Procedural active, IK enabled
	IDLE,  # Procedural paused, playing idle anims
	TRICK,  # IK disabled, skeleton anim playing
	RAGDOLL,  # Everything disabled
}

@export var player_entity: PlayerEntity
@export var visual_root: Node3D
@export var character_skin: CharacterSkin
@export var bike_skin: BikeSkin
@export var movement_controller: MovementController
@export var input_controller: InputController

@export_tool_button("Init IK from Bike") var init_ik_btn = _editor_init_ik_from_bike
@export_tool_button("Save Default Pose") var save_pose_btn = _editor_save_default_pose
@export_tool_button("Play Default Pose") var reset_pose_btn = _editor_reset_to_default_pose

@export_group("Procedural Settings")
@export var idle_timeout: float = 3.0
@export var max_bike_pitch: float = 30.0  ## Max bike-only pitch in degrees

var current_state: RiderState = RiderState.RIDING:
	set(value):
		if current_state != value:
			current_state = value
			state_changed.emit(value)

#region Internal State
var _base_butt_pos: Vector3
var _base_chest_pos: Vector3
var _base_visual_root_rotation: Vector3
var _idle_timer: float = 0.0
var _procedural_enabled: bool = true
var _visual_lean: float = 0.0
var _visual_pitch: float = 0.0
var _visual_yaw: float = 0.0

#endregion


func _ready():
	if Engine.is_editor_hint():
		return


func _process(delta: float):
	if Engine.is_editor_hint():
		return
	if current_state != RiderState.RIDING:
		return
	if not _procedural_enabled:
		return

	_update_procedural_animation(delta)
	_update_idle_timer(delta)


#region Public API


## Initialize the animation controller. Call after IK targets are set.
func initialize() -> void:
	if character_skin == null or bike_skin == null or visual_root == null:
		printerr("AnimationController: Missing character_skin, bike_skin, or visual_root")
		return

	# Store base positions/rotations for offset calculations
	var ik_ctrl = character_skin.ik_controller
	if ik_ctrl:
		_base_butt_pos = ik_ctrl.butt_pos.position
		_base_chest_pos = ik_ctrl.ik_chest.position

	_base_visual_root_rotation = visual_root.rotation
	_visual_yaw = player_entity.rotation.y


## Enable or disable procedural animation
func set_procedural_enabled(enabled: bool) -> void:
	_procedural_enabled = enabled
	if enabled:
		_reset_to_base_positions()


## Play an idle animation (fidget, look around, etc.)
func play_idle_animation(anim_name: String) -> void:
	if current_state == RiderState.RAGDOLL:
		return
	_transition_to_idle()
	if character_skin.ik_anim_player:
		character_skin.ik_anim_player.play(anim_name)


## Play landing settle animation
func play_land_settle() -> void:
	if current_state == RiderState.RAGDOLL:
		return
	# TODO: Implement when IK animations are created


## Play a trick animation (full skeleton override)
func play_trick(trick_name: String) -> void:
	if current_state == RiderState.RAGDOLL:
		return
	_transition_to_trick()
	if character_skin.anim_player:
		character_skin.anim_player.play(trick_name)


## Cancel current trick and return to riding
func cancel_trick() -> void:
	if current_state != RiderState.TRICK:
		return
	_transition_to_riding()


## Start ragdoll mode
func start_ragdoll() -> void:
	current_state = RiderState.RAGDOLL
	character_skin.disable_ik()
	character_skin.start_ragdoll()


## Stop ragdoll and return to riding
func stop_ragdoll() -> void:
	character_skin.stop_ragdoll()
	character_skin.enable_ik()
	_reset_to_base_positions()
	current_state = RiderState.RIDING


#endregion

#region State Transitions


func _transition_to_riding() -> void:
	current_state = RiderState.RIDING
	character_skin.enable_ik()
	_procedural_enabled = true


func _transition_to_idle() -> void:
	current_state = RiderState.IDLE
	_procedural_enabled = false


func _transition_to_trick() -> void:
	current_state = RiderState.TRICK
	character_skin.disable_ik()
	_procedural_enabled = false


#endregion

#region Procedural Animation


func _update_procedural_animation(delta: float) -> void:
	var ik_ctrl = character_skin.ik_controller

	# Smooth toward physics values at render rate
	var smooth_speed := 10 * delta
	_visual_lean = lerpf(_visual_lean, player_entity.lean_angle, smooth_speed)
	_visual_pitch = lerpf(_visual_pitch, player_entity.pitch_angle, smooth_speed)

	# Smooth entity steering rotation at render rate (rollback restores physics value before ticks)
	_visual_yaw = lerp_angle(_visual_yaw, player_entity.rotation.y, smooth_speed)
	player_entity.rotation.y = _visual_yaw

	# Pitch visual_root for wheelie/stoppie
	visual_root.rotation.x = -clamp(
		_visual_pitch, -deg_to_rad(max_bike_pitch), deg_to_rad(max_bike_pitch)
	)

	# Rotate chest for visual lean
	ik_ctrl.ik_chest.rotation.y = _visual_lean * deg_to_rad(15)

	# Apply lean rotation to visual_root (rotates both bike + rider)
	visual_root.rotation.z = _base_visual_root_rotation.z + _visual_lean

	_update_wheelie_arm()


func _update_wheelie_arm() -> void:
	var anim_player = character_skin.ik_anim_player
	if anim_player == null:
		return
	var anim_name = "IK_anim_lib/wheelie_arm_drag"
	if not anim_player.has_animation(anim_name):
		return
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name)
	# Only extend arm when trick_mod held during a wheelie, otherwise return to default (t=0)
	var in_wheelie = player_entity.pitch_angle > 0.0
	var ratio = (
		clamp(player_entity.pitch_angle, 0.0, 1.0)
		if (in_wheelie and input_controller.nfx_trick_held)
		else 0.0
	)
	anim_player.seek(ratio, true)


func _update_idle_timer(delta: float) -> void:
	# Check if player is mostly stationary
	var is_idle = player_entity.speed < 1.0 and abs(input_controller.nfx_steer) < 0.1

	if is_idle:
		_idle_timer += delta
		if _idle_timer >= idle_timeout and current_state == RiderState.RIDING:
			# TODO: Play random idle animation when they exist
			# play_idle_animation("idle_fidget")
			pass
	else:
		_idle_timer = 0.0
		if current_state == RiderState.IDLE:
			_transition_to_riding()


func _reset_to_base_positions() -> void:
	var ik_ctrl = character_skin.ik_controller
	if ik_ctrl:
		ik_ctrl.butt_pos.position = _base_butt_pos
		ik_ctrl.ik_chest.position = _base_chest_pos
		ik_ctrl.ik_chest.rotation = Vector3.ZERO
	if visual_root:
		visual_root.rotation = _base_visual_root_rotation
	if bike_skin:
		bike_skin.rotation.x = 0.0
	player_entity.lean_angle = 0.0
	_visual_lean = 0.0
	_visual_pitch = 0.0
	_visual_yaw = player_entity.rotation.y


#endregion


#region Editor Tools
func _editor_init_ik_from_bike() -> void:
	if bike_skin == null or character_skin == null:
		printerr("AnimationController: bike_skin and character_skin must be set")
		return
	var def = bike_skin.skin_definition
	character_skin.set_ik_targets_for_bike(
		def.seat_marker_position, def.left_handlebar_marker_position, def.left_peg_marker_position
	)
	character_skin.enable_ik()


func _editor_save_default_pose() -> void:
	var ik_ctrl = character_skin.ik_controller
	var anim_player = character_skin.ik_anim_player
	if ik_ctrl == null or anim_player == null:
		printerr("AnimationController: missing ik_controller or ik_anim_player")
		return

	var lib_name = "IK_anim_lib"
	var anim_name = "default_pose"

	if not anim_player.has_animation_library(lib_name):
		printerr("AnimationController: animation library '%s' not found" % lib_name)
		return

	var lib: AnimationLibrary = anim_player.get_animation_library(lib_name)
	if not lib.has_animation(anim_name):
		lib.add_animation(anim_name, Animation.new())
	var anim: Animation = lib.get_animation(anim_name)
	anim.clear()
	anim.length = 0.1

	var markers := {
		"IKTargets/ButtPosition": ik_ctrl.butt_pos,
		"IKTargets/ChestTarget": ik_ctrl.ik_chest,
		"IKTargets/HeadTarget": ik_ctrl.ik_head,
		"IKTargets/LeftHand": ik_ctrl.ik_left_hand,
		"IKTargets/RightHand": ik_ctrl.ik_right_hand,
		"IKTargets/LeftArmMagnet": ik_ctrl.ik_left_arm_magnet,
		"IKTargets/RightArmMagnet": ik_ctrl.ik_right_arm_magnet,
		"IKTargets/LeftFoot": ik_ctrl.ik_left_foot,
		"IKTargets/RightFoot": ik_ctrl.ik_right_foot,
		"IKTargets/LeftLegMagnet": ik_ctrl.ik_left_leg_magnet,
		"IKTargets/RightLegMagnet": ik_ctrl.ik_right_leg_magnet,
	}

	for node_path in markers:
		_keyframe_marker(anim, node_path, markers[node_path])

	var err = ResourceSaver.save(lib)
	if err == OK:
		print("AnimationController: Saved default_pose to IK_anim_lib.res")
	else:
		printerr("AnimationController: Failed to save IK_anim_lib.res, error: ", err)


func _keyframe_marker(anim: Animation, node_path: String, marker: Marker3D) -> void:
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, node_path + ":position")
	anim.track_insert_key(pos_track, 0.0, marker.position)

	var rot_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, node_path + ":rotation")
	anim.track_insert_key(rot_track, 0.0, marker.rotation)


func _editor_reset_to_default_pose() -> void:
	var anim_player = character_skin.ik_anim_player
	if anim_player == null:
		printerr("AnimationController: missing ik_anim_player")
		return
	var full_name = "IK_anim_lib/default_pose"
	if not anim_player.has_animation(full_name):
		printerr("AnimationController: no default_pose saved - run Save Default Pose first")
		return
	anim_player.play(full_name)
	anim_player.seek(0.0, true)
	anim_player.stop()


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if visual_root == null:
		issues.append("visual_root must be set")
	if character_skin == null:
		issues.append("character_skin must be set")
	if bike_skin == null:
		issues.append("bike_skin must be set")
	if movement_controller == null:
		issues.append("movement_controller must be set")
	if input_controller == null:
		issues.append("input_controller must be set")
	return issues
