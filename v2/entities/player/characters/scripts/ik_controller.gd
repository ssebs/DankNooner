@tool
class_name IKController extends Node3D

@export var char_skin: CharacterSkin

# IK target markers
@export var ik_left_arm_magnet: Marker3D
@export var ik_left_hand: Marker3D
@export var ik_right_arm_magnet: Marker3D
@export var ik_right_hand: Marker3D

@export var ik_left_leg_magnet: Marker3D
@export var ik_left_foot: Marker3D
@export var ik_right_leg_magnet: Marker3D
@export var ik_right_foot: Marker3D

@export var ik_chest: Marker3D
@export var ik_head: Marker3D
@export var butt_pos: Marker3D

var fabrik_ik: FABRIK3D = FABRIK3D.new()
var ik_settings_map: Array[Dictionary] = []

var can_move_butt: bool = true


func _physics_process(_delta):
	if can_move_butt:
		_move_hips_to_butt_target()
	if fabrik_ik.active:
		_apply_end_bone_rotations()


func enable_ik():
	fabrik_ik.active = true
	enable_butt_placement()


func disable_ik():
	fabrik_ik.active = false
	disable_butt_placement()


func enable_butt_placement():
	can_move_butt = true


func disable_butt_placement():
	can_move_butt = false


#region internal


func _move_hips_to_butt_target():
	var skel_3d = char_skin.skel_3d
	if skel_3d == null:
		return
	var hips_idx = skel_3d.find_bone("Hips")
	if hips_idx == -1:
		printerr("could not find Hips bone in skel_3d")
		return

	# Set the Hips bone's global position to match butt_pos
	var hips_global_pose = skel_3d.global_transform * skel_3d.get_bone_global_pose(hips_idx)
	var offset = butt_pos.global_position - hips_global_pose.origin

	var current_pose = skel_3d.get_bone_pose(hips_idx)
	current_pose.origin += skel_3d.global_transform.basis.inverse() * offset
	skel_3d.set_bone_pose(hips_idx, current_pose)


func _apply_end_bone_rotations():
	# Rotate end bones to match marker rotations (FABRIK only handles position)
	_rotate_bone_to_marker("LeftHand", ik_left_hand)
	_rotate_bone_to_marker("RightHand", ik_right_hand)
	_rotate_bone_to_marker("LeftFoot", ik_left_foot)
	_rotate_bone_to_marker("RightFoot", ik_right_foot)
	_rotate_bone_to_marker("Spine", ik_chest)
	_rotate_bone_to_marker("Head", ik_head)


func _rotate_bone_to_marker(bone_name: String, marker: Marker3D):
	var skel_3d = char_skin.skel_3d
	if skel_3d == null:
		return
	var bone_idx = skel_3d.find_bone(bone_name)
	if bone_idx == -1:
		return

	var parent_idx = skel_3d.get_bone_parent(bone_idx)
	if parent_idx == -1:
		return

	# Get marker's target rotation in skeleton-local space
	var target_global_basis = marker.global_transform.basis
	var parent_global_pose = skel_3d.get_bone_global_pose(parent_idx)
	var parent_global_basis = skel_3d.global_transform.basis * parent_global_pose.basis

	# Convert to bone-local rotation
	var pose = skel_3d.get_bone_pose(bone_idx)
	pose.basis = parent_global_basis.inverse() * target_global_basis
	skel_3d.set_bone_pose(bone_idx, pose)


func _create_ik() -> void:
	var skel_3d = char_skin.skel_3d
	var mesh_skin = char_skin.mesh_skin
	if skel_3d == null:
		printerr("Cannot create IK: skel_3d is null")
		return

	# Clear old fabrik_ik if it exists
	if fabrik_ik != null and is_instance_valid(fabrik_ik):
		fabrik_ik.queue_free()
	fabrik_ik = FABRIK3D.new()

	_build_ik_settings_map()

	fabrik_ik.angular_delta_limit = deg_to_rad(90)
	fabrik_ik.deterministic = true

	fabrik_ik.setting_count = ik_settings_map.size()

	for i in ik_settings_map.size():
		var setting: Dictionary = ik_settings_map[i]
		var target: Node3D = setting.get("target")
		var root_bone_name: String = setting.get("root_bone_name", "")
		var end_bone_name: String = setting.get("end_bone_name", "")

		if target == null:
			printerr("IK setting missing target at index ", i)
			continue

		fabrik_ik.set_root_bone_name(i, root_bone_name)
		fabrik_ik.set_end_bone_name(i, end_bone_name)
		fabrik_ik.set_target_node(i, target.get_path())

	skel_3d.add_child(fabrik_ik)
	fabrik_ik.owner = mesh_skin


func _build_ik_settings_map() -> void:
	ik_settings_map = [
		# Must be in magnet, then end order.
		{"target": ik_head, "root_bone_name": "Neck", "end_bone_name": "Head"},
		{"target": ik_chest, "root_bone_name": "Hips", "end_bone_name": "Spine"},
		{
			"target": ik_left_arm_magnet,
			"root_bone_name": "LeftUpperArm",
			"end_bone_name": "LeftLowerArm"
		},
		{"target": ik_left_hand, "root_bone_name": "LeftUpperArm", "end_bone_name": "LeftHand"},
		{
			"target": ik_right_arm_magnet,
			"root_bone_name": "RightUpperArm",
			"end_bone_name": "RightLowerArm"
		},
		{"target": ik_right_hand, "root_bone_name": "RightUpperArm", "end_bone_name": "RightHand"},
		{
			"target": ik_left_leg_magnet,
			"root_bone_name": "LeftUpperLeg",
			"end_bone_name": "LeftLowerLeg"
		},
		{"target": ik_left_foot, "root_bone_name": "LeftUpperLeg", "end_bone_name": "LeftFoot"},
		{
			"target": ik_right_leg_magnet,
			"root_bone_name": "RightUpperLeg",
			"end_bone_name": "RightLowerLeg"
		},
		{"target": ik_right_foot, "root_bone_name": "RightUpperLeg", "end_bone_name": "RightFoot"},
	]


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if char_skin == null:
		issues.append("char_skin must be set")
	if ik_left_arm_magnet == null:
		issues.append("ik_left_arm_magnet must be set")
	if ik_left_hand == null:
		issues.append("ik_left_hand must be set")
	if ik_right_arm_magnet == null:
		issues.append("ik_right_arm_magnet must be set")
	if ik_right_hand == null:
		issues.append("ik_right_hand must be set")
	if ik_left_leg_magnet == null:
		issues.append("ik_left_leg_magnet must be set")
	if ik_left_foot == null:
		issues.append("ik_left_foot must be set")
	if ik_right_leg_magnet == null:
		issues.append("ik_right_leg_magnet must be set")
	if ik_right_foot == null:
		issues.append("ik_right_foot must be set")
	if ik_chest == null:
		issues.append("ik_chest must be set")
	if ik_head == null:
		issues.append("ik_head must be set")
	if butt_pos == null:
		issues.append("butt_pos must be set")
	return issues
