@tool
## make sure to set HACK region's vars!
## audio_manager & username
class_name PlayerEntity extends CharacterBody3D

## Used for internals
signal respawned(peer_id: int)

## Used for GameMode
signal crashed(peer_id: int)
# signal trick_started(peer_id: int, trick_type: int)
# signal trick_ended(peer_id: int, trick_type: int)

@export var bike_definition: BikeSkinDefinition
@export var character_definition: CharacterSkinDefinition
@export var collision_shape_3d: CollisionShape3D

@export var input_controller: InputController
@export var animation_controller: AnimationController
@export var gearing_controller: GearingController
@export var trick_controller: TrickController
@export var crash_controller: CrashController
@export var movement_controller: MovementController
@export var camera_controller: CameraController

@onready var controllers_node: Node3D = %_Controllers
@onready var hud_controller: HUDController = %HUDController

@onready var visual_root: Node3D = %VisualRoot
@onready var character_skin: CharacterSkin = %CharacterSkin
@onready var bike_skin: BikeSkin = %BikeSkin
@onready var name_label: Label3D = %NameLabel
@onready var rear_raycast: RayCast3D = %RearRayCast
@onready var front_raycast: RayCast3D = %FrontRayCast
@onready var rollback_sync: RollbackSynchronizer = %RollbackSynchronizer

var is_local_client: bool = false

#region HACK - set from spawn_manager
var audio_manager: AudioManager
var settings_manager: SettingsManager
var username: String:
	set(v):
		username = v
		if is_node_ready():
			name_label.text = username
# `name` is also set from spawn_manager
#endregion

#region Netfox sync'd
# `global_transform`, `velocity` also sync'd
#endregion

#region DELETE_ME

# Trick/boost state (synced)
var is_boosting: bool = false
var boost_count: int = 2

# Crash state (synced)
var is_crashed: bool = false

# Brake danger (local, display only)
var grip_usage: float = 0.0
#endregion

# Discrete actions (rb_* pattern)
var rb_do_respawn: bool = false
var rb_respawn_transform: Transform3D = Transform3D()  # override spawn point when set

# Process-side state tracking (not sync'd)
var _prev_is_crashed: bool = false


func _ready():
	floor_max_angle = deg_to_rad(170.0)  # allow riding on steep ramps, loops, ceilings
	_init_mesh()
	_init_collision_shape()
	_init_ik()
	_init_raycasts()
	_init_controller_handlers()
	animation_controller.initialize()

	if Engine.is_editor_hint():
		return

	# await get_tree().process_frame

	# Network authority
	set_multiplayer_authority(1)
	input_controller.set_multiplayer_authority(int(name))
	rollback_sync.process_settings()

	call_deferred("_deferred_init")


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool):
	if Engine.is_editor_hint():
		return

	if rb_do_respawn:
		do_respawn()
		rb_do_respawn = false

	# Run other controllers (ORDER MATTERS)
	movement_controller.on_movement_rollback_tick(delta)
	gearing_controller.on_movement_rollback_tick(delta)
	trick_controller.on_movement_rollback_tick(delta)
	crash_controller.on_movement_rollback_tick(delta)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Detect crash state transition outside rollback (safe for signals/RPCs)
	if is_crashed and !_prev_is_crashed:
		crashed.emit(int(name))
	_prev_is_crashed = is_crashed

	if !is_local_client:
		return


#region init
## set definitions and apply mesh/colors/markers
func _init_mesh():
	bike_skin.skin_definition = bike_definition
	bike_skin._apply_definition()
	character_skin.skin_definition = character_definition
	character_skin.apply_definition()


## set collision shape from bike_definition
func _init_collision_shape():
	collision_shape_3d.shape = bike_definition.collision_shape

	collision_shape_3d.position = bike_definition.collision_position_offset
	collision_shape_3d.rotation_degrees = bike_definition.collision_rotation_offset_degrees
	collision_shape_3d.scale = bike_definition.collision_scale_multiplier


