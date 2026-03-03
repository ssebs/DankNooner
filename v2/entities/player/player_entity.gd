@tool
class_name PlayerEntity extends CharacterBody3D

@export var bike_definition: BikeSkinDefinition
@export var character_definition: CharacterSkinDefinition

@export var camera_controller: CameraController
@export var movement_controller: MovementController
@export var input_controller: InputController
@export var animation_controller: AnimationController
@export var gearing_controller: GearingController
@export var trick_controller: TrickController
@export var crash_controller: CrashController

@export var collision_shape_3d: CollisionShape3D

@onready var visual_root: Node3D = %VisualRoot
@onready var character_skin: CharacterSkin = %CharacterSkin
@onready var bike_skin: BikeSkin = %BikeSkin
@onready var name_label: Label3D = %NameLabel
@onready var rollback_sync: RollbackSynchronizer = %RollbackSynchronizer
@onready var hud: Control = %HUD

var is_local_client: bool = false

# Debug HUD elements
var _debug_speed_label: Label
var _debug_gear_label: Label
var _debug_rpm_bar: ProgressBar
var _debug_throttle_bar: ProgressBar
var _debug_clutch_bar: ProgressBar
var _debug_grip_bar: ProgressBar
var _debug_trick_label: Label
var _debug_boost_label: Label

#region Physics state (synced via RollbackSynchronizer state_properties)
var speed: float = 0.0
var lean_angle: float = 0.0
var pitch_angle: float = 0.0        # + = wheelie, - = stoppie
var fishtail_angle: float = 0.0
var ground_pitch: float = 0.0       # Slope alignment
#endregion

#region Gearing state (synced)
var current_gear: int = 1
var current_rpm: float = 1000.0
var clutch_value: float = 0.0
var rpm_ratio: float = 0.0
#endregion

#region Trick/boost state (synced)
var is_boosting: bool = false
var boost_count: int = 2
#endregion

#region Crash state (synced)
var is_crashed: bool = false
#endregion

#region Brake danger (local, display only)
var grip_usage: float = 0.0
#endregion

#region Discrete actions (rb_* pattern)
var rb_do_respawn: bool = false
var rb_activate_boost: bool = false
#endregion


func _ready():
	_init_mesh()
	_init_collision_shape()
	_init_ik()

	if Engine.is_editor_hint():
		return

	# await get_tree().process_frame

	# Network authority
	set_multiplayer_authority(1)
	input_controller.set_multiplayer_authority(int(name))
	rollback_sync.process_settings()

	call_deferred("_deferred_init")


func _init_ik():
	character_skin.set_ik_targets_for_bike(
		bike_definition.seat_marker_position,
		bike_definition.left_handlebar_marker_position,
		bike_definition.left_peg_marker_position
	)
	character_skin.enable_ik()
	animation_controller.initialize()


func _init_mesh():
	bike_skin.skin_definition = bike_definition
	character_skin.skin_definition = character_definition


func _init_collision_shape():
	collision_shape_3d.shape = bike_definition.collision_shape

	collision_shape_3d.position = bike_definition.collision_position_offset
	collision_shape_3d.rotation_degrees = bike_definition.collision_rotation_offset_degrees
	collision_shape_3d.scale = bike_definition.collision_scale_multiplier


func _deferred_init():
	if int(name) == multiplayer.get_unique_id():
		is_local_client = true
		camera_controller.switch_to_tps_cam()
		_init_input_handlers()
		_init_debug_hud()
	else:
		camera_controller.disable_cameras()
		hud.visible = false

	# set_username_label("Player: %s" % name)


func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool):
	# All rollback logic delegated to MovementController._rollback_tick()
	pass


func _init_input_handlers():
	if input_controller == null:
		printerr("cant find input_controller in PlayerEntity")
		return

	input_controller.cam_switch_pressed.connect(_on_cam_switch_pressed)


func _on_cam_switch_pressed():
	if is_local_client:
		camera_controller.toggle_cam()


