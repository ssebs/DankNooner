@tool
class_name BikeSkinDefinition extends Resource

## Name of the skin for saving to disk
@export var skin_name: String = "replace_me"

@export_group("Mesh")
## The SkinColor scene to instantiate
@export var mesh_res: PackedScene:
	set(value):
		if value:
			var instance = value.instantiate()
			assert(instance is SkinColor, "Wrong scene type!")
			instance.free()
		mesh_res = value
@export var mesh_position_offset: Vector3 = Vector3.ZERO
@export var mesh_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale_multiplier: Vector3 = Vector3.ONE

## SkinSlot colors (use TRANSPARENT to skip a slot)
## See skin_color.gd
@export var colors: Array[Color] = []

@export_group("Collision")
# TODO: use this
@export
var collision_shape: Shape3D = preload("res://resources/entities/bikes/hitbox/bike_hitbox.tres")
@export var collision_position_offset: Vector3 = Vector3.ZERO
@export var collision_rotation_offset_degrees: Vector3 = Vector3(90, 0, 0)
@export var collision_scale_multiplier: Vector3 = Vector3.ONE

## Marker positions
@export_group("Markers")
# TODO: use this
@export var training_wheels_marker_position: Vector3 = Vector3.ZERO
@export var training_wheels_marker_rotation_degrees: Vector3 = Vector3.ZERO

const USER_SKIN_DIR: String = "user://skins/"
const SKIN_PFX: String = "bike_skin_"

# TODO- copy save_to_disk, load_from_disk, _copy_from, to/from dict...
