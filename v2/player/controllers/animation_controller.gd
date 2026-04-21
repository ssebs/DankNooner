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
@export var max_butt_offset := 0.12
## Max chest pitch (deg) when leaning fwd/back. Negate to flip direction.
@export var max_chest_lean_pitch_deg: float = -15.0
## Max chest z shift when leaning fwd/back. Negate to flip direction.
@export var max_chest_z_offset: float = 0.5
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


#region Procedural Animation
func _update_procedural_animation(delta: float) -> void:
	var ik_ctrl = character_skin.ik_controller
	var blend = clampf(5.0 * delta, 0.0, 1.0)

	# Pitch visual_root for wheelie/stoppie, pivoting around wheel ground contact
	var bd = player_entity.bike_definition
	var max_wheelie_rad = deg_to_rad(bd.max_wheelie_angle_deg)
	var max_stoppie_rad = deg_to_rad(bd.max_stoppie_angle_deg)
	var target_pitch: float
	if movement_controller._is_on_floor:
		target_pitch = -clamp(movement_controller.pitch_angle, -max_stoppie_rad, max_wheelie_rad)
	else:
		target_pitch = -movement_controller.pitch_angle
	# Keep visual_root.rotation.x within PI of target so lerp takes the short path
	while visual_root.rotation.x - target_pitch > PI:
		visual_root.rotation.x -= TAU
	while visual_root.rotation.x - target_pitch < -PI:
		visual_root.rotation.x += TAU
	visual_root.rotation.x = lerpf(visual_root.rotation.x, target_pitch, blend)

	# Pivot offset: lerp along tire contact arc based on pitch
	var pitch_ratio = clamp(abs(visual_root.rotation.x) / (PI / 2.0), 0.0, 1.0)
	var rear_back = (
		bd.rear_wheel_back_position
		if bd.rear_wheel_back_position is Vector3
		else bd.rear_wheel_ground_position
	)
	var front_front = (
		bd.front_wheel_front_position
		if bd.front_wheel_front_position is Vector3
		else bd.front_wheel_ground_position
	)
	var pivot: Vector3
	if visual_root.rotation.x < 0:
		pivot = bd.rear_wheel_ground_position.lerp(rear_back, pitch_ratio)
	else:
		pivot = bd.front_wheel_ground_position.lerp(front_front, pitch_ratio)
	var rotated_pivot = Basis(Vector3.RIGHT, visual_root.rotation.x) * pivot
	visual_root.position = _base_visual_root_position + pivot - rotated_pivot

	# Rotate chest for visual lean
	var target_chest = movement_controller.roll_angle * deg_to_rad(30)
	ik_ctrl.ik_chest.rotation.y = lerpf(ik_ctrl.ik_chest.rotation.y, target_chest, blend)

	# Apply lean rotation to visual_root (rotates both bike + rider)
	visual_root.rotation.z = lerpf(visual_root.rotation.z, movement_controller.roll_angle, blend)

	# _update_wheelie_arm()

	# Shift booty over
	var target_butt_x = (
		# _base_butt_pos.x - clampf(movement_controller.roll_angle, -max_butt_offset, max_butt_offset)
		_base_butt_pos.x
		- clampf(visual_root.rotation.z, -max_butt_offset, max_butt_offset)
	)
	ik_ctrl.butt_pos.position.x = lerpf(ik_ctrl.butt_pos.position.x, target_butt_x, blend)

	# Shift chest to match butt
	var target_chest_x = (
		_base_chest_pos.x - clampf(visual_root.rotation.z, -max_butt_offset, max_butt_offset)
	)
	ik_ctrl.ik_chest.position.x = lerpf(ik_ctrl.ik_chest.position.x, target_chest_x, blend)

	_update_lean_animation(blend)

	bike_skin.rotate_steering(movement_controller.roll_angle, delta)
	bike_skin.rotate_wheels(movement_controller.speed, delta)


