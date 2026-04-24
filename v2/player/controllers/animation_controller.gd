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
@export var trick_controller: TrickController
@export var input_controller: InputController
@export var ik_anim_player: AnimationPlayer

@export_tool_button("Init IK from Bike") var init_ik_btn = _editor_init_ik_from_bike
@export_tool_button("Save Default Pose") var save_pose_btn = _editor_save_default_pose
@export_tool_button("Play Default Pose") var reset_pose_btn = _editor_reset_to_default_pose

@export_group("Procedural Settings")
@export var idle_timeout: float = 1.0
@export var max_butt_offset := 0.12
## Max chest pitch (deg) when leaning fwd/back. Negate to flip direction.
@export var max_chest_lean_pitch_deg: float = -15.0
## Max chest z shift when leaning fwd/back. Negate to flip direction.
@export var max_chest_z_offset: float = 0.2
## Max butt z shift when leaning fwd/back. Negate to flip direction.
@export var max_butt_z_offset: float = 0.1

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
var _idle_timer: float = 0.0
var _procedural_enabled: bool = true
var _targets_synced_from_bike: bool = true

# Cached refs (set in initialize)
var _ik_ctrl: IKController
var _bd: BikeSkinDefinition

# Per-tick cached inputs (set at top of _update_riding)
var _blend: float
var _roll: float
var _pitch: float

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
		RiderState.TRICK:
			_update_trick(delta)
		RiderState.RAGDOLL:
			pass


#region Procedural Animation
func _update_idle(delta: float) -> void:
	_update_idle_timer(delta)


func _update_trick(_delta: float) -> void:
	# Skeleton AnimationPlayer drives the pose; nothing procedural to do.
	pass


func _update_riding(delta: float) -> void:
	_blend = clampf(5.0 * delta, 0.0, 1.0)
	_roll = movement_controller.roll_angle
	_pitch = movement_controller.pitch_angle

	_riding_common(delta)

	if not movement_controller._is_on_floor:
		_riding_air(delta)
	elif trick_controller.is_in_wheelie():
		_riding_wheelie(delta)
	elif trick_controller.current_trick == TrickController.Trick.STOPPIE:
		_riding_stoppie(delta)
	else:
		_riding_basic(delta)

	# Pivot offset tracks current pitch every frame so position unwinds smoothly
	# as rotation.x lerps back to 0 when leaving a wheelie/stoppie.
	_apply_pivot_offset()

	_update_idle_timer(delta)


## Always-on bits: steering, wheels, lean rotation, chest/butt X shift, fwd/back lean.
func _riding_common(delta: float) -> void:
	visual_root.rotation.z = lerpf(visual_root.rotation.z, _roll, _blend)

	var target_chest_y = _roll * deg_to_rad(30)
	player_entity.chest_target.rotation.y = lerpf(
		player_entity.chest_target.rotation.y, target_chest_y, _blend
	)

	var lean_x_offset = clampf(visual_root.rotation.z, -max_butt_offset, max_butt_offset)
	var target_butt_x = _base_butt_pos.x - lean_x_offset
	var target_chest_x = _base_chest_pos.x - lean_x_offset
	_ik_ctrl.butt_pos.position.x = lerpf(_ik_ctrl.butt_pos.position.x, target_butt_x, _blend)
	player_entity.chest_target.position.x = lerpf(
		player_entity.chest_target.position.x, target_chest_x, _blend
	)

	var lean_input = input_controller.nfx_lean
	var target_chest_pitch = _base_chest_rot.x - lean_input * deg_to_rad(max_chest_lean_pitch_deg)
	var target_chest_z = _base_chest_pos.z + lean_input * max_chest_z_offset
	var target_butt_z = _base_butt_pos.z + lean_input * max_butt_z_offset
	player_entity.chest_target.rotation.x = lerpf(
		player_entity.chest_target.rotation.x, target_chest_pitch, _blend
	)
	player_entity.chest_target.position.z = lerpf(
		player_entity.chest_target.position.z, target_chest_z, _blend
	)
	_ik_ctrl.butt_pos.position.z = lerpf(_ik_ctrl.butt_pos.position.z, target_butt_z, _blend)

	var steer_input := _roll if _targets_synced_from_bike else 0.0
	bike_skin.rotate_steering(steer_input, delta)
	bike_skin.rotate_wheels(movement_controller.speed, delta, trick_controller.is_in_wheelie())

	if _targets_synced_from_bike:
		_sync_targets_from_bike()


## On ground, no trick — pitch still follows movement_controller (for sub-threshold wobble).
func _riding_basic(_delta: float) -> void:
	_lerp_ground_pitch()


func _riding_wheelie(_delta: float) -> void:
	_lerp_ground_pitch()


