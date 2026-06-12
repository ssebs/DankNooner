@tool
## Central API for all rider animation - procedural dynamics, polish animations, and tricks.
class_name AnimationController extends Node

signal state_changed(new_state: RiderState)

enum PlayMode {
	ONE_SHOT,  # play(anim, 1.0, false) — fires once, auto-fades when finished
	LOOP_WHILE_LATCHED,  # play(anim, 1.0, false) — same call as ONE_SHOT today; kept distinct for intent
	HOLD_WHILE_LATCHED,  # play_one_shot — settles + holds at end pose; pairs with reverse_on_end
}

enum RiderState {
	RIDING,  # Procedural active, IK enabled
	IDLE,  # Procedural paused, playing idle anims
	# TRICK,  # IK disabled, skeleton anim playing
	RAGDOLL,  # Everything disabled
}

@export var player_entity: PlayerEntity
@export var visual_root: Node3D
@export var character_skin: CharacterSkin
@export var bike_skin: BikeSkin
@export var movement_controller: MovementController
@export var trick_controller: TrickController
@export var input_controller: InputController
@export var ik_anim_player: AnimationPlayer

@export_tool_button("Init IK from Bike") var init_ik_btn = _editor_init_ik_from_bike
@export_tool_button("Save Default Pose") var save_pose_btn = _editor_save_default_pose
@export_tool_button("Play Default Pose") var reset_pose_btn = _editor_reset_to_default_pose

@export_group("Procedural Settings")
@export var idle_timeout: float = 0.1
@export var max_butt_offset := 0.12
## Max chest yaw (deg) when leaning into a turn — chest twists toward turn direction.
@export var max_chest_yaw_deg: float = 30.0
## Max chest pitch (deg) when leaning fwd/back. Negate to flip direction.
@export var max_chest_lean_pitch_deg: float = -15.0
## Max chest z shift when leaning fwd/back. Negate to flip direction.
@export var max_chest_z_offset: float = 0.2
## Max butt z shift when leaning fwd/back. Negate to flip direction.
@export var max_butt_z_offset: float = 0.1

# Animation track paths (relative to visual_root, which is anim root_node).
# Cached as NodePaths so CustomAnimPlayer.find_track lookups are cheap.
const _PATH_VISUAL_ROOT_ROT := ^":rotation"
const _PATH_BUTT_POS := ^"IKTargets/ButtTarget:position"
const _PATH_CHEST_POS := ^"IKTargets/ChestTarget:position"
const _PATH_CHEST_ROT := ^"IKTargets/ChestTarget:rotation"
const _PATH_HEAD_POS := ^"IKTargets/HeadTarget:position"
const _PATH_HEAD_ROT := ^"IKTargets/HeadTarget:rotation"
const _PATH_LHAND_POS := ^"IKTargets/LeftHandTarget:position"
const _PATH_LHAND_ROT := ^"IKTargets/LeftHandTarget:rotation"
const _PATH_RHAND_POS := ^"IKTargets/RightHandTarget:position"
const _PATH_RHAND_ROT := ^"IKTargets/RightHandTarget:rotation"
const _PATH_LFOOT_POS := ^"IKTargets/LeftFootTarget:position"
const _PATH_LFOOT_ROT := ^"IKTargets/LeftFootTarget:rotation"
const _PATH_RFOOT_POS := ^"IKTargets/RightFootTarget:position"
const _PATH_RFOOT_ROT := ^"IKTargets/RightFootTarget:rotation"
const _PATH_LARM_MAGNET_POS := ^"IKTargets/LeftArmMagnet:position"
const _PATH_LARM_MAGNET_ROT := ^"IKTargets/LeftArmMagnet:rotation"
const _PATH_RARM_MAGNET_POS := ^"IKTargets/RightArmMagnet:position"
const _PATH_RARM_MAGNET_ROT := ^"IKTargets/RightArmMagnet:rotation"
const _PATH_LLEG_MAGNET_POS := ^"IKTargets/LeftLegMagnet:position"
const _PATH_LLEG_MAGNET_ROT := ^"IKTargets/LeftLegMagnet:rotation"
const _PATH_RLEG_MAGNET_POS := ^"IKTargets/RightLegMagnet:position"
const _PATH_RLEG_MAGNET_ROT := ^"IKTargets/RightLegMagnet:rotation"

## Allowlist of track paths handled by the additive pose pipeline. Any track in a played
## animation whose path is NOT in this set is auto-applied raw to its node by
## CustomAnimPlayer.apply_to_nodes — animators can drop new tracks (VFX emitting flags,
## particle positions, materials, etc.) without touching this file.
const _POSE_PIPELINE_PATHS := {
	_PATH_VISUAL_ROOT_ROT: true,
	_PATH_BUTT_POS: true,
	_PATH_CHEST_POS: true,
	_PATH_CHEST_ROT: true,
	_PATH_HEAD_POS: true,
	_PATH_HEAD_ROT: true,
	_PATH_LHAND_POS: true,
	_PATH_LHAND_ROT: true,
	_PATH_RHAND_POS: true,
	_PATH_RHAND_ROT: true,
	_PATH_LFOOT_POS: true,
	_PATH_LFOOT_ROT: true,
	_PATH_RFOOT_POS: true,
	_PATH_RFOOT_ROT: true,
	_PATH_LARM_MAGNET_POS: true,
	_PATH_LARM_MAGNET_ROT: true,
	_PATH_RARM_MAGNET_POS: true,
	_PATH_RARM_MAGNET_ROT: true,
	_PATH_LLEG_MAGNET_POS: true,
	_PATH_LLEG_MAGNET_ROT: true,
	_PATH_RLEG_MAGNET_POS: true,
	_PATH_RLEG_MAGNET_ROT: true,
}