## Lean rider fwd/back from nfx_lean: pitch chest and shift butt along z.
func _update_lean_animation(blend: float) -> void:
	var ik_ctrl = character_skin.ik_controller
	var lean_input = input_controller.nfx_lean  # +1 fwd, -1 back

	var target_chest_pitch = _base_chest_rot.x - lean_input * deg_to_rad(max_chest_lean_pitch_deg)
	ik_ctrl.ik_chest.rotation.x = lerpf(ik_ctrl.ik_chest.rotation.x, target_chest_pitch, blend)

	var target_chest_z = _base_chest_pos.z + lean_input * max_chest_z_offset
	ik_ctrl.ik_chest.position.z = lerpf(ik_ctrl.ik_chest.position.z, target_chest_z, blend)

	var target_butt_z = _base_butt_pos.z + lean_input * max_butt_z_offset
	ik_ctrl.butt_pos.position.z = lerpf(ik_ctrl.butt_pos.position.z, target_butt_z, blend)


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
	var is_idle = movement_controller.speed < 1.0 and abs(input_controller.nfx_steer) < 0.1

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
		ik_ctrl.ik_chest.rotation = _base_chest_rot
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

	# Store base positions/rotations for offset calculations
	var ik_ctrl = character_skin.ik_controller
	if ik_ctrl:
		_base_butt_pos = ik_ctrl.butt_pos.position
		_base_chest_pos = ik_ctrl.ik_chest.position
		_base_chest_rot = ik_ctrl.ik_chest.rotation

	_base_visual_root_position = visual_root.position
	_base_visual_root_rotation = visual_root.rotation


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


## Called from player_entity.gd's do_respawn
func do_reset():
	pass


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


#region Editor Tools
func _editor_init_ik_from_bike() -> void:
	if bike_skin == null or character_skin == null:
		DebugUtils.DebugErrMsg("AnimationController: bike_skin and character_skin must be set")
		return

	var ik_ctrl = character_skin.ik_controller
	var def = bike_skin.skin_definition

	# Create proxy markers for all limbs so rotations are independent from bike markers
	var handlebar = bike_skin.steering_handlebar_marker
	var peg = bike_skin.left_peg_marker
	(
		ik_ctrl
		. set_bike_markers(
			bike_skin.seat_marker,
			_editor_get_or_create_proxy(handlebar, "LeftHandProxy", handlebar.get_parent()),
			_editor_get_or_create_mirror(handlebar, "RightHandProxy", handlebar.get_parent()),
			_editor_get_or_create_proxy(peg, "LeftFootProxy", bike_skin),
			_editor_get_or_create_mirror(peg, "RightFootProxy", bike_skin),
		)
	)

	# Load rider pose fields from BikeSkinDefinition if they've been saved
	if def.chest_position is Vector3 and def.chest_position != Vector3.ZERO:
		ik_ctrl.ik_chest.position = def.chest_position
	if def.chest_rotation is Vector3 and def.chest_rotation != Vector3.ZERO:
		ik_ctrl.ik_chest.rotation = def.chest_rotation
	if def.head_position is Vector3 and def.head_position != Vector3.ZERO:
		ik_ctrl.ik_head.position = def.head_position
	if def.head_rotation is Vector3 and def.head_rotation != Vector3.ZERO:
		ik_ctrl.ik_head.rotation = def.head_rotation
	if def.left_arm_magnet_position is Vector3 and def.left_arm_magnet_position != Vector3.ZERO:
		ik_ctrl.ik_left_arm_magnet.position = def.left_arm_magnet_position
	if def.right_arm_magnet_position is Vector3 and def.right_arm_magnet_position != Vector3.ZERO:
		ik_ctrl.ik_right_arm_magnet.position = def.right_arm_magnet_position
	if def.left_leg_magnet_position is Vector3 and def.left_leg_magnet_position != Vector3.ZERO:
		ik_ctrl.ik_left_leg_magnet.position = def.left_leg_magnet_position
	if def.right_leg_magnet_position is Vector3 and def.right_leg_magnet_position != Vector3.ZERO:
		ik_ctrl.ik_right_leg_magnet.position = def.right_leg_magnet_position
	if def.left_hand_rotation is Vector3 and def.left_hand_rotation != Vector3.ZERO:
		ik_ctrl.ik_left_hand.rotation = def.left_hand_rotation
	if def.right_hand_rotation is Vector3 and def.right_hand_rotation != Vector3.ZERO:
		ik_ctrl.ik_right_hand.rotation = def.right_hand_rotation
	if def.left_foot_rotation is Vector3 and def.left_foot_rotation != Vector3.ZERO:
		ik_ctrl.ik_left_foot.rotation = def.left_foot_rotation
	if def.right_foot_rotation is Vector3 and def.right_foot_rotation != Vector3.ZERO:
		ik_ctrl.ik_right_foot.rotation = def.right_foot_rotation

	ik_ctrl._create_ik()
	character_skin.enable_ik()


