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
## Past this distance from the active camera the rider's rig stops updating — limb IK is
## cosmetic, so a distant rider holding its last pose reads fine. The bike keeps driving,
## colliding and syncing; only the skeleton work stops, which is why this is safe during
## races where culling the simulation would not be. Same idea as the VisibleOnScreenEnabler3D
## approach in the Godot 3D perf docs, by distance so it doesn't pop as the camera swings.
@export var rig_cull_distance: float = 60.0
## How often the distance check runs. It's cheap, but there's no reason to do it per tick.
@export var rig_cull_check_interval: float = 0.5

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

## Rig LOD state — see rig_cull_distance.
var _ik_ctrl: IKController
var _rig_active: bool = true
var _rig_next_check_ms: int = 0

## Rider pose is fixed per bike definition, so these resolve once in initialize() rather
## than being rebuilt every tick — four Basis.from_euler calls plus a node lookup per
## rider per tick, all for values that never change.
var _hb_parent: Node3D
var _left_hand_local: Transform3D
var _right_hand_local: Transform3D
var _left_foot_local: Transform3D
var _right_foot_local: Transform3D


## Called from NPCRiderEntity._ready after skins are applied. Same sequence as
## PlayerEntity._init_ik().
func initialize() -> void:
	var ik_ctrl: IKController = npc.character_skin.ik_controller
	_ik_ctrl = ik_ctrl
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

	_hb_parent = npc.bike_skin.steering_handlebar_marker.get_parent() as Node3D
	_left_hand_local = Transform3D(
		Basis.from_euler(def.left_hand_rotation), def.left_hand_position
	)
	_right_hand_local = Transform3D(
		Basis.from_euler(def.right_hand_rotation), def.right_hand_position
	)
	_left_foot_local = Transform3D(
		Basis.from_euler(def.left_foot_rotation), def.left_foot_position
	)
	_right_foot_local = Transform3D(
		Basis.from_euler(def.right_foot_rotation), def.right_foot_position
	)
	_initialized = true


func _physics_process(delta: float):
	if !_initialized:
		return
	_update_rig_lod()
	# Lean/pitch stays on at any distance — it's two lerps on one node, and a bike that
	# stops leaning through corners is obvious in a way a frozen wrist isn't.
	if _rig_active:
		_sync_targets_from_bike()
	_update_yaw_rate(delta)
	_apply_visual_root_rotation(delta)


## Toggle the cosmetic rider rig by distance from the active camera. Runs on every peer
## against its own view — the rig is local cosmetics, nothing here is synced or authoritative.
##
## Note this cuts Process time as much as Physics: Skeleton3D runs its modifiers (the
## FABRIK3D solve) on the idle callback by default, so switching the modifier off lands in
## a different budget than the target writes below.
func _update_rig_lod() -> void:
	var now := Time.get_ticks_msec()
	if now < _rig_next_check_ms:
		return
	_rig_next_check_ms = now + int(rig_cull_check_interval * 1000.0)

	var cam := get_viewport().get_camera_3d()
	# No camera yet while a level is still loading — leave the rig as it is until there is one.
	if cam == null:
		return
	var active := (
		npc.global_position.distance_squared_to(cam.global_position)
		< rig_cull_distance * rig_cull_distance
	)
	if active == _rig_active:
		return
	_rig_active = active
	# enable_ik/disable_ik already own the modifier + hip-placement flags.
	if active:
		_ik_ctrl.enable_ik()
	else:
		_ik_ctrl.disable_ik()
	_ik_ctrl.set_physics_process(active)


## Same math as AnimationController._sync_targets_from_bike: hands anchored to
## the steering rotation node, feet to the bike skin, from saved definition
## transforms.
func _sync_targets_from_bike() -> void:
	# Locals and the handlebar parent are cached in initialize() — only the two parent
	# global_transforms actually change per tick, so read each once.
	var hb_global := _hb_parent.global_transform
	var peg_global := npc.bike_skin.global_transform

	_left_hand_target.global_transform = hb_global * _left_hand_local
	_right_hand_target.global_transform = hb_global * _right_hand_local
	_left_foot_target.global_transform = peg_global * _left_foot_local
	_right_foot_target.global_transform = peg_global * _right_foot_local


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