var current_state: RiderState = RiderState.RIDING:
	set(value):
		if current_state != value:
			current_state = value
			state_changed.emit(value)

#region Internal State
var _base_butt_pos: Vector3
var _base_chest_pos: Vector3
var _base_chest_rot: Vector3
var _base_visual_root_position: Vector3
var _base_visual_root_rotation: Vector3
# visual_root's rest transform is structural (scene default), not bike-dependent. Capture it
# once — re-capturing in a later initialize() (e.g. update_skins during a crash/wheelie) would
# bake the displaced live position in as the "base" and permanently offset the bike.
var _visual_root_base_captured: bool = false
var _base_left_arm_magnet_pos: Vector3
var _base_left_arm_magnet_rot: Vector3
var _base_right_arm_magnet_pos: Vector3
var _base_right_arm_magnet_rot: Vector3
var _base_left_leg_magnet_pos: Vector3
var _base_left_leg_magnet_rot: Vector3
var _base_right_leg_magnet_pos: Vector3
var _base_right_leg_magnet_rot: Vector3
var _idle_timer: float = 0.0
var _procedural_enabled: bool = true
var _targets_synced_from_bike: bool = true

# Cached refs (set in initialize)
var _ik_ctrl: IKController
var _bd: BikeSkinDefinition
var _anim_runner: CustomAnimPlayer
var _idle_anim: Animation
var _idle_layer: CustomAnimPlayer.Layer
# Trick anims live in _trick_entries (built in initialize()). To add a trick,
# append one row to _build_trick_entries() — see PLAN-animcontroller-refac.md.
var _trick_entries: Array = []
var _trick_by_enum: Dictionary = {}
var _back_up_start_anim: Animation
var _back_up_loop_anim: Animation
var _back_up_start_layer: CustomAnimPlayer.Layer
var _back_up_loop_layer: CustomAnimPlayer.Layer
var _was_reversing: bool = false

# Proc pose carried between frames (no anim deltas applied). Keeping this separate
# from what gets committed to the nodes prevents anim-delta drift across frames —
# the lerps inside proc need their own continuous state to read from.
var _proc_pose: _RiderPose

#endregion


func _ready():
	if Engine.is_editor_hint():
		call_deferred("_editor_auto_init")
		return


func _process(delta: float):
	if Engine.is_editor_hint():
		# Proxies are owned by the editor / AnimationPlayer — never auto-sync in editor.
		return
	if not _procedural_enabled:
		return

	match current_state:
		RiderState.IDLE:
			_update_idle(delta)
		RiderState.RIDING:
			_update_riding(delta)
		RiderState.RAGDOLL:
			pass


#region Procedural Animation — pose pipeline
## Each frame builds a _RiderPose, runs it through proc → anim deltas → commit.
## Proc/anim never write directly to nodes; only _commit_pose() does.


func _update_idle(delta: float) -> void:
	var pose := _next_proc_pose()
	# Ease wheelie/stoppie pitch back to 0 so the bike settles to ground.
	var blend = clampf(5.0 * delta, 0.0, 1.0)
	pose.visual_root_rot.x = lerp_angle(pose.visual_root_rot.x, 0.0, blend)

	_apply_riding_common(pose, delta, blend, movement_controller.roll_angle)

	_apply_pivot_offset_to_pose(pose)
	_proc_pose = pose
	var final_pose := pose.duplicate()
	_apply_anim_deltas(final_pose, delta)
	_commit_pose(final_pose)
	_anim_runner.apply_to_nodes(player_entity, _POSE_PIPELINE_PATHS)
	_update_idle_timer(delta)


func _update_riding(delta: float) -> void:
	var blend := clampf(5.0 * delta, 0.0, 1.0)
	var roll := movement_controller.roll_angle
	var pitch := movement_controller.pitch_angle

	var pose := _next_proc_pose()
	if _targets_synced_from_bike:
		_apply_bike_to_pose(pose)

	# Reversing: handlebars still turn (driven by roll_angle via bike_skin.rotate_steering
	# below) and the body rotates in _steer_calc, but suppress visual lean / chest yaw /
	# weight shift so the bike stays upright.
	var pose_roll := 0.0 if movement_controller.is_reversing else roll
	_apply_riding_common(pose, delta, blend, pose_roll)

	if not movement_controller._is_on_floor:
		_apply_pitch_air(pose, blend, pitch)
	else:
		_apply_pitch_ground(pose, blend, pitch)

	_apply_pivot_offset_to_pose(pose)

	# Steering + wheels run direct on bike_skin — they're not part of the rider pose.
	# Reverse inverts roll_angle (so the body rotates the correct way for input), but the
	# handlebars should still visually point in the input direction — un-invert here.
	var steer_input := roll if _targets_synced_from_bike else 0.0
	if movement_controller.is_reversing:
		steer_input = -steer_input
	bike_skin.rotate_steering(steer_input, delta)
	bike_skin.rotate_wheels(movement_controller.speed, delta, trick_controller.is_in_wheelie())

	_update_reverse_anim()

	# Snapshot proc-only state for next frame, then layer anim deltas onto a copy.
	_proc_pose = pose
	var final_pose := pose.duplicate()
	_apply_anim_deltas(final_pose, delta)
	_commit_pose(final_pose)
	_anim_runner.apply_to_nodes(player_entity, _POSE_PIPELINE_PATHS)

	_update_idle_timer(delta)