func _riding_stoppie(_delta: float) -> void:
	_lerp_ground_pitch()


func _riding_air(_delta: float) -> void:
	disable_target_sync()
	visual_root.rotation.x = lerp_angle(visual_root.rotation.x, -_pitch, _blend)


## Shared ground pitch target: follow movement_controller.pitch_angle, clamped to bike limits.
func _lerp_ground_pitch() -> void:
	enable_target_sync()
	var max_wheelie_rad = deg_to_rad(_bd.max_wheelie_angle_deg)
	var max_stoppie_rad = deg_to_rad(_bd.max_stoppie_angle_deg)
	var target = -clampf(_pitch, -max_stoppie_rad, max_wheelie_rad)
	visual_root.rotation.x = lerp_angle(visual_root.rotation.x, target, _blend)


## Pivot visual_root around the tire contact arc. Arc is picked by trick_controller state;
## when not in a trick, sign of rotation.x handles mid-transition unwind (prevents snapping).
func _apply_pivot_offset() -> void:
	var rot_x = visual_root.rotation.x
	var pitch_ratio = clampf(absf(rot_x) / (PI / 2.0), 0.0, 1.0)
	var use_rear: bool
	match trick_controller.current_trick:
		TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD:
			use_rear = true
		TrickController.Trick.STOPPIE:
			use_rear = false
		_:
			use_rear = rot_x < 0.0

	var pivot: Vector3
	if use_rear:
		pivot = _bd.rear_wheel_ground_position.lerp(_bd.rear_wheel_back_position, pitch_ratio)
	else:
		pivot = _bd.front_wheel_ground_position.lerp(_bd.front_wheel_front_position, pitch_ratio)
	var rotated_pivot = Basis(Vector3.RIGHT, rot_x) * pivot
	visual_root.position = _base_visual_root_position + pivot - rotated_pivot


# func _update_wheelie_arm() -> void:
# 	var anim_player = character_skin.ik_anim_player
# 	if anim_player == null:
# 		return
# 	var anim_name = "IK_anim_lib/wheelie_arm_drag"
# 	if not anim_player.has_animation(anim_name):
# 		return
# 	if anim_player.current_animation != anim_name:
# 		anim_player.play(anim_name)
# 	# Only extend arm when trick_mod held during a wheelie, otherwise return to default (t=0)
# 	var in_wheelie = movement_controller.pitch_angle > 0.0
# 	var ratio = (
# 		clamp(movement_controller.pitch_angle, 0.0, 1.0)
# 		if (in_wheelie and input_controller.nfx_trick_held)
# 		else 0.0
# 	)
# 	anim_player.seek(ratio, true)


func _update_idle_timer(delta: float) -> void:
	# Check if player is mostly stationary
	if movement_controller.speed < 0.5 and abs(input_controller.nfx_steer) < 0.1:
		_idle_timer += delta
		if _idle_timer >= idle_timeout:
			if current_state == RiderState.RIDING:
				_transition_to_idle()
			else:
				_idle_timer = 0.0

	else:
		_idle_timer = 0.0
		if current_state == RiderState.IDLE:
			_transition_to_riding()


func _reset_to_base_positions() -> void:
	if _ik_ctrl and _ik_ctrl.butt_pos:
		_ik_ctrl.butt_pos.position = _base_butt_pos
	if player_entity.chest_target:
		player_entity.chest_target.position = _base_chest_pos
		player_entity.chest_target.rotation = _base_chest_rot
	if visual_root:
		visual_root.position = _base_visual_root_position
		visual_root.rotation = _base_visual_root_rotation
	if bike_skin:
		bike_skin.rotation.x = 0.0


#endregion

#region Public API


## Initialize the animation controller. Call after IK targets are set.
func initialize() -> void:
	if character_skin == null or bike_skin == null or visual_root == null:
		DebugUtils.DebugErrMsg(
			"AnimationController: Missing character_skin, bike_skin, or visual_root"
		)
		return

	_ik_ctrl = character_skin.ik_controller
	_bd = player_entity.bike_definition

	if _ik_ctrl and _ik_ctrl.butt_pos:
		_base_butt_pos = _ik_ctrl.butt_pos.position
	if player_entity.chest_target:
		_base_chest_pos = player_entity.chest_target.position
		_base_chest_rot = player_entity.chest_target.rotation

	_base_visual_root_position = visual_root.position
	_base_visual_root_rotation = visual_root.rotation

	if ik_anim_player:
		ik_anim_player.root_node = ik_anim_player.get_path_to(visual_root)

	_sync_targets_from_bike()