func _editor_get_or_create_proxy(source: Marker3D, proxy_name: String, parent: Node3D) -> Marker3D:
	var existing = parent.get_node_or_null(proxy_name)
	if existing:
		existing.queue_free()
	var proxy = Marker3D.new()
	proxy.name = proxy_name
	parent.add_child(proxy)
	proxy.position = source.position
	return proxy


func _editor_get_or_create_mirror(source: Marker3D, proxy_name: String, parent: Node3D) -> Marker3D:
	var existing = parent.get_node_or_null(proxy_name)
	if existing:
		existing.queue_free()
	var proxy = Marker3D.new()
	proxy.name = proxy_name
	parent.add_child(proxy)
	proxy.position = source.position
	proxy.position.x = -source.position.x
	return proxy


func _editor_save_default_pose() -> void:
	var ik_ctrl = character_skin.ik_controller
	if ik_ctrl == null:
		DebugUtils.DebugErrMsg("AnimationController: missing ik_controller")
		return

	var def = bike_skin.skin_definition

	def.chest_position = ik_ctrl.ik_chest.position
	def.chest_rotation = ik_ctrl.ik_chest.rotation
	def.head_position = ik_ctrl.ik_head.position
	def.head_rotation = ik_ctrl.ik_head.rotation
	def.left_arm_magnet_position = ik_ctrl.ik_left_arm_magnet.position
	def.right_arm_magnet_position = ik_ctrl.ik_right_arm_magnet.position
	def.left_leg_magnet_position = ik_ctrl.ik_left_leg_magnet.position
	def.right_leg_magnet_position = ik_ctrl.ik_right_leg_magnet.position
	if ik_ctrl.ik_left_hand:
		def.left_hand_rotation = ik_ctrl.ik_left_hand.rotation
	if ik_ctrl.ik_right_hand:
		def.right_hand_rotation = ik_ctrl.ik_right_hand.rotation
	if ik_ctrl.ik_left_foot:
		def.left_foot_rotation = ik_ctrl.ik_left_foot.rotation
	if ik_ctrl.ik_right_foot:
		def.right_foot_rotation = ik_ctrl.ik_right_foot.rotation

	var err = ResourceSaver.save(def)
	if err == OK:
		DebugUtils.DebugMsg("AnimationController: Saved rider pose to %s" % def.resource_path)
	else:
		DebugUtils.DebugErrMsg(
			"AnimationController: Failed to save BikeSkinDefinition, error: %s" % err
		)


func _editor_reset_to_default_pose() -> void:
	var ik_ctrl = character_skin.ik_controller
	var def = bike_skin.skin_definition
	if ik_ctrl == null or def == null:
		DebugUtils.DebugErrMsg("AnimationController: missing ik_controller or bike_skin definition")
		return

	if def.chest_position is Vector3:
		ik_ctrl.ik_chest.position = def.chest_position
	if def.chest_rotation is Vector3:
		ik_ctrl.ik_chest.rotation = def.chest_rotation
	if def.head_position is Vector3:
		ik_ctrl.ik_head.position = def.head_position
	if def.head_rotation is Vector3:
		ik_ctrl.ik_head.rotation = def.head_rotation
	if def.left_arm_magnet_position is Vector3:
		ik_ctrl.ik_left_arm_magnet.position = def.left_arm_magnet_position
	if def.right_arm_magnet_position is Vector3:
		ik_ctrl.ik_right_arm_magnet.position = def.right_arm_magnet_position
	if def.left_leg_magnet_position is Vector3:
		ik_ctrl.ik_left_leg_magnet.position = def.left_leg_magnet_position
	if def.right_leg_magnet_position is Vector3:
		ik_ctrl.ik_right_leg_magnet.position = def.right_leg_magnet_position
	if def.left_hand_rotation is Vector3 and ik_ctrl.ik_left_hand:
		ik_ctrl.ik_left_hand.rotation = def.left_hand_rotation
	if def.right_hand_rotation is Vector3 and ik_ctrl.ik_right_hand:
		ik_ctrl.ik_right_hand.rotation = def.right_hand_rotation
	if def.left_foot_rotation is Vector3 and ik_ctrl.ik_left_foot:
		ik_ctrl.ik_left_foot.rotation = def.left_foot_rotation
	if def.right_foot_rotation is Vector3 and ik_ctrl.ik_right_foot:
		ik_ctrl.ik_right_foot.rotation = def.right_foot_rotation


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