## Returns the proc pose to mutate this frame. Carries proc state across frames so
## lerps are continuous; anim deltas are NOT in here (they're layered after).
## First call seeds from authored defaults / current bike-derived hand-foot positions.
func _next_proc_pose() -> _RiderPose:
	if _proc_pose != null:
		return _proc_pose.duplicate()
	var pose := _RiderPose.new()
	pose.visual_root_pos = _base_visual_root_position
	pose.visual_root_rot = _base_visual_root_rotation
	pose.butt_pos = _base_butt_pos
	pose.chest_pos = _base_chest_pos
	pose.chest_rot = _base_chest_rot
	pose.head_pos = player_entity.head_target.position
	pose.head_rot = player_entity.head_target.rotation
	pose.left_hand_pos = player_entity.left_hand_target.position
	pose.left_hand_rot = player_entity.left_hand_target.rotation
	pose.right_hand_pos = player_entity.right_hand_target.position
	pose.right_hand_rot = player_entity.right_hand_target.rotation
	pose.left_foot_pos = player_entity.left_foot_target.position
	pose.left_foot_rot = player_entity.left_foot_target.rotation
	pose.right_foot_pos = player_entity.right_foot_target.position
	pose.right_foot_rot = player_entity.right_foot_target.rotation
	return pose


## Compute hand/foot local transforms from BikeSkinDefinition + handlebar/peg parents,
## then convert into IKTargets-parent local space (the marker's parent), so anim deltas
## (which are local) layer cleanly on top.
func _apply_bike_to_pose(pose: _RiderPose) -> void:
	var hb_parent := bike_skin.steering_handlebar_marker.get_parent() as Node3D
	var peg_parent: Node3D = bike_skin
	var def: BikeSkinDefinition = _bd if _bd else bike_skin.skin_definition
	if def == null:
		return

	_set_pose_local_from_bike(
		pose, "left_hand", hb_parent, def.left_hand_position, def.left_hand_rotation
	)
	_set_pose_local_from_bike(
		pose, "right_hand", hb_parent, def.right_hand_position, def.right_hand_rotation
	)
	_set_pose_local_from_bike(
		pose, "left_foot", peg_parent, def.left_foot_position, def.left_foot_rotation
	)
	_set_pose_local_from_bike(
		pose, "right_foot", peg_parent, def.right_foot_position, def.right_foot_rotation
	)


## Helper: write `<key>_pos`/`<key>_rot` on pose, converted from the bike's parent space
## (handlebar parent for hands, bike_skin for feet) into the marker's own parent space.
func _set_pose_local_from_bike(
	pose: _RiderPose, key: String, bike_parent: Node3D, local_pos: Vector3, local_rot: Vector3
) -> void:
	var bike_global := (
		bike_parent.global_transform * Transform3D(Basis.from_euler(local_rot), local_pos)
	)
	# Marker's actual parent — IKTargets node — is what marker.position/.rotation are relative to.
	var marker: Node3D = player_entity.get(key + "_target")
	var marker_parent := marker.get_parent() as Node3D
	var local := marker_parent.global_transform.affine_inverse() * bike_global
	pose.set(key + "_pos", local.origin)
	pose.set(key + "_rot", local.basis.get_euler())


## Lean (Z), chest yaw, butt/chest X+Z weight shift. Reads + writes pose only —
## NEVER touch the live nodes here, they hold post-anim values from last frame.
func _apply_riding_common(pose: _RiderPose, _delta: float, blend: float, roll: float) -> void:
	pose.visual_root_rot.z = lerpf(pose.visual_root_rot.z, roll, blend)

	var target_chest_y = roll * deg_to_rad(max_chest_yaw_deg)
	pose.chest_rot.y = lerpf(pose.chest_rot.y, target_chest_y, blend)

	var lean_x_offset = clampf(pose.visual_root_rot.z, -max_butt_offset, max_butt_offset)
	pose.butt_pos.x = lerpf(pose.butt_pos.x, _base_butt_pos.x - lean_x_offset, blend)
	pose.chest_pos.x = lerpf(pose.chest_pos.x, _base_chest_pos.x - lean_x_offset, blend)

	var lean_input = input_controller.nfx_lean
	var target_chest_pitch = _base_chest_rot.x - lean_input * deg_to_rad(max_chest_lean_pitch_deg)
	pose.chest_rot.x = lerpf(pose.chest_rot.x, target_chest_pitch, blend)
	pose.chest_pos.z = lerpf(
		pose.chest_pos.z, _base_chest_pos.z + lean_input * max_chest_z_offset, blend
	)
	pose.butt_pos.z = lerpf(
		pose.butt_pos.z, _base_butt_pos.z + lean_input * max_butt_z_offset, blend
	)


func _apply_pitch_ground(pose: _RiderPose, blend: float, pitch: float) -> void:
	enable_target_sync()
	var max_wheelie_rad = deg_to_rad(_bd.max_wheelie_angle_deg)
	var max_stoppie_rad = deg_to_rad(_bd.max_stoppie_angle_deg)
	var target = -clampf(pitch, -max_stoppie_rad, max_wheelie_rad)
	pose.visual_root_rot.x = lerp_angle(pose.visual_root_rot.x, target, blend)


func _apply_pitch_air(pose: _RiderPose, blend: float, pitch: float) -> void:
	disable_target_sync()
	pose.visual_root_rot.x = lerp_angle(pose.visual_root_rot.x, -pitch, blend)