## Sync hand/foot target transforms from the bike's steering handlebar proxy and peg
## definition values. Called every tick while target sync is enabled; skipped when
## AnimationPlayer is driving the targets.
func _sync_targets_from_bike() -> void:
	if bike_skin == null:
		return
	# Steering handlebar proxy still lives on bike_skin (rotates with steering)
	var hb: Marker3D = bike_skin.steering_handlebar_marker
	if hb == null:
		return

	var hb_parent := hb.get_parent() as Node3D

	# Peg transform computed from definition (no marker node needed)
	var peg_pos = _bd.left_peg_marker_position
	var peg_rot_deg = _bd.left_peg_marker_rotation_degrees
	var peg_rot = Vector3(
		deg_to_rad(peg_rot_deg.x), deg_to_rad(peg_rot_deg.y), deg_to_rad(peg_rot_deg.z)
	)
	var peg_local = Transform3D(Basis.from_euler(peg_rot), peg_pos)
	var peg_parent = bike_skin

	var def: BikeSkinDefinition = _bd if _bd else bike_skin.skin_definition

	var left_hand_local := _local_with_rotation_override(
		hb.transform, def.left_hand_rotation if def else Vector3.ZERO
	)
	var right_hand_local := _local_with_rotation_override(
		_mirror_transform_x(hb.transform), def.right_hand_rotation if def else Vector3.ZERO
	)
	var left_foot_local := _local_with_rotation_override(
		peg_local, def.left_foot_rotation if def else Vector3.ZERO
	)
	var right_foot_local := _local_with_rotation_override(
		_mirror_transform_x(peg_local), def.right_foot_rotation if def else Vector3.ZERO
	)

	player_entity.left_hand_target.global_transform = hb_parent.global_transform * left_hand_local
	player_entity.right_hand_target.global_transform = hb_parent.global_transform * right_hand_local
	player_entity.left_foot_target.global_transform = peg_parent.global_transform * left_foot_local
	player_entity.right_foot_target.global_transform = peg_parent.global_transform * right_foot_local


## If rotation_override is non-zero, replace the local basis with it (preserving origin).
## Matches the old behavior where def.<limb>_rotation was written straight into the proxy's
## local rotation, overriding the bike marker's authored basis.
static func _local_with_rotation_override(
	base: Transform3D, rotation_override: Vector3
) -> Transform3D:
	if rotation_override == Vector3.ZERO:
		return base
	return Transform3D(Basis.from_euler(rotation_override), base.origin)


## Enable or disable procedural animation
func set_procedural_enabled(enabled: bool) -> void:
	_procedural_enabled = enabled
	if enabled:
		_reset_to_base_positions()


## Hand ownership of the hand/foot targets back to procedural riding. Next tick's
## _sync_targets_from_bike() snaps them to the bike's handlebar/peg positions.
func enable_target_sync() -> void:
	_targets_synced_from_bike = true


## Release the hand/foot targets so an AnimationPlayer track can drive their transforms.
## Sync is skipped while disabled.
func disable_target_sync() -> void:
	_targets_synced_from_bike = false


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


## Called from player_entity.gd's do_respawn
func do_reset():
	pass


#endregion


#region State Transitions
func _transition_to_riding() -> void:
	print("_transition_to_riding")

	# ik_anim_player.play_backwards("idle")
	ik_anim_player.play("idle", -1, -2.0, true)  # play backwds, 2x speed
	await get_tree().create_timer(ik_anim_player.current_animation_length / 2).timeout
	_procedural_enabled = true

	current_state = RiderState.RIDING
	ik_anim_player.stop()
	character_skin.enable_ik()
	enable_target_sync()


func _transition_to_idle() -> void:
	current_state = RiderState.IDLE
	_procedural_enabled = true
	disable_target_sync()
	ik_anim_player.play("idle")


func _transition_to_trick() -> void:
	current_state = RiderState.TRICK
	character_skin.disable_ik()
	_procedural_enabled = false
	disable_target_sync()


#endregion


#region Editor Tools
func _editor_auto_init() -> void:
	if bike_skin == null or character_skin == null:
		return
	if character_skin.ik_controller == null:
		return
	_editor_init_ik_from_bike()


func _editor_sync_pose_from_definition() -> void:
	if bike_skin == null or player_entity == null:
		return
	var def = bike_skin.skin_definition
	if def == null:
		return

	player_entity.chest_target.position = def.chest_position
	player_entity.chest_target.rotation = def.chest_rotation
	player_entity.head_target.position = def.head_position
	player_entity.head_target.rotation = def.head_rotation
	player_entity.left_arm_magnet.position = def.left_arm_magnet_position
	player_entity.right_arm_magnet.position = def.right_arm_magnet_position
	player_entity.left_leg_magnet.position = def.left_leg_magnet_position
	player_entity.right_leg_magnet.position = def.right_leg_magnet_position
	_sync_targets_from_bike()


