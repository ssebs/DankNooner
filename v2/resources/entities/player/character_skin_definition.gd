@tool
class_name CharacterSkinDefinition extends Resource

## The SkinColor scene to instantiate
@export var mesh_res: PackedScene:
	set(value):
		if value:
			var instance = value.instantiate()
			assert(instance is SkinColor, "Wrong scene type!")
			instance.free()
		mesh_res = value

## Primary color (use TRANSPARENT to skip)
@export var primary_color: Color = Color.TRANSPARENT

## Secondary color - only used if mesh has_secondary
@export var secondary_color: Color = Color.TRANSPARENT

## Marker positions
@export_group("Markers")
@export var back_marker_position: Vector3 = Vector3.ZERO
@export var back_marker_rotation_degrees: Vector3 = Vector3.ZERO