## Pivot visual_root around the tire contact arc — same logic as before but writes
## into pose.visual_root_pos rather than the node directly.
##
## Pivot wheel is picked by the SIGN of rot_x, not by trick state. _apply_pitch_ground
## maps wheelie target → negative rot_x and stoppie target → positive rot_x, so sign
## always matches the visible rotation. Picking by trick state instead caused under-ground
## clipping during wheelie↔stoppie transitions: trick flips instantly but rot_x lerps,
## so for ~0.2s the wrong wheel pivots through the ground.
func _apply_pivot_offset_to_pose(pose: _RiderPose) -> void:
	var rot_x := pose.visual_root_rot.x
	var pitch_ratio = clampf(absf(rot_x) / (PI / 2.0), 0.0, 1.0)
	var use_rear := rot_x < 0.0

	var pivot: Vector3
	if use_rear:
		pivot = _bd.rear_wheel_ground_position.lerp(_bd.rear_wheel_back_position, pitch_ratio)
	else:
		pivot = _bd.front_wheel_ground_position.lerp(_bd.front_wheel_front_position, pitch_ratio)
	var rotated_pivot = Basis(Vector3.RIGHT, rot_x) * pivot
	pose.visual_root_pos = _base_visual_root_position + pivot - rotated_pivot


## Sample every active CustomAnimPlayer layer, add its delta-from-default into the pose.
## Anim tracks key local position/rotation, so deltas just sum into pose fields.
func _apply_anim_deltas(pose: _RiderPose, delta: float) -> void:
	_anim_runner.tick(delta)
	if _anim_runner.get_layers().is_empty():
		return
	pose.visual_root_rot += _anim_runner.sample_vec3(_PATH_VISUAL_ROOT_ROT)
	pose.butt_pos += _anim_runner.sample_vec3(_PATH_BUTT_POS)
	pose.chest_pos += _anim_runner.sample_vec3(_PATH_CHEST_POS)
	pose.chest_rot += _anim_runner.sample_vec3(_PATH_CHEST_ROT)
	pose.head_pos += _anim_runner.sample_vec3(_PATH_HEAD_POS)
	pose.head_rot += _anim_runner.sample_vec3(_PATH_HEAD_ROT)
	pose.left_hand_pos += _anim_runner.sample_vec3(_PATH_LHAND_POS)
	pose.left_hand_rot += _anim_runner.sample_vec3(_PATH_LHAND_ROT)
	pose.right_hand_pos += _anim_runner.sample_vec3(_PATH_RHAND_POS)
	pose.right_hand_rot += _anim_runner.sample_vec3(_PATH_RHAND_ROT)
	pose.left_foot_pos += _anim_runner.sample_vec3(_PATH_LFOOT_POS)
	pose.left_foot_rot += _anim_runner.sample_vec3(_PATH_LFOOT_ROT)
	pose.right_foot_pos += _anim_runner.sample_vec3(_PATH_RFOOT_POS)
	pose.right_foot_rot += _anim_runner.sample_vec3(_PATH_RFOOT_ROT)


## Single point of contact with the actual nodes.
func _commit_pose(pose: _RiderPose) -> void:
	visual_root.position = pose.visual_root_pos
	visual_root.rotation = pose.visual_root_rot
	_ik_ctrl.butt_pos.position = pose.butt_pos
	player_entity.chest_target.position = pose.chest_pos
	player_entity.chest_target.rotation = pose.chest_rot
	player_entity.head_target.position = pose.head_pos
	player_entity.head_target.rotation = pose.head_rot
	player_entity.left_hand_target.position = pose.left_hand_pos
	player_entity.left_hand_target.rotation = pose.left_hand_rot
	player_entity.right_hand_target.position = pose.right_hand_pos
	player_entity.right_hand_target.rotation = pose.right_hand_rot
	player_entity.left_foot_target.position = pose.left_foot_pos
	player_entity.left_foot_target.rotation = pose.left_foot_rot
	player_entity.right_foot_target.position = pose.right_foot_pos
	player_entity.right_foot_target.rotation = pose.right_foot_rot
	# Magnets — no procedural state, just base + anim delta
	player_entity.left_arm_magnet.position = (
		_base_left_arm_magnet_pos + _anim_runner.sample_vec3(_PATH_LARM_MAGNET_POS)
	)
	player_entity.left_arm_magnet.rotation = (
		_base_left_arm_magnet_rot + _anim_runner.sample_vec3(_PATH_LARM_MAGNET_ROT)
	)
	player_entity.right_arm_magnet.position = (
		_base_right_arm_magnet_pos + _anim_runner.sample_vec3(_PATH_RARM_MAGNET_POS)
	)
	player_entity.right_arm_magnet.rotation = (
		_base_right_arm_magnet_rot + _anim_runner.sample_vec3(_PATH_RARM_MAGNET_ROT)
	)
	player_entity.left_leg_magnet.position = (
		_base_left_leg_magnet_pos + _anim_runner.sample_vec3(_PATH_LLEG_MAGNET_POS)
	)
	player_entity.left_leg_magnet.rotation = (
		_base_left_leg_magnet_rot + _anim_runner.sample_vec3(_PATH_LLEG_MAGNET_ROT)
	)
	player_entity.right_leg_magnet.position = (
		_base_right_leg_magnet_pos + _anim_runner.sample_vec3(_PATH_RLEG_MAGNET_POS)
	)
	player_entity.right_leg_magnet.rotation = (
		_base_right_leg_magnet_rot + _anim_runner.sample_vec3(_PATH_RLEG_MAGNET_ROT)
	)