#region Debug HUD
func _init_debug_hud():
	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 0.0
	vbox.anchor_bottom = 0.0
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.offset_right = 250
	vbox.add_theme_constant_override("separation", 4)
	hud.add_child(vbox)

	_debug_speed_label = Label.new()
	vbox.add_child(_debug_speed_label)

	_debug_gear_label = Label.new()
	vbox.add_child(_debug_gear_label)

	# RPM bar
	var rpm_label = Label.new()
	rpm_label.text = "RPM"
	vbox.add_child(rpm_label)
	_debug_rpm_bar = ProgressBar.new()
	_debug_rpm_bar.custom_minimum_size = Vector2(200, 20)
	_debug_rpm_bar.max_value = 1.0
	_debug_rpm_bar.step = 0.01
	_debug_rpm_bar.show_percentage = false
	vbox.add_child(_debug_rpm_bar)

	# Throttle bar
	var throttle_label = Label.new()
	throttle_label.text = "Throttle"
	vbox.add_child(throttle_label)
	_debug_throttle_bar = ProgressBar.new()
	_debug_throttle_bar.custom_minimum_size = Vector2(200, 20)
	_debug_throttle_bar.max_value = 1.0
	_debug_throttle_bar.step = 0.01
	_debug_throttle_bar.show_percentage = false
	vbox.add_child(_debug_throttle_bar)

	# Clutch bar
	var clutch_label = Label.new()
	clutch_label.text = "Clutch"
	vbox.add_child(clutch_label)
	_debug_clutch_bar = ProgressBar.new()
	_debug_clutch_bar.custom_minimum_size = Vector2(200, 20)
	_debug_clutch_bar.max_value = 1.0
	_debug_clutch_bar.step = 0.01
	_debug_clutch_bar.show_percentage = false
	vbox.add_child(_debug_clutch_bar)

	# Brake danger bar
	var grip_label = Label.new()
	grip_label.text = "Brake Danger"
	vbox.add_child(grip_label)
	_debug_grip_bar = ProgressBar.new()
	_debug_grip_bar.custom_minimum_size = Vector2(200, 20)
	_debug_grip_bar.max_value = 1.0
	_debug_grip_bar.step = 0.01
	_debug_grip_bar.show_percentage = false
	vbox.add_child(_debug_grip_bar)

	_debug_trick_label = Label.new()
	vbox.add_child(_debug_trick_label)

	_debug_boost_label = Label.new()
	vbox.add_child(_debug_boost_label)


func _process(_delta: float):
	if Engine.is_editor_hint():
		return
	if not is_local_client:
		return
	_update_debug_hud()


func _update_debug_hud():
	if _debug_speed_label == null:
		return

	_debug_speed_label.text = "Speed: %d" % int(speed)

	if gearing_controller and gearing_controller.is_stalled:
		_debug_gear_label.text = "STALLED - Gear: %d" % current_gear
	else:
		_debug_gear_label.text = "Gear: %d" % current_gear

	_debug_rpm_bar.value = rpm_ratio
	if rpm_ratio > 0.9:
		_debug_rpm_bar.modulate = Color(1.0, 0.2, 0.2)
	elif rpm_ratio > 0.7:
		_debug_rpm_bar.modulate = Color(1.0, 0.8, 0.2)
	else:
		_debug_rpm_bar.modulate = Color(0.2, 0.6, 1.0)

	_debug_throttle_bar.value = input_controller.throttle
	if rpm_ratio > 0.9:
		_debug_throttle_bar.modulate = Color(1.0, 0.2, 0.2)
	else:
		_debug_throttle_bar.modulate = Color(0.2, 0.8, 0.2)

	_debug_clutch_bar.value = clutch_value
	_debug_clutch_bar.modulate = Color(0.8, 0.6, 0.2)

	_debug_grip_bar.value = grip_usage
	if grip_usage > 0.8:
		_debug_grip_bar.modulate = Color(1.0, 0.1, 0.1)
	elif grip_usage > 0.5:
		_debug_grip_bar.modulate = Color(1.0, 0.6, 0.0)
	else:
		_debug_grip_bar.modulate = Color(0.2, 0.8, 0.2)

	# Trick display
	if trick_controller:
		var trick_name = TrickController.Trick.keys()[trick_controller._last_trick]
		if trick_controller._last_trick != TrickController.Trick.NONE:
			_debug_trick_label.text = trick_name
			_debug_trick_label.visible = true
		else:
			_debug_trick_label.visible = false

	# Boost display
	_debug_boost_label.text = "Boost: %d" % boost_count
	if is_boosting:
		_debug_boost_label.text += " [ACTIVE]"
		_debug_boost_label.modulate = Color(1.0, 0.8, 0.0)
	else:
		_debug_boost_label.modulate = Color.WHITE

	if is_crashed:
		_debug_speed_label.text = "CRASHED - Respawning..."
#endregion


func on_respawn():
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
	movement_controller.angular_velocity = 0
	movement_controller.current_speed = 0
	if animation_controller:
		animation_controller.stop_ragdoll()


func set_username_label(username: String):
	name_label.text = username


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if camera_controller == null:
		issues.append("camera_controller must not be empty")
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
