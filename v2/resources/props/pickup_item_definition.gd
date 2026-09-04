@tool
class_name PickupItemDefinition extends Resource

enum PickupItemType{GAS_CAN,}

@export_group("Mesh")
## The Scene to instantiate
@export var mesh_res: PackedScene:
	set(value):
		if value:
			var instance = value.instantiate()
			# Any 3D scene works (a raw .glb, a SkinColor, etc.) — it just needs to be spatial
			# so the mesh offsets below apply.
			assert(instance is Node3D, "Mesh scene root must be a Node3D")
			instance.free()
		mesh_res = value
@export var mesh_position_offset: Vector3 = Vector3.ZERO
@export var mesh_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale_multiplier: Vector3 = Vector3.ONE

@export_group("Bubble")
## Radius of the pickup's spherical collider and its bubble mesh (both always spheres).
@export var radius: float = 1.5

@export_group("Type")
@export var item_type:PickupItemType