## Drive back_up_start + back_up_loop layers off movement_controller.is_reversing.
## Enter: play start one-shot (settles + holds). Once it finishes, layer the loop on top.
## Exit: stop the loop (fades), reverse-play the start back to t=0 (auto-fades).
func _update_reverse_anim() -> void:
	var reversing := movement_controller.is_reversing
	if reversing and not _was_reversing:
		if _back_up_start_anim:
			_back_up_start_layer = _anim_runner.play_one_shot(_back_up_start_anim, 1.0)
	elif not reversing and _was_reversing:
		if _back_up_loop_layer != null and _back_up_loop_layer.is_playing():
			_anim_runner.stop(_back_up_loop_layer)
			_back_up_loop_layer = null
		if _back_up_start_layer != null and _back_up_start_layer.is_playing():
			_back_up_start_layer.speed = -1.0
			_back_up_start_layer.hold_at_end = false
			_back_up_start_layer.target_weight = 1.0

	# While reversing, kick off the loop once the start anim has settled.
	if reversing and _back_up_loop_anim and _back_up_start_layer != null:
		var loop_running := _back_up_loop_layer != null and _back_up_loop_layer.is_playing()
		if not loop_running and _back_up_start_layer.time >= _back_up_start_layer.get_duration():
			_back_up_loop_layer = _anim_runner.play(_back_up_loop_anim, 1.0, true)

	_was_reversing = reversing


func _update_idle_timer(delta: float) -> void:
	# Reversing keeps us in RIDING — idle anim would fight the back_up pose.
	if movement_controller.is_reversing:
		_idle_timer = 0.0
		if current_state == RiderState.IDLE:
			_transition_to_riding()
		return
	# Check if player is mostly stationary
	if movement_controller.speed < 0.5 and abs(input_controller.nfx_steer) < 0.1:
		_idle_timer += delta
		if _idle_timer >= idle_timeout and current_state == RiderState.RIDING:
			_transition_to_idle()
	else:
		_idle_timer = 0.0
		if current_state == RiderState.IDLE:
			_transition_to_riding()


func _reset_to_base_positions() -> void:
	_ik_ctrl.butt_pos.position = _base_butt_pos
	player_entity.chest_target.position = _base_chest_pos
	player_entity.chest_target.rotation = _base_chest_rot
	visual_root.position = _base_visual_root_position
	visual_root.rotation = _base_visual_root_rotation
	bike_skin.rotation.x = 0.0


#endregion

#region Public API


## Initialize the animation controller. Call after IK targets are set.
func initialize() -> void:
	# Required exports validated via _get_configuration_warnings()
	_ik_ctrl = character_skin.ik_controller
	_bd = player_entity.bike_definition

	_base_butt_pos = _ik_ctrl.butt_pos.position
	_base_chest_pos = player_entity.chest_target.position
	_base_chest_rot = player_entity.chest_target.rotation
	if not _visual_root_base_captured:
		_base_visual_root_position = visual_root.position
		_base_visual_root_rotation = visual_root.rotation
		_visual_root_base_captured = true
	_base_left_arm_magnet_pos = player_entity.left_arm_magnet.position
	_base_left_arm_magnet_rot = player_entity.left_arm_magnet.rotation
	_base_right_arm_magnet_pos = player_entity.right_arm_magnet.position
	_base_right_arm_magnet_rot = player_entity.right_arm_magnet.rotation
	_base_left_leg_magnet_pos = player_entity.left_leg_magnet.position
	_base_left_leg_magnet_rot = player_entity.left_leg_magnet.rotation
	_base_right_leg_magnet_pos = player_entity.right_leg_magnet.position
	_base_right_leg_magnet_rot = player_entity.right_leg_magnet.rotation

	ik_anim_player.root_node = ik_anim_player.get_path_to(visual_root)

	# CustomAnimPlayer is created lazily so editor + runtime share the same setup.
	if _anim_runner == null:
		_anim_runner = CustomAnimPlayer.new()
		_anim_runner.name = "AnimRunner"
		add_child(_anim_runner)
	# Cache anims off the existing AnimationPlayer's library — keeps editor authoring intact.
	if ik_anim_player.has_animation("idle"):
		_idle_anim = ik_anim_player.get_animation("idle")
		_fixup_anim_paths(_idle_anim)
	_build_trick_entries()
	for entry in _trick_entries:
		if ik_anim_player.has_animation(entry.anim_name):
			entry.anim = ik_anim_player.get_animation(entry.anim_name)
			_fixup_anim_paths(entry.anim)
		_trick_by_enum[entry.trick] = entry
	if ik_anim_player.has_animation("back_up_start"):
		_back_up_start_anim = ik_anim_player.get_animation("back_up_start")
		_fixup_anim_paths(_back_up_start_anim)
	if ik_anim_player.has_animation("back_up_loop"):
		_back_up_loop_anim = ik_anim_player.get_animation("back_up_loop")
		_fixup_anim_paths(_back_up_loop_anim)

	if not trick_controller.trick_started.is_connected(_on_trick_started):
		trick_controller.trick_started.connect(_on_trick_started)
		trick_controller.trick_ended.connect(_on_trick_ended)

	_sync_targets_from_bike()


## Rewrite `%UniqueName:property` track paths to `IKTargets/UniqueName:property` so
## CustomAnimPlayer.find_track (exact match against _PATH_* constants) resolves them.
## All IK markers live under VisualRoot/IKTargets, so the rewrite is mechanical.
func _fixup_anim_paths(anim: Animation) -> void:
	for i in anim.get_track_count():
		var path_str := String(anim.track_get_path(i))
		if path_str.begins_with("%"):
			anim.track_set_path(i, NodePath("IKTargets/" + path_str.substr(1)))