func _editor_init_ik_from_bike() -> void:
	if bike_skin == null or character_skin == null:
		DebugUtils.DebugErrMsg("AnimationController: bike_skin and character_skin must be set")
		return
	if player_entity == null:
		DebugUtils.DebugErrMsg("AnimationController: player_entity must be set for editor init")
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
		player_entity.left_hand_target, player_entity.right_hand_target,
		player_entity.left_foot_target, player_entity.right_foot_target,
		player_entity.chest_target, player_entity.head_target,
		player_entity.left_arm_magnet, player_entity.right_arm_magnet,
		player_entity.left_leg_magnet, player_entity.right_leg_magnet
	)

	_sync_targets_from_bike()

	# Load rider pose from definition
	if def.chest_position is Vector3 and def.chest_position != Vector3.ZERO:
		player_entity.chest_target.position = def.chest_position
	if def.chest_rotation is Vector3 and def.chest_rotation != Vector3.ZERO:
		player_entity.chest_target.rotation = def.chest_rotation
	if def.head_position is Vector3 and def.head_position != Vector3.ZERO:
		player_entity.head_target.position = def.head_position
	if def.head_rotation is Vector3 and def.head_rotation != Vector3.ZERO:
		player_entity.head_target.rotation = def.head_rotation
	if def.left_arm_magnet_position is Vector3 and def.left_arm_magnet_position != Vector3.ZERO:
		player_entity.left_arm_magnet.position = def.left_arm_magnet_position
	if def.right_arm_magnet_position is Vector3 and def.right_arm_magnet_position != Vector3.ZERO:
		player_entity.right_arm_magnet.position = def.right_arm_magnet_position
	if def.left_leg_magnet_position is Vector3 and def.left_leg_magnet_position != Vector3.ZERO:
		player_entity.left_leg_magnet.position = def.left_leg_magnet_position
	if def.right_leg_magnet_position is Vector3 and def.right_leg_magnet_position != Vector3.ZERO:
		player_entity.right_leg_magnet.position = def.right_leg_magnet_position

	ik_ctrl._create_ik()
	character_skin.enable_ik()
	disable_target_sync()


## Inverse of _local_with_rotation_override: extract the euler that, when plugged into
## Basis.from_euler() and multiplied by parent.global.basis, reproduces marker.global.basis.
static func _rotation_in_parent_space(marker: Node3D, parent: Node3D) -> Vector3:
	var parent_basis := parent.global_transform.basis.orthonormalized()
	var marker_basis := marker.global_transform.basis.orthonormalized()
	return (parent_basis.inverse() * marker_basis).get_euler()


static func _mirror_transform_x(t: Transform3D) -> Transform3D:
	t.origin.x = -t.origin.x
	t.basis.x.y = -t.basis.x.y
	t.basis.x.z = -t.basis.x.z
	t.basis.y.x = -t.basis.y.x
	t.basis.z.x = -t.basis.z.x
	return t


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
	var hb: Marker3D = bike_skin.steering_handlebar_marker
	var hb_parent := hb.get_parent() as Node3D if hb else bike_skin as Node3D
	var peg_parent := bike_skin as Node3D

	if player_entity.left_hand_target:
		def.left_hand_rotation = _rotation_in_parent_space(
			player_entity.left_hand_target, hb_parent
		)
	if player_entity.right_hand_target:
		def.right_hand_rotation = _rotation_in_parent_space(
			player_entity.right_hand_target, hb_parent
		)
	if player_entity.left_foot_target:
		def.left_foot_rotation = _rotation_in_parent_space(
			player_entity.left_foot_target, peg_parent
		)
	if player_entity.right_foot_target:
		def.right_foot_rotation = _rotation_in_parent_space(
			player_entity.right_foot_target, peg_parent
		)

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

	if def.chest_position is Vector3:
		player_entity.chest_target.position = def.chest_position
	if def.chest_rotation is Vector3:
		player_entity.chest_target.rotation = def.chest_rotation
	if def.head_position is Vector3:
		player_entity.head_target.position = def.head_position
	if def.head_rotation is Vector3:
		player_entity.head_target.rotation = def.head_rotation
	if def.left_arm_magnet_position is Vector3:
		player_entity.left_arm_magnet.position = def.left_arm_magnet_position
	if def.right_arm_magnet_position is Vector3:
		player_entity.right_arm_magnet.position = def.right_arm_magnet_position
	if def.left_leg_magnet_position is Vector3:
		player_entity.left_leg_magnet.position = def.left_leg_magnet_position
	if def.right_leg_magnet_position is Vector3:
		player_entity.right_leg_magnet.position = def.right_leg_magnet_position
	player_entity.butt_target.position = def.seat_marker_position
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
