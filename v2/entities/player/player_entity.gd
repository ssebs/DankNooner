@tool
## make sure to set HACK region's vars!
## audio_manager & username
class_name PlayerEntity extends CharacterBody3D

@export var bike_definition: BikeSkinDefinition
@export var character_definition: CharacterSkinDefinition
@export var collision_shape_3d: CollisionShape3D

@export var input_controller: InputController
@export var animation_controller: AnimationController
@export var gearing_controller: GearingController
@export var trick_controller: TrickController
@export var crash_controller: CrashController

# @onready var hud_controller: HUDController = %HUDController
@onready var movement_controller: MovementController = %MovementController
@onready var camera_controller: CameraController = %CameraController

@onready var visual_root: Node3D = %VisualRoot
@onready var character_skin: CharacterSkin = %CharacterSkin
@onready var bike_skin: BikeSkin = %BikeSkin
@onready var name_label: Label3D = %NameLabel
@onready var rollback_sync: RollbackSynchronizer = %RollbackSynchronizer

var is_local_client: bool = false

#region HACK - set from level_manager
var audio_manager: AudioManager
var username: String:
	set(v):
		username = v
		if is_node_ready():
			name_label.text = username
# `name` is also set from level_manager
#endregion

# Physics state (synced via RollbackSynchronizer state_properties)
var speed: float = 0.0
var lean_angle: float = 0.0
var pitch_angle: float = 0.0  # + = wheelie, - = stoppie
var fishtail_angle: float = 0.0
var ground_pitch: float = 0.0  # Slope alignment

# Gearing state (synced)
var current_gear: int = 1
var current_rpm: float = 1000.0
var clutch_value: float = 0.0
var rpm_ratio: float = 0.0

# Trick/boost state (synced)
var is_boosting: bool = false
var boost_count: int = 2

# Crash state (synced)
var is_crashed: bool = false

# Brake danger (local, display only)
var grip_usage: float = 0.0

# Discrete actions (rb_* pattern)
var rb_do_respawn: bool = false
var rb_activate_boost: bool = false


func _ready():
	_init_mesh()
	_init_collision_shape()
	_init_ik()
	animation_controller.initialize()

	if Engine.is_editor_hint():
		return

	# await get_tree().process_frame

	# Network authority
	set_multiplayer_authority(1)
	input_controller.set_multiplayer_authority(int(name))
	rollback_sync.process_settings()

	call_deferred("_deferred_init")


func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool):
	# All rollback logic delegated to MovementController._rollback_tick()
	pass


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if !is_local_client:
		return

	# hud_controller.speed = speed
	# hud_controller.current_gear = current_gear
	# hud_controller.is_stalled = gearing_controller.is_stalled if gearing_controller else false
	# hud_controller.rpm_ratio = rpm_ratio
	# hud_controller.throttle = input_controller.throttle if input_controller else 0.0
	# hud_controller.clutch_value = clutch_value
	# hud_controller.grip_usage = grip_usage
	# hud_controller.last_trick = trick_controller._last_trick if trick_controller else 0
	# hud_controller.boost_count = boost_count
	# hud_controller.is_boosting = is_boosting
	# hud_controller.is_crashed = is_crashed


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


## set ik targets, enable ik
func _init_ik():
	character_skin.set_ik_targets_for_bike(
		bike_definition.seat_marker_position,
		bike_definition.left_handlebar_marker_position,
		bike_definition.left_peg_marker_position
	)
	character_skin.enable_ik()


func _deferred_init():
	if int(name) == multiplayer.get_unique_id():
		is_local_client = true
		camera_controller.switch_to_tps_cam()
		_init_input_handlers()
		_init_audio()
		# hud_controller.show_hud()
	else:
		camera_controller.disable_cameras()
		# hud_controller.hide_hud()


#endregion


#region local init (deferred)
func _init_audio():
	if !audio_manager:
		return
	gearing_controller.rpm_updated.connect(_on_rpm_updated)

	# TODO - add clunk sound when changing gears
	# gearing_controller.rpm_updated.connect(_on_rpm_updated)
	audio_manager.play_ninja500_revs()


func _init_input_handlers():
	if input_controller == null:
		printerr("cant find input_controller in PlayerEntity")
		return

	input_controller.cam_switch_pressed.connect(_on_cam_switch_pressed)


#endregion


#region handlers
func _on_cam_switch_pressed():
	if is_local_client:
		camera_controller.toggle_cam()


func _on_rpm_updated(new_rpm_ratio: float):
	if !audio_manager:
		return
	audio_manager.update_ninja500_rpm(new_rpm_ratio)


#endregion

#region public api


func do_respawn():
	global_transform = get_parent().global_transform
	velocity = Vector3.ZERO
	speed = 0.0
	lean_angle = 0.0
	pitch_angle = 0.0
	fishtail_angle = 0.0
	current_gear = 1
	current_rpm = bike_definition.idle_rpm if bike_definition else 1000.0
	clutch_value = 0.0
	rpm_ratio = 0.0
	is_boosting = false
	is_crashed = false
	movement_controller.spawn_timer = movement_controller.default_spawn_timer
	if animation_controller:
		animation_controller.stop_ragdoll()


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
	if bike_definition == null:
		issues.append("bike_definition must not be empty")
	if collision_shape_3d == null:
		issues.append("collision_shape_3d must not be empty")
	return issues