func _on_trick_started(trick_type: TrickController.Trick) -> void:
	var entry: _TrickAnimEntry = _trick_by_enum.get(trick_type)
	if entry == null or entry.anim == null:
		return
	match entry.play_mode:
		PlayMode.HOLD_WHILE_LATCHED:
			# Settle into pose, hold while latched. If a reverse-out is mid-flight (re-entry
			# during the unwind), flip it back to forward instead of starting a new layer.
			if entry.layer != null and entry.layer.is_playing():
				entry.layer.speed = 1.0
				entry.layer.hold_at_end = true
				entry.layer.target_weight = 1.0
			else:
				entry.layer = _anim_runner.play_one_shot(entry.anim, 1.0)
		_:
			# ONE_SHOT / LOOP_WHILE_LATCHED both call play(); trick_ended doesn't stop them,
			# so the anim plays through fully and auto-fades at end.
			if entry.layer == null or not entry.layer.is_playing():
				entry.layer = _anim_runner.play(entry.anim, 1.0, false)


func _on_trick_ended(trick_type: TrickController.Trick) -> void:
	var entry: _TrickAnimEntry = _trick_by_enum.get(trick_type)
	if entry == null or not entry.reverse_on_end:
		return
	# Reverse from current time back to 0 — rider unwinds out of the pose smoothly.
	# When time hits 0, hold_at_end=false makes the layer auto-fade and clear itself.
	if entry.layer != null and entry.layer.is_playing():
		entry.layer.speed = -1.0
		entry.layer.hold_at_end = false
		entry.layer.target_weight = 1.0


## Sync hand/foot target transforms from saved positions/rotations in BikeSkinDefinition,
## anchored to the steering handlebar's parent (so steering rotates the hands) and bike_skin
## (for feet). Called every tick while target sync is enabled.
func _sync_targets_from_bike() -> void:
	var hb_parent := bike_skin.steering_handlebar_marker.get_parent() as Node3D
	var peg_parent: Node3D = bike_skin
	# In editor, _bd may not be initialized yet — fall back to skin's own definition.
	var def: BikeSkinDefinition = _bd if _bd else bike_skin.skin_definition
	if def == null:
		return

	var left_hand_local := Transform3D(
		Basis.from_euler(def.left_hand_rotation), def.left_hand_position
	)
	var right_hand_local := Transform3D(
		Basis.from_euler(def.right_hand_rotation), def.right_hand_position
	)
	var left_foot_local := Transform3D(
		Basis.from_euler(def.left_foot_rotation), def.left_foot_position
	)
	var right_foot_local := Transform3D(
		Basis.from_euler(def.right_foot_rotation), def.right_foot_position
	)

	player_entity.left_hand_target.global_transform = hb_parent.global_transform * left_hand_local
	player_entity.right_hand_target.global_transform = hb_parent.global_transform * right_hand_local
	player_entity.left_foot_target.global_transform = peg_parent.global_transform * left_foot_local
	player_entity.right_foot_target.global_transform = (
		peg_parent.global_transform * right_foot_local
	)


## Enable or disable procedural animation
func set_procedural_enabled(enabled: bool) -> void:
	_procedural_enabled = enabled
	if enabled:
		_reset_to_base_positions()
		_proc_pose = null  # reseed from defaults next tick


## Hand ownership of the hand/foot targets back to procedural riding. Next tick's
## _sync_targets_from_bike() snaps them to the bike's handlebar/peg positions.
func enable_target_sync() -> void:
	_targets_synced_from_bike = true


## Release the hand/foot targets so an AnimationPlayer track can drive their transforms.
## Sync is skipped while disabled.
func disable_target_sync() -> void:
	_targets_synced_from_bike = false


## Start ragdoll mode
func start_ragdoll(launch_impulse: Vector3 = Vector3.ZERO) -> void:
	current_state = RiderState.RAGDOLL
	# RAGDOLL stops the pose pipeline (_process is `pass`), so any anim layer
	# mid-flight freezes — including non-pose tracks like spark `:emitting`
	# flags that latch true→false. Rewind to t=0 + apply, then drop.
	if _anim_runner:
		_anim_runner.stop_all_and_reset(player_entity, _POSE_PIPELINE_PATHS)
	_idle_layer = null
	for entry in _trick_entries:
		entry.layer = null
	_back_up_start_layer = null
	_back_up_loop_layer = null
	_was_reversing = false
	character_skin.disable_ik()
	character_skin.start_ragdoll(launch_impulse)


## Stop ragdoll and return to riding
func stop_ragdoll() -> void:
	character_skin.stop_ragdoll()
	character_skin.enable_ik()
	_reset_to_base_positions()
	_proc_pose = null
	current_state = RiderState.RIDING


## Called from player_entity.gd's do_respawn
func do_reset():
	# Flush any active anim layers (heel clicker, idle, etc.) so a crash mid-trick
	# doesn't leave deltas baked into the respawn pose.
	if _anim_runner:
		_anim_runner.stop_all()
	_idle_layer = null
	for entry in _trick_entries:
		entry.layer = null
	_back_up_start_layer = null
	_back_up_loop_layer = null
	_was_reversing = false
	_proc_pose = null


#endregion


#region State Transitions
func _transition_to_riding() -> void:
	DebugUtils.DebugMsg("_transition_to_riding")
	if _idle_layer != null and _idle_layer.is_playing():
		_anim_runner.stop(_idle_layer)
		_idle_layer = null
	current_state = RiderState.RIDING
	character_skin.enable_ik()
	enable_target_sync()


