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

## Primary color (use TRANSPARENT to skip)
@export var primary_color: Color = Color.TRANSPARENT
## Secondary color - only used if mesh has_secondary
@export var secondary_color: Color = Color.TRANSPARENT

@export_group("Collision")
@export var collision_shape: Shape3D
@export var collision_position_offset: Vector3 = Vector3.ZERO
@export var collision_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var collision_scale_multiplier: Vector3 = Vector3.ONE

## Marker positions
@export_group("Markers")
@export var training_wheels_marker_position: Vector3 = Vector3.ZERO
@export var training_wheels_marker_rotation_degrees: Vector3 = Vector3.ZERO

const USER_SKIN_DIR: String = "user://skins/"
const SKIN_PFX: String = "bike_skin_"

# TODO- copy save_to_disk, load_from_disk, _copy_from, to/from dict...