## Position ground raycasts at wheel positions from bike_definition
func _init_raycasts():
	front_raycast.position = bike_definition.front_wheel_ground_position + Vector3.UP * 0.5
	front_raycast.target_position = Vector3.DOWN * 1.5
	rear_raycast.position = bike_definition.rear_wheel_ground_position + Vector3.UP * 0.5
	rear_raycast.target_position = Vector3.DOWN * 1.5


## Set up IK by passing bike markers to IKController, creating proxy markers for limbs
func _init_ik():
	var ik_ctrl = character_skin.ik_controller

	var handlebar = bike_skin.steering_handlebar_marker
	var peg = bike_skin.left_peg_marker
	var seat = bike_skin.seat_marker

	# Create proxy markers for all limbs so rotations are independent from bike markers
	var left_hand = _create_proxy(handlebar, "LeftHandProxy", handlebar.get_parent())
	var right_hand = _create_mirrored_proxy(handlebar, "RightHandProxy", handlebar.get_parent())
	var left_foot = _create_proxy(peg, "LeftFootProxy", bike_skin)
	var right_foot = _create_mirrored_proxy(peg, "RightFootProxy", bike_skin)

	ik_ctrl.set_bike_markers(seat, left_hand, right_hand, left_foot, right_foot)

	# Apply rider pose from BikeSkinDefinition
	_apply_rider_pose_from_definition()

	# Recreate IK now that bike markers are set (initial _create_ik ran before markers existed)
	ik_ctrl._create_ik()
	character_skin.enable_ik()


func _create_proxy(source: Marker3D, proxy_name: String, parent: Node3D) -> Marker3D:
	var existing = parent.get_node_or_null(proxy_name)
	if existing:
		existing.queue_free()

	var proxy = Marker3D.new()
	proxy.name = proxy_name
	parent.add_child(proxy)
	proxy.transform = source.transform
	return proxy


func _create_mirrored_proxy(source: Marker3D, proxy_name: String, parent: Node3D) -> Marker3D:
	var existing = parent.get_node_or_null(proxy_name)
	if existing:
		existing.queue_free()

	var proxy = Marker3D.new()
	proxy.name = proxy_name
	parent.add_child(proxy)
	proxy.global_transform = AnimationController._mirror_transform_x(source.global_transform)
	return proxy


func _apply_rider_pose_from_definition():
	var ik_ctrl = character_skin.ik_controller
	var bd = bike_definition

	if bd.chest_position is Vector3 and bd.chest_position != Vector3.ZERO:
		ik_ctrl.ik_chest.position = bd.chest_position
	if bd.chest_rotation is Vector3 and bd.chest_rotation != Vector3.ZERO:
		ik_ctrl.ik_chest.rotation = bd.chest_rotation
	if bd.head_position is Vector3 and bd.head_position != Vector3.ZERO:
		ik_ctrl.ik_head.position = bd.head_position
	if bd.head_rotation is Vector3 and bd.head_rotation != Vector3.ZERO:
		ik_ctrl.ik_head.rotation = bd.head_rotation
	if bd.left_arm_magnet_position is Vector3 and bd.left_arm_magnet_position != Vector3.ZERO:
		ik_ctrl.ik_left_arm_magnet.position = bd.left_arm_magnet_position
	if bd.right_arm_magnet_position is Vector3 and bd.right_arm_magnet_position != Vector3.ZERO:
		ik_ctrl.ik_right_arm_magnet.position = bd.right_arm_magnet_position
	if bd.left_leg_magnet_position is Vector3 and bd.left_leg_magnet_position != Vector3.ZERO:
		ik_ctrl.ik_left_leg_magnet.position = bd.left_leg_magnet_position
	if bd.right_leg_magnet_position is Vector3 and bd.right_leg_magnet_position != Vector3.ZERO:
		ik_ctrl.ik_right_leg_magnet.position = bd.right_leg_magnet_position
	if bd.left_hand_rotation is Vector3 and bd.left_hand_rotation != Vector3.ZERO:
		ik_ctrl.ik_left_hand.rotation = bd.left_hand_rotation
	if bd.right_hand_rotation is Vector3 and bd.right_hand_rotation != Vector3.ZERO:
		ik_ctrl.ik_right_hand.rotation = bd.right_hand_rotation
	if bd.left_foot_rotation is Vector3 and bd.left_foot_rotation != Vector3.ZERO:
		ik_ctrl.ik_left_foot.rotation = bd.left_foot_rotation
	if bd.right_foot_rotation is Vector3 and bd.right_foot_rotation != Vector3.ZERO:
		ik_ctrl.ik_right_foot.rotation = bd.right_foot_rotation