func _transition_to_idle() -> void:
	current_state = RiderState.IDLE
	_procedural_enabled = true
	disable_target_sync()
	if _idle_anim:
		# One-shot, holds the end pose. _transition_to_riding fades it out.
		_idle_layer = _anim_runner.play_one_shot(_idle_anim, 1.0)


#endregion


#region Editor Tools
func _editor_auto_init() -> void:
	# Silent skip during editor scene load when exports aren't wired yet.
	if not _editor_refs_ready():
		return
	_editor_init_ik_from_bike()


func _editor_refs_ready() -> bool:
	return (
		bike_skin != null
		and character_skin != null
		and player_entity != null
		and character_skin.ik_controller != null
	)


func _editor_init_ik_from_bike() -> void:
	if not _editor_refs_ready():
		(
			DebugUtils
			. DebugErrMsg(
				"AnimationController: bike_skin, character_skin, player_entity, and IKController must be set"
			)
		)
		return

	var ik_ctrl = character_skin.ik_controller
	var def = bike_skin.skin_definition

	if ik_anim_player:
		ik_anim_player.stop()

	# Position butt from definition
	player_entity.butt_target.position = def.seat_marker_position

	# Pass all markers to IKController
	ik_ctrl.set_targets(
		player_entity.butt_target,
		player_entity.left_hand_target,
		player_entity.right_hand_target,
		player_entity.left_foot_target,
		player_entity.right_foot_target,
		player_entity.chest_target,
		player_entity.head_target,
		player_entity.left_arm_magnet,
		player_entity.right_arm_magnet,
		player_entity.left_leg_magnet,
		player_entity.right_leg_magnet
	)

	_sync_targets_from_bike()

	# Load rider pose from definition. ZERO means "not yet authored" — skip those.
	if def.chest_position != Vector3.ZERO:
		player_entity.chest_target.position = def.chest_position
	if def.chest_rotation != Vector3.ZERO:
		player_entity.chest_target.rotation = def.chest_rotation
	if def.head_position != Vector3.ZERO:
		player_entity.head_target.position = def.head_position
	if def.head_rotation != Vector3.ZERO:
		player_entity.head_target.rotation = def.head_rotation
	if def.left_arm_magnet_position != Vector3.ZERO:
		player_entity.left_arm_magnet.position = def.left_arm_magnet_position
	if def.right_arm_magnet_position != Vector3.ZERO:
		player_entity.right_arm_magnet.position = def.right_arm_magnet_position
	if def.left_leg_magnet_position != Vector3.ZERO:
		player_entity.left_leg_magnet.position = def.left_leg_magnet_position
	if def.right_leg_magnet_position != Vector3.ZERO:
		player_entity.right_leg_magnet.position = def.right_leg_magnet_position

	_load_wheel_markers_from_definition(def)

	ik_ctrl._create_ik()
	character_skin.enable_ik()
	disable_target_sync()


## Position the editor wheel-authoring markers from .tres values so the user sees current state.
func _load_wheel_markers_from_definition(def: BikeSkinDefinition) -> void:
	if player_entity.front_wheel_ground_marker:
		player_entity.front_wheel_ground_marker.position = def.front_wheel_ground_position
	if player_entity.rear_wheel_ground_marker:
		player_entity.rear_wheel_ground_marker.position = def.rear_wheel_ground_position
	if player_entity.front_wheel_front_marker:
		player_entity.front_wheel_front_marker.position = def.front_wheel_front_position
	if player_entity.rear_wheel_back_marker:
		player_entity.rear_wheel_back_marker.position = def.rear_wheel_back_position


## Inverse of _local_with_rotation_override: extract the euler that, when plugged into
## Basis.from_euler() and multiplied by parent.global.basis, reproduces marker.global.basis.
static func _rotation_in_parent_space(marker: Node3D, parent: Node3D) -> Vector3:
	var parent_basis := parent.global_transform.basis.orthonormalized()
	var marker_basis := marker.global_transform.basis.orthonormalized()
	return (parent_basis.inverse() * marker_basis).get_euler()


## Express marker.global.origin in parent's local space, so that
## parent.global_transform * Transform3D(_, returned_position) reproduces marker.global.origin.
static func _position_in_parent_space(marker: Node3D, parent: Node3D) -> Vector3:
	return parent.global_transform.affine_inverse() * marker.global_transform.origin


