class_name PlayerAnimationController extends Node

# Skeleton reference
var character_skel: Skeleton3D = null

# Target markers
var right_handlebar_marker: Marker3D
var left_handlebar_marker: Marker3D
var seat_marker: Marker3D

# Shared state
var state: BikeState

# Input state (from signals)
var steer_input: float = 0.0

# Body sway settings
@export var body_sway_offset: float = 0.15  # How far the body moves left/right
@export var body_sway_speed: float = 8.0     # How fast the body follows input

# Current body offset
var current_body_offset: float = 0.0

# Bone names - configure these to match your rig
@export var right_upper_arm_bone: String = "UpperArm.R"
@export var right_forearm_bone: String = "LowerArm.R"
@export var right_hand_bone: String = "Palm.R"
@export var left_upper_arm_bone: String = "UpperArm.L"
@export var left_forearm_bone: String = "LowerArm.L"
@export var left_hand_bone: String = "Palm.L"
@export var hips_bone: String = "Hips"

# Bone indices (cached for performance)
var right_upper_arm_idx: int = -1
var right_forearm_idx: int = -1
var right_hand_idx: int = -1
var left_upper_arm_idx: int = -1
var left_forearm_idx: int = -1
var left_hand_idx: int = -1
var hips_bone_idx: int = -1

# Bone lengths (calculated from rest pose)
var right_upper_arm_length: float = 0.0
var right_forearm_length: float = 0.0
var left_upper_arm_length: float = 0.0
var left_forearm_length: float = 0.0

var bones_initialized: bool = false


func setup(bike_state: BikeState, input: BikeInput, skel: Skeleton3D,
        right_marker: Marker3D, left_marker: Marker3D, seat: Marker3D) -> void:
    state = bike_state
    character_skel = skel
    right_handlebar_marker = right_marker
    left_handlebar_marker = left_marker
    seat_marker = seat

    # Connect to input signals
    input.steer_changed.connect(_on_steer_changed)

    # Setup bone indices
    _setup_bones()


func _setup_bones() -> void:
    if not character_skel:
        push_warning("PlayerAnimationController: No skeleton assigned")
        return

    # Cache bone indices for right arm
    right_upper_arm_idx = character_skel.find_bone(right_upper_arm_bone)
    right_forearm_idx = character_skel.find_bone(right_forearm_bone)
    right_hand_idx = character_skel.find_bone(right_hand_bone)

    if right_upper_arm_idx < 0 or right_forearm_idx < 0 or right_hand_idx < 0:
        push_error("PlayerAnimationController: Right arm bones not found")
        return

    # Cache bone indices for left arm
    left_upper_arm_idx = character_skel.find_bone(left_upper_arm_bone)
    left_forearm_idx = character_skel.find_bone(left_forearm_bone)
    left_hand_idx = character_skel.find_bone(left_hand_bone)

    if left_upper_arm_idx < 0 or left_forearm_idx < 0 or left_hand_idx < 0:
        push_error("PlayerAnimationController: Left arm bones not found")
        return

    # Hips bone
    hips_bone_idx = character_skel.find_bone(hips_bone)
    if hips_bone_idx < 0:
        push_warning("PlayerAnimationController: Hips bone '%s' not found" % hips_bone)

    # Calculate bone lengths from rest pose
    _calculate_bone_lengths()

    bones_initialized = true
    print("PlayerAnimationController: Bones initialized successfully")


func _calculate_bone_lengths() -> void:
    # Get rest pose positions to calculate bone lengths
    var right_upper_pos = character_skel.get_bone_global_rest(right_upper_arm_idx).origin
    var right_forearm_pos = character_skel.get_bone_global_rest(right_forearm_idx).origin
    var right_hand_pos = character_skel.get_bone_global_rest(right_hand_idx).origin

    right_upper_arm_length = right_upper_pos.distance_to(right_forearm_pos)
    right_forearm_length = right_forearm_pos.distance_to(right_hand_pos)

    var left_upper_pos = character_skel.get_bone_global_rest(left_upper_arm_idx).origin
    var left_forearm_pos = character_skel.get_bone_global_rest(left_forearm_idx).origin
    var left_hand_pos = character_skel.get_bone_global_rest(left_hand_idx).origin

    left_upper_arm_length = left_upper_pos.distance_to(left_forearm_pos)
    left_forearm_length = left_forearm_pos.distance_to(left_hand_pos)

    print("Arm lengths - R upper: %.2f, R fore: %.2f, L upper: %.2f, L fore: %.2f" % [
        right_upper_arm_length, right_forearm_length,
        left_upper_arm_length, left_forearm_length
    ])


func _physics_process(_delta: float) -> void:
    if not character_skel or not bones_initialized:
        return

    _update_hips_position()
    _solve_arm_ik(right_upper_arm_idx, right_forearm_idx, right_hand_idx,
        right_upper_arm_length, right_forearm_length,
        right_handlebar_marker.global_position, Vector3(0, 0, 1))  # Elbow hint: outward right
    _solve_arm_ik(left_upper_arm_idx, left_forearm_idx, left_hand_idx,
        left_upper_arm_length, left_forearm_length,
        left_handlebar_marker.global_position, Vector3(0, 0, 1))  # Elbow hint: outward left