func _deferred_init():
	if int(name) == multiplayer.get_unique_id():
		is_local_client = true
		camera_controller.deferred_init()
		_init_audio()
		hud_controller.show_hud()
	else:
		hud_controller.hide_hud()


func _init_audio():
	if !audio_manager:
		return
	gearing_controller.rpm_updated.connect(_on_rpm_updated)

	# TODO - add clunk sound when changing gears
	audio_manager.play_ninja500_revs()


func _init_controller_handlers():
	gearing_controller.gear_changed.connect(_on_gear_changed)
	trick_controller.trick_started.connect(_on_trick_started)
	trick_controller.trick_ended.connect(_on_trick_ended)


#endregion


#region handlers
func _on_rpm_updated(new_rpm_ratio: float):
	if !audio_manager:
		return
	audio_manager.update_ninja500_rpm(new_rpm_ratio)


func _on_gear_changed(new_gear: int):
	DebugUtils.DebugMsg("Gear: %d" % new_gear, OS.has_feature("debug"))


func _on_trick_started(trick_type: TrickController.Trick):
	DebugUtils.DebugMsg(
		"Trick Started: %s" % TrickController.trick_to_str(trick_type), OS.has_feature("debug")
	)


func _on_trick_ended(trick_type: TrickController.Trick):
	DebugUtils.DebugMsg(
		"Trick Ended: %s" % TrickController.trick_to_str(trick_type),
		OS.has_feature("debug") and false
	)


#endregion

#region public api


func update_skins(new_bike_def: BikeSkinDefinition, new_char_def: CharacterSkinDefinition):
	bike_definition = new_bike_def
	character_definition = new_char_def
	_init_mesh()
	_init_collision_shape()
	_init_ik()
	_init_raycasts()


func do_respawn():
	if rb_respawn_transform != Transform3D():
		global_transform = rb_respawn_transform
		rb_respawn_transform = Transform3D()
	else:
		global_transform = get_parent().global_transform
	velocity = Vector3.ZERO
	is_boosting = false
	is_crashed = false
	for child in controllers_node.get_children():
		if !child.has_method("do_reset"):
			continue
		child.do_reset()
	# movement_controller.do_reset()
	# gearing_controller.do_reset()
	# trick_controller.do_reset()
	# crash_controller.do_reset()
	# animation_controller.do_reset()
	if animation_controller:
		animation_controller.stop_ragdoll()
	respawned.emit()


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if movement_controller == null:
		issues.append("movement_controller must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if animation_controller == null:
		issues.append("animation_controller must not be empty")
	if gearing_controller == null:
		issues.append("gearing_controller must not be empty")
	if trick_controller == null:
		issues.append("trick_controller must not be empty")
	if crash_controller == null:
		issues.append("crash_controller must not be empty")
	if camera_controller == null:
		issues.append("camera_controller must not be empty")
	if hud_controller == null:
		issues.append("hud_controller must not be empty")
	if bike_definition == null:
		issues.append("bike_definition must not be empty")
	if collision_shape_3d == null:
		issues.append("collision_shape_3d must not be empty")
	return issues
