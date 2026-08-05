@tool
class_name AnimalSkinDefinition extends Resource

## Name of the skin
@export var skin_name: String = "replace_me"

@export_group("Mesh")
## The scene to instantiate
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

@export_group("Collision")
@export var collision_shape: Shape3D
@export var collision_position_offset: Vector3 = Vector3(0, 0, 0)
@export var collision_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var collision_scale_multiplier: Vector3 = Vector3.ONE
