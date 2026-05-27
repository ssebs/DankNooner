@tool
## Reusable 3D thumbnail. Renders a skin definition into a SubViewport.
## Works in-editor for scale/framing preview.
class_name Thumbnail3D extends SubViewportContainer

enum Type { BIKE, CHARACTER, GENERIC }

@export var type: Type = Type.BIKE:
	set(value):
		type = value
		if is_node_ready():
			_rebuild()

## BikeSkinDefinition when type=BIKE, CharacterSkinDefinition when type=CHARACTER,
## any Resource for GENERIC.
@export var skin_definition: Resource:
	set(value):
		skin_definition = value
		if is_node_ready():
			_rebuild()

@export_group("Camera")
@export var camera_position: Vector3 = Vector3(2.2, 1.2, 2.2):
	set(value):
		camera_position = value
		_apply_camera()
@export var camera_look_at: Vector3 = Vector3(0, 0.4, 0):
	set(value):
		camera_look_at = value
		_apply_camera()
@export_range(10.0, 120.0) var camera_fov: float = 50.0:
	set(value):
		camera_fov = value
		_apply_camera()

const BIKE_SKIN_SCENE: PackedScene = preload("res://player/bikes/bike_skin.tscn")
const CHARACTER_SKIN_SCENE: PackedScene = preload("res://player/characters/character_skin.tscn")

@onready var sub_viewport: SubViewport = %SubViewport
@onready var spawn_parent: Node3D = %SpawnParent
@onready var camera: Camera3D = %Camera3D


func _ready() -> void:
	# sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_apply_camera()
	_rebuild()


## Convenience setter for runtime callers — equivalent to setting `type` + `skin_definition`.
func set_skin(t: Type, def: Resource) -> void:
	if not is_node_ready():
		await ready
	type = t
	skin_definition = def


func _apply_camera() -> void:
	if camera == null:
		return
	camera.position = camera_position
	camera.look_at(camera_look_at, Vector3.UP)
	camera.fov = camera_fov


func _rebuild() -> void:
	for child in spawn_parent.get_children():
		child.queue_free()
	if skin_definition == null:
		return

	match type:
		Type.BIKE:
			_spawn_bike()
		Type.CHARACTER:
			_spawn_character()
		Type.GENERIC:
			pass  # Subclasses / external callers can add to spawn_parent themselves.


func _spawn_bike() -> void:
	if not (skin_definition is BikeSkinDefinition):
		push_warning("Thumbnail3D: type=BIKE but skin_definition is not a BikeSkinDefinition")
		return
	var bike: BikeSkin = BIKE_SKIN_SCENE.instantiate()
	bike.skin_definition = skin_definition
	spawn_parent.add_child(bike)
	if Engine.is_editor_hint():
		bike.owner = sub_viewport


func _spawn_character() -> void:
	if not (skin_definition is CharacterSkinDefinition):
		push_warning(
			"Thumbnail3D: type=CHARACTER but skin_definition is not a CharacterSkinDefinition"
		)
		return
	var char_node: CharacterSkin = CHARACTER_SKIN_SCENE.instantiate()
	char_node.skin_definition = skin_definition
	spawn_parent.add_child(char_node)
	if Engine.is_editor_hint():
		char_node.owner = sub_viewport
