## Lite rider animation for NPCRiderEntity — seats the rider with the same IK
## system as the player's AnimationController (set_targets → _create_ik →
## enable_ik), then drives cosmetic lean / wheelie pitch on VisualRoot.
## No trick pipeline, no CustomAnimPlayer, no netfox. Runs locally on every
## peer — it derives purely from the synced transform + npc_state.
##
## NOTE: unlike the player scene, IKTargets is a CHILD of VisualRoot here, so
## the markers lean/pitch together with the bike — the rider stays glued on.
class_name NPCAnimationController extends Node

@export var npc: NPCRiderEntity
@export var max_lean_angle_deg: float = 30.0
## How much yaw rate (rad/s) maps to lean angle.
@export var lean_per_yaw_rate: float = 0.5
@export var wheelie_pitch_deg: float = 35.0
@export var crash_roll_deg: float = 80.0
@export var rotation_blend_speed: float = 6.0

@onready var _butt_target: Marker3D = %ButtTarget
@onready var _chest_target: Marker3D = %ChestTarget
@onready var _head_target: Marker3D = %HeadTarget
@onready var _left_hand_target: Marker3D = %LeftHandTarget
@onready var _right_hand_target: Marker3D = %RightHandTarget
@onready var _left_foot_target: Marker3D = %LeftFootTarget
@onready var _right_foot_target: Marker3D = %RightFootTarget
@onready var _left_arm_magnet: Marker3D = %LeftArmMagnet
@onready var _right_arm_magnet: Marker3D = %RightArmMagnet
@onready var _left_leg_magnet: Marker3D = %LeftLegMagnet
@onready var _right_leg_magnet: Marker3D = %RightLegMagnet

var _initialized: bool = false
var _prev_yaw: float = 0.0
var _yaw_rate: float = 0.0


## Called from NPCRiderEntity._ready after skins are applied. Same sequence as
## PlayerEntity._init_ik().
func initialize() -> void:
	var ik_ctrl: IKController = npc.character_skin.ik_controller
	var def := npc.bike_definition
	_butt_target.position = def.seat_marker_position
	ik_ctrl.set_targets(
		_butt_target,
		_left_hand_target,
		_right_hand_target,
		_left_foot_target,
		_right_foot_target,
		_chest_target,
		_head_target,
		_left_arm_magnet,
		_right_arm_magnet,
		_left_leg_magnet,
		_right_leg_magnet
	)
	_apply_rider_pose_from_definition(def)
	ik_ctrl._create_ik()
	npc.character_skin.enable_ik()
	_prev_yaw = npc.rotation.y
	_initialized = true


func _physics_process(delta: float):
	if !_initialized:
		return
	_sync_targets_from_bike()
	_update_yaw_rate(delta)
	_apply_visual_root_rotation(delta)


## Same math as AnimationController._sync_targets_from_bike: hands anchored to
## the steering rotation node, feet to the bike skin, from saved definition
## transforms.
func _sync_targets_from_bike() -> void:
	var def := npc.bike_definition
	var hb_parent := npc.bike_skin.steering_handlebar_marker.get_parent() as Node3D
	var peg_parent: Node3D = npc.bike_skin

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

	_left_hand_target.global_transform = hb_parent.global_transform * left_hand_local
	_right_hand_target.global_transform = hb_parent.global_transform * right_hand_local
	_left_foot_target.global_transform = peg_parent.global_transform * left_foot_local
	_right_foot_target.global_transform = peg_parent.global_transform * right_foot_local


## Rider pose from definition — ZERO means "not yet authored", skip those
## (same convention as PlayerEntity._apply_rider_pose_from_definition).
func _apply_rider_pose_from_definition(def: BikeSkinDefinition) -> void:
	if def.chest_position != Vector3.ZERO:
		_chest_target.position = def.chest_position
	if def.chest_rotation != Vector3.ZERO:
		_chest_target.rotation = def.chest_rotation
	if def.head_position != Vector3.ZERO:
		_head_target.position = def.head_position
	if def.head_rotation != Vector3.ZERO:
		_head_target.rotation = def.head_rotation
	if def.left_arm_magnet_position != Vector3.ZERO:
		_left_arm_magnet.position = def.left_arm_magnet_position
	if def.right_arm_magnet_position != Vector3.ZERO:
		_right_arm_magnet.position = def.right_arm_magnet_position
	if def.left_leg_magnet_position != Vector3.ZERO:
		_left_leg_magnet.position = def.left_leg_magnet_position
	if def.right_leg_magnet_position != Vector3.ZERO:
		_right_leg_magnet.position = def.right_leg_magnet_position


func _update_yaw_rate(delta: float) -> void:
	var yaw := npc.rotation.y
	var raw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / delta
	_prev_yaw = yaw
	# Smooth — on clients yaw arrives stepwise at network rate.
	_yaw_rate = lerpf(_yaw_rate, raw_rate, 10.0 * delta)


## visual_root.rotation.z = lean, .x = wheelie pitch (negative x pitches the
## front up — same mapping as AnimationController._apply_pitch_ground).
func _apply_visual_root_rotation(delta: float) -> void:
	var target_roll: float = 0.0
	var target_pitch: float = 0.0
	match npc.npc_state:
		NPCRiderEntity.NPCState.CRASHED:
			target_roll = deg_to_rad(crash_roll_deg)
		NPCRiderEntity.NPCState.WHEELIE:
			target_pitch = -deg_to_rad(wheelie_pitch_deg)
			target_roll = _lean_target()
		_:
			target_roll = _lean_target()

	var vr := npc.visual_root
	var blend := rotation_blend_speed * delta
	vr.rotation.z = lerp_angle(vr.rotation.z, target_roll, blend)
	vr.rotation.x = lerp_angle(vr.rotation.x, target_pitch, blend)


func _lean_target() -> float:
	var max_lean := deg_to_rad(max_lean_angle_deg)
	# Turning left (+yaw rate) leans left (-z roll).
	return clampf(-_yaw_rate * lean_per_yaw_rate, -max_lean, max_lean)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if npc == null:
		issues.append("npc must not be empty")
	return issues
