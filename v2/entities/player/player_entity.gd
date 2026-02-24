@tool
class_name PlayerEntity extends CharacterBody3D

@export var bike_definition: BikeSkinDefinition
@export var character_definition: CharacterSkinDefinition

@export var camera_controller: CameraController
@export var movement_controller: MovementController
@export var input_controller: InputController

@export var mesh_node: Node3D
@export var collision_shape_3d: CollisionShape3D

@onready var name_label: Label3D = %NameLabel
@onready var rollback_sync: RollbackSynchronizer = %RollbackSynchronizer

var is_local_client: bool = false

# rollback_tick vars
## rollback do respawn
var rb_do_respawn: bool = false


func _ready():
	# _init_mesh()
	_init_collision_shape()

	if Engine.is_editor_hint():
		return

	# await get_tree().process_frame

	# Network authority
	set_multiplayer_authority(1)
	input_controller.set_multiplayer_authority(int(name))
	rollback_sync.process_settings()

	call_deferred("_deferred_init")


func _deferred_init():
	if int(name) == multiplayer.get_unique_id():
		is_local_client = true
		camera_controller.switch_to_tps_cam()
		_init_input_handlers()
	else:
		camera_controller.disable_cameras()

	# set_username_label("Player: %s" % name)


func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool):
	if rb_do_respawn:
		on_respawn()
		rb_do_respawn = false


func _init_input_handlers():
	if input_controller == null:
		printerr("cant find input_controller in PlayerEntity")
		return

	# Note - throttle, brake, and steer are handled in movement_controller
	input_controller.lean_changed.connect(_on_lean_changed)
	input_controller.rear_brake_pressed.connect(_on_rear_brake_pressed)
	input_controller.trick_mod_pressed.connect(_on_trick_mod_pressed)
	input_controller.clutch_pressed.connect(_on_clutch_pressed)
	input_controller.gear_up_pressed.connect(_on_gear_up_pressed)
	input_controller.gear_down_pressed.connect(_on_gear_down_pressed)
	input_controller.cam_switch_pressed.connect(_on_cam_switch_pressed)


func _on_cam_switch_pressed():
	if is_local_client:
		camera_controller.toggle_cam()


#region unused input handlers
func _on_lean_changed(_value: float):
	pass


func _on_rear_brake_pressed():
	pass


func _on_trick_mod_pressed():
	pass


func _on_clutch_pressed():
	pass


func _on_gear_up_pressed():
	pass


func _on_gear_down_pressed():
	pass


#endregion


func on_respawn():
	global_transform = get_parent().global_transform
	velocity = Vector3.ZERO
	movement_controller.spawn_timer = movement_controller.default_spawn_timer
	movement_controller.angular_velocity = 0
	movement_controller.current_speed = 0


func _init_collision_shape():
	collision_shape_3d.shape = bike_definition.collision_shape

	collision_shape_3d.position = bike_definition.collision_position_offset
	collision_shape_3d.rotation_degrees = bike_definition.collision_rotation_offset_degrees
	collision_shape_3d.scale = bike_definition.collision_scale_multiplier


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
	if bike_definition == null:
		issues.append("bike_definition must not be empty")
	if mesh_node == null:
		issues.append("mesh_node must not be empty")
	if collision_shape_3d == null:
		issues.append("collision_shape_3d must not be empty")

	return issues
