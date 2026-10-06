## Bike + rider meshes and the IK targets that seat one on the other, with the same IK system as
## the player's AnimationController (set_targets → create_ik → enable_ik). Shared by
## NPCRiderEntity (as its VisualRoot) and the garage preview.
class_name RiderVisual extends Node3D

## Null on a car NPC, which drops both skins in its _enter_tree.
@onready var bike_skin: BikeSkin = get_node_or_null("BikeSkin")
@onready var character_skin: CharacterSkin = get_node_or_null("CharacterSkin")
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

## Rider pose is fixed per bike definition, so these resolve once in seat() rather
## than being rebuilt every tick — four Basis.from_euler calls plus a node lookup per
## rider per tick, all for values that never change.
var _hb_parent: Node3D
var _left_hand_local: Transform3D
var _right_hand_local: Transform3D
var _left_foot_local: Transform3D
var _right_foot_local: Transform3D


## Seat the rider on the bike's skin_definition. Call again after either skin rebuilds.
func seat() -> void:
	var def := bike_skin.skin_definition
	var ik_ctrl: IKController = character_skin.ik_controller
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
	ik_ctrl.create_ik()
	character_skin.enable_ik()

	_hb_parent = bike_skin.steering_handlebar_marker.get_parent() as Node3D
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
	sync_targets()


## Same math as AnimationController._sync_targets_from_bike: hands anchored to
## the steering rotation node, feet to the bike skin, from saved definition
## transforms.
func sync_targets() -> void:
	# Locals and the handlebar parent are cached in seat() — only the two parent
	# global_transforms actually change per tick, so read each once.
	var hb_global := _hb_parent.global_transform
	var peg_global := bike_skin.global_transform

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