func _update_hips_position() -> void:
    if hips_bone_idx < 0:
        return

    var skel_inverse = character_skel.global_transform.affine_inverse()
    var target_local = skel_inverse * seat_marker.global_transform
    character_skel.set_bone_global_pose_override(hips_bone_idx, target_local, 1.0, true)


func _solve_arm_ik(upper_idx: int, forearm_idx: int, hand_idx: int,
        upper_len: float, forearm_len: float, target_global: Vector3, pole_hint: Vector3) -> void:
    # Get the shoulder (upper arm origin) position in global space
    var upper_global_pose = character_skel.global_transform * character_skel.get_bone_global_pose(upper_idx)
    var shoulder_pos = upper_global_pose.origin

    # Calculate distance to target
    var to_target = target_global - shoulder_pos
    var target_dist = to_target.length()
    var total_arm_length = upper_len + forearm_len

    # Clamp target distance to arm reach
    if target_dist > total_arm_length * 0.999:
        target_dist = total_arm_length * 0.999
        target_global = shoulder_pos + to_target.normalized() * target_dist
        to_target = target_global - shoulder_pos

    # Law of cosines to find elbow angle
    # c² = a² + b² - 2ab*cos(C)
    # cos(C) = (a² + b² - c²) / (2ab)
    var cos_elbow = (upper_len * upper_len + forearm_len * forearm_len - target_dist * target_dist) / (2.0 * upper_len * forearm_len)
    cos_elbow = clamp(cos_elbow, -1.0, 1.0)
    var _elbow_angle = acos(cos_elbow)  # Angle at elbow joint (kept for reference)

    # Angle at shoulder
    var cos_shoulder = (upper_len * upper_len + target_dist * target_dist - forearm_len * forearm_len) / (2.0 * upper_len * target_dist)
    cos_shoulder = clamp(cos_shoulder, -1.0, 1.0)
    var shoulder_angle = acos(cos_shoulder)

    # Build rotation for upper arm
    var target_dir = to_target.normalized()

    # Create a plane for the arm using the pole hint
    var arm_plane_normal = target_dir.cross(pole_hint).normalized()
    if arm_plane_normal.length_squared() < 0.001:
        arm_plane_normal = target_dir.cross(Vector3.UP).normalized()

    # Elbow direction (perpendicular to target direction, in the arm plane)
    var elbow_dir = arm_plane_normal.cross(target_dir).normalized()

    # Upper arm points toward: target direction rotated by shoulder_angle toward elbow
    var upper_arm_dir = (target_dir * cos(shoulder_angle) + elbow_dir * sin(shoulder_angle)).normalized()

    # Calculate elbow position
    var elbow_pos = shoulder_pos + upper_arm_dir * upper_len

    # Forearm direction: from elbow to target
    var forearm_dir = (target_global - elbow_pos).normalized()

    # Create transforms and apply
    var skel_inverse = character_skel.global_transform.affine_inverse()

    # Upper arm transform
    var upper_basis = _basis_from_direction(upper_arm_dir, arm_plane_normal)
    var upper_transform = Transform3D(upper_basis, shoulder_pos)
    character_skel.set_bone_global_pose_override(upper_idx, skel_inverse * upper_transform, 1.0, true)

    # Forearm transform
    var forearm_basis = _basis_from_direction(forearm_dir, arm_plane_normal)
    var forearm_transform = Transform3D(forearm_basis, elbow_pos)
    character_skel.set_bone_global_pose_override(forearm_idx, skel_inverse * forearm_transform, 1.0, true)

    # Hand transform (at target, same orientation as forearm for now)
    var hand_transform = Transform3D(forearm_basis, target_global)
    character_skel.set_bone_global_pose_override(hand_idx, skel_inverse * hand_transform, 1.0, true)


func _basis_from_direction(forward: Vector3, up_hint: Vector3) -> Basis:
    # Create a basis where -Z points in the forward direction (Godot convention)
    var z_axis = -forward.normalized()
    var x_axis = up_hint.cross(z_axis).normalized()
    if x_axis.length_squared() < 0.001:
        x_axis = Vector3.UP.cross(z_axis).normalized()
    var y_axis = z_axis.cross(x_axis).normalized()
    return Basis(x_axis, y_axis, z_axis)


func _on_steer_changed(value: float) -> void:
    steer_input = value


func reset() -> void:
    steer_input = 0.0
    current_body_offset = 0.0
    # Clear bone overrides
    if character_skel and bones_initialized:
        character_skel.set_bone_global_pose_override(right_upper_arm_idx, Transform3D(), 0.0, false)
        character_skel.set_bone_global_pose_override(right_forearm_idx, Transform3D(), 0.0, false)
        character_skel.set_bone_global_pose_override(right_hand_idx, Transform3D(), 0.0, false)
        character_skel.set_bone_global_pose_override(left_upper_arm_idx, Transform3D(), 0.0, false)
        character_skel.set_bone_global_pose_override(left_forearm_idx, Transform3D(), 0.0, false)
        character_skel.set_bone_global_pose_override(left_hand_idx, Transform3D(), 0.0, false)
        character_skel.set_bone_global_pose_override(hips_bone_idx, Transform3D(), 0.0, false)