func _editor_save_default_pose() -> void:
	var def = bike_skin.skin_definition
	if def == null:
		DebugUtils.DebugErrMsg("AnimationController: missing bike_skin definition")
		return

	def.chest_position = player_entity.chest_target.position
	def.chest_rotation = player_entity.chest_target.rotation
	def.head_position = player_entity.head_target.position
	def.head_rotation = player_entity.head_target.rotation
	def.left_arm_magnet_position = player_entity.left_arm_magnet.position
	def.right_arm_magnet_position = player_entity.right_arm_magnet.position
	def.left_leg_magnet_position = player_entity.left_leg_magnet.position
	def.right_leg_magnet_position = player_entity.right_leg_magnet.position
	# Save butt position as seat marker
	def.seat_marker_position = player_entity.butt_target.position

	# Hand/foot rotations in bike marker parent space
	var hb_parent := bike_skin.steering_handlebar_marker.get_parent() as Node3D
	var peg_parent: Node3D = bike_skin

	if player_entity.left_hand_target:
		def.left_hand_position = _position_in_parent_space(
			player_entity.left_hand_target, hb_parent
		)
		def.left_hand_rotation = _rotation_in_parent_space(
			player_entity.left_hand_target, hb_parent
		)
	if player_entity.right_hand_target:
		def.right_hand_position = _position_in_parent_space(
			player_entity.right_hand_target, hb_parent
		)
		def.right_hand_rotation = _rotation_in_parent_space(
			player_entity.right_hand_target, hb_parent
		)
	if player_entity.left_foot_target:
		def.left_foot_position = _position_in_parent_space(
			player_entity.left_foot_target, peg_parent
		)
		def.left_foot_rotation = _rotation_in_parent_space(
			player_entity.left_foot_target, peg_parent
		)
	if player_entity.right_foot_target:
		def.right_foot_position = _position_in_parent_space(
			player_entity.right_foot_target, peg_parent
		)
		def.right_foot_rotation = _rotation_in_parent_space(
			player_entity.right_foot_target, peg_parent
		)

	# Bike wheel marker positions (editor-authored, used at runtime by raycasts + pivot calc)
	if player_entity.front_wheel_ground_marker:
		def.front_wheel_ground_position = player_entity.front_wheel_ground_marker.position
	if player_entity.rear_wheel_ground_marker:
		def.rear_wheel_ground_position = player_entity.rear_wheel_ground_marker.position
	if player_entity.front_wheel_front_marker:
		def.front_wheel_front_position = player_entity.front_wheel_front_marker.position
	if player_entity.rear_wheel_back_marker:
		def.rear_wheel_back_position = player_entity.rear_wheel_back_marker.position

	var err = ResourceSaver.save(def)
	if err == OK:
		DebugUtils.DebugMsg("AnimationController: Saved rider pose to %s" % def.resource_path)
	else:
		DebugUtils.DebugErrMsg(
			"AnimationController: Failed to save BikeSkinDefinition, error: %s" % err
		)


func _editor_reset_to_default_pose() -> void:
	var def = bike_skin.skin_definition
	if def == null:
		DebugUtils.DebugErrMsg("AnimationController: missing bike_skin definition")
		return

	player_entity.chest_target.position = def.chest_position
	player_entity.chest_target.rotation = def.chest_rotation
	player_entity.head_target.position = def.head_position
	player_entity.head_target.rotation = def.head_rotation
	player_entity.left_arm_magnet.position = def.left_arm_magnet_position
	player_entity.right_arm_magnet.position = def.right_arm_magnet_position
	player_entity.left_leg_magnet.position = def.left_leg_magnet_position
	player_entity.right_leg_magnet.position = def.right_leg_magnet_position
	player_entity.butt_target.position = def.seat_marker_position
	_load_wheel_markers_from_definition(def)
	_sync_targets_from_bike()


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must be set")
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
	if ik_anim_player == null:
		issues.append("ik_anim_player must be set")
	return issues


## Data row for a trick anim. To add a trick: append one _make_entry(...) row in
## _build_trick_entries(). No new vars, no init branches, no cleanup spots.
class _TrickAnimEntry:
	var trick: int  # TrickController.Trick
	var anim_name: String
	var play_mode: int  # PlayMode
	var reverse_on_end: bool
	var anim: Animation = null
	var layer: CustomAnimPlayer.Layer = null


func _make_entry(
	trick: int, anim_name: String, play_mode: int, reverse_on_end: bool
) -> _TrickAnimEntry:
	var e := _TrickAnimEntry.new()
	e.trick = trick
	e.anim_name = anim_name
	e.play_mode = play_mode
	e.reverse_on_end = reverse_on_end
	return e


func _build_trick_entries() -> void:
	_trick_entries = [
		_make_entry(TrickController.Trick.HEEL_CLICKER, "heel_clicker", PlayMode.ONE_SHOT, false),
		_make_entry(
			TrickController.Trick.HIGH_CHAIR, "high_chair", PlayMode.HOLD_WHILE_LATCHED, true
		),
		_make_entry(
			TrickController.Trick.TWO_LEFT_FEET, "two_left_feet", PlayMode.LOOP_WHILE_LATCHED, false
		),
	]


## Per-frame snapshot of every value the rider pose pipeline mutates. Pure data;
## stages read/write its fields and only _commit_pose() touches actual nodes.
## Hand/foot pos+rot are stored in the marker's parent local space (matches the
## animation track value space, so anim deltas just sum in).
class _RiderPose:
	var visual_root_pos: Vector3
	var visual_root_rot: Vector3
	var butt_pos: Vector3
	var chest_pos: Vector3
	var chest_rot: Vector3
	var head_pos: Vector3
	var head_rot: Vector3
	var left_hand_pos: Vector3
	var left_hand_rot: Vector3
	var right_hand_pos: Vector3
	var right_hand_rot: Vector3
	var left_foot_pos: Vector3
	var left_foot_rot: Vector3
	var right_foot_pos: Vector3
	var right_foot_rot: Vector3

	func duplicate() -> _RiderPose:
		var p := _RiderPose.new()
		p.visual_root_pos = visual_root_pos
		p.visual_root_rot = visual_root_rot
		p.butt_pos = butt_pos
		p.chest_pos = chest_pos
		p.chest_rot = chest_rot
		p.head_pos = head_pos
		p.head_rot = head_rot
		p.left_hand_pos = left_hand_pos
		p.left_hand_rot = left_hand_rot
		p.right_hand_pos = right_hand_pos
		p.right_hand_rot = right_hand_rot
		p.left_foot_pos = left_foot_pos
		p.left_foot_rot = left_foot_rot
		p.right_foot_pos = right_foot_pos
		p.right_foot_rot = right_foot_rot
		return p
